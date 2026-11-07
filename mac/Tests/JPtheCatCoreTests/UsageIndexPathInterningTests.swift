import Foundation
import XCTest

@testable import JPtheCatCore

/// `events.source_path` stored a full absolute path on every row across only ~13.7K distinct values;
/// interning into a `paths` table cut the real 378 MB index by ~31%.
///
/// This runs against LIVE USER DATA on every existing install, so these guards pin the three
/// non-negotiables: it is crash-safe, it is idempotent, and it is not a data change.
final class UsageIndexPathInterningTests: XCTestCase {
	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-intern-\(UUID().uuidString).sqlite").path
	}

	/// Builds a database in the PRE-interning shape and fills it with events through the legacy
	/// `source_path` column — the exact on-disk state every existing install upgrades from.
	private func stageLegacyDatabase(rows: [(msg: String, model: String, ts: Double, output: Int, path: String?)])
		throws -> String
	{
		let path = tempDBPath()
		let db = try SQLiteDatabase(path: path)
		try db.execute(
			"""
			CREATE TABLE events (
			  provider TEXT NOT NULL, msg_id TEXT NOT NULL, req_id TEXT NOT NULL,
			  model TEXT NOT NULL, ts REAL NOT NULL, project TEXT,
			  input INTEGER NOT NULL, output INTEGER NOT NULL,
			  cache5m INTEGER NOT NULL, cache1h INTEGER NOT NULL, cache_read INTEGER NOT NULL,
			  source_path TEXT,
			  PRIMARY KEY (provider, msg_id, req_id)
			) WITHOUT ROWID;
			CREATE INDEX idx_events_ts ON events(ts);
			CREATE INDEX idx_events_scan
			  ON events(provider, ts, model, input, output, cache5m, cache1h, cache_read);
			CREATE INDEX idx_events_source_tail ON events(substr(source_path, -24));
			CREATE TABLE cursors (
			  path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime REAL NOT NULL, offset INTEGER NOT NULL,
			  fingerprint TEXT NOT NULL DEFAULT '', ctime REAL NOT NULL DEFAULT 0,
			  provider TEXT NOT NULL DEFAULT '', parser_revision INTEGER NOT NULL DEFAULT 1
			) WITHOUT ROWID;
			""")
		let insert = try db.prepare(
			"INSERT INTO events (provider, msg_id, req_id, model, ts, project, input, output, cache5m, cache1h, cache_read, source_path) "
				+ "VALUES ('claude', ?1, 'r', ?2, ?3, 'proj', 1000, ?4, 0, 0, 0, ?5);")
		for row in rows {
			insert.bind(1, row.msg)
			insert.bind(2, row.model)
			insert.bind(3, row.ts)
			insert.bind(4, row.output)
			insert.bind(5, row.path)
			_ = try insert.step()
			insert.reset()
		}
		return path
	}

	private func legacyRows() -> [(msg: String, model: String, ts: Double, output: Int, path: String?)] {
		let day = 86_400.0
		let base = 1_783_000_000.0
		return [
			("m1", "claude-opus-4-8", base, 10, "/Users/x/.claude/projects/alpha/session-01.jsonl"),
			("m2", "claude-opus-4-8", base + day, 20, "/Users/x/.claude/projects/alpha/session-01.jsonl"),
			("m3", "claude-sonnet-4-8", base + 2 * day, 30, "/Users/x/.claude/projects/beta/session-02.jsonl"),
			("m4", "claude-sonnet-4-8", base + 3 * day, 40, nil),  // a row that never had a source path
		]
	}

	private func indexExists(_ db: SQLiteDatabase, _ name: String) throws -> Bool {
		let s = try db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name = ?1;")
		s.bind(1, name)
		let found = try s.step()
		s.reset()
		return found
	}

	private func columnExists(_ db: SQLiteDatabase, _ column: String) throws -> Bool {
		let s = try db.prepare("SELECT 1 FROM pragma_table_info('events') WHERE name = ?1;")
		s.bind(1, column)
		let found = try s.step()
		s.reset()
		return found
	}

	/// Single-value probe on an inspection connection. `reset()` is LOAD-BEARING, not tidiness: a
	/// statement left parked in `SQLITE_ROW` holds an open read snapshot, which pins this connection to
	/// the PRE-migration schema and makes every later probe report the interned-away column as still
	/// present. (The same hazard `UsageIndex.cursor(for:)` documents, observed here first-hand.)
	private func scalar(_ db: SQLiteDatabase, _ sql: String) throws -> Int {
		let s = try db.prepare(sql)
		guard try s.step() else { return -1 }
		let value = s.int(0)
		s.reset()
		return value
	}

	private func text(_ db: SQLiteDatabase, _ sql: String) throws -> String? {
		let s = try db.prepare(sql)
		guard try s.step() else { return nil }
		let value = s.text(0)
		s.reset()
		return value
	}

	// MARK: - The migration itself

	func testMigrationInternsEveryPathAndDropsTheWideColumn() throws {
		let path = try stageLegacyDatabase(rows: legacyRows())
		let index = try UsageIndex(path: path)
		// Pre-migration the legacy column is still authoritative and must still read correctly.
		XCTAssertEqual(
			try index.sourcePaths(provider: .claude),
			[
				"/Users/x/.claude/projects/alpha/session-01.jsonl",
				"/Users/x/.claude/projects/beta/session-02.jsonl",
			])

		try index.migrateSourcePathIndexIfNeeded()

		let db = try SQLiteDatabase(path: path)
		XCTAssertFalse(try columnExists(db, "source_path"), "the wide column must be gone")
		XCTAssertTrue(try columnExists(db, "path_id"))
		XCTAssertTrue(try indexExists(db, "idx_events_path_id"))
		XCTAssertFalse(try indexExists(db, "idx_events_source_tail"))
		XCTAssertTrue(try indexExists(db, "idx_events_scan"), "the covering money-scan index must survive")

		// Exactly one `paths` row per DISTINCT path — the whole point of the change.
		XCTAssertEqual(try scalar(db, "SELECT count(*) FROM paths;"), 2)
		XCTAssertEqual(
			try index.sourcePaths(provider: .claude),
			[
				"/Users/x/.claude/projects/alpha/session-01.jsonl",
				"/Users/x/.claude/projects/beta/session-02.jsonl",
			], "path provenance must read identically after interning")
		XCTAssertEqual(index.eventCount(provider: .claude), 4, "including the NULL-path row")
	}

	/// Running twice must be a no-op the second time — it is scheduled on EVERY launch.
	func testMigrationIsIdempotent() throws {
		let path = try stageLegacyDatabase(rows: legacyRows())
		let index = try UsageIndex(path: path)
		try index.migrateSourcePathIndexIfNeeded()
		let after = try index.sourcePaths(provider: .claude)

		try index.migrateSourcePathIndexIfNeeded()
		try index.migrateSourcePathIndexIfNeeded()
		XCTAssertEqual(try index.sourcePaths(provider: .claude), after)
		XCTAssertEqual(index.eventCount(provider: .claude), 4)

		let db = try SQLiteDatabase(path: path)
		XCTAssertEqual(
			try scalar(db, "SELECT count(*) FROM paths;"), 2, "a re-run must not duplicate interned paths")

		// A brand-new index over the already-migrated file must also see it as done.
		let reopened = try UsageIndex(path: path)
		try reopened.migrateSourcePathIndexIfNeeded()
		XCTAssertEqual(try reopened.sourcePaths(provider: .claude), after)
	}

	// MARK: - Not a data change

	/// [Money-safety] The migration touches provenance ONLY. Every aggregate the dashboard, widgets,
	/// analytics tray and CSV export read must come out byte-identical.
	func testAggregateOutputIsIdenticalBeforeAndAfter() throws {
		let path = try stageLegacyDatabase(rows: legacyRows())
		let index = try UsageIndex(path: path)
		let now = Date(timeIntervalSince1970: 1_783_000_000 + 4 * 86_400)
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone.current
		let providers: [ProviderID] = [.claude]

		func snapshot() throws -> (rollup: UsageRollup, series: [Double], rows: [ModelDaySummary],
			projects: [ProjectCostSummary], windows: UsageMultiWindowSummaries)
		{
			(
				try index.rollup(provider: .claude, days: 30, now: now, calendar: calendar),
				try index.dailyCostSeries(provider: .claude, days: 30, now: now, calendar: calendar),
				try index.modelDaySummaries(providers: providers, days: 30, now: now, calendar: calendar),
				try index.projectCostSummaries(providers: providers, days: 30, now: now, calendar: calendar),
				try index.multiWindowSummaries(providers: providers, windows: [7, 30], now: now, calendar: calendar)
			)
		}

		let before = try snapshot()
		try index.migrateSourcePathIndexIfNeeded()
		let after = try snapshot()

		XCTAssertEqual(after.rollup.last7d.cost, before.rollup.last7d.cost, accuracy: 1e-12)
		XCTAssertEqual(after.rollup.last7d.eventCount, before.rollup.last7d.eventCount)
		XCTAssertEqual(after.rollup.last7d.usage.output, before.rollup.last7d.usage.output)
		XCTAssertEqual(after.series, before.series)
		XCTAssertEqual(after.rows, before.rows)
		XCTAssertEqual(after.projects, before.projects)
		for days in [7, 30] {
			XCTAssertEqual(
				after.windows.byDays[days]?.aggregate.dailyCostSeries,
				before.windows.byDays[days]?.aggregate.dailyCostSeries, "window \(days)")
			XCTAssertEqual(
				after.windows.byDays[days]?.aggregate.rollup.last7d.cost ?? -1,
				before.windows.byDays[days]?.aggregate.rollup.last7d.cost ?? -2,
				accuracy: 1e-12, "window \(days)")
		}
		XCTAssertGreaterThan(before.rollup.last7d.cost, 0, "the fixture must actually carry money")
	}

	// MARK: - Crash safety

	/// [Crash safety — the in-process failure] `sqlite3_exec` halts a multi-statement string at the
	/// first failure and RETURNS WITH THE TRANSACTION STILL OPEN. An index over `source_path` that the
	/// migration does not know to drop makes `ALTER TABLE … DROP COLUMN` fail exactly there. The
	/// database must come out readable and UNCHANGED, the connection must not be wedged, and a re-run
	/// once the blocker is gone must complete the migration.
	func testAFailedMigrationRollsBackFullyAndLeavesTheConnectionUsable() throws {
		let path = try stageLegacyDatabase(rows: legacyRows())
		let blocker = try SQLiteDatabase(path: path)
		try blocker.execute("CREATE INDEX idx_evil ON events(source_path, ts);")

		let index = try UsageIndex(path: path)
		XCTAssertThrowsError(try index.migrateSourcePathIndexIfNeeded())

		// Readable, correct, and still in the pre-migration shape — never half-interned.
		let db = try SQLiteDatabase(path: path)
		XCTAssertTrue(try columnExists(db, "source_path"))
		XCTAssertEqual(try text(db, "PRAGMA integrity_check;"), "ok")
		XCTAssertEqual(
			try scalar(db, "SELECT count(*) FROM paths;"), 0,
			"the backfill must have rolled back with everything else")
		XCTAssertEqual(index.eventCount(provider: .claude), 4)
		XCTAssertEqual(try index.sourcePaths(provider: .claude).count, 2)

		// [CRITICAL] The ROLLBACK must have run: a still-open transaction wedges every later ingest with
		// "cannot start a transaction within a transaction" for the rest of the process.
		try index.ingest(
			[
				UsageEvent(
					messageId: "m9", requestId: "r", provider: .claude, model: "claude-opus-4-8",
					timestamp: Date(timeIntervalSince1970: 1_783_000_000), usage: TokenUsage(output: 5))
			], sourcePath: "/Users/x/.claude/projects/alpha/session-01.jsonl")
		XCTAssertEqual(index.eventCount(provider: .claude), 5)

		// Re-run once the blocker is gone: the migration completes, losing nothing.
		try blocker.execute("DROP INDEX idx_evil;")
		try index.migrateSourcePathIndexIfNeeded()
		XCTAssertFalse(try columnExists(db, "source_path"))
		XCTAssertEqual(index.eventCount(provider: .claude), 5)
		XCTAssertEqual(try index.sourcePaths(provider: .claude).count, 2)
	}

	/// [Crash safety — the kill -9 analogue] Interrupt the migration between its backfill and its
	/// `DROP COLUMN` by tearing the connection down with the transaction still open, which is what
	/// SQLite recovers from after a hard kill. The file must be readable and unchanged, and a fresh
	/// `UsageIndex` must complete the migration.
	func testAnInterruptedMigrationLeavesACorrectDatabaseAndARerunCompletesIt() throws {
		let path = try stageLegacyDatabase(rows: legacyRows())
		do {
			// The migration's own first two statements, then a hard teardown instead of the COMMIT.
			let doomed = try SQLiteDatabase(path: path)
			try doomed.execute("CREATE TABLE IF NOT EXISTS paths (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE);")
			try doomed.execute("ALTER TABLE events ADD COLUMN path_id INTEGER;")
			try doomed.execute(
				"""
				BEGIN IMMEDIATE;
				INSERT OR IGNORE INTO paths (path)
				  SELECT DISTINCT source_path FROM events WHERE source_path IS NOT NULL;
				UPDATE events SET path_id = (SELECT id FROM paths WHERE paths.path = events.source_path)
				  WHERE path_id IS NULL AND source_path IS NOT NULL;
				""")
		}  // `deinit` -> sqlite3_close_v2 with an open write transaction == the crash SQLite recovers from

		let db = try SQLiteDatabase(path: path)
		XCTAssertEqual(try text(db, "PRAGMA integrity_check;"), "ok")

		let index = try UsageIndex(path: path)
		XCTAssertEqual(index.eventCount(provider: .claude), 4, "no event may be lost to the interruption")
		try index.migrateSourcePathIndexIfNeeded()
		XCTAssertFalse(try columnExists(db, "source_path"))
		XCTAssertEqual(index.eventCount(provider: .claude), 4)
		XCTAssertEqual(
			try index.sourcePaths(provider: .claude),
			[
				"/Users/x/.claude/projects/alpha/session-01.jsonl",
				"/Users/x/.claude/projects/beta/session-02.jsonl",
			])
	}

	// MARK: - The pre-migration window

	/// Between an upgrade launch and the off-main migration the database is still legacy-shaped, and
	/// `deleteEvents` must still find rows this session INGESTED — the case that breaks if the upsert
	/// writes only `path_id` while the delete still matches on `source_path`.
	func testIngestAndDeleteStayConsistentBeforeTheMigrationRuns() throws {
		let path = try stageLegacyDatabase(rows: legacyRows())
		let index = try UsageIndex(path: path)
		let fresh = "/Users/x/.claude/projects/gamma/session-03.jsonl"
		try index.ingest(
			[
				UsageEvent(
					messageId: "m5", requestId: "r", provider: .claude, model: "claude-opus-4-8",
					timestamp: Date(timeIntervalSince1970: 1_783_000_000), usage: TokenUsage(output: 7))
			], sourcePath: fresh)
		XCTAssertTrue(try index.sourcePaths(provider: .claude).contains(fresh))

		try index.deleteEvents(sourcePath: fresh)
		XCTAssertFalse(
			try index.sourcePaths(provider: .claude).contains(fresh),
			"a delete during the pre-migration window must find the rows that window ingested")
		XCTAssertEqual(index.eventCount(provider: .claude), 4)

		// And the row ingested during that window still interns correctly once the migration runs.
		try index.ingest(
			[
				UsageEvent(
					messageId: "m6", requestId: "r", provider: .claude, model: "claude-opus-4-8",
					timestamp: Date(timeIntervalSince1970: 1_783_000_000), usage: TokenUsage(output: 7))
			], sourcePath: fresh)
		try index.migrateSourcePathIndexIfNeeded()
		XCTAssertTrue(try index.sourcePaths(provider: .claude).contains(fresh))
		try index.deleteEvents(sourcePath: fresh)
		XCTAssertFalse(try index.sourcePaths(provider: .claude).contains(fresh))
		XCTAssertEqual(index.eventCount(provider: .claude), 4)
	}

	// MARK: - Downgrade

	/// [The rejected design's one real hazard, closed] A `source_path` normalization was reviewed and
	/// rejected once because the DOWNGRADE path degraded SILENTLY: an older build hit
	/// `CREATE INDEX … ON events(source_path)` in its `createSchema()`, threw `no such column`, made
	/// `UsageIndex.init` throw, and `StatusBarController`'s `try?` left `index = nil` — every retained
	/// event beyond the providers' own log retention vanished from the user's totals, with no error.
	/// Reachable via a stale DMG or the Homebrew cask, so it is not hypothetical.
	///
	/// This replays an older build's ENTIRE schema prologue verbatim against a migrated database. It
	/// must not throw, must not lose an event, and re-upgrading must re-intern cleanly.
	func testAnOlderBuildOpeningAMigratedDatabaseLosesNothing() throws {
		let path = try stageLegacyDatabase(rows: legacyRows())
		let index = try UsageIndex(path: path)
		try index.migrateSourcePathIndexIfNeeded()
		XCTAssertEqual(index.eventCount(provider: .claude), 4)

		// An older build's `createSchema()`, statement for statement.
		let old = try SQLiteDatabase(path: path)
		XCTAssertNoThrow(
			try old.execute(
				"""
				CREATE TABLE IF NOT EXISTS events (
				  provider TEXT NOT NULL, msg_id TEXT NOT NULL, req_id TEXT NOT NULL,
				  model TEXT NOT NULL, ts REAL NOT NULL, project TEXT,
				  input INTEGER NOT NULL, output INTEGER NOT NULL,
				  cache5m INTEGER NOT NULL, cache1h INTEGER NOT NULL, cache_read INTEGER NOT NULL,
				  source_path TEXT,
				  PRIMARY KEY (provider, msg_id, req_id)
				) WITHOUT ROWID;
				CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
				"""))
		try? old.execute("ALTER TABLE events ADD COLUMN source_path TEXT;")
		// The old `migrateSourcePathIndexIfNeeded`, which is where the silent failure used to live.
		XCTAssertNoThrow(
			try old.execute(
				"CREATE INDEX IF NOT EXISTS idx_events_source_tail ON events(substr(source_path, -24));"))
		XCTAssertEqual(
			try scalar(old, "SELECT count(*) FROM events;"), 4,
			"a downgraded build must still see every retained event")

		// Re-upgrading re-interns the resurrected column without disturbing the already-interned rows.
		let reupgraded = try UsageIndex(path: path)
		try reupgraded.migrateSourcePathIndexIfNeeded()
		XCTAssertEqual(reupgraded.eventCount(provider: .claude), 4)
		XCTAssertEqual(
			try reupgraded.sourcePaths(provider: .claude),
			[
				"/Users/x/.claude/projects/alpha/session-01.jsonl",
				"/Users/x/.claude/projects/beta/session-02.jsonl",
			], "the interned provenance must survive a downgrade-and-back round trip")
		let db = try SQLiteDatabase(path: path)
		XCTAssertFalse(try columnExists(db, "source_path"))
		XCTAssertEqual(try scalar(db, "SELECT count(*) FROM paths;"), 2, "no path may be re-interned twice")
	}

	// MARK: - Range-scoped delete

	/// `deleteEvents(sourcePath:timestampAtOrAfter:)` must remove exactly the suffix at or after the
	/// bound, for that path ONLY — never another file's rows, never the retained history below it.
	func testRangeScopedDeleteRemovesOnlyTheSuffixOfThatPath() throws {
		let index = try UsageIndex(path: tempDBPath())
		let base = 1_783_000_000.0
		func event(_ id: String, _ offset: Double) -> UsageEvent {
			UsageEvent(
				messageId: id, requestId: "r", provider: .claude, model: "claude-opus-4-8",
				timestamp: Date(timeIntervalSince1970: base + offset), usage: TokenUsage(output: 10))
		}
		try index.ingest([event("a1", 0), event("a2", 100), event("a3", 200)], sourcePath: "/logs/a.jsonl")
		try index.ingest([event("b1", 0), event("b2", 200)], sourcePath: "/logs/b.jsonl")
		XCTAssertEqual(index.eventCount(provider: .claude), 5)

		// The boundary is INCLUSIVE, matching the `>=` bound the watermark decode re-reads with.
		try index.deleteEvents(
			sourcePath: "/logs/a.jsonl", timestampAtOrAfter: Date(timeIntervalSince1970: base + 100))
		XCTAssertEqual(index.eventCount(provider: .claude), 3, "a2 and a3 go, a1 and both b rows stay")
		XCTAssertEqual(try index.sourcePaths(provider: .claude), ["/logs/a.jsonl", "/logs/b.jsonl"])

		// A bound past everything is a no-op; an unknown path is a no-op.
		try index.deleteEvents(
			sourcePath: "/logs/a.jsonl", timestampAtOrAfter: Date(timeIntervalSince1970: base + 9_999))
		try index.deleteEvents(
			sourcePath: "/never/seen.jsonl", timestampAtOrAfter: Date(timeIntervalSince1970: 0))
		XCTAssertEqual(index.eventCount(provider: .claude), 3)

		// A nil bound is still the whole-file delete.
		try index.deleteEvents(sourcePath: "/logs/a.jsonl")
		XCTAssertEqual(try index.sourcePaths(provider: .claude), ["/logs/b.jsonl"])
	}
}
