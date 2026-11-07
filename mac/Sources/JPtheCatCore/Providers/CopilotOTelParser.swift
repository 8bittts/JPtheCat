import Foundation

/// Parses GitHub Copilot CLI's OpenTelemetry JSONL export (`~/.copilot/otel/*.jsonl`, opt-in via
/// `COPILOT_OTEL_FILE_EXPORTER_PATH=<path>`). Isolated from `CopilotProvider` on purpose: the record shape needs
/// multi-heuristic reconciliation across four span/log kinds, verified line-for-line against
/// ccusage's reference implementation (`rust/crates/ccusage/src/adapter/copilot/parser.rs`) rather
/// than guessed — keeping that logic in its own file makes it independently testable and stops it
/// from entangling with the provider's plumbing. Follows this codebase's established convention for
/// irregular provider JSON: `JSONSerialization` + tolerant `[String: Any]` access, not `Decodable`
/// (every other provider does the same — Claude, Codex, Gemini, OpenCode's model column).
enum CopilotOTelParser {
	enum RecordKind: Equatable {
		case chatSpan
		case inferenceLog
		case agentTurnLog
		case agentSummarySpan
	}

	struct Candidate {
		let kind: RecordKind
		let traceID: String?
		let responseID: String?
		let model: String
		let sessionID: String
		let timestamp: Date
		let usage: TokenUsage
		let dedupKey: String
		/// GitHub Copilot's per-request consumption in nano-AIU (`github.copilot.nano_aiu`), 0 when the
		/// attribute is absent. This is a raw CONSUMPTION COUNT — never a dollar amount and never a
		/// quota %; `token_limit`/`current_tokens` are the model context window, not a spend ceiling.
		/// It rides the SAME per-turn dedup as tokens (a candidate only survives when it already carries
		/// tokens, since `candidate(...)` drops token-less records), so summing `aiuNano` over the
		/// deduped set never double-counts.
		let aiuNano: Int
	}

	fileprivate struct TraceContext {
		var model: String?
		var sessionID: String?
		var sessionPriority: Int = 0
	}

	// MARK: - Attribute keys (verified against ccusage's parser.rs)

	private static let modelAttrs = ["gen_ai.response.model", "gen_ai.request.model"]
	private static let sessionAttrs: [(key: String, priority: Int)] = [
		("gen_ai.conversation.id", 3),
		("copilot_chat.session_id", 3),
		("copilot_chat.chat_session_id", 3),
		("session.id", 3),
		("github.copilot.interaction_id", 2),
		("gen_ai.response.id", 1),
	]

	// MARK: - Decode

	static func decode(line: Data) -> [String: Any]? {
		try? JSONSerialization.jsonObject(with: line) as? [String: Any]
	}

	// MARK: - Classification

	private static func isSpanRecord(_ record: [String: Any]) -> Bool {
		if (record["type"] as? String) == "span" { return true }
		guard let name = record["name"] as? String, !name.isEmpty else { return false }
		return record["spanId"] != nil || record["traceId"] != nil || record["startTime"] != nil
			|| record["endTime"] != nil || record["duration"] != nil || record["kind"] != nil
	}

	private static func attributes(_ record: [String: Any]) -> [String: Any] {
		record["attributes"] as? [String: Any] ?? [:]
	}

	private static func bodyText(_ record: [String: Any]) -> String {
		(record["body"] as? String) ?? (record["_body"] as? String) ?? ""
	}

	static func classify(_ record: [String: Any]) -> RecordKind? {
		let attrs = attributes(record)
		let operationName = attrs["gen_ai.operation.name"] as? String
		let name = (record["name"] as? String) ?? ""

		if isSpanRecord(record) {
			if operationName == "chat" || name.hasPrefix("chat ") { return .chatSpan }
			if operationName == "invoke_agent" || name.hasPrefix("invoke_agent ") { return .agentSummarySpan }
			return nil
		}

		let eventName = attrs["event.name"] as? String
		let body = bodyText(record)
		if eventName == "gen_ai.client.inference.operation.details" || body.hasPrefix("GenAI inference:") {
			return .inferenceLog
		}
		if eventName == "copilot_chat.agent.turn" || body.hasPrefix("copilot_chat.agent.turn") {
			return .agentTurnLog
		}
		return nil
	}

	// MARK: - Trace-context inheritance + candidate extraction

	private static func attrString(_ attrs: [String: Any], _ key: String) -> String? {
		if let s = attrs[key] as? String, !s.isEmpty { return s }
		return nil
	}

	private static func firstNonEmptyAttr(_ attrs: [String: Any], _ keys: [String]) -> String? {
		for key in keys {
			if let value = attrString(attrs, key) { return value }
		}
		return nil
	}

	private static func bestSessionAttr(_ attrs: [String: Any]) -> (id: String, priority: Int)? {
		var best: (id: String, priority: Int)?
		for (key, priority) in sessionAttrs {
			guard let value = attrString(attrs, key) else { continue }
			if best == nil || priority > best!.priority { best = (value, priority) }
		}
		return best
	}

	private static func collectTraceContexts(_ records: [[String: Any]]) -> [String: TraceContext] {
		var contexts: [String: TraceContext] = [:]
		for record in records { absorbTraceContext(record, into: &contexts) }
		return contexts
	}

	/// Folds ONE record into the trace-context map.
	///
	/// [CRITICAL] Call order must stay FILE ORDER: `model` is first-writer-wins (`context.model == nil`)
	/// and session id is strict-greater-priority, so both resolve to a different value if records are
	/// reordered, skipped, or folded in twice. This is the single shared implementation so the
	/// materialize-everything path and the streaming path cannot drift apart.
	private static func absorbTraceContext(
		_ record: [String: Any], into contexts: inout [String: TraceContext]
	) {
		guard let traceID = record["traceId"] as? String, !traceID.isEmpty else { return }
		let attrs = attributes(record)
		var context = contexts[traceID] ?? TraceContext()
		if context.model == nil {
			context.model = firstNonEmptyAttr(attrs, modelAttrs)
		}
		if let session = bestSessionAttr(attrs), session.priority > context.sessionPriority {
			context.sessionID = session.id
			context.sessionPriority = session.priority
		}
		contexts[traceID] = context
	}

	private static func attrNumber(_ attrs: [String: Any], _ key: String) -> Int {
		if let n = attrs[key] as? NSNumber { return n.intValue }
		if let d = attrs[key] as? Double { return Int(d) }
		if let s = attrs[key] as? String, let d = Double(s) { return Int(d) }
		return 0
	}

	private static func attrNumberFirst(_ attrs: [String: Any], _ keys: [String]) -> Int {
		for key in keys {
			let value = attrNumber(attrs, key)
			if value != 0 { return value }
		}
		return 0
	}

	private static func timestamp(_ record: [String: Any], fallback: Date) -> Date {
		func fromParts(_ raw: Any?) -> Date? {
			guard let array = raw as? [Any], array.count == 2,
				let seconds = (array[0] as? NSNumber)?.doubleValue,
				let nanos = (array[1] as? NSNumber)?.doubleValue
			else { return nil }
			return Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000)
		}
		func fromScalar(_ raw: Any?) -> Date? {
			guard let n = (raw as? NSNumber)?.doubleValue, n > 0 else { return nil }
			let ms: Double
			if n >= 1e17 { ms = n / 1_000_000 }  // nanoseconds
			else if n >= 1e14 { ms = n / 1_000 }  // microseconds
			else if n >= 1e11 { ms = n }  // already milliseconds
			else { ms = n * 1000 }  // seconds
			return Date(timeIntervalSince1970: ms / 1000)
		}

		if let date = fromParts(record["endTime"]) { return date }
		if let date = fromParts(record["startTime"]) { return date }
		if let date = fromParts(record["hrTime"]) { return date }
		if let date = fromParts(record["_hrTime"]) { return date }
		if let date = fromParts(record["time"]) { return date }
		if let date = fromScalar(record["timestamp"]) { return date }
		if let date = fromScalar(record["observedTimestamp"]) { return date }
		if let n = (record["timeUnixNano"] as? NSNumber)?.doubleValue, n > 0 {
			return Date(timeIntervalSince1970: n / 1_000_000_000)
		}
		return fallback
	}

	private static func candidate(
		from record: [String: Any], kind: RecordKind, index: Int, fallback: Date,
		contexts: [String: TraceContext]
	) -> Candidate? {
		let attrs = attributes(record)
		let traceID = record["traceId"] as? String
		let context = traceID.flatMap { contexts[$0] }

		let input = attrNumber(attrs, "gen_ai.usage.input_tokens")
		let output = attrNumber(attrs, "gen_ai.usage.output_tokens")
		let cacheRead = attrNumber(attrs, "gen_ai.usage.cache_read.input_tokens")
		let cacheWrite = attrNumberFirst(
			attrs, ["gen_ai.usage.cache_write.input_tokens", "gen_ai.usage.cache_creation.input_tokens"])
		let reasoning = attrNumberFirst(
			attrs, ["gen_ai.usage.reasoning.output_tokens", "gen_ai.usage.reasoning_tokens"])

		// Net-of-cache-read input, matching ccusage exactly, so totals aren't double-counted.
		let netInput = max(0, input - min(input, cacheRead))
		let usage = TokenUsage(
			input: netInput, output: output, cacheCreate5m: cacheWrite, cacheCreate1h: 0,
			cacheRead: cacheRead)
		guard usage.total + reasoning > 0 else { return nil }
		// Fold reasoning into output — TokenUsage has no dedicated reasoning bucket (matches the
		// convention OpenCode/Gemini already use for reasoning tokens).
		let finalUsage = TokenUsage(
			input: usage.input, output: usage.output + reasoning, cacheCreate5m: usage.cacheCreate5m,
			cacheCreate1h: usage.cacheCreate1h, cacheRead: usage.cacheRead)

		let model = firstNonEmptyAttr(attrs, modelAttrs) ?? context?.model ?? "copilot"
		let sessionID =
			bestSessionAttr(attrs)?.id ?? context?.sessionID ?? traceID ?? "unknown-session"
		let responseID = attrString(attrs, "gen_ai.response.id")
		let aiuNano = attrNumberFirst(attrs, ["github.copilot.nano_aiu", "copilot.nano_aiu"])
		let ts = timestamp(record, fallback: fallback)
		let spanID = record["spanId"] as? String

		let dedupKey: String
		switch kind {
		case .chatSpan, .agentSummarySpan:
			if let traceID, let spanID { dedupKey = "\(kind)-span:\(traceID):\(spanID)" } else {
				dedupKey = "\(kind)-span:\(sessionID):\(Int(ts.timeIntervalSince1970 * 1000)):\(index)"
			}
		case .inferenceLog:
			if let traceID, let spanID { dedupKey = "log:\(traceID):\(spanID)" } else {
				dedupKey = "log:\(sessionID):\(Int(ts.timeIntervalSince1970 * 1000)):\(index)"
			}
		case .agentTurnLog:
			let turnIndex =
				attrString(attrs, "turn.index") ?? attrString(attrs, "copilot_chat.turn.index")
				?? "idx-\(index)"
			if let traceID { dedupKey = "agent-turn:\(traceID):\(turnIndex)" } else {
				dedupKey = "agent-turn:\(sessionID):\(turnIndex):\(index)"
			}
		}

		return Candidate(
			kind: kind, traceID: traceID, responseID: responseID, model: model, sessionID: sessionID,
			timestamp: ts, usage: finalUsage, dedupKey: dedupKey, aiuNano: aiuNano)
	}

	static func candidates(from records: [[String: Any]], fallback: Date) -> [Candidate] {
		let contexts = collectTraceContexts(records)
		var results: [Candidate] = []
		for (index, record) in records.enumerated() {
			guard let kind = classify(record) else { continue }
			if let candidate = candidate(
				from: record, kind: kind, index: index, fallback: fallback, contexts: contexts) {
				results.append(candidate)
			}
		}
		return results
	}

	// MARK: - Streaming accumulation (one pass, no whole-file record array)

	/// One streaming pass's accumulation: trace contexts folded in from EVERY decoded record (metric
	/// lines included — they carry the `traceId`/model/session attributes candidates inherit), plus
	/// ONLY the records `classify()` accepts, each tagged with its ORIGINAL whole-file index.
	///
	/// [Why this exists] Both file entry points used to materialize every decoded record into a
	/// `[[String: Any]]` before classifying anything. On a real 9.6 MB / 14,198-line OTel file that is
	/// ~46 MB of live `NSDictionary` graph, and 98.8% of it is `"type":"metric"` lines `classify()`
	/// throws away — see `CopilotProvider`'s cache doc. Keeping only the ~169 survivors plus the
	/// context map holds the same information for well under 1% of the footprint.
	///
	/// [CRITICAL] This must stay behaviour-IDENTICAL to the materialize-everything shape, not an
	/// approximation. Two things make it so and must not be weakened: contexts are folded from every
	/// record in file order (`absorbTraceContext`'s first-writer-wins model and strict-greater session
	/// priority both depend on it), and the retained `index` is the record's position in the WHOLE
	/// file, because `candidate(...)`'s dedup-key fallbacks embed it. Guard:
	/// `CopilotOTelStreamingParityTests`.
	struct StreamedRecords {
		fileprivate var contexts: [String: TraceContext] = [:]
		fileprivate var kept: [(index: Int, record: [String: Any], kind: RecordKind)] = []
		private var index = 0

		mutating func absorb(_ record: [String: Any]) {
			let recordIndex = index
			index += 1
			CopilotOTelParser.absorbTraceContext(record, into: &contexts)
			guard let kind = CopilotOTelParser.classify(record) else { return }
			kept.append((index: recordIndex, record: record, kind: kind))
		}
	}

	static func candidates(from streamed: StreamedRecords, fallback: Date) -> [Candidate] {
		var results: [Candidate] = []
		results.reserveCapacity(streamed.kept.count)
		for entry in streamed.kept {
			if let candidate = candidate(
				from: entry.record, kind: entry.kind, index: entry.index, fallback: fallback,
				contexts: streamed.contexts) {
				results.append(candidate)
			}
		}
		return results
	}

	/// A record with no usable timestamp of its own falls back to the file's own mtime.
	private static func modificationFallback(fileURL: URL) -> Date {
		((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date)
			?? .distantPast
	}

	// MARK: - Dedup priority (ChatSpan > InferenceLog > AgentTurnLog > AgentSummarySpan)

	static func dedupedCandidates(_ candidates: [Candidate]) -> [Candidate] {
		var chatTraces = Set<String>()
		var chatResponses = Set<String>()
		var inferenceTraces = Set<String>()
		var inferenceResponses = Set<String>()
		var agentTurnTraces = Set<String>()
		var agentTurnResponses = Set<String>()

		for c in candidates where c.kind == .chatSpan {
			if let t = c.traceID { chatTraces.insert(t) }
			if let r = c.responseID { chatResponses.insert(r) }
		}
		for c in candidates where c.kind == .inferenceLog {
			if let t = c.traceID { inferenceTraces.insert(t) }
			if let r = c.responseID { inferenceResponses.insert(r) }
		}
		for c in candidates where c.kind == .agentTurnLog {
			if let t = c.traceID { agentTurnTraces.insert(t) }
			if let r = c.responseID { agentTurnResponses.insert(r) }
		}

		func covered(_ c: Candidate, traces: Set<String>, responses: Set<String>) -> Bool {
			(c.traceID.map { traces.contains($0) } ?? false)
				|| (c.responseID.map { responses.contains($0) } ?? false)
		}

		return candidates.filter { c in
			switch c.kind {
			case .chatSpan:
				return true
			case .inferenceLog:
				return !covered(c, traces: chatTraces, responses: chatResponses)
			case .agentTurnLog:
				return !covered(c, traces: chatTraces, responses: chatResponses)
					&& !covered(c, traces: inferenceTraces, responses: inferenceResponses)
			case .agentSummarySpan:
				return !covered(c, traces: chatTraces, responses: chatResponses)
					&& !covered(c, traces: inferenceTraces, responses: inferenceResponses)
					&& !covered(c, traces: agentTurnTraces, responses: agentTurnResponses)
			}
		}
	}

	// MARK: - Model normalization

	/// Strips a `vendor/model` prefix, mirroring `OpenCodeProvider.normalizeModel`. Copilot's
	/// `gen_ai.request.model` attribute may or may not carry a vendor prefix depending on the
	/// underlying routed model.
	static func normalizeModel(_ raw: String) -> String {
		ProviderModelNormalization.strippingVendorPrefix(raw, fallback: "copilot")
	}

	// MARK: - Public entry points

	private static func events(from candidates: [Candidate]) -> [UsageEvent] {
		dedupedCandidates(candidates).map { c in
			UsageEvent(
				messageId: c.sessionID, requestId: c.dedupKey, provider: .copilot,
				model: normalizeModel(c.model), timestamp: c.timestamp, usage: c.usage, project: nil)
		}
	}

	static func parse(fileURL: URL, reader: JSONLStreamReader = JSONLStreamReader()) -> [UsageEvent] {
		events(fromDeduping: candidates(fileURL: fileURL, reader: reader))
	}

	/// The exact per-file reduction `parse(fileURL:)` applies, split out so a caller holding already-parsed
	/// candidates (e.g. `CopilotProvider`'s shared file-traversal cache) gets byte-identical results
	/// without re-reading and re-decoding the file.
	static func events(fromDeduping candidates: [Candidate]) -> [UsageEvent] {
		Deduplicator.dedupe(events(from: candidates))
	}

	static func parse(fileURL: URL, from offset: Int, reader: JSONLStreamReader = JSONLStreamReader())
		-> (events: [UsageEvent], consumed: Int)
	{
		var streamed = StreamedRecords()
		let consumed = reader.read(fileURL: fileURL, from: offset) { data in
			if let record = decode(line: data) { streamed.absorb(record) }
		}
		let candidates = candidates(from: streamed, fallback: modificationFallback(fileURL: fileURL))
		return (Deduplicator.dedupe(events(from: candidates)), consumed)
	}

	// MARK: - AIU consumption (local `github.copilot.nano_aiu` samples)

	/// One deduped per-request AIU consumption sample. `nano` is a raw count (`github.copilot.nano_aiu`),
	/// NOT a dollar amount and NOT a quota %. Callers must present it as consumption only.
	struct AIUSample: Equatable {
		let timestamp: Date
		let nano: Int
	}

	/// Deduped per-request AIU samples from already-decoded records. Runs the SAME dedup as `events`,
	/// so an AIU value is counted at most once per turn (no chatSpan/inferenceLog double-count), and
	/// drops zero-AIU turns so the samples map 1:1 to requests that actually consumed AIU.
	static func aiuSamples(from candidates: [Candidate]) -> [AIUSample] {
		dedupedCandidates(candidates)
			.filter { $0.aiuNano > 0 }
			.map { AIUSample(timestamp: $0.timestamp, nano: $0.aiuNano) }
	}

	/// All (pre-dedup) candidates from a single OTel file — exposed so a provider can combine
	/// candidates across every file and dedup ONCE across the whole corpus (matching how the
	/// token-event path dedups across files), rather than per-file in isolation.
	static func candidates(fileURL: URL, reader: JSONLStreamReader = JSONLStreamReader()) -> [Candidate] {
		var streamed = StreamedRecords()
		reader.read(fileURL: fileURL) { data in
			if let record = decode(line: data) { streamed.absorb(record) }
		}
		return candidates(from: streamed, fallback: modificationFallback(fileURL: fileURL))
	}
}
