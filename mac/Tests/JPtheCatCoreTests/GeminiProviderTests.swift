import Foundation
import XCTest

@testable import JPtheCatCore

final class GeminiProviderTests: XCTestCase {
	// MARK: - Fixtures

	/// Stage one `~/.gemini/tmp`-shaped root with a session file under `<hash>/chats/session-*.json`.
	private func stage(
		_ json: String, hash: String = "h", name: String = "session-2026-07-01T00-00-00-aaaa.json"
	) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-gemini-\(UUID().uuidString)", isDirectory: true)
		let chats = root.appendingPathComponent(hash, isDirectory: true)
			.appendingPathComponent("chats", isDirectory: true)
		try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
		let file = chats.appendingPathComponent(name)
		try json.write(to: file, atomically: true, encoding: .utf8)
		return (root, file)
	}

	private func geminiMsg(
		id: String, input: Int, output: Int, cached: Int, thoughts: Int, tool: Int,
		model: String = "gemini-2.5-pro", ts: String = "2026-07-01T00:00:00.000Z"
	) -> String {
		"""
		{"id":"\(id)","timestamp":"\(ts)","type":"gemini","model":"\(model)","tokens":{"input":\(input),"output":\(output),"cached":\(cached),"thoughts":\(thoughts),"tool":\(tool)}}
		"""
	}

	private func session(sid: String, messages: [String]) -> String {
		"""
		{"sessionId":"\(sid)","projectHash":"h","startTime":"2026-07-01T00:00:00.000Z","lastUpdated":"2026-07-01T00:00:00.000Z","kind":"main","messages":[\(messages.joined(separator: ","))]}
		"""
	}

	// MARK: - Allowlist / availability

	func testStrictAllowlistIgnoresLogsAndCreds() throws {
		let (root, _) = try stage(
			session(sid: "s1", messages: [geminiMsg(id: "m1", input: 1000, output: 100, cached: 0, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		// The exact siblings Gemini writes next to a session dir. None match the 3-gate allowlist.
		let projectDir = root.appendingPathComponent("h", isDirectory: true)
		for decoy in ["logs.json", "oauth_creds.json", "installation_id"] {
			try "PROMPTS-OR-SECRET".write(
				to: projectDir.appendingPathComponent(decoy), atomically: true, encoding: .utf8)
		}
		// A logs.json even *inside* chats/ must be excluded (prefix gate, not just parent gate).
		try "[]".write(
			to: projectDir.appendingPathComponent("chats/logs.json"), atomically: true, encoding: .utf8)

		let provider = GeminiProvider(root: root)
		XCTAssertEqual(provider.sessionFiles().count, 1, "only session-*.json under chats/ is read")
		XCTAssertEqual(provider.loadEvents().count, 1)
	}

	func testIsAvailableReflectsRoot() throws {
		let (root, _) = try stage(session(sid: "s1", messages: [geminiMsg(id: "m1", input: 10, output: 1, cached: 0, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(GeminiProvider(root: root).isAvailable())
		XCTAssertFalse(
			GeminiProvider(root: root.appendingPathComponent("nope", isDirectory: true)).isAvailable())
	}

	// MARK: - Token mapping (the correctness core)

	func testTokenMappingSplitsCacheAndFoldsThoughts() throws {
		let (root, _) = try stage(
			session(sid: "s1", messages: [geminiMsg(id: "m1", input: 1000, output: 500, cached: 200, thoughts: 100, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		let events = GeminiProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let u = events[0].usage
		XCTAssertEqual(u.input, 800)  // 1000 - 200 cached
		XCTAssertEqual(u.cacheRead, 200)
		XCTAssertEqual(u.output, 600)  // 500 + 100 thoughts
		XCTAssertEqual(u.cacheCreate5m, 0)
		XCTAssertEqual(u.cacheCreate1h, 0)
		// Emitted total equals Gemini's own `total` (input+output+thoughts+tool = 1600).
		XCTAssertEqual(u.total, 1600)
		XCTAssertEqual(events[0].provider, .gemini)
		XCTAssertEqual(events[0].model, "gemini-2.5-pro")
		XCTAssertNil(events[0].project)
	}

	func testToolTokensFoldIntoInput() throws {
		let (root, _) = try stage(
			session(sid: "s1", messages: [geminiMsg(id: "m1", input: 1000, output: 0, cached: 200, thoughts: 0, tool: 50)]))
		defer { try? FileManager.default.removeItem(at: root) }
		let u = GeminiProvider(root: root).loadEvents()[0].usage
		XCTAssertEqual(u.input, 850)  // (1000 - 200) + 50 tool
		XCTAssertEqual(u.cacheRead, 200)
	}

	func testCachedGreaterThanInputClampsToZeroNeverNegative() throws {
		let (root, _) = try stage(
			session(sid: "s1", messages: [geminiMsg(id: "m1", input: 100, output: 10, cached: 300, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		let u = GeminiProvider(root: root).loadEvents()[0].usage
		XCTAssertEqual(u.input, 0)  // max(0, 100 - 300)
		XCTAssertEqual(u.cacheRead, 300)
	}

	func testZeroTokenTurnIsSkipped() throws {
		let (root, _) = try stage(
			session(sid: "s1", messages: [geminiMsg(id: "m1", input: 0, output: 0, cached: 0, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(GeminiProvider(root: root).loadEvents().count, 0)
	}

	func testUserMessagesAreSkipped() throws {
		let user = """
			{"id":"u1","timestamp":"2026-07-01T00:00:00.000Z","type":"user","message":"/init"}
			"""
		let (root, _) = try stage(
			session(sid: "s1", messages: [user, geminiMsg(id: "m1", input: 100, output: 10, cached: 0, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		let events = GeminiProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events[0].messageId, "m1")
	}

	// MARK: - Identity / dedupe / robustness

	func testSyntheticIdIsMessageUUIDScopedToSession() throws {
		let (root, _) = try stage(
			session(sid: "sess-9", messages: [geminiMsg(id: "uuid-1", input: 100, output: 10, cached: 0, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		let events = GeminiProvider(root: root).loadEvents()
		XCTAssertEqual(events[0].id, "uuid-1:sess-9")
		// Re-parsing the same file yields identical ids (idempotency for the keep-max upsert).
		XCTAssertEqual(
			GeminiProvider(root: root).loadEvents().map(\.id), events.map(\.id))
	}

	func testDuplicateMessageIdCollapsesToOne() throws {
		let (root, _) = try stage(
			session(
				sid: "s1",
				messages: [
					geminiMsg(id: "dup", input: 100, output: 10, cached: 0, thoughts: 0, tool: 0),
					geminiMsg(id: "dup", input: 999, output: 99, cached: 0, thoughts: 0, tool: 0),
				]))
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(GeminiProvider(root: root).loadEvents().count, 1)
	}

	func testTruncatedJsonYieldsNothingAndDoesNotThrow() throws {
		let (root, file) = try stage(session(sid: "s1", messages: [geminiMsg(id: "m1", input: 100, output: 10, cached: 0, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		// Half-written object (transient mid-write) — must fail closed, not crash.
		try #"{"sessionId":"s1","messages":[{"id":"m1","type":"gemini","tokens":{"inp"#.write(
			to: file, atomically: true, encoding: .utf8)
		XCTAssertEqual(GeminiProvider.parseUsage(fileURL: file).count, 0)
	}

	// MARK: - Index integration (whole-file re-read, net-new-only)

	func testIndexIngestIsIdempotentAndNetNewOnly() throws {
		let (root, file) = try stage(
			session(sid: "s1", messages: [geminiMsg(id: "m1", input: 1000, output: 100, cached: 0, thoughts: 0, tool: 0)]))
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-gtest-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }
		let index = try UsageIndex(path: dbPath)
		let gemini = GeminiProvider(root: root)

		_ = try UsageIndexer(index: index).refresh(gemini)
		XCTAssertEqual(index.eventCount(provider: .gemini), 1)

		// Re-ingest with no file change: idempotent, count unchanged.
		let stats = try UsageIndexer(index: index).refresh(gemini)
		XCTAssertEqual(index.eventCount(provider: .gemini), 1)
		XCTAssertEqual(stats.filesSkipped, 1, "unchanged file is skipped by the cursor fingerprint")

		// Append a turn to the whole-JSON file: re-read whole, net-new-only -> count grows by exactly 1.
		try session(
			sid: "s1",
			messages: [
				geminiMsg(id: "m1", input: 1000, output: 100, cached: 0, thoughts: 0, tool: 0),
				geminiMsg(id: "m2", input: 500, output: 50, cached: 0, thoughts: 0, tool: 0),
			]).write(to: file, atomically: true, encoding: .utf8)
		_ = try UsageIndexer(index: index).refresh(gemini)
		XCTAssertEqual(index.eventCount(provider: .gemini), 2)
	}
}
