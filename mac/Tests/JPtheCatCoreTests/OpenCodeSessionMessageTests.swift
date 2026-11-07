import Foundation
import XCTest

@testable import JPtheCatCore

/// OpenCode's session-v2 store writes assistant turns to `session_message` (role in the `type`
/// column, model under `$.model`) and stops appending to `message`. A live store migrated on
/// 2026-09-29 kept 16,091 legacy rows while every later turn landed only in `session_message`, so a
/// reader of `message` alone silently lost all post-migration usage for all seven OpenCode rows.
final class OpenCodeSessionMessageTests: XCTestCase {
	private struct Turn {
		let id: String
		let session: String
		let model: String
		let provider: String
		let tokens: (input: Int, output: Int, reasoning: Int, read: Int, write: Int)
		let created: Int
		var type = "assistant"
	}

	private var roots: [URL] = []

	override func tearDown() {
		for root in roots { try? FileManager.default.removeItem(at: root) }
		roots = []
		super.tearDown()
	}

	/// Stages a store with the real column layout of both generations. `legacy` rows go to `message`,
	/// `current` rows to `session_message`; `withLegacyTable: false` models a store created after the
	/// migration, which has no `message` table at all.
	private func stage(
		legacy: [Turn] = [], current: [Turn] = [], withLegacyTable: Bool = true
	) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-oc-v2-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		roots.append(root)
		let file = root.appendingPathComponent("opencode.db")
		let db = try SQLiteDatabase(path: file.path)
		try db.execute(
			"""
			CREATE TABLE session (
			  id TEXT PRIMARY KEY, project_id TEXT, model TEXT,
			  tokens_input INTEGER NOT NULL DEFAULT 0, tokens_output INTEGER NOT NULL DEFAULT 0,
			  tokens_reasoning INTEGER NOT NULL DEFAULT 0, tokens_cache_read INTEGER NOT NULL DEFAULT 0,
			  tokens_cache_write INTEGER NOT NULL DEFAULT 0, time_created INTEGER NOT NULL
			);
			CREATE TABLE session_v2 (id TEXT PRIMARY KEY, project_id TEXT, model TEXT, time_created INTEGER);
			CREATE TABLE session_message (
			  id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL,
			  time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL
			);
			INSERT INTO session_v2 (id, project_id, time_created) VALUES ('s-new', 'proj-v2', 1);
			""")
		if withLegacyTable {
			try db.execute(
				"""
				CREATE TABLE message (
				  id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL,
				  time_updated INTEGER NOT NULL, data TEXT NOT NULL
				);
				""")
		}
		for turn in legacy {
			let data: [String: Any] = [
				"role": turn.type, "modelID": turn.model, "providerID": turn.provider,
				"tokens": tokens(turn), "time": ["created": turn.created],
			]
			let stmt = try db.prepare(
				"INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?1, ?2, ?3, ?3, ?4)")
			stmt.bind(1, turn.id)
			stmt.bind(2, turn.session)
			stmt.bind(3, turn.created)
			stmt.bind(4, try json(data))
			_ = try stmt.step()
		}
		for (seq, turn) in current.enumerated() {
			let data: [String: Any] = [
				"model": ["id": turn.model, "providerID": turn.provider, "variant": "default"],
				"tokens": tokens(turn), "time": ["created": turn.created, "completed": turn.created + 1],
				"finish": "stop",
			]
			let stmt = try db.prepare(
				"""
				INSERT INTO session_message (id, session_id, type, seq, time_created, time_updated, data)
				VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)
				""")
			stmt.bind(1, turn.id)
			stmt.bind(2, turn.session)
			stmt.bind(3, turn.type)
			stmt.bind(4, seq)
			stmt.bind(5, turn.created)
			stmt.bind(6, try json(data))
			_ = try stmt.step()
		}
		return (root, file)
	}

	private func tokens(_ turn: Turn) -> [String: Any] {
		[
			"input": turn.tokens.input, "output": turn.tokens.output, "reasoning": turn.tokens.reasoning,
			"cache": ["read": turn.tokens.read, "write": turn.tokens.write],
		]
	}

	private func json(_ object: [String: Any]) throws -> String {
		String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
	}

	private let goTurn = Turn(
		id: "msg-go", session: "s-new", model: "deepseek-v4.1-flash", provider: "opencode-go",
		tokens: (1000, 200, 0, 5000, 0), created: 1_792_000_000_000)
	private let sparkTurn = Turn(
		id: "msg-spark", session: "s-new", model: "muse-spark-1.3", provider: "meta",
		tokens: (400, 100, 20, 0, 0), created: 1_792_000_100_000)

	/// A store created after the migration has no `message` table. Every row type still sees its turns,
	/// with the v2 session's project label, through both the direct and the indexed path.
	func testSessionMessageOnlyStoreFeedsEveryRow() throws {
		let (root, file) = try stage(current: [goTurn, sparkTurn], withLegacyTable: false)
		let go = OpenCodeGoProvider(root: root)
		let deepseek = OpenCodeBrandProvider(brand: .deepseek, root: root)
		let spark = MuseSparkProvider(root: root)

		let goEvents = go.loadEvents()
		XCTAssertEqual(goEvents.map(\.model), ["deepseek-v4.1-flash"])
		XCTAssertEqual(goEvents.first?.usage.cacheRead, 5000)
		XCTAssertEqual(goEvents.first?.project, "proj-v2")
		XCTAssertEqual(deepseek.loadEvents().map(\.messageId), ["msg-go"])
		let sparkEvents = spark.loadEvents()
		XCTAssertEqual(sparkEvents.map(\.model), ["muse-spark-1.3"])
		XCTAssertEqual(sparkEvents.first?.usage.output, 120, "reasoning counts as output")

		XCTAssertEqual(go.decodeFile(file, from: 0, parserState: nil).events.map(\.messageId), ["msg-go"])
		XCTAssertEqual(spark.decodeFile(file, from: 0, parserState: nil).events.map(\.messageId), ["msg-spark"])
	}

	/// The migration copies every legacy row into `session_message`; later turns exist only there.
	/// A copied turn counts once, the post-migration turn counts, and user/compaction rows never count.
	func testMigratedRowsCountOnceAndPostMigrationRowsAreRead() throws {
		let migrated = Turn(
			id: "msg-old", session: "s-old", model: "deepseek-v4.1-flash", provider: "opencode-go",
			tokens: (300, 30, 0, 0, 0), created: 1_790_000_000_000)
		let user = Turn(id: "msg-user", session: "s-new", model: "deepseek-v4.1-flash", provider: "opencode-go",
			tokens: (999, 999, 0, 0, 0), created: 1_792_000_000_500, type: "user")
		let (root, _) = try stage(legacy: [migrated], current: [migrated, goTurn, user])
		let provider = OpenCodeGoProvider(root: root)

		let events = provider.loadEvents()
		XCTAssertEqual(events.map(\.messageId).sorted(), ["msg-go", "msg-old"])
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.input }, 1300)

		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .opencodego), 2)
	}

	/// When both tables hold the same id, the `session_message` copy is the one current OpenCode edits,
	/// so its counts win over the frozen legacy copy.
	func testSessionMessageCopyWinsOverTheLegacyCopy() throws {
		let legacyCopy = Turn(
			id: "msg-go", session: "s-new", model: "deepseek-v4.1-flash", provider: "opencode-go",
			tokens: (1, 1, 0, 0, 0), created: goTurn.created)
		let (root, _) = try stage(legacy: [legacyCopy], current: [goTurn])
		let events = OpenCodeGoProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events.first?.usage.input, 1000)
	}

	/// An edit to an older `session_message` row below the watermark must reach the index, exactly as
	/// it does for `message` (`replacementStart` covers both tables).
	func testOlderSessionMessageEditReachesTheIndex() throws {
		let older = Turn(
			id: "msg-older", session: "s-new", model: "deepseek-v4.1-flash", provider: "opencode-go",
			tokens: (100, 10, 0, 0, 0), created: 1_791_900_000_000)
		let (root, file) = try stage(current: [older, goTurn], withLegacyTable: false)
		let provider = OpenCodeGoProvider(root: root)
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		try UsageIndexer(index: index).refresh(provider)

		let source = try SQLiteDatabase(path: file.path)
		try source.execute(
			"""
			UPDATE session_message SET data = json_set(data, '$.tokens.output', 900),
			  time_updated = 1792000200000 WHERE id = 'msg-older';
			""")
		try UsageIndexer(index: index).refresh(provider)
		let rollup = try index.rollup(
			provider: .opencodego, days: 7, now: Date(timeIntervalSince1970: 1_792_100_000))
		XCTAssertEqual(rollup.last7d.usage.output, provider.loadEvents().reduce(0) { $0 + $1.usage.output })
		XCTAssertEqual(provider.loadEvents().first { $0.messageId == "msg-older" }?.usage.output, 900)
	}

	/// The shared availability probe must see models that exist only in `session_message`; otherwise
	/// every row stays hidden on a post-migration store.
	func testDetectionSeesSessionMessageModels() throws {
		let (_, file) = try stage(current: [goTurn, sparkTurn], withLegacyTable: false)
		let detection = OpenCodeDetection.probe(fileURL: file)
		XCTAssertTrue(detection.go)
		XCTAssertTrue(detection.museSpark)
		XCTAssertEqual(detection.brands, [.deepseek])
		XCTAssertFalse(detection.zen)
	}

	/// A malformed `session_message` row must fail the scan, never read as a shorter total.
	func testMalformedSessionMessageFailsTheIndexedScan() throws {
		let (root, file) = try stage(current: [goTurn], withLegacyTable: false)
		let provider = OpenCodeGoProvider(root: root)
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		try UsageIndexer(index: index).refresh(provider)
		let source = try SQLiteDatabase(path: file.path)
		try source.execute("UPDATE session_message SET data = 'broken json', time_updated = 1792000300000;")
		XCTAssertThrowsError(try UsageIndexer(index: index).refresh(provider))
		XCTAssertEqual(index.eventCount(provider: .opencodego), 1)
	}
}
