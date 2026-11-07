import Foundation
import XCTest

@testable import JPtheCatCore

private final class ThreadSafeErrorLog: @unchecked Sendable {
	private let lock = NSLock()
	private var storage: [String] = []

	func append(_ error: String) {
		lock.lock()
		storage.append(error)
		lock.unlock()
	}

	var values: [String] {
		lock.lock()
		defer { lock.unlock() }
		return storage
	}
}

final class UsageIndexTests: XCTestCase {
	func testLegacyInlinePrimaryKeyMigratesAndKeepsIndependentProviderCursors() throws {
		let path = tempDBPath()
		let legacy = try SQLiteDatabase(path: path)
		try legacy.execute("""
			CREATE TABLE cursors (path TEXT PRIMARY KEY, size INTEGER NOT NULL,
			mtime REAL NOT NULL, offset INTEGER NOT NULL, fingerprint TEXT NOT NULL DEFAULT '') WITHOUT ROWID;
			INSERT INTO cursors VALUES ('shared.db', 100, 20, 10, 'fingerprint');
			""")
		let index = try UsageIndex(path: path)
		for provider in [ProviderID.museSpark, .nemotron, .mimo, .bigPickle, .deepseek] {
			try index.setCursor(path: "shared.db", size: 200, mtime: 30, offset: 42, provider: provider)
			XCTAssertEqual(index.cursor(for: "shared.db", provider: provider)?.offset, 42)
		}
		let reopened = try UsageIndex(path: path)
		for provider in [ProviderID.museSpark, .nemotron, .mimo, .bigPickle, .deepseek] {
			XCTAssertEqual(reopened.cursor(for: "shared.db", provider: provider)?.offset, 42)
		}
		let retained = try legacy.prepare("SELECT offset FROM cursors WHERE provider = ''")
		XCTAssertTrue(try retained.step())
		XCTAssertEqual(retained.int(0), 10)
	}

	func testOpeningExistingIndexDropsRetiredDailyTableAndProjectIndex() throws {
		let path = tempDBPath()
		_ = try UsageIndex(path: path)

		let legacy = try SQLiteDatabase(path: path)
		try legacy.execute(
			"""
			CREATE INDEX idx_events_project_ts ON events(project, ts);
			CREATE TABLE daily (provider TEXT NOT NULL, day TEXT NOT NULL);
			""")
		XCTAssertTrue(try schemaObjectExists("idx_events_project_ts", in: legacy))
		XCTAssertTrue(try schemaObjectExists("daily", in: legacy))

		_ = try UsageIndex(path: path)
		XCTAssertFalse(try schemaObjectExists("idx_events_project_ts", in: legacy))
		XCTAssertFalse(try schemaObjectExists("daily", in: legacy))
	}

	private func schemaObjectExists(_ name: String, in db: SQLiteDatabase) throws -> Bool {
		let statement = try db.prepare("SELECT 1 FROM sqlite_master WHERE name = ?1;")
		statement.bind(1, name)
		return try statement.step()
	}

	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}
	private let iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private func tempDir() throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-idx-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}
	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-idx-\(UUID().uuidString).sqlite").path
	}

	private func claudeLine(
		_ req: String, _ msg: String, _ model: String, _ ts: String, output: Int, input: Int = 100,
		cacheRead: Int = 0
	) -> String {
		"{\"type\":\"assistant\",\"requestId\":\"\(req)\",\"timestamp\":\"\(ts)\",\"cwd\":\"/Users/x/proj\","
			+ "\"message\":{\"id\":\"\(msg)\",\"model\":\"\(model)\",\"usage\":{\"input_tokens\":\(input),"
			+ "\"output_tokens\":\(output),\"cache_read_input_tokens\":\(cacheRead),"
			+ "\"cache_creation\":{\"ephemeral_5m_input_tokens\":0,\"ephemeral_1h_input_tokens\":0}}}}"
	}
	private func event(_ msg: String, _ req: String, _ ts: String, output: Int, model: String, provider: ProviderID = .claude)
		-> UsageEvent
	{
		UsageEvent(
			messageId: msg, requestId: req, provider: provider, model: model,
			timestamp: iso.date(from: ts)!, usage: TokenUsage(output: output))
	}

	// MARK: - FileCursor change classification (pure logic)

	func testFileCursorClassifyCoversEveryTransition() {
		let stored = FileState(size: 100, mtime: 5, offset: 100)
		XCTAssertEqual(FileCursor.classify(size: 100, mtime: 5, stored: stored, canTailAppend: true), .unchanged)
		XCTAssertEqual(FileCursor.classify(size: 160, mtime: 6, stored: stored, canTailAppend: true), .appended(from: 100))
		XCTAssertEqual(FileCursor.classify(size: 160, mtime: 6, stored: stored, canTailAppend: false), .reset)  // Codex
		XCTAssertEqual(FileCursor.classify(size: 40, mtime: 6, stored: stored, canTailAppend: true), .reset)  // truncated
		XCTAssertEqual(FileCursor.classify(size: 100, mtime: 9, stored: stored, canTailAppend: true), .reset)  // in-place rewrite
		XCTAssertEqual(FileCursor.classify(size: 100, mtime: 5, stored: nil, canTailAppend: true), .reset)  // new
	}

	// MARK: - Keep-max-output upsert (matches the Deduplicator)

	func testKeepMaxOutputUpsertIsOrderIndependent() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let ts = "2026-06-30T10:00:00.000Z"
		// same (msg,req) three times, out of order: 40, 90, 60 -> keep 90.
		try index.ingest([event("m", "r", ts, output: 40, model: "claude-opus-4-8")])
		try index.ingest([event("m", "r", ts, output: 90, model: "claude-opus-4-8")])
		try index.ingest([event("m", "r", ts, output: 60, model: "claude-opus-4-8")])
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		let r = try index.rollup(provider: .claude, now: now, calendar: utc())
		XCTAssertEqual(r.last7d.usage.output, 90)
	}

	func testProviderIsPartOfIdentitySoClaudeAndCodexNeverCollide() throws {
		let index = try UsageIndex(path: tempDBPath())
		let ts = "2026-06-30T10:00:00.000Z"
		try index.ingest([event("m", "r", ts, output: 10, model: "claude-opus-4-8", provider: .claude)])
		try index.ingest([event("m", "r", ts, output: 20, model: "gpt-5-codex", provider: .codex)])
		XCTAssertEqual(index.eventCount(), 2)
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		XCTAssertEqual(index.eventCount(provider: .codex), 1)
	}

	// MARK: - Per-day cost series (the 7-day chart source)

	func testDailyCostSeriesBucketsByDayWithPerEventCostAndWindow() throws {
		let index = try UsageIndex(path: tempDBPath())
		let model = "claude-opus-4-8"  // output $25 / MTok
		try index.ingest([event("a", "r1", "2026-06-30T12:00:00.000Z", output: 1_000_000, model: model)])  // pre-window
		try index.ingest([event("b", "r2", "2026-07-01T09:00:00.000Z", output: 1_000_000, model: model)])  // bucket 0
		try index.ingest([event("c", "r3", "2026-07-04T15:00:00.000Z", output: 2_000_000, model: model)])  // bucket 3
		try index.ingest([event("d", "r4", "2026-07-07T01:00:00.000Z", output: 1_000_000, model: model)])  // bucket 6 (today)

		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		let series = try index.dailyCostSeries(provider: .claude, days: 7, now: now, calendar: utc())
		XCTAssertEqual(series.count, 7)
		XCTAssertEqual(series[0], 25.0, accuracy: 1e-9)
		XCTAssertEqual(series[1], 0, accuracy: 1e-9)
		XCTAssertEqual(series[3], 50.0, accuracy: 1e-9)  // per-event cost, not summed-token cost
		XCTAssertEqual(series[6], 25.0, accuracy: 1e-9)
		XCTAssertEqual(series.reduce(0, +), 100.0, accuracy: 1e-9)
	}

	func testWindowSummariesAggregateSumsPerProviderSeries() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.ingest([event("a", "r1", "2026-07-07T01:00:00.000Z", output: 1_000_000, model: "claude-opus-4-8", provider: .claude)])  // $25
		try index.ingest([event("b", "r2", "2026-07-07T02:00:00.000Z", output: 1_000_000, model: "gpt-5-codex", provider: .codex)])  // $10
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		let summaries = try index.windowSummaries(
			providers: [.claude, .codex], days: 7, now: now, calendar: utc())
		XCTAssertEqual(summaries.aggregate.dailyCostSeries[6], 35.0, accuracy: 1e-9)
		XCTAssertEqual(try index.dailyCostSeries(provider: .claude, days: 7, now: now, calendar: utc())[6], 25.0, accuracy: 1e-9)
	}

	// MARK: - Golden equivalence: index rollup == full-scan rollup

	func testIndexRollupExactlyMatchesFullCorpusScan() throws {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12))!
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }

		let today = "2026-06-30T10:00:00.000Z"
		let day5 = "2026-06-25T10:00:00.000Z"  // inside the 7-day window
		let day10 = "2026-06-20T10:00:00.000Z"  // outside it

		try ([
			claudeLine("reqA", "msgA", "claude-opus-4-8", today, output: 10),  // streaming copy 1
			claudeLine("reqA", "msgA", "claude-opus-4-8", today, output: 120),  // final copy -> keep-max
			claudeLine("reqB", "msgB", "claude-haiku-4-5", today, output: 50),
		].joined(separator: "\n") + "\n")
			.write(to: root.appendingPathComponent("f1.jsonl"), atomically: true, encoding: .utf8)
		try ([
			claudeLine("reqC", "msgC", "claude-opus-4-8", day5, output: 200),
			claudeLine("reqD", "msgD", "claude-opus-4-8", day10, output: 30),
		].joined(separator: "\n") + "\n")
			.write(to: root.appendingPathComponent("f2.jsonl"), atomically: true, encoding: .utf8)

		let full = UsageStore().rollup(ClaudeProvider(root: root).loadEvents(), now: now, calendar: cal)

		let index = try UsageIndex(path: tempDBPath())
		try UsageIndexer(index: index).refresh(ClaudeProvider(root: root))
		let idx = try index.rollup(provider: .claude, now: now, calendar: cal)

		// Sanity on the shape: today = reqA(kept 120) + reqB; 7d adds reqC; reqD (10d) excluded.
		XCTAssertEqual(full.today.eventCount, 2)
		XCTAssertEqual(full.last7d.eventCount, 3)

		// Exact equivalence across every rollup surface.
		XCTAssertEqual(idx.today.cost, full.today.cost, accuracy: 1e-9)
		XCTAssertEqual(idx.last7d.cost, full.last7d.cost, accuracy: 1e-9)
		XCTAssertEqual(idx.today.eventCount, full.today.eventCount)
		XCTAssertEqual(idx.last7d.eventCount, full.last7d.eventCount)
		XCTAssertEqual(idx.today.usage.output, full.today.usage.output)
		XCTAssertEqual(idx.last7d.usage.output, full.last7d.usage.output)
		XCTAssertEqual(Set(idx.byModel7d.keys), Set(full.byModel7d.keys))
		for model in full.byModel7d.keys {
			XCTAssertEqual(
				idx.byModel7d[model]?.cost ?? -1, full.byModel7d[model]?.cost ?? -2, accuracy: 1e-9,
				"cost mismatch for \(model)")
		}
	}

	// MARK: - Incremental refresh

	func testUnchangedFilesAreSkippedOnSecondRefresh() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		try (claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10) + "\n")
			.write(to: root.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
		try (claudeLine("reqB", "msgB", "claude-opus-4-8", ts, output: 20) + "\n")
			.write(to: root.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		let claude = ClaudeProvider(root: root)

		let first = try indexer.refresh(claude)
		XCTAssertEqual(first.filesRead, 2)
		XCTAssertEqual(index.eventCount(provider: .claude), 2)

		let second = try indexer.refresh(claude)
		XCTAssertEqual(second.filesRead, 0)
		XCTAssertEqual(second.filesSkipped, 2)
		XCTAssertEqual(second.eventsIngested, 0)
	}

	/// Root-cause regression guard for "why does cold launch take so long" — before this fix, EVERY
	/// historical file paid a real open+read fingerprint on EVERY app launch, even when nothing about
	/// it had changed since the app last quit, because only the in-memory (this-process-only)
	/// `verifiedFileStateCache` was ever checked — never the PERSISTED cursor. Seeding the cursor
	/// directly via `setCursor` (never touching `verifiedFileStateCache`, which is only populated by a
	/// real fingerprint read inside `refresh`) simulates a cursor written by a PRIOR launch in a
	/// genuinely fresh process, so any skip below can only come from the persisted `ctime` column.
	func testColdStartSkipsFingerprintReadViaPersistedCtime() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		let content = claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10) + "\n"
		try content.write(
			to: root.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
		let provider = ClaudeProvider(root: root)
		// The provider's OWN enumeration, not a hand-built URL — FileManager.enumerator resolves
		// /var/folders/... symlinks to /private/var/folders/..., so a cursor seeded under a
		// separately-constructed (unresolved) URL would never match what refresh looks up.
		let file = try XCTUnwrap(provider.jsonlFiles().first)

		let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
		let size = try XCTUnwrap((attrs[.size] as? NSNumber)?.intValue)
		let mtime = try XCTUnwrap((attrs[.modificationDate] as? Date)?.timeIntervalSince1970)
		let ctime = try XCTUnwrap(FileCursor.changeTime(fileURL: file))

		let index = try UsageIndex(path: tempDBPath())
		try index.setCursor(
			path: file.path, size: size, mtime: mtime, offset: content.utf8.count, fingerprint: "",
			ctime: ctime, provider: .claude, parserRevision: provider.parserRevision)

		let stats = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(stats.filesRead, 0)
		XCTAssertEqual(stats.filesSkipped, 1)
		XCTAssertEqual(stats.eventsIngested, 0)
		// THE assertion this test is named for. `filesSkipped` is incremented at BOTH the cheap
		// (size, mtime, ctime) skip AND at `.unchanged`, which is only reached AFTER paying a full
		// fingerprint open+read — so every assertion above reports identically whether the expensive
		// read happened or not. Without this counter the test could not fail.
		XCTAssertEqual(
			stats.fingerprintReads, 0,
			"a persisted ctime match must skip the fingerprint READ, not merely the decode")
		// The event was never actually ingested (only the cursor was seeded), so zero events here
		// proves decode was genuinely skipped, not merely that the offset was reused.
		XCTAssertEqual(index.eventCount(provider: .claude), 0)
	}

	func testParserRevisionChangeForcesScopedFullReindexOfUnchangedFile() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let content = claudeLine(
			"reqA", "msgA", "claude-opus-4-8", "2026-06-30T10:00:00.000Z", output: 10) + "\n"
		try content.write(to: root.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
		let provider = ClaudeProvider(root: root)
		let file = try XCTUnwrap(provider.jsonlFiles().first)
		let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
		let size = try XCTUnwrap((attrs[.size] as? NSNumber)?.intValue)
		let mtime = try XCTUnwrap((attrs[.modificationDate] as? Date)?.timeIntervalSince1970)
		let ctime = try XCTUnwrap(FileCursor.changeTime(fileURL: file))
		let index = try UsageIndex(path: tempDBPath())
		try index.setCursor(
			path: file.path, size: size, mtime: mtime, offset: size, ctime: ctime,
			provider: .claude, parserRevision: 0)

		let stats = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(stats.filesRead, 1)
		XCTAssertEqual(stats.filesSkipped, 0)
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		XCTAssertEqual(index.cursor(for: file.path, provider: .claude)?.parserRevision, provider.parserRevision)
	}

	/// A cursor's persisted `ctime` from BEFORE this column existed defaults to `0` and must never be
	/// treated as a real match. The content here is genuinely unchanged, so `classify` legitimately
	/// still concludes `.unchanged` via the fingerprint (no re-decode needed) — the real proof that the
	/// zero-ctime fast path was correctly REFUSED is that a genuine fingerprint read ran and backfilled
	/// the persisted `ctime` to a real (non-zero) value, rather than silently trusting the stale cursor
	/// forever.
	func testZeroCtimeCursorForcesARealReadThatBackfillsCtime() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		let content = claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10) + "\n"
		try content.write(
			to: root.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
		let provider = ClaudeProvider(root: root)
		let file = try XCTUnwrap(provider.jsonlFiles().first)

		let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
		let size = try XCTUnwrap((attrs[.size] as? NSNumber)?.intValue)
		let mtime = try XCTUnwrap((attrs[.modificationDate] as? Date)?.timeIntervalSince1970)

		let index = try UsageIndex(path: tempDBPath())
		// Simulates a cursor written by a pre-ctime app version: ctime defaults to 0.
		try index.setCursor(
			path: file.path, size: size, mtime: mtime, offset: content.utf8.count, fingerprint: "",
			provider: .claude, parserRevision: provider.parserRevision)

		let stats = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(stats.filesSkipped, 1, "content is genuinely unchanged, so no re-decode is needed")
		XCTAssertEqual(stats.filesRead, 0)
		XCTAssertEqual(index.eventCount(provider: .claude), 0)
		XCTAssertEqual(
			stats.fingerprintReads, 1,
			"a zero-ctime cursor must PAY a real fingerprint read — this is the negative control for the "
				+ "cold-start guard, and without the counter both tests report identically")
		let backfilled = try XCTUnwrap(index.cursor(for: file.path, provider: .claude))
		XCTAssertGreaterThan(
			backfilled.ctime, 0, "a zero-ctime cursor must be backfilled by a REAL read, never silently trusted")
	}

	/// Regression guard for `UsageIndex.generation`, the cache-invalidation signal
	/// `DashboardWidgetPublisher` uses to skip recomputing `multiWindowSummaries` when nothing changed:
	/// it must bump on a real ingest, stay put on a no-op refresh (no new events), and bump again when
	/// events are actually deleted.
	func testGenerationBumpsOnlyWhenEventsActuallyChange() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		let path = root.appendingPathComponent("a.jsonl")
		try (claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10) + "\n")
			.write(to: path, atomically: true, encoding: .utf8)

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		let claude = ClaudeProvider(root: root)

		XCTAssertEqual(index.generation, 0)
		try indexer.refresh(claude)
		let afterFirstIngest = index.generation
		XCTAssertGreaterThan(afterFirstIngest, 0)

		try indexer.refresh(claude)  // unchanged file: no new events, no rollup change
		XCTAssertEqual(index.generation, afterFirstIngest)

		// Use the indexer's own recorded source path (not `path.path`) — /tmp resolves through a
		// /private symlink, so a path built independently can differ by string even when it names the
		// same file; the indexer's cursor/source_path is the actual identity to delete by.
		let storedPath = try XCTUnwrap(index.sourcePaths(provider: .claude).first)
		_ = try index.deleteEvents(sourcePath: storedPath)
		XCTAssertGreaterThan(index.generation, afterFirstIngest)
	}

	/// [Regression guard — shipped v1.083, fixed 2026-07-27] `cursor(for:)` reuses ONE prepared
	/// statement. It reset on the way IN but not on the way OUT, so after a cache HIT the statement sat
	/// parked in `SQLITE_ROW`, holding an open read snapshot on the shared connection for the rest of
	/// the process. Proven at the C API level: that state makes `VACUUM` fail with "cannot VACUUM - SQL
	/// statements in progress" and `PRAGMA wal_checkpoint(TRUNCATE)` fail with "database table is
	/// locked", so the `-wal` file grows without bound within a session despite `wal_autocheckpoint`
	/// being 1000 pages. Observed live: 2.0 -> 2.4 -> 2.8 MB over 45 s on the running app.
	///
	/// The HIT is load-bearing — a miss steps to `SQLITE_DONE`, which auto-resets and never blocks. A
	/// test whose index has no matching cursor row cannot catch this.
	func testCursorLookupDoesNotParkAStatementThatBlocksCheckpointing() throws {
		let path = tempDBPath()
		let index = try UsageIndex(path: path)
		try index.setCursor(path: "/logs/a.jsonl", size: 10, mtime: 1, offset: 10, ctime: 5, provider: .claude)

		// A HIT. This is what leaves the statement parked without the out-reset.
		XCTAssertNotNil(index.cursor(for: "/logs/a.jsonl", provider: .claude))

		// If the statement is still parked in SQLITE_ROW, both of these fail on the SAME connection.
		XCTAssertNoThrow(
			try index.checkpointForTesting(),
			"a parked cursor statement blocks WAL checkpointing, so the -wal file grows unbounded")
		XCTAssertNoThrow(
			try index.vacuumForTesting(),
			"a parked cursor statement blocks VACUUM, silently defeating any compaction")
	}

	/// The miss path is the negative control: it must ALSO not block, and it must not regress into
	/// returning stale data now that the hit path resets on exit.
	func testCursorLookupStillReturnsCorrectResultsAcrossHitsAndMisses() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.setCursor(path: "/logs/a.jsonl", size: 10, mtime: 1, offset: 10, ctime: 5, provider: .claude)
		try index.setCursor(path: "/logs/b.jsonl", size: 20, mtime: 2, offset: 20, ctime: 6, provider: .codex)

		XCTAssertEqual(index.cursor(for: "/logs/a.jsonl", provider: .claude)?.size, 10)
		XCTAssertNil(index.cursor(for: "/logs/missing.jsonl", provider: .claude))
		XCTAssertEqual(index.cursor(for: "/logs/b.jsonl", provider: .codex)?.size, 20)
		XCTAssertEqual(index.cursor(for: "/logs/a.jsonl", provider: .claude)?.offset, 10)
		XCTAssertNil(index.cursor(for: "/logs/gone.jsonl", provider: .claude))
	}

	/// [Regression guard — shipped v1.083, fixed 2026-07-27] `sqlite3_exec` halts a multi-statement
	/// string at the first failure and RETURNS WITH THE TRANSACTION STILL OPEN. Without an explicit
	/// ROLLBACK the shared connection is wedged: every subsequent `ingest` (the only `db.transaction`
	/// call site) fails "cannot start a transaction within a transaction", so the app silently stops
	/// recording spend for the rest of the process.
	func testAFailedMultiStatementTransactionDoesNotWedgeTheConnection() throws {
		let path = tempDBPath()
		let index = try UsageIndex(path: path)
		let db = try SQLiteDatabase(path: path)

		// Deliberately fail mid-string, exactly like a disk-full DDL failure would.
		XCTAssertThrowsError(
			try db.execute("BEGIN IMMEDIATE; SELECT 1 FROM no_such_table; COMMIT;"))
		try? db.execute("ROLLBACK;")

		// The index must still be able to write. If a transaction were left dangling on ITS connection,
		// this ingest would throw.
		let ts = iso.date(from: "2026-06-30T10:00:00.000Z")!
		XCTAssertNoThrow(
			try index.ingest([
				UsageEvent(
					messageId: "m", requestId: "r", provider: .claude, model: "claude-opus-4-8",
					timestamp: ts, usage: TokenUsage(output: 10))
			]))
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
	}

	/// [Regression guard — publisher parked behind an in-flight scan] `generation` is a one-word read,
	/// but it used to go through `withConnectionLock` — the same recursive lock a scan holds for its
	/// entire `while try stmt.step()` loop. `DashboardWidgetPublisher.makeWindows` reads `generation`
	/// as its very first act, so a publish blocked for the length of an in-flight dashboard scan before
	/// it could even check its own cache. It now has its own lock.
	func testGenerationReadDoesNotBlockOnTheConnectionLock() throws {
		let index = try UsageIndex(path: tempDBPath())
		let started = expectation(description: "long index operation started")
		let release = expectation(description: "generation read completed")

		// Hold the CONNECTION lock (not the generation lock) on a background thread.
		let holder = Thread {
			index.withConnectionLockForTesting {
				started.fulfill()
				// Block until the main thread has proven `generation` is readable meanwhile.
				_ = XCTWaiter().wait(for: [release], timeout: 5)
			}
		}
		holder.start()
		wait(for: [started], timeout: 5)

		// Must return promptly rather than deadlocking behind the held connection lock.
		XCTAssertEqual(index.generation, 0)
		release.fulfill()
	}

	func testConcurrentRefreshesOnSharedIndexDoNotNestTransactions() throws {
		struct ProbeProvider: IndexableProvider, Sendable {
			let id: ProviderID = .claude
			let url: URL
			var canTailAppend: Bool { false }
			var parserRevision: Int { 1 }
			func watchPaths() -> [URL] { [url.deletingLastPathComponent()] }
			func isAvailable() -> Bool { true }
			func loadEvents() -> [UsageEvent] { [] }
			func dataFiles() -> [URL] { [url] }

			func decodeFile(
				_ url: URL, from _: Int, parserState _: String?
			) -> IndexedDecodeResult {
				Thread.sleep(forTimeInterval: 0.03)
				let now = Date()
				let events = (0..<30_000).map { i in
					UsageEvent(
						messageId: "m\(i)", requestId: "r\(i)", provider: .claude,
						model: "claude-haiku-4-5-20251001", timestamp: now,
						usage: TokenUsage(input: 1, output: 1), project: "probe")
				}
				return IndexedDecodeResult(events: events, consumed: 1)
			}
		}

		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("probe.jsonl")
		try Data("x".utf8).write(to: file)

		let index = try UsageIndex(path: tempDBPath())
		let provider = ProbeProvider(url: file)
		let start = DispatchSemaphore(value: 0)
		let group = DispatchGroup()
		let errors = ThreadSafeErrorLog()

		for _ in 0..<6 {
			group.enter()
			DispatchQueue.global(qos: .userInitiated).async {
				start.wait()
				do {
					_ = try UsageIndexer(index: index).refresh(provider)
				} catch {
					errors.append("\(error)")
				}
				group.leave()
			}
		}

		for _ in 0..<6 { start.signal() }
		group.wait()

		XCTAssertEqual(errors.values, [])
		XCTAssertEqual(index.eventCount(provider: .claude), 30_000)
	}

	/// [Phase 3 — durable retention beyond provider rotation.] When a provider rotates/prunes its OWN
	/// log, that file leaves `dataFiles()`. JP is a warehouse: it RETAINS the already-indexed events
	/// (it no longer deletes them) and only FORGETS the file — drops the cursor so the retention sweep
	/// stays bounded to live files.
	func testRotatedAwaySourceFileRetainsIndexedRowsButDropsTheCursor() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		let file = root.appendingPathComponent("rotated.jsonl")
		try (claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10) + "\n")
			.write(to: file, atomically: true, encoding: .utf8)

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		let claude = ClaudeProvider(root: root)
		_ = try indexer.refresh(claude)
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		let storedPath = try XCTUnwrap(index.cursorPaths(provider: .claude).first)
		XCTAssertEqual(index.cursor(for: storedPath, provider: .claude)?.provider, ProviderID.claude.rawValue)

		// The provider rotates the log away entirely.
		try FileManager.default.removeItem(at: file)
		_ = try indexer.refresh(claude)

		// Events RETAINED (warehouse); the file is forgotten so the per-refresh sweep can't grow.
		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let r = try index.rollup(provider: .claude, now: now, calendar: utc())
		XCTAssertEqual(index.eventCount(provider: .claude), 1, "rotated-away events must be retained")
		XCTAssertEqual(r.last7d.eventCount, 1)
		XCTAssertEqual(r.last7d.usage.output, 10)
		XCTAssertNil(index.cursor(for: storedPath, provider: .claude), "the rotated-away file's cursor is dropped")
		XCTAssertTrue(try index.cursorPaths(provider: .claude).isEmpty)
	}

	/// The anti-freeze DESIGN proof: retaining history must NOT make per-refresh work grow with history.
	/// After many rotate-in/rotate-out cycles the retained EVENTS (and their `source_path`s) grow without
	/// bound, but the stale-sweep candidate set — `cursorPaths(provider:)` — stays bounded to the LIVE
	/// files, so `refresh` never re-scans the whole retained corpus (the freeze/memory anti-pattern).
	func testRetentionKeepsThePerRefreshStaleSweepBounded() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		let claude = ClaudeProvider(root: root)
		let ts = "2026-06-30T10:00:00.000Z"

		let rounds = 12
		for i in 0..<rounds {
			let file = root.appendingPathComponent("session-\(i).jsonl")
			try (claudeLine("req\(i)", "msg\(i)", "claude-opus-4-8", ts, output: 10) + "\n")
				.write(to: file, atomically: true, encoding: .utf8)
			_ = try indexer.refresh(claude)  // ingest this round's file
			try FileManager.default.removeItem(at: file)  // provider rotates it away
			_ = try indexer.refresh(claude)  // sweep: retain events, drop the cursor
		}

		// Every round's events retained -> history (events + source_paths) grows with rounds...
		XCTAssertEqual(index.eventCount(provider: .claude), rounds)
		XCTAssertEqual(try index.sourcePaths(provider: .claude).count, rounds)
		// ...but the cursor set (the stale-sweep candidate set) stays BOUNDED — no live files remain.
		XCTAssertTrue(
			try index.cursorPaths(provider: .claude).isEmpty,
			"per-refresh stale sweep must not grow with retained history")
	}

	/// A legacy cursor (persisted before the `provider` column existed, so `provider == ""`) gets
	/// backfilled on the next SKIPPING refresh, so the retention sweep can later scope it by provider.
	func testSkippingRefreshBackfillsAnEmptyProviderOntoALegacyCursor() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		let file = root.appendingPathComponent("legacy.jsonl")
		try (claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10) + "\n")
			.write(to: file, atomically: true, encoding: .utf8)

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		let claude = ClaudeProvider(root: root)
		_ = try indexer.refresh(claude)
		let path = try XCTUnwrap(index.cursorPaths(provider: .claude).first)

		// Rewrite the cursor as a LEGACY '' row (same fingerprint/ctime so the next refresh SKIPS it):
		// deleteCursor + a fresh insert with provider:nil binds '' (the CASE-preserve only guards UPDATEs).
		let s = try XCTUnwrap(index.cursor(for: path, provider: .claude))
		try index.deleteCursor(path: path, provider: .claude)
		try index.setCursor(
			path: path, size: s.size, mtime: s.mtime, offset: s.offset, fingerprint: s.fingerprint,
			ctime: s.ctime, provider: nil)
		// The claude row was deleted; the empty-provider row is separate
		XCTAssertNil(index.cursor(for: path, provider: .claude), "claude row was deleted")
		XCTAssertTrue(try index.cursorPaths(provider: .claude).isEmpty, "empty provider is unscoped")

		_ = try indexer.refresh(claude)  // file unchanged -> skip path -> one-time provider backfill

		// After refresh, the empty-provider row should be backfilled to claude
		XCTAssertEqual(index.cursor(for: path, provider: .claude)?.provider, ProviderID.claude.rawValue)
		XCTAssertEqual(try index.cursorPaths(provider: .claude), [path], "now sweepable by provider")
	}

	func testAppendedLinesAreTailedNotFullyReRead() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		let file = root.appendingPathComponent("s.jsonl")
		try ([
			claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10),  // streaming copy 1
			claudeLine("reqB", "msgB", "claude-opus-4-8", ts, output: 50),
		].joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		let claude = ClaudeProvider(root: root)
		_ = try indexer.refresh(claude)
		XCTAssertEqual(index.eventCount(provider: .claude), 2)

		// Append reqA's final copy (keep-max 120) + a new reqC.
		let handle = try FileHandle(forWritingTo: file)
		try handle.seekToEnd()
		let appended = [
			claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 120),
			claudeLine("reqC", "msgC", "claude-opus-4-8", ts, output: 70),
		].joined(separator: "\n") + "\n"
		try handle.write(contentsOf: Data(appended.utf8))
		try handle.close()

		let second = try indexer.refresh(claude)
		XCTAssertEqual(second.filesRead, 1)
		XCTAssertEqual(second.eventsIngested, 2)
		XCTAssertEqual(index.eventCount(provider: .claude), 3)

		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let r = try index.rollup(provider: .claude, now: now, calendar: utc())
		XCTAssertEqual(r.last7d.usage.output, 240)  // 120 + 50 + 70 (keep-max applied to reqA)
	}

	func testCompleteFinalLineWithoutNewlineIsIndexed() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		try claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10)
			.write(to: root.appendingPathComponent("no-newline.jsonl"), atomically: true, encoding: .utf8)

		let index = try UsageIndex(path: tempDBPath())
		try UsageIndexer(index: index).refresh(ClaudeProvider(root: root))

		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let r = try index.rollup(provider: .claude, now: now, calendar: utc())
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		XCTAssertEqual(r.last7d.usage.input, 100)
		XCTAssertEqual(r.last7d.usage.output, 10)
	}

	func testSameSizeSameMtimeRewriteIsDetected() throws {
		let root = try tempDir()
		defer { try? FileManager.default.removeItem(at: root) }
		let ts = "2026-06-30T10:00:00.000Z"
		let file = root.appendingPathComponent("same-size.jsonl")
		try (claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 10) + "\n")
			.write(to: file, atomically: true, encoding: .utf8)
		let originalMtime = try XCTUnwrap(
			(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date))

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		_ = try indexer.refresh(ClaudeProvider(root: root))

		try (claudeLine("reqA", "msgA", "claude-opus-4-8", ts, output: 20) + "\n")
			.write(to: file, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.modificationDate: originalMtime], ofItemAtPath: file.path)
		_ = try indexer.refresh(ClaudeProvider(root: root))

		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let r = try index.rollup(provider: .claude, now: now, calendar: utc())
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		XCTAssertEqual(r.last7d.usage.output, 20)
	}

	func testCodexResetReplacesRowsFromRewrittenFile() throws {
		let root = try codexRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent(
			"2026/07/01/rollout-2026-07-01T12-00-00-feedface-aaaa-bbbb-cccc-555555555555.jsonl")
		try writeCodexTotals([(100, 0, 10), (200, 0, 20), (300, 0, 30)], to: file)

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		_ = try indexer.refresh(CodexProvider(root: root))
		XCTAssertEqual(index.eventCount(provider: .codex), 3)

		try writeCodexTotals([(50, 0, 5)], to: file)
		_ = try indexer.refresh(CodexProvider(root: root))

		let now = iso.date(from: "2026-07-01T12:30:00.000Z")!
		let r = try index.rollup(provider: .codex, now: now, calendar: utc())
		XCTAssertEqual(index.eventCount(provider: .codex), 1)
		XCTAssertEqual(r.last7d.usage.input, 50)
		XCTAssertEqual(r.last7d.usage.output, 5)
	}

	func testCodexOrdinalShiftDoesNotLeaveStaleRowsAfterRewrite() throws {
		let root = try codexRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent(
			"2026/07/01/rollout-2026-07-01T12-00-00-feedface-0000-0000-0000-00000000abcd.jsonl")
		try writeCodexTotals([(0, 0, 0), (100, 0, 10)], to: file)

		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		_ = try indexer.refresh(CodexProvider(root: root))
		XCTAssertEqual(index.eventCount(provider: .codex), 1)

		try writeCodexTotals([(50, 0, 5), (100, 0, 10)], to: file)
		_ = try indexer.refresh(CodexProvider(root: root))

		let now = iso.date(from: "2026-07-01T12:30:00.000Z")!
		let r = try index.rollup(provider: .codex, now: now, calendar: utc())
		XCTAssertEqual(index.eventCount(provider: .codex), 2)
		XCTAssertEqual(r.last7d.usage.input, 100)
		XCTAssertEqual(r.last7d.usage.output, 10)
	}

	func testCodexGrowingRolloutResumesFromPersistedParserState() throws {
		let root = try codexRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent(
			"2026/07/01/rollout-2026-07-01T12-00-00-feedface-0000-0000-0000-00000000cafe.jsonl")
		try writeCodexTotals([(100, 20, 10)], to: file)
		let dbPath = tempDBPath()

		do {
			let index = try UsageIndex(path: dbPath)
			let provider = CodexProvider(root: root)
			let dataFiles = provider.dataFiles()
			XCTAssertEqual(dataFiles.count, 1)
			let indexedFile = try XCTUnwrap(dataFiles.first)
			let initialStats = try UsageIndexer(index: index).refresh(provider)
			XCTAssertEqual(initialStats.filesRead, 1)
			XCTAssertFalse(index.cursor(for: indexedFile.path, provider: provider.id)?.parserState.isEmpty ?? true)
		}

		let appended =
			#"{"type":"event_msg","timestamp":"2026-07-01T12:00:02.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":25}}}}"#
		try appendLine(appended, to: file)
		let index = try UsageIndex(path: dbPath)
		let stats = try UsageIndexer(index: index).refresh(CodexProvider(root: root))
		let rollup = try index.rollup(
			provider: .codex, now: iso.date(from: "2026-07-01T12:30:00.000Z")!, calendar: utc())

		XCTAssertEqual(stats.filesRead, 1)
		XCTAssertEqual(stats.eventsIngested, 1)
		XCTAssertEqual(index.eventCount(provider: .codex), 2)
		XCTAssertEqual(rollup.last7d.usage.input, 150)
		XCTAssertEqual(rollup.last7d.usage.cacheRead, 50)
		XCTAssertEqual(rollup.last7d.usage.output, 25)
	}

	func testCodexRateLimitRestoresFromDurableParserState() throws {
		let root = try codexRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent(
			"2026/07/01/rollout-2026-07-01T12-00-00-feedface-0000-0000-0000-00000000beef.jsonl")
		try FileManager.default.createDirectory(
			at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		let reset = iso.date(from: "2026-07-08T12:00:00.000Z")!.timeIntervalSince1970
		let line =
			#"{"type":"event_msg","timestamp":"2026-07-01T12:00:01.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}},"rate_limits":{"limit_id":"codex","plan_type":"pro","primary":{"used_percent":42,"window_minutes":10080,"resets_at":\#(reset)},"secondary":null}}}"#
		try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
		let dbPath = tempDBPath()

		do {
			let index = try UsageIndex(path: dbPath)
			_ = try UsageIndexer(index: index).refresh(CodexProvider(root: root))
		}

		let restoredIndex = try UsageIndex(path: dbPath)
		let states = try restoredIndex.parserStates(provider: .codex)
		XCTAssertEqual(states.count, 1)
		let now = iso.date(from: "2026-07-01T13:00:00.000Z")!
		let snapshot = CodexProvider(root: root).latestRateLimitState(
			now: now, persistedStates: states).current
		XCTAssertEqual(snapshot?.secondary?.usedPercent, 42)
		XCTAssertEqual(snapshot?.planType, "pro")
	}

	func testCodexAppendedCounterCorrectionFallsBackToFullReconciliation() throws {
		let root = try codexRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent(
			"2026/07/01/rollout-2026-07-01T12-00-00-feedface-0000-0000-0000-00000000fade.jsonl")
		try writeCodexTotals([(100, 0, 10)], to: file)
		let index = try UsageIndex(path: tempDBPath())
		let indexer = UsageIndexer(index: index)
		_ = try indexer.refresh(CodexProvider(root: root))

		let correction =
			#"{"type":"event_msg","timestamp":"2026-07-01T12:00:02.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":90,"cached_input_tokens":0,"output_tokens":9}}}}"#
		try appendLine(correction, to: file)
		_ = try indexer.refresh(CodexProvider(root: root))
		let rollup = try index.rollup(
			provider: .codex, now: iso.date(from: "2026-07-01T12:30:00.000Z")!, calendar: utc())

		XCTAssertEqual(index.eventCount(provider: .codex), 1)
		XCTAssertEqual(rollup.last7d.usage.input, 90)
		XCTAssertEqual(rollup.last7d.usage.output, 9)
	}

	private func codexRoot() throws -> URL {
		let root = try tempDir()
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("2026/07/01", isDirectory: true),
			withIntermediateDirectories: true)
		return root
	}

	private func writeCodexTotals(_ totals: [(input: Int, cached: Int, output: Int)], to file: URL)
		throws
	{
		var lines = [
			"""
			{"type":"turn_context","timestamp":"2026-07-01T12:00:00.000Z","payload":{"model":"gpt-5.5","cwd":"/Users/x/proj"}}
			"""
		]
		for (index, total) in totals.enumerated() {
			lines.append(
				"""
				{"type":"event_msg","timestamp":"2026-07-01T12:00:0\(index + 1).000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(total.input),"cached_input_tokens":\(total.cached),"output_tokens":\(total.output)}}}}
				""")
		}
		try (lines.joined(separator: "\n") + "\n").write(
			to: file, atomically: true, encoding: .utf8)
	}

	private func appendLine(_ line: String, to file: URL) throws {
		let handle = try FileHandle(forWritingTo: file)
		defer { try? handle.close() }
		try handle.seekToEnd()
		try handle.write(contentsOf: Data((line + "\n").utf8))
	}
}

// MARK: - modelDaySummaries (Advanced Analytics tray)

final class UsageIndexModelDaySummariesTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}
	private let iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()
	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-mds-\(UUID().uuidString).sqlite").path
	}
	private func event(
		_ msg: String, _ req: String, _ ts: String, model: String, provider: ProviderID = .claude,
		input: Int = 100, output: Int = 200, cache5m: Int = 0, cache1h: Int = 0, cacheRead: Int = 0
	) -> UsageEvent {
		UsageEvent(
			messageId: msg, requestId: req, provider: provider, model: model,
			timestamp: iso.date(from: ts)!,
			usage: TokenUsage(
				input: input, output: output, cacheCreate5m: cache5m, cacheCreate1h: cache1h,
				cacheRead: cacheRead))
	}

	/// Two events land on the same model/day and must accumulate (event count, every token type, and
	/// cost) into ONE row rather than producing one row per event.
	func testAggregatesMultipleEventsForTheSameModelAndDay() throws {
		let index = try UsageIndex(path: tempDBPath())
		let model = "claude-opus-4-8"
		try index.ingest([
			event("a", "r1", "2026-07-07T01:00:00.000Z", model: model, input: 100, output: 200, cache5m: 10, cache1h: 20, cacheRead: 30),
			event("b", "r2", "2026-07-07T09:00:00.000Z", model: model, input: 50, output: 100, cache5m: 5, cache1h: 0, cacheRead: 15),
		])
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		let rows = try index.modelDaySummaries(providers: [.claude], days: 7, now: now, calendar: utc())

		XCTAssertEqual(rows.count, 1)
		let row = try XCTUnwrap(rows.first)
		XCTAssertEqual(row.provider, .claude)
		XCTAssertEqual(row.model, model)
		XCTAssertEqual(row.eventCount, 2)
		XCTAssertEqual(row.inputTokens, 150)
		XCTAssertEqual(row.outputTokens, 300)
		XCTAssertEqual(row.cache5mTokens, 15)
		XCTAssertEqual(row.cache1hTokens, 20)
		XCTAssertEqual(row.cacheReadTokens, 45)
		XCTAssertGreaterThan(row.cost, 0)
	}

	/// Different days for the same model produce distinct rows; different providers/models within the
	/// same day also stay distinct — the query never collapses across a slicing dimension.
	func testSlicesRowsPerProviderModelAndDayIndependently() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.ingest([
			event("a", "r1", "2026-07-01T09:00:00.000Z", model: "claude-opus-4-8", provider: .claude),
			event("b", "r2", "2026-07-02T09:00:00.000Z", model: "claude-opus-4-8", provider: .claude),
			event("c", "r3", "2026-07-02T09:00:00.000Z", model: "claude-haiku-4-5", provider: .claude),
			event("d", "r4", "2026-07-02T09:00:00.000Z", model: "gpt-5-codex", provider: .codex),
		])
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		let rows = try index.modelDaySummaries(providers: [.claude, .codex], days: 7, now: now, calendar: utc())

		XCTAssertEqual(rows.count, 4)
		// Oldest day first (stable order guarantee for the CSV/table view).
		XCTAssertEqual(rows.first?.day, utc().startOfDay(for: iso.date(from: "2026-07-01T09:00:00.000Z")!))
		XCTAssertTrue(rows.contains { $0.provider == .codex && $0.model == "gpt-5-codex" })
		XCTAssertTrue(rows.contains { $0.provider == .claude && $0.model == "claude-haiku-4-5" })
	}

	func testOmitsProvidersOutsideTheRequestedAllowlist() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.ingest([
			event("a", "r1", "2026-07-07T01:00:00.000Z", model: "claude-opus-4-8", provider: .claude),
			event("b", "r2", "2026-07-07T01:00:00.000Z", model: "gpt-5-codex", provider: .codex),
		])
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		let rows = try index.modelDaySummaries(providers: [.claude], days: 7, now: now, calendar: utc())
		XCTAssertEqual(rows.count, 1)
		XCTAssertEqual(rows.first?.provider, .claude)
	}
}

// MARK: - ModelDaySummary.bucketed (Copilot, which bypasses UsageIndex entirely)

/// Copilot's events flow via `CopilotProvider.loadEvents()` directly (never through `UsageIndexer`/
/// `UsageIndex`), so the Advanced Analytics tray needs a SEPARATE pure bucketing path with the exact
/// same aggregation rule as `UsageIndex.modelDaySummaries`'s SQL loop.
final class ModelDaySummaryBucketedTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}
	private let iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()
	private func event(
		_ msg: String, _ req: String, _ ts: String, model: String, provider: ProviderID = .copilot,
		input: Int = 100, output: Int = 200
	) -> UsageEvent {
		UsageEvent(
			messageId: msg, requestId: req, provider: provider, model: model,
			timestamp: iso.date(from: ts)!,
			usage: TokenUsage(input: input, output: output))
	}

	func testAggregatesMultipleEventsForTheSameModelAndDay() throws {
		let rows = ModelDaySummary.bucketed(
			events: [
				event("a", "r1", "2026-07-07T01:00:00.000Z", model: "gpt-5-mini", input: 100, output: 200),
				event("b", "r2", "2026-07-07T09:00:00.000Z", model: "gpt-5-mini", input: 50, output: 100),
			],
			calculator: CostCalculator(), calendar: utc())

		XCTAssertEqual(rows.count, 1)
		let row = try XCTUnwrap(rows.first)
		XCTAssertEqual(row.provider, .copilot)
		XCTAssertEqual(row.model, "gpt-5-mini")
		XCTAssertEqual(row.eventCount, 2)
		XCTAssertEqual(row.inputTokens, 150)
		XCTAssertEqual(row.outputTokens, 300)
	}

	func testSlicesRowsPerModelAndDayIndependently() {
		let rows = ModelDaySummary.bucketed(
			events: [
				event("a", "r1", "2026-07-01T09:00:00.000Z", model: "gpt-5-mini"),
				event("b", "r2", "2026-07-02T09:00:00.000Z", model: "gpt-5-mini"),
				event("c", "r3", "2026-07-02T09:00:00.000Z", model: "claude-sonnet-4.5"),
			],
			calculator: CostCalculator(), calendar: utc())

		XCTAssertEqual(rows.count, 3)
		XCTAssertEqual(rows.first?.day, utc().startOfDay(for: iso.date(from: "2026-07-01T09:00:00.000Z")!))
	}

	func testEmptyEventsProducesEmptyRows() {
		XCTAssertEqual(
			ModelDaySummary.bucketed(events: [], calculator: CostCalculator(), calendar: utc()).count, 0)
	}
}

// MARK: - ModelDayAccumulator parity (the shared bucketing rule)

/// `ModelDaySummary.bucketed` and `UsageIndex.modelDaySummaries` are the SAME aggregation over two
/// different row sources (an in-memory `[UsageEvent]` versus a SQLite cursor), and both feed the SAME
/// Advanced Analytics table and CSV export. That contract used to be enforced only by two byte-identical
/// 45-line transcriptions of the key/accumulator/sort logic, free to drift apart silently; they now
/// share one `ModelDayAccumulator`. These tests are what proves the shared rule actually produces
/// row-for-row identical output, so a future refactor cannot re-split them without going red.
final class UsageIndexModelDayAccumulatorParityTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}
	private let iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()
	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-mda-\(UUID().uuidString).sqlite").path
	}

	/// Deliberately adversarial to the shared rule: several providers (including one whose events are
	/// interleaved with another's), the SAME model name under two providers, repeats within one slot,
	/// every token type non-zero and unequal, events supplied OUT of chronological order (so first-seen
	/// insertion order differs between the array walk and SQLite's index-ordered cursor), and a model
	/// with no price at all so the `?? 0` cost branch is exercised on both sides.
	private func fixture() -> [UsageEvent] {
		func ev(
			_ msg: String, _ ts: String, provider: ProviderID, model: String,
			_ input: Int, _ output: Int, _ c5: Int, _ c1: Int, _ read: Int
		) -> UsageEvent {
			UsageEvent(
				messageId: msg, requestId: "r-\(msg)", provider: provider, model: model,
				timestamp: iso.date(from: ts)!,
				usage: TokenUsage(
					input: input, output: output, cacheCreate5m: c5, cacheCreate1h: c1, cacheRead: read))
		}
		return [
			ev("h", "2026-07-05T23:59:59.000Z", provider: .claude, model: "claude-opus-4-8", 7, 11, 13, 17, 19),
			ev("a", "2026-07-03T01:00:00.000Z", provider: .claude, model: "claude-opus-4-8", 100, 200, 10, 20, 30),
			ev("d", "2026-07-04T09:00:00.000Z", provider: .codex, model: "gpt-5-codex", 41, 43, 47, 53, 59),
			ev("b", "2026-07-03T18:30:00.000Z", provider: .claude, model: "claude-opus-4-8", 51, 52, 53, 54, 55),
			ev("g", "2026-07-04T09:00:00.000Z", provider: .codex, model: "gpt-5-codex", 61, 67, 71, 73, 79),
			ev("c", "2026-07-03T02:00:00.000Z", provider: .claude, model: "claude-haiku-4-5", 5, 6, 7, 8, 9),
			// Same model string under two providers on the same day: the key must not collapse them.
			ev("e", "2026-07-04T10:00:00.000Z", provider: .claude, model: "gpt-5-codex", 1, 2, 3, 4, 5),
			// Fully unpriced -> `calculator.cost(...) == nil` -> 0 on both paths.
			ev("f", "2026-07-05T08:00:00.000Z", provider: .codex, model: "totally-made-up-model-xyz", 9, 8, 7, 6, 5),
		]
	}

	/// Every non-cost field must match EXACTLY. `cost` is compared with a tolerance rather than `==`
	/// because the two paths sum the same per-event doubles in a different order (array order versus
	/// SQLite's index order), and double addition is not associative — a last-ulp difference there is
	/// correct behavior, not drift.
	private func assertSameRows(
		_ lhs: [ModelDaySummary], _ rhs: [ModelDaySummary], file: StaticString = #filePath,
		line: UInt = #line
	) {
		XCTAssertEqual(lhs.count, rhs.count, "row COUNT differs", file: file, line: line)
		guard lhs.count == rhs.count else { return }
		for (offset, pair) in zip(lhs, rhs).enumerated() {
			let (l, r) = pair
			let where_ = "row \(offset)"
			XCTAssertEqual(l.provider, r.provider, where_, file: file, line: line)
			XCTAssertEqual(l.model, r.model, where_, file: file, line: line)
			XCTAssertEqual(l.day, r.day, where_, file: file, line: line)
			XCTAssertEqual(l.eventCount, r.eventCount, where_, file: file, line: line)
			XCTAssertEqual(l.inputTokens, r.inputTokens, where_, file: file, line: line)
			XCTAssertEqual(l.outputTokens, r.outputTokens, where_, file: file, line: line)
			XCTAssertEqual(l.cache5mTokens, r.cache5mTokens, where_, file: file, line: line)
			XCTAssertEqual(l.cache1hTokens, r.cache1hTokens, where_, file: file, line: line)
			XCTAssertEqual(l.cacheReadTokens, r.cacheReadTokens, where_, file: file, line: line)
			XCTAssertEqual(l.cost, r.cost, accuracy: 1e-9, where_, file: file, line: line)
		}
	}

	func testBucketedAndModelDaySummariesAgreeRowForRow() throws {
		let events = fixture()
		let calendar = utc()
		let now = iso.date(from: "2026-07-06T12:00:00.000Z")!
		let calculator = CostCalculator()

		let index = try UsageIndex(path: tempDBPath())
		try index.ingest(events)
		let indexed = try index.modelDaySummaries(
			providers: [.claude, .codex], days: 7, calculator: calculator, now: now, calendar: calendar)
		let inMemory = ModelDaySummary.bucketed(
			events: events, calculator: calculator, calendar: calendar)

		// Sanity: the fixture must actually produce multiple slots, or "identical" would be vacuous.
		XCTAssertEqual(indexed.count, 6, "fixture must span several (provider, model, day) slots")
		XCTAssertTrue(indexed.contains { $0.eventCount == 2 }, "fixture must accumulate a repeated slot")
		assertSameRows(indexed, inMemory)
	}

	/// The sort is a TOTAL order over the key, so the two paths' differing first-seen insertion order
	/// cannot leak into the result. Pinned explicitly because it is the one property that lets the
	/// shared accumulator serve an array walk and a cursor walk interchangeably.
	func testRowOrderIsIdenticalAndIndependentOfInsertionOrder() throws {
		let calendar = utc()
		let forwards = fixture().sorted { $0.timestamp < $1.timestamp }
		let backwards = Array(forwards.reversed())
		let calculator = CostCalculator()

		let a = ModelDaySummary.bucketed(events: forwards, calculator: calculator, calendar: calendar)
		let b = ModelDaySummary.bucketed(events: backwards, calculator: calculator, calendar: calendar)
		assertSameRows(a, b)

		let index = try UsageIndex(path: tempDBPath())
		try index.ingest(backwards)
		let indexed = try index.modelDaySummaries(
			providers: [.claude, .codex], days: 7, calculator: calculator,
			now: iso.date(from: "2026-07-06T12:00:00.000Z")!, calendar: calendar)
		assertSameRows(indexed, a)

		// Oldest day first, then provider, then model — asserted on the concrete keys, not just
		// "some order", so a comparator inversion cannot pass.
		XCTAssertEqual(
			indexed.map { "\($0.provider.rawValue)/\($0.model)" },
			[
				// 2026-07-03
				"claude/claude-haiku-4-5", "claude/claude-opus-4-8",
				// 2026-07-04 (same model, two providers -> tie broken by provider)
				"claude/gpt-5-codex", "codex/gpt-5-codex",
				// 2026-07-05
				"claude/claude-opus-4-8", "codex/totally-made-up-model-xyz",
			])
	}

	func testBothPathsReturnNoRowsForNoEvents() throws {
		let index = try UsageIndex(path: tempDBPath())
		let indexed = try index.modelDaySummaries(
			providers: [.claude, .codex], days: 7, now: iso.date(from: "2026-07-06T12:00:00.000Z")!,
			calendar: utc())
		assertSameRows(indexed, ModelDaySummary.bucketed(
			events: [], calculator: CostCalculator(), calendar: utc()))
		XCTAssertTrue(indexed.isEmpty)
	}
}

// MARK: - AnalyticsCSVExporter

final class AnalyticsCSVExporterTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}

	func testProducesHeaderAndOneRowPerSummary() {
		let cal = utc()
		let day = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
		let rows = [
			ModelDaySummary(
				provider: .claude, model: "claude-opus-4-8", day: day, eventCount: 3, inputTokens: 100,
				outputTokens: 200, cache5mTokens: 10, cache1hTokens: 20, cacheReadTokens: 30, cost: 12.3456)
		]
		let csv = AnalyticsCSVExporter.csv(rows: rows, calendar: cal)
		let lines = csv.components(separatedBy: "\r\n")
		XCTAssertEqual(lines.count, 2)
		XCTAssertEqual(lines[0], "date,provider,model,events,input_tokens,output_tokens,cache_5m_tokens,cache_1h_tokens,cache_read_tokens,cost_usd")
		XCTAssertEqual(lines[1], "2026-07-01,claude,claude-opus-4-8,3,100,200,10,20,30,12.3456")
	}

	/// RFC4180 edge cases: a model/field containing a comma, an embedded quote, and a newline must all
	/// round-trip as ONE quoted field, never split the row or corrupt column alignment.
	func testQuotesFieldsContainingCommaQuoteOrNewline() {
		let cal = utc()
		let day = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
		let rows = [
			ModelDaySummary(
				provider: .claude, model: "weird, \"model\"\nname", day: day, eventCount: 1,
				inputTokens: 1, outputTokens: 1, cache5mTokens: 0, cache1hTokens: 0, cacheReadTokens: 0,
				cost: 0)
		]
		let csv = AnalyticsCSVExporter.csv(rows: rows, calendar: cal)
		XCTAssertTrue(csv.contains("\"weird, \"\"model\"\"\nname\""))
	}

	func testDefaultFilenameIncludesDate() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 9))!
		XCTAssertEqual(AnalyticsCSVExporter.defaultFilename(now: now, calendar: cal), "jpthecat-analytics-2026-07-09.csv")
	}
}

// MARK: - AnalyticsJSONExporter

final class AnalyticsJSONExporterTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}

	func testEmitsOneObjectPerSummaryWithCSVMatchingFieldsAndRoundedCost() throws {
		let cal = utc()
		let day = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
		let rows = [
			ModelDaySummary(
				provider: .claude, model: "claude-opus-4-8", day: day, eventCount: 3, inputTokens: 100,
				outputTokens: 200, cache5mTokens: 10, cache1hTokens: 20, cacheReadTokens: 30, cost: 12.34567)
		]
		let json = AnalyticsJSONExporter.json(rows: rows, calendar: cal)
		let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
		let obj = try XCTUnwrap(parsed?.first)
		XCTAssertEqual(obj["date"] as? String, "2026-07-01")
		XCTAssertEqual(obj["provider"] as? String, "claude")
		XCTAssertEqual(obj["model"] as? String, "claude-opus-4-8")
		XCTAssertEqual(obj["events"] as? Int, 3)
		XCTAssertEqual(obj["input_tokens"] as? Int, 100)
		XCTAssertEqual(obj["output_tokens"] as? Int, 200)
		XCTAssertEqual(obj["cache_5m_tokens"] as? Int, 10)
		XCTAssertEqual(obj["cache_1h_tokens"] as? Int, 20)
		XCTAssertEqual(obj["cache_read_tokens"] as? Int, 30)
		// Rounded to 4 dp to match the CSV's `%.4f` precision.
		XCTAssertEqual(try XCTUnwrap(obj["cost_usd"] as? Double), 12.3457, accuracy: 1e-9)
	}

	func testEmptyRowsProduceAnEmptyJSONArray() throws {
		let json = AnalyticsJSONExporter.json(rows: [], calendar: utc())
		let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any]
		XCTAssertEqual(parsed?.count, 0)
	}

	func testDefaultFilenameUsesJSONExtension() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 9))!
		XCTAssertEqual(AnalyticsJSONExporter.defaultFilename(now: now, calendar: cal), "jpthecat-analytics-2026-07-09.json")
	}
}

// MARK: - AnalyticsMarkdownExporter

final class AnalyticsMarkdownExporterTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}

	func testProducesHeaderSeparatorAndOneRowPerSummary() {
		let cal = utc()
		let day = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
		let rows = [
			ModelDaySummary(
				provider: .claude, model: "claude-opus-4-8", day: day, eventCount: 3, inputTokens: 100,
				outputTokens: 200, cache5mTokens: 10, cache1hTokens: 20, cacheReadTokens: 30, cost: 12.3456)
		]
		let md = AnalyticsMarkdownExporter.markdown(rows: rows, calendar: cal)
		let lines = md.components(separatedBy: "\n")
		XCTAssertEqual(lines.count, 3)  // header + alignment + one data row
		XCTAssertEqual(
			lines[0],
			"| date | provider | model | events | input_tokens | output_tokens | cache_5m_tokens | cache_1h_tokens | cache_read_tokens | cost_usd |")
		XCTAssertEqual(lines[1], "| :-- | :-- | :-- | --: | --: | --: | --: | --: | --: | --: |")
		XCTAssertEqual(
			lines[2], "| 2026-07-01 | claude | claude-opus-4-8 | 3 | 100 | 200 | 10 | 20 | 30 | 12.3456 |")
	}

	/// A `|` or newline in a model name must never break the table's column alignment.
	func testEscapesPipeAndNewlineInCellValues() {
		let cal = utc()
		let day = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
		let rows = [
			ModelDaySummary(
				provider: .claude, model: "weird|model\nname", day: day, eventCount: 1, inputTokens: 1,
				outputTokens: 1, cache5mTokens: 0, cache1hTokens: 0, cacheReadTokens: 0, cost: 0)
		]
		let md = AnalyticsMarkdownExporter.markdown(rows: rows, calendar: cal)
		let dataLine = md.components(separatedBy: "\n")[2]
		XCTAssertTrue(dataLine.contains("weird\\|model name"))  // pipe escaped, newline flattened to space
		// The data row still has exactly the 10 columns (11 pipes) — the escape didn't add a column.
		XCTAssertEqual(dataLine.filter { $0 == "|" }.count - dataLine.filter { $0 == "\\" }.count, 11)
	}

	func testDefaultFilenameUsesMarkdownExtension() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 9))!
		XCTAssertEqual(AnalyticsMarkdownExporter.defaultFilename(now: now, calendar: cal), "jpthecat-analytics-2026-07-09.md")
	}
}
