import Foundation
import XCTest

@testable import JPtheCatCore

final class GrokProviderTests: XCTestCase {
	// MARK: - Fixtures

	/// Stage a `~/.grok`-shaped root with one session's `updates.jsonl`.
	private func stage(
		_ lines: [String],
		cwdEncoded: String = "%2FUsers%2Ftest%2Fproj",
		sessionID: String = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
	) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-\(UUID().uuidString)", isDirectory: true)
		let sessionDir = root
			.appendingPathComponent("sessions", isDirectory: true)
			.appendingPathComponent(cwdEncoded, isDirectory: true)
			.appendingPathComponent(sessionID, isDirectory: true)
		try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
		let file = sessionDir.appendingPathComponent("updates.jsonl")
		try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
		return (root, file)
	}

	private func turnCompleted(
		eventId: String,
		promptId: String,
		sessionId: String = "sess-1",
		input: Int,
		output: Int,
		cached: Int,
		reasoning: Int,
		model: String = "grok-4.5",
		ts: Int = 1_783_974_266,
		agentMs: Int = 1_783_974_266_328
	) -> String {
		// Real xAI accounting counts reasoning separately from AND in addition to output, so
		// totalTokens = input + output + reasoning (the parser ignores this field, but keep it faithful).
		"""
		{"timestamp":\(ts),"method":"_x.ai/session/update","params":{"sessionId":"\(sessionId)","update":{"sessionUpdate":"turn_completed","prompt_id":"\(promptId)","stop_reason":"end_turn","usage":{"inputTokens":\(input),"outputTokens":\(output),"totalTokens":\(input + output + reasoning),"cachedReadTokens":\(cached),"reasoningTokens":\(reasoning),"modelCalls":1,"modelUsage":{"\(model)":{"inputTokens":\(input),"outputTokens":\(output),"totalTokens":\(input + output + reasoning),"cachedReadTokens":\(cached),"reasoningTokens":\(reasoning),"modelCalls":1}},"numTurns":1}}},"_meta":{"eventId":"\(eventId)","agentTimestampMs":\(agentMs)}}
		"""
	}

	/// A single `turn_completed` line whose `modelUsage` fans out across MULTIPLE models — the branch
	/// where each model becomes its own priced `UsageEvent`. `models` maps model-id → (in, out, cached,
	/// reasoning); a zero-token entry is included to prove it is skipped.
	private func turnCompletedMultiModel(
		eventId: String,
		promptId: String,
		sessionId: String = "sess-1",
		models: [(model: String, input: Int, output: Int, cached: Int, reasoning: Int)],
		ts: Int = 1_783_974_266,
		agentMs: Int = 1_783_974_266_328
	) -> String {
		let modelEntries = models.map { m in
			"\"\(m.model)\":{\"inputTokens\":\(m.input),\"outputTokens\":\(m.output),\"totalTokens\":\(m.input + m.output + m.reasoning),\"cachedReadTokens\":\(m.cached),\"reasoningTokens\":\(m.reasoning),\"modelCalls\":1}"
		}
		.joined(separator: ",")
		let totalIn = models.reduce(0) { $0 + $1.input }
		let totalOut = models.reduce(0) { $0 + $1.output }
		let totalCached = models.reduce(0) { $0 + $1.cached }
		let totalReasoning = models.reduce(0) { $0 + $1.reasoning }
		return """
		{"timestamp":\(ts),"method":"_x.ai/session/update","params":{"sessionId":"\(sessionId)","update":{"sessionUpdate":"turn_completed","prompt_id":"\(promptId)","stop_reason":"end_turn","usage":{"inputTokens":\(totalIn),"outputTokens":\(totalOut),"totalTokens":\(totalIn + totalOut + totalReasoning),"cachedReadTokens":\(totalCached),"reasoningTokens":\(totalReasoning),"modelCalls":\(models.count),"modelUsage":{\(modelEntries)},"numTurns":1}}},"_meta":{"eventId":"\(eventId)","agentTimestampMs":\(agentMs)}}
		"""
	}

	private func inferenceDone(
		sid: String,
		ts: String = "2026-09-02T22:00:00.000Z",
		prompt: Int,
		cached: Int,
		completion: Int,
		reasoning: Int,
		loop: Int = 1
	) -> String {
		"""
		{"ts":"\(ts)","src":"shell","pid":1,"sid":"\(sid)","ver":"1.0.13","lvl":"info","msg":"shell.turn.inference_done","ctx":{"loop_index":\(loop),"prompt_tokens":\(prompt),"cached_prompt_tokens":\(cached),"completion_tokens":\(completion),"reasoning_tokens":\(reasoning),"elapsed_since_turn_start_ms":1000,"attempts":1,"model_elapsed_ms":100,"tokens_per_sec":40}}
		"""
	}

	private func writeLog(_ root: URL, lines: [String]) throws {
		let dir = root.appendingPathComponent("logs", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		try (lines.joined(separator: "\n") + "\n").write(
			to: dir.appendingPathComponent("unified.jsonl"), atomically: true, encoding: .utf8)
	}

	private func writeSummary(
		_ root: URL,
		cwdEncoded: String = "%2FUsers%2Ftest%2Fproj",
		sessionID: String = "019f5d26-fb0e-7921-8835-f94d3f70d0b1",
		model: String = "grok-4.6"
	) throws {
		let dir = root
			.appendingPathComponent("sessions/\(cwdEncoded)/\(sessionID)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		try #"{"current_model_id":"\#(model)"}"#.write(
			to: dir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
	}

	private func userMessageChunk(model: String = "grok-4.6") -> String {
		"""
		{"timestamp":1,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":""},"_meta":{"modelId":"\(model)"}}}}
		"""
	}

	// MARK: - Allowlist / availability

	func testStrictAllowlistOnlyReadsUpdatesJsonl() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 1000, output: 50, cached: 200, reasoning: 10)
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let sessionDir = root
			.appendingPathComponent("sessions/%2FUsers%2Ftest%2Fproj/019f5d26-fb0e-7921-8835-f94d3f70d0b1")
		// Sibling files that must never be parsed (prompts / auth / noise).
		try #"{"type":"user","content":"SECRET PROMPT"}"#.write(
			to: sessionDir.appendingPathComponent("chat_history.jsonl"), atomically: true, encoding: .utf8)
		try #"{"token":"secret"}"#.write(
			to: root.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
		try #"{"noise":true}"#.write(
			to: sessionDir.appendingPathComponent("signals.json"), atomically: true, encoding: .utf8)

		let provider = GrokProvider(root: root)
		XCTAssertEqual(provider.updatesFiles().count, 1)
		XCTAssertEqual(provider.loadEvents().count, 1)
	}

	func testIsAvailableReflectsSessions() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 10, output: 1, cached: 0, reasoning: 0)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(GrokProvider(root: root).isAvailable())
		XCTAssertFalse(
			GrokProvider(root: root.appendingPathComponent("empty", isDirectory: true)).isAvailable())
	}

	// MARK: - Token mapping

	func testTokenMappingSplitsCacheAndFoldsReasoning() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 1000, output: 500, cached: 200, reasoning: 100)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let events = GrokProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let u = events[0].usage
		XCTAssertEqual(u.input, 800)  // 1000 - 200 cached
		XCTAssertEqual(u.cacheRead, 200)
		XCTAssertEqual(u.output, 600)  // 500 + 100 reasoning
		XCTAssertEqual(u.cacheCreate5m, 0)
		XCTAssertEqual(u.cacheCreate1h, 0)
		XCTAssertEqual(u.total, 1600)
		XCTAssertEqual(events[0].provider, .grok)
		XCTAssertEqual(events[0].model, "grok-4.5")
	}

	func testCachedGreaterThanInputClampsToZeroNeverNegative() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 100, output: 10, cached: 300, reasoning: 0)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let u = GrokProvider(root: root).loadEvents()[0].usage
		XCTAssertEqual(u.input, 0)
		XCTAssertEqual(u.cacheRead, 300)
	}

	func testZeroTokenTurnIsSkipped() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 0, output: 0, cached: 0, reasoning: 0)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(GrokProvider(root: root).loadEvents().isEmpty)
	}

	func testDedupIdentityUsesEventIdAndPromptId() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "evt-abc", promptId: "prompt-xyz", input: 100, output: 10, cached: 0,
				reasoning: 0, model: "grok-4.5")
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let e = GrokProvider(root: root).loadEvents()[0]
		// The model suffix is ALWAYS applied (count-independent) so a re-logged turn can't change its
		// own identity by gaining/losing a model entry.
		XCTAssertEqual(e.messageId, "evt-abc-grok-4.5")
		XCTAssertEqual(e.requestId, "prompt-xyz")
	}

	func testMultiModelTurnSplitsPerModelWithStableIdentity() throws {
		// One turn fanned across two priced models plus a zero-token third that must be dropped.
		let (root, _) = try stage([
			turnCompletedMultiModel(
				eventId: "evt-1", promptId: "prompt-1",
				models: [
					("grok-4.5", 1000, 500, 200, 100),
					("grok-code-fast-1", 300, 40, 0, 0),
					("grok-4.3", 0, 0, 0, 0),  // zero-token entry → skipped
				])
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let events = GrokProvider(root: root).loadEvents().sorted { $0.model < $1.model }
		XCTAssertEqual(events.count, 2, "one event per non-empty model; the zero-token model is skipped")

		let byModel = Dictionary(uniqueKeysWithValues: events.map { ($0.model, $0) })
		let big = try XCTUnwrap(byModel["grok-4.5"])
		let fast = try XCTUnwrap(byModel["grok-code-fast-1"])

		// Identity is count-independent `<eventId>-<model>`, so each model is a distinct, stable row.
		XCTAssertEqual(big.messageId, "evt-1-grok-4.5")
		XCTAssertEqual(fast.messageId, "evt-1-grok-code-fast-1")
		XCTAssertNotEqual(big.id, fast.id)
		XCTAssertEqual(big.requestId, "prompt-1")
		XCTAssertEqual(fast.requestId, "prompt-1")

		// Per-model token split is applied independently (input = raw − cached, output += reasoning).
		XCTAssertEqual(big.usage.input, 800)  // 1000 − 200 cached
		XCTAssertEqual(big.usage.cacheRead, 200)
		XCTAssertEqual(big.usage.output, 600)  // 500 + 100 reasoning
		XCTAssertEqual(fast.usage.input, 300)
		XCTAssertEqual(fast.usage.output, 40)
		XCTAssertEqual(fast.usage.cacheRead, 0)
	}

	func testProjectDecodedFromEncodedCwdFolder() throws {
		let (root, _) = try stage(
			[
				turnCompleted(
					eventId: "e1", promptId: "p1", input: 10, output: 1, cached: 0, reasoning: 0)
			], cwdEncoded: "%2FUsers%2Fexample%2FDocuments%2FJPtheCat")
		defer { try? FileManager.default.removeItem(at: root) }
		let e = GrokProvider(root: root).loadEvents()[0]
		XCTAssertEqual(e.project, "/Users/example/Documents/JPtheCat")
	}

	func testTimestampFromAgentTimestampMs() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 10, output: 1, cached: 0, reasoning: 0,
				ts: 1_783_974_266, agentMs: 1_783_974_266_328)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let e = GrokProvider(root: root).loadEvents()[0]
		XCTAssertEqual(e.timestamp.timeIntervalSince1970, 1_783_974_266.328, accuracy: 0.001)
	}

	func testIgnoresNonTurnCompletedLines() throws {
		let noise = #"{"timestamp":1,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hi"}}}}"#
		let (root, _) = try stage([
			noise,
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 50, output: 5, cached: 0, reasoning: 0),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(GrokProvider(root: root).loadEvents().count, 1)
	}

	func testDuplicateLinesKeepMaxOutput() throws {
		// Same eventId written twice (streaming/re-write) — keep-max on output.
		let first = turnCompleted(
			eventId: "e1", promptId: "p1", input: 100, output: 10, cached: 0, reasoning: 0)
		let second = turnCompleted(
			eventId: "e1", promptId: "p1", input: 100, output: 40, cached: 0, reasoning: 5)
		let (root, _) = try stage([first, second])
		defer { try? FileManager.default.removeItem(at: root) }
		let events = GrokProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events[0].usage.output, 45)  // 40 + 5 reasoning
	}

	// MARK: - Detection

	func testDetectionFalseOnEmptyHome() throws {
		let empty = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-empty-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: empty) }
		// Bare home with no binary and no sessions must not count as installed.
		XCTAssertFalse(GrokProvider.isGrokBuildDetected(home: empty))
	}

	func testDetectionTrueWhenSessionsPresent() throws {
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 10, output: 1, cached: 0, reasoning: 0)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(GrokProvider.isGrokBuildDetected(home: root))
	}

	// MARK: - Index / tail append

	func testIndexableTailAppendIsIdempotent() throws {
		let (root, file) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", input: 100, output: 10, cached: 0, reasoning: 0)
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let db = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-idx-\(UUID().uuidString).sqlite")
		defer { try? FileManager.default.removeItem(at: db) }

		let index = try UsageIndex(path: db.path)
		let provider = GrokProvider(root: root)
		let indexer = UsageIndexer(index: index)
		let first = try indexer.refresh(provider)
		XCTAssertEqual(first.eventsIngested, 1)

		// Append a second turn; re-refresh should only ingest the new line.
		let handle = try FileHandle(forWritingTo: file)
		defer { try? handle.close() }
		try handle.seekToEnd()
		let extra = turnCompleted(
			eventId: "e2", promptId: "p2", input: 200, output: 20, cached: 50, reasoning: 0) + "\n"
		try handle.write(contentsOf: Data(extra.utf8))

		let second = try indexer.refresh(provider)
		XCTAssertEqual(second.eventsIngested, 1, "only the newly appended turn should ingest")
		XCTAssertEqual(index.eventCount(provider: .grok), 2)
	}

	// MARK: - Pricing coverage for emitted IDs

	func testGrokComposer25FastListPriceIsCovered() {
		let table = PricingTable.bundledDefault()
		XCTAssertNotNil(table.price(for: "grok-composer-2.5-fast"))
		XCTAssertNotNil(table.price(for: "composer-2.5-fast"))
		let p = table.price(for: "grok-composer-2.5-fast")!
		// Cursor on-demand Fast tier: $3 / $15 per MTok (cursor.com/changelog/composer-2-5).
		XCTAssertEqual(p.inputCostPerToken, 3e-6, accuracy: 1e-12)
		XCTAssertEqual(p.outputCostPerToken, 15e-6, accuracy: 1e-12)
	}

	func testGrok45ListPriceIsCovered() {
		let table = PricingTable.bundledDefault()
		XCTAssertNotNil(table.price(for: "grok-4.5"))
		XCTAssertNotNil(table.price(for: "grok-4.5-latest"))
		XCTAssertNotNil(table.price(for: "grok-4.5-build"))
		XCTAssertNotNil(table.price(for: "grok-build-latest"))
		let p = table.price(for: "grok-4.5")!
		// Official docs.x.ai: $2 / $0.30 cached / $6 per 1M → per-token
		XCTAssertEqual(p.inputCostPerToken, 2e-6, accuracy: 1e-12)
		XCTAssertEqual(p.cacheReadInputTokenCost ?? -1, 0.3e-6, accuracy: 1e-12)
		XCTAssertEqual(p.outputCostPerToken, 6e-6, accuracy: 1e-12)
		let emittedBuildAlias = table.price(for: "grok-4.5-build")!
		XCTAssertEqual(emittedBuildAlias.inputCostPerToken, p.inputCostPerToken, accuracy: 1e-12)
		XCTAssertEqual(emittedBuildAlias.cacheReadInputTokenCost, p.cacheReadInputTokenCost)
		XCTAssertEqual(emittedBuildAlias.outputCostPerToken, p.outputCostPerToken, accuracy: 1e-12)
	}

	func testGrok46BuildListPriceIsCovered() {
		let table = PricingTable.bundledDefault()
		XCTAssertNotNil(table.price(for: "grok-4.6"))
		XCTAssertNotNil(table.price(for: "grok-4.6-latest"))
		XCTAssertNotNil(table.price(for: "grok-4.6-build"))
		let p = table.price(for: "grok-4.6")!
		// Official docs.x.ai/developers/models/grok-4.6: $2 / $0.50 cached / $6 per 1M,
		// long-context ≥200k $4 / $1 / $12. Distinct from grok-4.5's $0.30 cached rate.
		XCTAssertEqual(p.inputCostPerToken, 2e-6, accuracy: 1e-12)
		XCTAssertEqual(p.cacheReadInputTokenCost ?? -1, 0.5e-6, accuracy: 1e-12)
		XCTAssertEqual(p.outputCostPerToken, 6e-6, accuracy: 1e-12)
		XCTAssertEqual(p.inputCostPerTokenAbove200k ?? -1, 4e-6, accuracy: 1e-12)
		XCTAssertEqual(p.cacheReadInputTokenCostAbove200k ?? -1, 1e-6, accuracy: 1e-12)
		XCTAssertEqual(p.outputCostPerTokenAbove200k ?? -1, 12e-6, accuracy: 1e-12)
		let emittedBuildAlias = table.price(for: "grok-4.6-build")!
		XCTAssertEqual(emittedBuildAlias.inputCostPerToken, p.inputCostPerToken, accuracy: 1e-12)
		XCTAssertEqual(emittedBuildAlias.cacheReadInputTokenCost, p.cacheReadInputTokenCost)
		XCTAssertEqual(emittedBuildAlias.outputCostPerToken, p.outputCostPerToken, accuracy: 1e-12)
		XCTAssertNotEqual(
			table.price(for: "grok-4.6-build")?.cacheReadInputTokenCost,
			table.price(for: "grok-4.5-build")?.cacheReadInputTokenCost)
	}

	func testOfficialXAICachedRatesAreModelSpecificNotFlatTenth() {
		// https://docs.x.ai/developers/pricing + per-model pages: cached input is NOT always 0.1×.
		let table = PricingTable.bundledDefault()
		let grok43 = table.price(for: "grok-4.3")!
		XCTAssertEqual(grok43.inputCostPerToken, 1.25e-6, accuracy: 1e-12)
		XCTAssertEqual(grok43.cacheReadInputTokenCost ?? -1, 0.2e-6, accuracy: 1e-12)
		XCTAssertEqual(grok43.outputCostPerToken, 2.5e-6, accuracy: 1e-12)

		let build = table.price(for: "grok-build-0.1")!
		XCTAssertEqual(build.inputCostPerToken, 1e-6, accuracy: 1e-12)
		XCTAssertEqual(build.cacheReadInputTokenCost ?? -1, 0.2e-6, accuracy: 1e-12)
		XCTAssertEqual(build.outputCostPerToken, 2e-6, accuracy: 1e-12)

		// Aliases from official model pages.
		XCTAssertNotNil(table.price(for: "grok-code-fast-1"))
		XCTAssertNotNil(table.price(for: "grok-latest"))
		XCTAssertEqual(
			table.price(for: "grok-code-fast")?.inputCostPerToken ?? -1, 1e-6, accuracy: 1e-12)
		XCTAssertEqual(
			table.price(for: "grok-4.20")?.cacheReadInputTokenCost ?? -1, 0.2e-6, accuracy: 1e-12)
	}

	// MARK: - Mid-turn inference_done overlay

	func testInProgressInferenceDoneShowsBeforeTurnCompleted() throws {
		let sid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
		let (root, _) = try stage([
			#"{"timestamp":1,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":""},"_meta":{"totalTokens":999999}}}}"#
		])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeSummary(root)
		try writeLog(root, lines: [
			inferenceDone(sid: sid, prompt: 1000, cached: 200, completion: 50, reasoning: 10),
		])

		let events = GrokProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events[0].messageId, "inprogress-\(sid)")
		XCTAssertEqual(events[0].model, "grok-4.6")
		XCTAssertEqual(events[0].usage.input, 800)
		XCTAssertEqual(events[0].usage.cacheRead, 200)
		XCTAssertEqual(events[0].usage.output, 60)
		XCTAssertEqual(events[0].provider, .grok)
		let cost = CostCalculator().cost(model: events[0].model, usage: events[0].usage)
		XCTAssertNotNil(cost)
		XCTAssertGreaterThan(cost ?? 0, 0)
	}

	func testCompletedTurnDoesNotDoubleCountInferenceDone() throws {
		let sid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", sessionId: sid,
				input: 1000, output: 50, cached: 200, reasoning: 10, model: "grok-4.6")
		])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeSummary(root)
		try writeLog(root, lines: [
			inferenceDone(sid: sid, prompt: 1000, cached: 200, completion: 50, reasoning: 10),
		])

		let events = GrokProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1, "overlay must drop once turn_completed covers the same tokens")
		XCTAssertEqual(events[0].messageId, "e1-grok-4.6")
		XCTAssertEqual(events[0].usage.input, 800)
		XCTAssertEqual(events[0].usage.output, 60)
		XCTAssertEqual(events[0].usage.cacheRead, 200)
	}

	func testInProgressDeltaIsOnlyUncoveredRounds() throws {
		let sid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
		let (root, _) = try stage([
			turnCompleted(
				eventId: "e1", promptId: "p1", sessionId: sid,
				input: 100, output: 10, cached: 0, reasoning: 0, model: "grok-4.6")
		])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeSummary(root)
		try writeLog(root, lines: [
			inferenceDone(
				sid: sid, ts: "2026-09-02T22:00:00.000Z", prompt: 100, cached: 0, completion: 10,
				reasoning: 0, loop: 1),
			inferenceDone(
				sid: sid, ts: "2026-09-02T22:01:00.000Z", prompt: 200, cached: 100, completion: 20,
				reasoning: 5, loop: 2),
		])

		let events = GrokProvider(root: root).loadEvents().sorted { $0.messageId < $1.messageId }
		XCTAssertEqual(events.count, 2)
		let completed = try XCTUnwrap(events.first { $0.messageId == "e1-grok-4.6" })
		let live = try XCTUnwrap(events.first { $0.messageId == "inprogress-\(sid)" })
		XCTAssertEqual(completed.usage.input, 100)
		XCTAssertEqual(live.usage.input, 100)  // (100-0 + 200-100) − 100
		XCTAssertEqual(live.usage.output, 25)  // (10 + 25) − 10
		XCTAssertEqual(live.usage.cacheRead, 100)
	}

	func testUnifiedLogNoiseIsIgnored() throws {
		let sid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
		let (root, _) = try stage([
			userMessageChunk()
		])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeSummary(root)
		try writeLog(root, lines: [
			#"{"ts":"2026-09-02T22:00:00.000Z","src":"shell","pid":1,"sid":"\#(sid)","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":1}}}"#,
			#"{"ts":"2026-09-02T22:00:01.000Z","src":"shell","pid":1,"msg":"auth init token state"}"#,
			inferenceDone(sid: sid, prompt: 50, cached: 0, completion: 5, reasoning: 0),
		])
		XCTAssertEqual(GrokProvider(root: root).loadEvents().count, 1)
	}

	func testModelFallsBackToUserMessageChunkWhenSummaryMissing() throws {
		let sid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
		let (root, _) = try stage([userMessageChunk(model: "grok-4.6")])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeLog(root, lines: [
			inferenceDone(sid: sid, prompt: 40, cached: 0, completion: 4, reasoning: 0),
		])
		let events = GrokProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events[0].model, "grok-4.6")
	}

	func testContextOccupancyTotalTokensIsNotBilled() throws {
		let (root, _) = try stage([
			#"{"timestamp":1,"method":"session/update","params":{"_meta":{"totalTokens":101221},"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":""}}}}"#
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(GrokProvider(root: root).loadEvents().count, 0)
	}

	func testIndexerOverlayReplacedWhenTurnCompletes() throws {
		let sid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
		let (root, file) = try stage([userMessageChunk()])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeSummary(root)
		try writeLog(root, lines: [
			inferenceDone(sid: sid, prompt: 1000, cached: 200, completion: 50, reasoning: 10),
		])

		let db = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-live-\(UUID().uuidString).sqlite")
		defer { try? FileManager.default.removeItem(at: db) }
		let index = try UsageIndex(path: db.path)
		let provider = GrokProvider(root: root)
		let indexer = UsageIndexer(index: index)

		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .grok), 1)

		let handle = try FileHandle(forWritingTo: file)
		defer { try? handle.close() }
		try handle.seekToEnd()
		let extra = turnCompleted(
			eventId: "e1", promptId: "p1", sessionId: sid,
			input: 1000, output: 50, cached: 200, reasoning: 10, model: "grok-4.6") + "\n"
		try handle.write(contentsOf: Data(extra.utf8))

		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .grok), 1, "overlay row must yield to turn_completed")
		let events = provider.loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events[0].messageId, "e1-grok-4.6")
	}

	func testOverlaySyncIsIdempotentOnUnchangedInputs() throws {
		let sid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"
		let (root, _) = try stage([userMessageChunk()])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeSummary(root)
		try writeLog(root, lines: [
			inferenceDone(sid: sid, prompt: 80, cached: 0, completion: 8, reasoning: 0),
		])
		let db = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-sync-\(UUID().uuidString).sqlite")
		defer { try? FileManager.default.removeItem(at: db) }
		let index = try UsageIndex(path: db.path)
		let provider = GrokProvider(root: root)
		try provider.syncInProgressUsage(into: index)
		let generation = index.generation
		try provider.syncInProgressUsage(into: index)
		XCTAssertEqual(index.generation, generation, "unchanged overlay must not bump index generation")
		XCTAssertEqual(index.eventCount(provider: .grok), 1)
	}

	// MARK: - Per-request split (xAI's 200K premium is decided per request)

	private let splitSid = "019f5d26-fb0e-7921-8835-f94d3f70d0b1"

	/// One 150K-context request of a grok-4.7 turn: 50K uncached input, 100K cached, 600 output.
	private func halfTurnRequest(ts: String, loop: Int = 1) -> String {
		inferenceDone(
			sid: splitSid, ts: ts, prompt: 150_000, cached: 100_000, completion: 500, reasoning: 100,
			loop: loop)
	}

	/// A grok-4.7 turn whose summed context (300K) crosses the premium while each request does not.
	private func premiumTurn(eventId: String = "e1", promptId: String = "p1", secondsBefore: Int = 0) -> String {
		turnCompleted(
			eventId: eventId, promptId: promptId, sessionId: splitSid,
			input: 300_000, output: 1_000, cached: 200_000, reasoning: 200, model: "grok-4.7",
			ts: 1_783_974_266 - secondsBefore, agentMs: (1_783_974_266 - secondsBefore) * 1000 + 328)
	}

	private func completedEvents(_ root: URL) -> [UsageEvent] {
		GrokProvider(root: root).loadEvents()
			.filter { !$0.messageId.hasPrefix("inprogress-") }
			.sorted { $0.timestamp < $1.timestamp }
	}

	func testReconcilingRequestsSplitATurnSoEachIsPricedBelowThePremium() throws {
		let (root, _) = try stage([premiumTurn()])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeLog(root, lines: [
			halfTurnRequest(ts: "2026-07-13T20:22:26.000Z"),
			halfTurnRequest(ts: "2026-07-13T20:24:25.000Z", loop: 2),
		])

		let events = completedEvents(root)
		XCTAssertEqual(events.map(\.messageId), ["e1-grok-4.7-r0", "e1-grok-4.7-r1"])
		XCTAssertEqual(events.map(\.requestId), ["p1", "p1"])
		XCTAssertEqual(events.map(\.model), ["grok-4.7", "grok-4.7"])
		XCTAssertEqual(
			events[0].timestamp, ISOTimestamp.parse("2026-07-13T20:22:26.000Z"),
			"each request keeps its own time")
		for event in events {
			XCTAssertEqual(event.usage, TokenUsage(input: 50_000, output: 600, cacheRead: 100_000))
		}

		let calculator = CostCalculator()
		let split = events.compactMap { calculator.cost(model: $0.model, usage: $0.usage) }.reduce(0, +)
		let turn = try XCTUnwrap(
			calculator.cost(model: "grok-4.7", usage: TokenUsage(input: 100_000, output: 1_200, cacheRead: 200_000)))
		// Base: 50K x $2 + 100K x $0.50 + 600 x $6 per MTok = $0.1536 per request.
		XCTAssertEqual(split, 0.3072, accuracy: 1e-9)
		// The same tokens tiered as one 300K request bill at 2x: $0.6144.
		XCTAssertEqual(turn, 0.6144, accuracy: 1e-9)
	}

	func testRequestsThatDoNotReconcileKeepOneUpperBoundTurnEvent() throws {
		// The log retained only the turn's last request, so the run never sums to the turn.
		let (root, _) = try stage([premiumTurn()])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeLog(root, lines: [halfTurnRequest(ts: "2026-07-13T20:24:25.000Z")])

		let events = completedEvents(root)
		XCTAssertEqual(events.map(\.messageId), ["e1-grok-4.7"])
		XCTAssertEqual(events[0].usage, TokenUsage(input: 100_000, output: 1_200, cacheRead: 200_000))

		// A run that overshoots the turn on any field stops the walk rather than skipping ahead.
		let oversized = GrokInferenceRound(
			sid: splitSid, timestamp: Date(timeIntervalSince1970: 1_783_974_200),
			usage: TokenUsage(input: 100_001, output: 1, cacheRead: 0))
		XCTAssertNil(
			GrokRequestRounds.rounds(
				forTurn: TokenUsage(input: 100_000, output: 1_200, cacheRead: 200_000),
				completedAt: Date(timeIntervalSince1970: 1_783_974_266), in: [oversized]))
	}

	func testMultiModelTurnIsNeverSplitByRequests() throws {
		// Requests carry no model, so a turn spread over several models stays one event per model.
		let (root, _) = try stage([
			turnCompletedMultiModel(
				eventId: "e1", promptId: "p1", sessionId: splitSid,
				models: [("grok-4.7", 1_000, 50, 0, 0), ("grok-composer-2.5", 500, 20, 0, 0)])
		])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeLog(root, lines: [
			inferenceDone(
				sid: splitSid, ts: "2026-07-13T20:24:25.000Z", prompt: 1_000, cached: 0, completion: 50,
				reasoning: 0)
		])

		let ids = completedEvents(root).map(\.messageId).sorted()
		XCTAssertEqual(ids, ["e1-grok-4.7", "e1-grok-composer-2.5"])
	}

	func testRequestsAfterTheTurnBelongToTheNextTurn() throws {
		let (root, _) = try stage([premiumTurn()])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeLog(root, lines: [
			halfTurnRequest(ts: "2026-07-13T20:23:26.000Z"),
			// Grok stamps the turn in whole seconds, so a request one second later still belongs to it.
			halfTurnRequest(ts: "2026-07-13T20:24:27.000Z", loop: 2),
			// The next turn's first request, still running.
			halfTurnRequest(ts: "2026-07-13T20:25:26.000Z"),
		])

		let events = completedEvents(root)
		XCTAssertEqual(events.map(\.messageId), ["e1-grok-4.7-r0", "e1-grok-4.7-r1"])
		XCTAssertEqual(events.last?.timestamp, ISOTimestamp.parse("2026-07-13T20:24:27.000Z"))
	}

	func testTwoTurnsInOneSessionEachClaimTheirOwnRequests() throws {
		let earlier = turnCompleted(
			eventId: "e0", promptId: "p0", sessionId: splitSid,
			input: 9_000, output: 90, cached: 0, reasoning: 0, model: "grok-4.7",
			ts: 1_783_974_266 - 300, agentMs: (1_783_974_266 - 300) * 1000 + 328)
		let (root, _) = try stage([earlier, premiumTurn()])
		defer { try? FileManager.default.removeItem(at: root) }
		try writeLog(root, lines: [
			inferenceDone(
				sid: splitSid, ts: "2026-07-13T20:14:26.000Z", prompt: 4_000, cached: 0, completion: 40,
				reasoning: 0),
			inferenceDone(
				sid: splitSid, ts: "2026-07-13T20:19:16.000Z", prompt: 5_000, cached: 0, completion: 50,
				reasoning: 0, loop: 2),
			halfTurnRequest(ts: "2026-07-13T20:23:26.000Z"),
			halfTurnRequest(ts: "2026-07-13T20:24:25.000Z", loop: 2),
		])

		let events = completedEvents(root)
		XCTAssertEqual(
			events.map(\.messageId), ["e0-grok-4.7-r0", "e0-grok-4.7-r1", "e1-grok-4.7-r0", "e1-grok-4.7-r1"])
		XCTAssertEqual(events.map(\.usage.input), [4_000, 5_000, 50_000, 50_000])
		XCTAssertEqual(events.map(\.requestId), ["p0", "p0", "p1", "p1"])
	}

	func testIndexedSplitTurnsIngestOnceAndMatchTheDirectRead() throws {
		let (root, file) = try stage([premiumTurn(eventId: "e0", promptId: "p0", secondsBefore: 300)])
		defer { try? FileManager.default.removeItem(at: root) }
		let firstTurnRequests = [
			halfTurnRequest(ts: "2026-07-13T20:14:26.000Z"),
			halfTurnRequest(ts: "2026-07-13T20:19:16.000Z", loop: 2),
		]
		try writeLog(root, lines: firstTurnRequests)

		let db = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-split-\(UUID().uuidString).sqlite")
		defer { try? FileManager.default.removeItem(at: db) }
		let index = try UsageIndex(path: db.path)
		let provider = GrokProvider(root: root)
		let indexer = UsageIndexer(index: index)

		XCTAssertEqual(try indexer.refresh(provider).eventsIngested, 2)
		XCTAssertEqual(try indexer.refresh(provider).eventsIngested, 0, "an unchanged session must not re-ingest")

		// The next turn's requests land in the log before its `turn_completed` line is appended.
		try writeLog(root, lines: firstTurnRequests + [
			halfTurnRequest(ts: "2026-07-13T20:23:26.000Z"),
			halfTurnRequest(ts: "2026-07-13T20:24:25.000Z", loop: 2),
		])
		let handle = try FileHandle(forWritingTo: file)
		defer { try? handle.close() }
		try handle.seekToEnd()
		try handle.write(contentsOf: Data((premiumTurn() + "\n").utf8))

		XCTAssertEqual(try indexer.refresh(provider).eventsIngested, 2, "only the appended turn's requests ingest")
		XCTAssertEqual(index.eventCount(provider: .grok), 4)
		XCTAssertEqual(
			completedEvents(root).map(\.messageId),
			["e0-grok-4.7-r0", "e0-grok-4.7-r1", "e1-grok-4.7-r0", "e1-grok-4.7-r1"])
	}
}
