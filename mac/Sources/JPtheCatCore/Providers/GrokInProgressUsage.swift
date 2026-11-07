import Foundation

/// Process-wide skip cache for Grok's mid-turn overlay ingest. `UsageIndex.ingest`/`deleteEvents`
/// bump `generation` even on a no-op delete, which would bust the dashboard window-summary cache
/// every poll. Skip when the overlay inputs (unified.jsonl + involved session files) and the last
/// emitted overlay have not moved.
private final class GrokInProgressOverlayCache: @unchecked Sendable {
	private struct Entry: Equatable {
		let inputFingerprint: Int
		let ingested: Bool
	}
	private let lock = NSLock()
	private var entries: [ObjectIdentifier: Entry] = [:]

	func shouldSkip(index: UsageIndex, inputFingerprint: Int) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		guard let entry = entries[ObjectIdentifier(index)] else { return false }
		return entry.inputFingerprint == inputFingerprint
	}

	func previouslyIngested(_ index: UsageIndex) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		return entries[ObjectIdentifier(index)]?.ingested ?? false
	}

	func remember(index: UsageIndex, inputFingerprint: Int, ingested: Bool) {
		lock.lock()
		defer { lock.unlock() }
		entries[ObjectIdentifier(index)] = Entry(
			inputFingerprint: inputFingerprint, ingested: ingested)
	}
}

private let grokInProgressOverlayCache = GrokInProgressOverlayCache()

/// One Grok model-round from `~/.grok/logs/unified.jsonl` `shell.turn.inference_done`.
/// These lines are the per-round billed tokens that later sum into `turn_completed.usage`.
struct GrokInferenceRound: Equatable, Sendable {
	let sid: String
	let timestamp: Date
	let usage: TokenUsage
}

extension GrokProvider {
	/// Log line Grok emits after each model round (verified against Grok Build 1.0.13).
	public static let inferenceDoneMessage = "shell.turn.inference_done"
	/// Sentinel source path for mid-turn overlay rows. Not a real file — `deleteEvents` keys on it
	/// so a completed turn can drop the overlay without touching durable `turn_completed` rows.
	public static let inProgressSourcePath = "grok://in-progress"

	var logsRoot: URL {
		root.appendingPathComponent("logs", isDirectory: true)
	}

	var unifiedLogURL: URL {
		logsRoot.appendingPathComponent("unified.jsonl")
	}

	/// Mid-turn billed rounds not yet covered by a `turn_completed` line.
	///
	/// Grok Build writes `update.usage` only when a turn ends. Agent turns run for many model
	/// rounds, so the dashboard sat at `$0.00` / `0 tok` for the whole turn while the official
	/// weekly gauge still moved. `shell.turn.inference_done` is the same billed ledger (prompt /
	/// cached / completion / reasoning), written after every round. Overlay = sum(rounds) −
	/// sum(`turn_completed`) per session, floored at zero, one synthetic event per sid so a
	/// finished turn does not change the turn count from N rounds down to 1.
	///
	/// Never treats `_meta.totalTokens` on ACP chunks as billed usage — that is context occupancy.
	func inProgressEvents(completedBySid: [String: TokenUsage]? = nil) -> [UsageEvent] {
		GrokProvider.inProgressEvents(
			root: root, sessions: updatesFiles(), completedBySid: completedBySid)
	}

	/// Replace the synthetic overlay rows in `index`. No-ops when the overlay fingerprint is
	/// unchanged so a dashboard poll does not bust `WindowSummaryCache`.
	public func syncInProgressUsage(into index: UsageIndex) throws {
		try syncInProgressUsage(into: index, sessions: updatesFiles())
	}

	func syncInProgressUsage(into index: UsageIndex, sessions: [URL]) throws {
		let inputFingerprint = overlayInputFingerprint(
			indexGeneration: index.generation, sessions: sessions)
		if grokInProgressOverlayCache.shouldSkip(
			index: index, inputFingerprint: inputFingerprint)
		{
			return
		}
		let rounds = Self.loadInferenceRounds(logURL: unifiedLogURL)
		let completedByPath = try index.usageBySourcePath(
			provider: .grok, sourcePaths: Set(sessions.map(\.path)))
		var completedBySid: [String: TokenUsage] = [:]
		for file in sessions {
			let sid = file.deletingLastPathComponent().lastPathComponent
			completedBySid[sid, default: TokenUsage()] += completedByPath[file.path] ?? TokenUsage()
		}
		let events = Self.eventsFromRounds(
			rounds, sessions: sessions, completedBySid: completedBySid)
		let ingested = !events.isEmpty
		let hadOverlay = grokInProgressOverlayCache.previouslyIngested(index)
		if ingested {
			try index.deleteEvents(sourcePath: Self.inProgressSourcePath)
			try index.ingest(events, sourcePath: Self.inProgressSourcePath)
		} else if hadOverlay {
			try index.deleteEvents(sourcePath: Self.inProgressSourcePath)
		}
		grokInProgressOverlayCache.remember(
			index: index,
			inputFingerprint: overlayInputFingerprint(
				indexGeneration: index.generation, sessions: sessions),
			ingested: ingested)
	}

	static func inProgressEvents(
		root: URL, sessions: [URL], completedBySid: [String: TokenUsage]?
	) -> [UsageEvent] {
		let log = root.appendingPathComponent("logs/unified.jsonl")
		let rounds = loadInferenceRounds(logURL: log)
		return eventsFromRounds(rounds, sessions: sessions, completedBySid: completedBySid)
	}

	static func eventsFromRounds(
		_ rounds: [GrokInferenceRound], sessions: [URL], completedBySid: [String: TokenUsage]?
	) -> [UsageEvent] {
		guard !rounds.isEmpty else { return [] }
		var bySid: [String: [GrokInferenceRound]] = [:]
		for round in rounds {
			bySid[round.sid, default: []].append(round)
		}
		var sessionBySid: [String: URL] = [:]
		for file in sessions {
			sessionBySid[file.deletingLastPathComponent().lastPathComponent] = file
		}
		var events: [UsageEvent] = []
		for (sid, sidRounds) in bySid {
			guard let updates = sessionBySid[sid] else { continue }
			let completed: TokenUsage
			if let preset = completedBySid {
				completed = preset[sid] ?? TokenUsage()
			} else {
				completed = parseUsage(fileURL: updates).reduce(into: TokenUsage()) { $0 += $1.usage }
			}
			let live = sidRounds.reduce(into: TokenUsage()) { $0 += $1.usage }
			let delta = saturatingSubtract(live, completed)
			guard delta.total > 0 else { continue }
			let sessionDir = updates.deletingLastPathComponent()
			guard let model = sessionModelID(sessionDir: sessionDir, updatesFile: updates) else {
				continue
			}
			let timestamp = sidRounds.map(\.timestamp).max() ?? .distantPast
			guard timestamp != .distantPast else { continue }
			events.append(
				UsageEvent(
					messageId: "inprogress-\(sid)",
					requestId: sid,
					provider: .grok,
					model: model,
					timestamp: timestamp,
					usage: delta,
					project: projectName(fromUpdatesFile: updates)))
		}
		return events
	}

	static func decodeInferenceRound(line: Data) -> GrokInferenceRound? {
		guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
			object["msg"] as? String == inferenceDoneMessage,
			let sid = object["sid"] as? String, !sid.isEmpty,
			let ctx = object["ctx"] as? [String: Any]
		else { return nil }
		let prompt = JSONNumber.int(ctx["prompt_tokens"])
		let cached = JSONNumber.int(ctx["cached_prompt_tokens"])
		let completion = JSONNumber.int(ctx["completion_tokens"])
		let reasoning = JSONNumber.int(ctx["reasoning_tokens"])
		guard
			let tokens = tokenUsage(from: [
				"inputTokens": prompt,
				"cachedReadTokens": cached,
				"outputTokens": completion,
				"reasoningTokens": reasoning,
			])
		else { return nil }
		let timestamp = ISOTimestamp.parse(object["ts"] as? String)
		guard timestamp != .distantPast else { return nil }
		return GrokInferenceRound(sid: sid, timestamp: timestamp, usage: tokens)
	}

	static func loadInferenceRounds(logURL: URL) -> [GrokInferenceRound] {
		var rounds: [GrokInferenceRound] = []
		JSONLStreamReader().read(fileURL: logURL) { data in
			// Cheap reject before JSON — unified.jsonl also carries auth and billing noise.
			let line = String(decoding: data, as: UTF8.self)
			guard line.contains(inferenceDoneMessage),
				let round = decodeInferenceRound(line: data)
			else { return }
			rounds.append(round)
		}
		return rounds
	}

	static func sessionModelID(sessionDir: URL, updatesFile: URL) -> String? {
		if let fromSummary = modelIDFromSummary(sessionDir) { return fromSummary }
		return modelIDFromUpdates(updatesFile)
	}

	static func modelIDFromSummary(_ sessionDir: URL) -> String? {
		let url = sessionDir.appendingPathComponent("summary.json")
		guard let data = try? Data(contentsOf: url),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let model = object["current_model_id"] as? String, !model.isEmpty
		else { return nil }
		return model
	}

	static func modelIDFromUpdates(_ updatesFile: URL) -> String? {
		var model: String?
		JSONLStreamReader().read(fileURL: updatesFile) { data in
			guard model == nil,
				let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				let params = object["params"] as? [String: Any],
				let update = params["update"] as? [String: Any],
				let meta = update["_meta"] as? [String: Any],
				let id = meta["modelId"] as? String, !id.isEmpty
			else { return }
			model = id
		}
		return model
	}

	static func saturatingSubtract(_ lhs: TokenUsage, _ rhs: TokenUsage) -> TokenUsage {
		TokenUsage(
			input: max(0, lhs.input - rhs.input),
			output: max(0, lhs.output - rhs.output),
			cacheCreate5m: max(0, lhs.cacheCreate5m - rhs.cacheCreate5m),
			cacheCreate1h: max(0, lhs.cacheCreate1h - rhs.cacheCreate1h),
			cacheRead: max(0, lhs.cacheRead - rhs.cacheRead))
	}

	func overlayInputFingerprint(indexGeneration: Int, sessions: [URL]) -> Int {
		var fingerprint = Hasher()
		fingerprint.combine(indexGeneration)
		if let state = FileCursor.state(fileURL: unifiedLogURL) {
			fingerprint.combine(state.size)
			fingerprint.combine(state.mtime)
			fingerprint.combine(state.ctime)
		} else {
			fingerprint.combine("log:missing")
		}
		for path in sessions.map(\.path).sorted() { fingerprint.combine(path) }
		return fingerprint.finalize()
	}
}
