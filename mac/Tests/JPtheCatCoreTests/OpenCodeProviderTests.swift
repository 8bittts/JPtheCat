import Foundation
import XCTest

@testable import JPtheCatCore

final class OpenCodeProviderTests: XCTestCase {
	// MARK: - opencode.db fixture helper

	private func stageDatabase(root: URL? = nil, rows: [(id: String, model: String?, tokens: (input: Int, output: Int, reasoning: Int, cacheRead: Int, cacheWrite: Int), timeCreatedMillis: Int, projectID: String?)])
		throws -> (root: URL, file: URL)
	{
		let root =
			root
			?? URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-opencode-db-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
			"""
		)
		for row in rows {
			let statement = try db.prepare(
				"""
				INSERT OR REPLACE INTO session
				  (id, project_id, slug, title, cost, tokens_input, tokens_output, tokens_reasoning,
				   tokens_cache_read, tokens_cache_write, model, time_created, time_updated)
				VALUES (?1, ?2, 'slug', 'title', 0, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)
				"""
			)
			statement.bind(1, row.id)
			statement.bind(2, row.projectID)
			statement.bind(3, row.tokens.input)
			statement.bind(4, row.tokens.output)
			statement.bind(5, row.tokens.reasoning)
			statement.bind(6, row.tokens.cacheRead)
			statement.bind(7, row.tokens.cacheWrite)
			statement.bind(8, row.model)
			statement.bind(9, row.timeCreatedMillis)
			_ = try statement.step()
		}
		return (root, file)
	}

	private func stage(_ lines: [String]) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-opencode-\(UUID().uuidString)", isDirectory: true)
		let logDir = root.appendingPathComponent("log", isDirectory: true)
		try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
		let file = logDir.appendingPathComponent("opencode.log")
		try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
		return (root, file)
	}

	private func sessionLine(
		session: String = "ses_1",
		run: String = "run_1",
		model: String = "google/gemini-3-pro-preview",
		input: Int = 1_000,
		output: Int = 200,
		reasoning: Int = 30,
		cacheRead: Int = 40,
		cacheWrite: Int = 50,
		directory: String = "/Users/example/Documents/JPtheCat"
	) -> String {
		"""
		timestamp=2026-07-07T01:02:03.456Z level=INFO run=\(run) message=updated id=\(session) directory=\(directory) model=\(model) cost=0.123 tokens.input=\(input) tokens.output=\(output) tokens.reasoning=\(reasoning) tokens.cache.read=\(cacheRead) tokens.cache.write=\(cacheWrite) time.updated=1783386123456
		"""
	}

	func testIsAvailableRequiresOpenCodeLogFile() throws {
		let (root, _) = try stage([])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(OpenCodeProvider(root: root).isAvailable())
		XCTAssertFalse(OpenCodeProvider(root: root.appendingPathComponent("missing")).isAvailable())
	}

	func testParsesTokenCountersWithoutReadingPromptPayloads() throws {
		let (root, _) = try stage([
			#"timestamp=2026-07-07T01:00:00.000Z level=INFO run=r message="user prompt" content="do not parse me" tokens.input=999"#,
			sessionLine(),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .opencode)
		XCTAssertEqual(event.messageId, "ses_1")
		XCTAssertEqual(event.requestId, "run_1")
		XCTAssertEqual(event.model, "gemini-3-pro-preview")
		XCTAssertEqual(event.project, "JPtheCat")
		XCTAssertEqual(event.usage.input, 1_000)
		XCTAssertEqual(event.usage.output, 230)
		XCTAssertEqual(event.usage.cacheRead, 40)
		XCTAssertEqual(event.usage.cacheCreate5m, 50)
		XCTAssertEqual(event.usage.cacheCreate1h, 0)
	}

	func testKeepsLargestCumulativeSessionSnapshot() throws {
		let (root, _) = try stage([
			sessionLine(input: 100, output: 10),
			sessionLine(input: 500, output: 80),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events[0].usage.input, 500)
		XCTAssertEqual(events[0].usage.output, 110)
	}

	func testModelFallsBackToOpenCodeWhenSessionRowHasOnlyTokens() throws {
		let event = OpenCodeProvider.decode(
			line:
				"timestamp=2026-07-07T01:00:00Z run=r message=updated id=ses model=undefined tokens.input=1 tokens.output=2 tokens.reasoning=0 tokens.cache.read=0 tokens.cache.write=0")
		XCTAssertEqual(event?.model, "opencode")
	}

	func testProviderPrefixedModelIDNormalizesForPricingLookup() {
		XCTAssertEqual(
			OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: "google/gemini-3-pro-preview", providerID: "opencode")),
			"gemini-3-pro-preview")
		XCTAssertEqual(
			OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: "anthropic/claude-opus-4-8", providerID: "opencode")),
			"claude-opus-4-8")
		XCTAssertEqual(
			OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: "deepseek-v4-flash-free", providerID: "opencode")),
			"deepseek-v4-flash-free")
	}

	func testQuotedFieldParserKeepsSpacesInDirectory() {
		let fields = OpenCodeProvider.parseFields(
			#"timestamp=2026-07-07T01:00:00Z directory="/Users/example/My Project" title="hello world" tokens.input=7"#)
		XCTAssertEqual(fields["directory"], "/Users/example/My Project")
		XCTAssertEqual(fields["title"], "hello world")
		XCTAssertEqual(fields["tokens.input"], "7")
	}

	func testIndexIngestTailsAppendOnlyLog() throws {
		let (root, file) = try stage([sessionLine(session: "ses_1", input: 100, output: 10)])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-opencode-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = OpenCodeProvider(root: root)
		let indexer = UsageIndexer(index: index)

		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .opencode), 1)

		let unchanged = try indexer.refresh(provider)
		XCTAssertEqual(unchanged.filesSkipped, 1)
		XCTAssertEqual(index.eventCount(provider: .opencode), 1)

		let appended = sessionLine(session: "ses_2", input: 200, output: 20)
		let handle = try FileHandle(forWritingTo: file)
		try handle.seekToEnd()
		try handle.write(contentsOf: Data((appended + "\n").utf8))
		try handle.close()

		let stats = try indexer.refresh(provider)
		XCTAssertEqual(stats.filesRead, 1)
		XCTAssertEqual(index.eventCount(provider: .opencode), 2)
	}

	// MARK: - opencode.db (SQLite)

	func testZenSonnet55UsesItsOwnCacheRateAndRepairsExistingIndex() throws {
		let now = Date(timeIntervalSince1970: 1_791_626_400)
		let (root, file) = try stageDatabase(rows: [
			(id: "ses_sonnet", model: #"{"id":"claude-sonnet-5-5","providerID":"opencode"}"#,
			 tokens: (input: 0, output: 0, reasoning: 0, cacheRead: 100_000, cacheWrite: 0),
			 timeCreatedMillis: Int(now.timeIntervalSince1970 * 1000), projectID: nil)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let provider = OpenCodeProvider(root: root)
		let direct = try XCTUnwrap(provider.loadEvents().first)
		XCTAssertEqual(direct.model, "claude-sonnet-5-5-zen")
		XCTAssertEqual(try XCTUnwrap(CostCalculator().cost(model: direct.model, usage: direct.usage)), 0.02, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(CostCalculator().cost(model: "claude-sonnet-5-5", usage: direct.usage)), 0.01, accuracy: 1e-12)
		let dbPath = NSTemporaryDirectory() + "jpc-sonnet-zen-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }
		let index = try UsageIndex(path: dbPath)
		let stale = UsageEvent(messageId: direct.messageId, requestId: direct.requestId, provider: .opencode,
			model: "claude-sonnet-5-5", timestamp: direct.timestamp, usage: direct.usage)
		try index.ingest([stale], sourcePath: file.path)
		let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
		try index.setCursor(path: file.path, size: try XCTUnwrap((attrs[.size] as? NSNumber)?.intValue),
			mtime: try XCTUnwrap((attrs[.modificationDate] as? Date)?.timeIntervalSince1970),
			offset: Int(now.timeIntervalSince1970 * 1000), ctime: try XCTUnwrap(FileCursor.changeTime(fileURL: file)),
			provider: .opencode, parserRevision: 3)
		XCTAssertEqual(try index.rollup(provider: .opencode, now: now).today.cost, 0.01, accuracy: 1e-12)
		let stats = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(stats.filesRead, 1)
		XCTAssertEqual(index.eventCount(provider: .opencode), 1)
		XCTAssertEqual(try index.rollup(provider: .opencode, now: now).today.cost, 0.02, accuracy: 1e-12)
		for gateway in ["anthropic", "opencode-go"] {
			XCTAssertEqual(OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: "claude-sonnet-5-5", providerID: gateway)), "claude-sonnet-5-5")
		}
		XCTAssertEqual(OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: "claude-sonnet-5-5-free", providerID: "opencode")), "claude-sonnet-5-5-free")
	}

	func testReadsSessionsFromDatabase() throws {
		let (root, _) = try stageDatabase(rows: [
			(
				id: "ses_db_1",
				model: #"{"id":"mimo-v2.5-free","providerID":"opencode"}"#,
				tokens: (input: 1_000, output: 200, reasoning: 30, cacheRead: 40, cacheWrite: 50),
				timeCreatedMillis: 1_783_386_123_456,
				projectID: "proj_abc"
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .opencode)
		XCTAssertEqual(event.messageId, "ses_db_1")
		XCTAssertEqual(event.requestId, "opencode-db")
		XCTAssertEqual(event.model, "mimo-v2.5-free")
		XCTAssertEqual(event.project, "proj_abc")
		XCTAssertEqual(event.usage.input, 1_000)
		XCTAssertEqual(event.usage.output, 230)
		XCTAssertEqual(event.usage.cacheRead, 40)
		XCTAssertEqual(event.usage.cacheCreate5m, 50)
		XCTAssertEqual(event.usage.cacheCreate1h, 0)
		XCTAssertEqual(event.timestamp.timeIntervalSince1970, 1_783_386_123.456, accuracy: 0.01)
	}

	func testDatabaseCumulativeUpdateReplacesNotAdds() throws {
		let (root, file) = try stageDatabase(rows: [
			(
				id: "ses_1", model: #"{"id":"big-pickle","providerID":"opencode"}"#,
				tokens: (input: 100, output: 10, reasoning: 0, cacheRead: 0, cacheWrite: 0),
				timeCreatedMillis: 1, projectID: nil
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-opencode-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = OpenCodeProvider(root: root)
		let indexer = UsageIndexer(index: index)

		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .opencode), 1)

		// Simulate OpenCode updating the session in place with a larger cumulative snapshot. Force a WAL
		// checkpoint so the change actually lands in the main file's on-disk size/mtime (real OpenCode
		// writes accumulate in -wal until its own periodic PASSIVE checkpoint; here we force TRUNCATE so
		// the fixture deterministically looks "changed" to FileCursor without waiting on that).
		let update = try SQLiteDatabase(path: file.path)
		try update.execute(
			"UPDATE session SET tokens_input = 500, tokens_output = 80, time_updated = 2 WHERE id = 'ses_1';"
		)
		try update.execute("PRAGMA wal_checkpoint(TRUNCATE);")

		let stats = try indexer.refresh(provider)
		XCTAssertEqual(stats.filesRead, 1)
		XCTAssertEqual(index.eventCount(provider: .opencode), 1)

		// A third refresh with nothing changed must not double-count or churn the row.
		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .opencode), 1)
	}

	func testFallsBackToFlatLogWhenDatabaseAbsent() throws {
		let (root, _) = try stage([sessionLine(session: "ses_log_only")])
		defer { try? FileManager.default.removeItem(at: root) }

		let provider = OpenCodeProvider(root: root)
		XCTAssertTrue(provider.isAvailable())
		let events = provider.loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events.first?.messageId, "ses_log_only")
		XCTAssertEqual(events.first?.requestId, "run_1")
	}

	func testPrefersDatabaseOverLogWhenBothPresent() throws {
		let (root, _) = try stageDatabase(rows: [
			(
				id: "ses_db_wins", model: #"{"id":"big-pickle","providerID":"opencode"}"#,
				tokens: (input: 10, output: 10, reasoning: 0, cacheRead: 0, cacheWrite: 0),
				timeCreatedMillis: 1, projectID: nil
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let logDir = root.appendingPathComponent("log", isDirectory: true)
		try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
		try (sessionLine(session: "ses_log_loses") + "\n")
			.write(to: logDir.appendingPathComponent("opencode.log"), atomically: true, encoding: .utf8)

		let provider = OpenCodeProvider(root: root)
		XCTAssertEqual(provider.dataFiles(), [provider.databaseFile()])
		let events = provider.loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events.first?.messageId, "ses_db_wins")
	}

	func testMalformedModelJSONFallsBackToPlainString() {
		XCTAssertEqual(
			OpenCodeModelColumn.parse("not json at all"),
			OpenCodeModelRef(modelID: "not json at all", providerID: nil))
		let parsed = OpenCodeModelColumn.parse(#"{"id":"anthropic/claude-opus-4-8","providerID":"opencode"}"#)
		XCTAssertEqual(parsed, OpenCodeModelRef(modelID: "anthropic/claude-opus-4-8", providerID: "opencode"))
		XCTAssertEqual(OpenCodeProvider.normalizeModel(parsed), "claude-opus-4-8")
		XCTAssertEqual(OpenCodeModelColumn.parse(nil), OpenCodeModelRef(modelID: nil, providerID: nil))
		XCTAssertEqual(OpenCodeModelColumn.parse(""), OpenCodeModelRef(modelID: nil, providerID: nil))
		XCTAssertEqual(OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: nil, providerID: nil)), "opencode")
	}

	func testSkipsEmptySessionRows() throws {
		let (root, _) = try stageDatabase(rows: [
			(
				id: "ses_empty", model: #"{"id":"big-pickle","providerID":"opencode"}"#,
				tokens: (input: 0, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0),
				timeCreatedMillis: 1, projectID: nil
			),
			(
				id: "ses_real", model: #"{"id":"big-pickle","providerID":"opencode"}"#,
				tokens: (input: 5, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0),
				timeCreatedMillis: 1, projectID: nil
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(events.map(\.messageId), ["ses_real"])
	}
}
