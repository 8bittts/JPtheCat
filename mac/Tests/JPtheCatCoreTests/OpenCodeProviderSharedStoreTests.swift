import Foundation
import XCTest

@testable import JPtheCatCore

/// `OpenCodeProvider` and `MuseSparkProvider` read the SAME `~/.local/share/opencode` tree and differ
/// only in how they filter its rows. These guards pin the two things that used to be duplicated:
/// path resolution, and the traversal of the legacy `opencode.log` (which was fully streamed — and
/// re-`parseFields`-ed line by line — once per provider per refresh).
final class OpenCodeProviderSharedStoreTests: XCTestCase {
	private func tempDirectory() throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-opencode-shared-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func line(session: String, model: String, input: Int) -> String {
		"timestamp=2026-07-07T01:02:03.456Z level=INFO run=run_1 message=updated id=\(session) "
			+ "directory=/Users/e/Proj model=\(model) tokens.input=\(input) tokens.output=10 "
			+ "tokens.reasoning=0 tokens.cache.read=0 tokens.cache.write=0"
	}

	private func stageLog(_ lines: [String]) throws -> (root: URL, file: URL) {
		let root = try tempDirectory()
		let logDir = root.appendingPathComponent("log", isDirectory: true)
		try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
		let file = logDir.appendingPathComponent("opencode.log")
		try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
		return (root, file)
	}

	// MARK: - Path resolution

	func testBothProvidersResolveTheSamePathsFromTheSameRoot() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(
			OpenCodeProvider(root: root).databaseFile(), MuseSparkProvider(root: root).databaseFile())
		XCTAssertEqual(
			OpenCodeStorePaths.databaseFile(root: root), root.appendingPathComponent("opencode.db"))
		XCTAssertEqual(
			OpenCodeStorePaths.logFile(root: root),
			root.appendingPathComponent("log", isDirectory: true)
				.appendingPathComponent("opencode.log"))
		// A root that already points AT a file is honoured, which fixtures and the indexer both rely on.
		let db = root.appendingPathComponent("x.db")
		XCTAssertEqual(OpenCodeStorePaths.databaseFile(root: db), db)
		let log = root.appendingPathComponent("x.log")
		XCTAssertEqual(OpenCodeStorePaths.logFile(root: log), log)
	}

	func testDataFilesPreferTheDatabaseAndNeverReturnBoth() throws {
		let (root, _) = try stageLog([line(session: "ses_log", model: "openai/gpt-5", input: 1)])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(
			OpenCodeProvider(root: root).dataFiles(), [OpenCodeStorePaths.logFile(root: root)])

		FileManager.default.createFile(
			atPath: OpenCodeStorePaths.databaseFile(root: root).path, contents: Data())
		XCTAssertEqual(
			OpenCodeProvider(root: root).dataFiles(), [OpenCodeStorePaths.databaseFile(root: root)])
		XCTAssertEqual(
			MuseSparkProvider(root: root).dataFiles(), OpenCodeProvider(root: root).dataFiles())
	}

	// MARK: - One log traversal, two filters

	func testBothProvidersShareOneLegacyLogTraversal() throws {
		let (root, _) = try stageLog([
			line(session: "ses_oc", model: "openai/gpt-5", input: 100),
			line(session: "ses_spark", model: "meta/muse-spark-1.1", input: 200),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let before = OpenCodeLogReader.traversalCount
		let openCode = OpenCodeProvider(root: root).loadEvents()
		let spark = MuseSparkProvider(root: root).loadEvents()
		let traversals = OpenCodeLogReader.traversalCount - before

		XCTAssertEqual(openCode.map(\.messageId), ["ses_oc"])
		XCTAssertEqual(spark.map(\.messageId), ["ses_spark"])
		XCTAssertEqual(spark.first?.provider, .museSpark)
		XCTAssertEqual(
			traversals, 1,
			"the same opencode.log was streamed once per provider before the shared traversal landed")

		// A repeat pass over an unchanged file costs no traversal at all.
		_ = OpenCodeProvider(root: root).loadEvents()
		_ = MuseSparkProvider(root: root).loadEvents()
		XCTAssertEqual(OpenCodeLogReader.traversalCount - before, 1)
	}

	/// [Regression guard] `(size, mtime)` alone is the v1.013-v1.015 correctness hole: a mtime-preserving
	/// rewrite leaves both identical while the bytes change. The cache key includes `ctime`, which the
	/// kernel bumps regardless.
	func testLogCacheInvalidatesOnSameSizeSameMtimeRewrite() throws {
		let (root, file) = try stageLog([line(session: "ses_a", model: "openai/gpt-5", input: 100)])
		defer { try? FileManager.default.removeItem(at: root) }

		let first = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(first.map(\.messageId), ["ses_a"])
		let mtime = try XCTUnwrap(
			FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)

		// Same byte length ("ses_a" -> "ses_b"), mtime deliberately restored.
		try (line(session: "ses_b", model: "openai/gpt-5", input: 100) + "\n")
			.write(to: file, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)

		XCTAssertEqual(OpenCodeProvider(root: root).loadEvents().map(\.messageId), ["ses_b"])
	}

	// MARK: - One connection

	func testStoreServesEveryScanFromOneReadOnlyConnection() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("opencode.db")
		let db = try SQLiteDatabase(path: file.path)
		try db.execute(
			"""
			CREATE TABLE session (
			  id TEXT PRIMARY KEY, project_id TEXT, slug TEXT, title TEXT,
			  cost REAL NOT NULL DEFAULT 0, tokens_input INTEGER NOT NULL DEFAULT 0,
			  tokens_output INTEGER NOT NULL DEFAULT 0, tokens_reasoning INTEGER NOT NULL DEFAULT 0,
			  tokens_cache_read INTEGER NOT NULL DEFAULT 0, tokens_cache_write INTEGER NOT NULL DEFAULT 0,
			  model TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL
			);
			CREATE TABLE message (
			  id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL,
			  time_updated INTEGER NOT NULL, data TEXT NOT NULL
			);
			INSERT INTO session VALUES
			  ('ses_1','proj_a','s','t',0,100,10,0,0,0,'{"id":"muse-spark-1.1","providerID":"meta"}',5,5);
			""")
		try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")

		let store = try XCTUnwrap(OpenCodeStore(fileURL: file))
		let refs = try XCTUnwrap(store.distinctModelRefs())
		XCTAssertEqual(refs, [OpenCodeModelRef(modelID: "muse-spark-1.1", providerID: "meta")])
		XCTAssertTrue(OpenCodeDetection.classify(refs).museSpark)
		XCTAssertEqual(store.projectIDsBySession(), ["ses_1": "proj_a"])
		XCTAssertTrue(store.modelMessageTotals("%muse-spark%").isEmpty)
		var sessions: [String] = []
		try store.forEachSession { sessions.append($0.id) }
		XCTAssertEqual(sessions, ["ses_1"])
		var messages = 0
		try store.forEachAssistantMessage(createdAtOrAfterMillis: 0) { _ in messages += 1 }
		XCTAssertEqual(messages, 0)
	}

	/// The store never opens (let alone creates) a file that is not a real database.
	func testStoreReturnsNilForAnUnreadableDatabase() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let missing = root.appendingPathComponent("absent.db")
		XCTAssertNil(OpenCodeStore(fileURL: missing))
		XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
	}
}
