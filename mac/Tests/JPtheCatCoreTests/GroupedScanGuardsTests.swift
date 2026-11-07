import Foundation
import XCTest

@testable import JPtheCatCore

/// Two guards for the grouped window-summary scan: a perf-regression guard (the scan must stay
/// index-backed, never a full-table SCAN) and the tz self-verification (SQLite's day bucketing must
/// agree with Foundation's before the grouped path is trusted).
final class GroupedScanGuardsTests: XCTestCase {
	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-guards-\(UUID().uuidString).sqlite").path
	}
	private func ev(_ provider: ProviderID, _ model: String, _ ts: Date, input: Int) -> UsageEvent {
		UsageEvent(
			messageId: UUID().uuidString, requestId: "r", provider: provider, model: model, timestamp: ts,
			usage: TokenUsage(input: input))
	}

	// PERF GUARD: the grouped scan's WHERE (ts range + provider IN) must resolve via an index SEARCH,
	// never a full `SCAN events` over the whole corpus. Dropping the scan index or adding an `ORDER BY`
	// that forces a table scan would silently regress it toward per-event cost — the ~31× win is exactly
	// this index SEARCH plus a bounded GROUP-BY temp b-tree.
	//
	// NOTE the predicate is `USING COVERING INDEX`, not `USING INDEX`: SQLite emits the former once the
	// index carries every projected column, and `"USING COVERING INDEX".contains("USING INDEX")` is
	// FALSE, so the old assertion fails deterministically (verified — it fails on the empty DB this test
	// builds, so it is not data-dependent). Asserting the covering form is also strictly stronger: it
	// catches a silent regression to a narrower index that still SEARCHes but re-descends the main
	// WITHOUT ROWID b-tree per row.
	func testGroupedScanStaysIndexBackedNotAFullTableScan() throws {
		let index = try UsageIndex(path: tempDBPath())
		let plan = try index.groupedScanQueryPlan(providers: [.claude, .codex])
		let joined = plan.joined(separator: " | ")
		XCTAssertFalse(plan.isEmpty, "expected a query plan")
		XCTAssertTrue(
			plan.contains { $0.contains("SEARCH") && $0.contains("events") && $0.contains("USING") && $0.contains("INDEX") },
			"grouped scan must SEARCH events via an index — got: \(joined)")
		XCTAssertFalse(
			plan.contains { $0.hasPrefix("SCAN") },
			"grouped scan must not full-table-SCAN events — got: \(joined)")
	}

	/// The scan must be COVERED, and by the index we actually ship. `events` is `WITHOUT ROWID` keyed
	/// on `msg_id` — random w.r.t. `ts` — so an uncovered hit pays a main-b-tree descent per row.
	func testGroupedScanUsesTheCoveringIndexByName() throws {
		let index = try UsageIndex(path: tempDBPath())
		let plan = try index.groupedScanQueryPlan(providers: [.claude, .codex])
		let joined = plan.joined(separator: " | ")
		XCTAssertTrue(
			plan.contains { $0.contains("USING COVERING INDEX") && $0.contains("idx_events_scan") },
			"the grouped scan must be covered by idx_events_scan — got: \(joined)")
	}

	/// A fresh database builds the covering index inline (it is empty, so the build is free) and must
	/// NOT carry the narrower `idx_events_provider_ts`, which is a strict key PREFIX of it and therefore
	/// pure dead weight — 44 MB of it on a real corpus.
	func testFreshDatabaseShipsOnlyTheCoveringIndex() throws {
		let path = tempDBPath()
		_ = try UsageIndex(path: path)
		let db = try SQLiteDatabase(path: path)
		func exists(_ name: String) throws -> Bool {
			let s = try db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name = ?1;")
			s.bind(1, name)
			return try s.step()
		}
		XCTAssertTrue(try exists("idx_events_scan"))
		XCTAssertFalse(
			try exists("idx_events_provider_ts"),
			"the narrower prefix index must not be created alongside the covering one")
		XCTAssertFalse(
			try exists("idx_events_ts"),
			"timestamp-only idx_events_ts is unused in production and must not ship on a fresh database")
	}

	/// Existing databases still carry `idx_events_ts` until the off-main drop. After it runs, the
	/// grouped scan must stay covered by `idx_events_scan` — never fall back to a full table scan.
	func testDropUnusedTimestampIndexRemovesItAndKeepsGroupedScanCovered() throws {
		let path = tempDBPath()
		let index = try UsageIndex(path: path)
		let db = try SQLiteDatabase(path: path)
		try db.execute("CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);")
		func exists(_ name: String) throws -> Bool {
			let s = try db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name = ?1;")
			s.bind(1, name)
			return try s.step()
		}
		XCTAssertTrue(try exists("idx_events_ts"))
		try index.dropUnusedTimestampIndexIfNeeded()
		XCTAssertFalse(try exists("idx_events_ts"))
		try index.dropUnusedTimestampIndexIfNeeded()
		XCTAssertFalse(try exists("idx_events_ts"), "drop must be idempotent")
		let plan = try index.groupedScanQueryPlan(providers: [.claude, .codex])
		let joined = plan.joined(separator: " | ")
		XCTAssertTrue(
			plan.contains { $0.contains("USING COVERING INDEX") && $0.contains("idx_events_scan") },
			"grouped scan must stay covered by idx_events_scan after the ts-index drop — got: \(joined)")
	}

	/// [Money-safety] `deleteEvents` must delete EXACTLY the rows an exact path match would, now that
	/// the path is resolved through the interned `paths` table rather than compared inline. A typo in
	/// the interning subquery would silently delete the wrong events, so pin the behavior including
	/// the cases most likely to break it: two paths sharing a 24-character tail (the collision the
	/// retired `idx_events_source_tail` had to survive, kept because it is still the sharpest fixture
	/// for "near-miss paths stay distinct"), and a path shorter than that window.
	func testDeleteBySourcePathMatchesOnlyTheExactPath() throws {
		let index = try UsageIndex(path: tempDBPath())
		let ts = Date(timeIntervalSince1970: 1_783_000_000)
		func ev(_ id: String) -> UsageEvent {
			UsageEvent(
				messageId: id, requestId: "r", provider: .claude, model: "claude-opus-4-8",
				timestamp: ts, usage: TokenUsage(output: 10))
		}
		// Two paths whose LAST 24 CHARACTERS are identical — the exact collision the tail index has to
		// survive. Only the fully-matching path may be deleted.
		let a = "/alpha/projects/session-0000000000000001.jsonl"
		let b = "/beta/projects/session-0000000000000001.jsonl"
		XCTAssertEqual(String(a.suffix(24)), String(b.suffix(24)), "the test fixture must actually collide")
		try index.ingest([ev("m1")], sourcePath: a)
		try index.ingest([ev("m2")], sourcePath: b)
		// A path SHORTER than the 24-char window (substr(-24) returns the whole string).
		let short = "/s.jsonl"
		try index.ingest([ev("m3")], sourcePath: short)
		XCTAssertEqual(index.eventCount(provider: .claude), 3)

		try index.deleteEvents(sourcePath: a)
		XCTAssertEqual(
			try index.sourcePaths(provider: .claude), Set([b, short]),
			"only the exactly-matching path may be deleted, never its tail-twin")

		try index.deleteEvents(sourcePath: short)
		XCTAssertEqual(try index.sourcePaths(provider: .claude), Set([b]))

		// A path that never existed must delete nothing.
		try index.deleteEvents(sourcePath: "/never/seen.jsonl")
		XCTAssertEqual(try index.sourcePaths(provider: .claude), Set([b]))
	}

	/// The delete must stay INDEXED, in BOTH its plain and its range-scoped form. It fires several
	/// times a minute from the `.reset` branch, because `canTailAppend == false` for Codex, Gemini,
	/// OpenCode, Copilot and Muse Spark.
	///
	/// The plan comes from `deleteEventsQueryPlan`, which EXPLAINs the SAME `deleteEventsSQL` string
	/// `deleteEvents` executes, so this assertion cannot drift from what actually runs.
	func testDeleteBySourcePathStaysIndexBacked() throws {
		let index = try UsageIndex(path: tempDBPath())
		for ranged in [false, true] {
			let plan = try index.deleteEventsQueryPlan(ranged: ranged)
			let joined = plan.joined(separator: " | ")
			XCTAssertFalse(plan.isEmpty, "expected a query plan (ranged: \(ranged))")
			XCTAssertTrue(
				plan.contains { $0.contains("SEARCH") && $0.contains("idx_events_path_id") },
				"the delete must SEARCH events via idx_events_path_id (ranged: \(ranged)) — got: \(joined)")
			XCTAssertTrue(
				plan.contains { $0.contains("SEARCH") && $0.contains("paths") },
				"the path must resolve through the paths UNIQUE index (ranged: \(ranged)) — got: \(joined)")
			XCTAssertFalse(
				plan.contains { $0.hasPrefix("SCAN") },
				"the delete must never full-table-SCAN (ranged: \(ranged)) — got: \(joined)")
		}
	}

	/// A fresh database ships the narrow `path_id` index and NEITHER retired path-shaped index — the
	/// 127 MB full-text one nor its 65.5 MB tail successor — and carries no `source_path` column at all.
	func testFreshDatabaseShipsOnlyThePathIDIndex() throws {
		let path = tempDBPath()
		_ = try UsageIndex(path: path)
		let db = try SQLiteDatabase(path: path)
		XCTAssertTrue(try indexExists(db, "idx_events_path_id"))
		XCTAssertFalse(try indexExists(db, "idx_events_source_tail"))
		XCTAssertFalse(try indexExists(db, "idx_events_source_path"))
		XCTAssertFalse(
			try columnExists(db, table: "events", column: "source_path"),
			"a fresh database must never be born with the interned-away column")
		XCTAssertTrue(try columnExists(db, table: "events", column: "path_id"))
	}

	/// Same replace-don't-add contract as the scan index: the migration must land the end state from a
	/// legacy database carrying EITHER retired index (or both), and a second call must be a no-op.
	func testSourcePathMigrationReplacesEveryRetiredIndexAndIsIdempotent() throws {
		let path = tempDBPath()
		_ = try UsageIndex(path: path)
		let db = try SQLiteDatabase(path: path)
		// Rebuild the pre-interning shape: the wide column back, both retired indexes present.
		try db.execute("ALTER TABLE events ADD COLUMN source_path TEXT;")
		try db.execute("CREATE INDEX idx_events_source_path ON events(source_path);")
		try db.execute("CREATE INDEX idx_events_source_tail ON events(substr(source_path, -24));")
		try db.execute("DROP INDEX IF EXISTS idx_events_path_id;")
		// A NON-EMPTY table, so `init` takes the off-main path instead of finishing the interning inline.
		try db.execute(
			"INSERT INTO events (provider, msg_id, req_id, model, ts, input, output, cache5m, cache1h, cache_read, source_path) "
				+ "VALUES ('claude','m1','r','claude-opus-4-8',1783000000.0,1,2,0,0,0,'/legacy/a.jsonl');")

		let index = try UsageIndex(path: path)
		try index.migrateSourcePathIndexIfNeeded()
		XCTAssertTrue(try indexExists(db, "idx_events_path_id"))
		XCTAssertFalse(
			try indexExists(db, "idx_events_source_path"),
			"migration must DROP the 127 MB full-text index, not leave it")
		XCTAssertFalse(
			try indexExists(db, "idx_events_source_tail"),
			"migration must DROP the 65.5 MB tail index, not leave it")
		XCTAssertFalse(try columnExists(db, table: "events", column: "source_path"))
		XCTAssertEqual(index.eventCount(provider: .claude), 1, "no event may be lost to the migration")
		XCTAssertEqual(
			try index.sourcePaths(provider: .claude), ["/legacy/a.jsonl"],
			"the legacy path must survive as an interned paths row")

		try index.migrateSourcePathIndexIfNeeded()
		XCTAssertTrue(try indexExists(db, "idx_events_path_id"))
		XCTAssertFalse(try columnExists(db, table: "events", column: "source_path"))
	}

	private func indexExists(_ db: SQLiteDatabase, _ name: String) throws -> Bool {
		let s = try db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name = ?1;")
		s.bind(1, name)
		return try s.step()
	}

	private func columnExists(_ db: SQLiteDatabase, table: String, column: String) throws -> Bool {
		let s = try db.prepare("SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2;")
		s.bind(1, table)
		s.bind(2, column)
		return try s.step()
	}

	/// The migration is idempotent, replaces rather than adds, and NEVER leaves the database with
	/// neither index — a partial state would degrade every money scan to a full table scan.
	func testScanIndexMigrationReplacesTheLegacyIndexAndIsIdempotent() throws {
		let path = tempDBPath()
		_ = try UsageIndex(path: path)
		let db = try SQLiteDatabase(path: path)
		// Simulate a pre-migration database: legacy narrow index present, covering one absent.
		try db.execute("DROP INDEX IF EXISTS idx_events_scan;")
		try db.execute("CREATE INDEX IF NOT EXISTS idx_events_provider_ts ON events(provider, ts);")

		let index = try UsageIndex(path: path)
		try index.migrateScanIndexIfNeeded()
		func exists(_ name: String) throws -> Bool {
			let s = try db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name = ?1;")
			s.bind(1, name)
			return try s.step()
		}
		XCTAssertTrue(try exists("idx_events_scan"), "migration must create the covering index")
		XCTAssertFalse(
			try exists("idx_events_provider_ts"),
			"migration must DROP the now-redundant prefix index — leaving it keeps +54 MB (auto_vacuum=0)")

		// Idempotent: a second call is a no-op and must not throw or rebuild.
		try index.migrateScanIndexIfNeeded()
		XCTAssertTrue(try exists("idx_events_scan"))
		XCTAssertFalse(try exists("idx_events_provider_ts"))
	}

	// TZ SELF-CHECK: on the normal path (system tz) SQLite's `localtime` day string for `now` agrees with
	// Foundation's, so the tz-probe passes and the fast grouped path runs and matches the per-event oracle.
	// (The probe only DIVERGES — and then falls back to the era/tz-agnostic per-event path — under a live
	// OS timezone change that leaves the C-library tz stale, which is not deterministically forceable in a
	// unit test; the fallback keeps the result correct in that case by construction.)
	func testTzProbePassesOnTheNormalPathAndRunsTheGroupedScan() throws {
		let index = try UsageIndex(path: tempDBPath())
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = TimeZone.current
		let now = Date(timeIntervalSince1970: 1_784_000_000)
		try index.ingest([ev(.claude, "claude-opus-4-8", now.addingTimeInterval(-3_600), input: 1_000_000)])

		XCTAssertNotNil(UsageIndex.sqlLocalDayExpression(cal), "system-tz calendar must be fast-path eligible")
		let e = try index.multiWindowSummariesPerEvent(providers: [.claude], windows: [7], now: now, calendar: cal)
		let a = try index.multiWindowSummariesGrouped(providers: [.claude], windows: [7], now: now, calendar: cal)
		let expected = e.byDays[7]!.aggregate.rollup.last7d.cost
		let actual = a.byDays[7]!.aggregate.rollup.last7d.cost
		XCTAssertEqual(actual, expected, accuracy: 1e-9, "probe must not spuriously fall back on the normal path")
		XCTAssertEqual(actual, 5.0, accuracy: 1e-9, "grouped path actually ran (1M input @ opus-4-8 = $5), not an empty fallback")
	}
}
