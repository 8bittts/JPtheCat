import Foundation
import XCTest

@testable import JPtheCatCore

/// Muse Spark declares `canTailAppend: false`, so `FileCursor.classify` returns `.reset` for ANY
/// change to `opencode.db` — and the DB mutates on every message during a live session. Unbounded,
/// each 2 s refresh deleted N rows and re-upserted N rows where N is the LIFETIME message count, so
/// both write volume and SQLite free-page churn grew linearly with total history, forever.
///
/// These guards pin the change-scoped bound: the cursor's `offset` field carries a
/// `max($.time.created)` watermark, the decode filters on it, and the `.reset` delete no longer wipes
/// the whole source path once a watermark exists.
final class MuseSparkProviderWatermarkTests: XCTestCase {
	private func tempDirectory() throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-muse-watermark-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func stage(root: URL) throws -> URL {
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
			INSERT INTO session VALUES ('ses_1','proj_a','s','t',0,0,0,0,0,0,NULL,1,1);
			""")
		try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
		return file
	}

	@discardableResult
	private func insertMessage(
		into file: URL, id: String, createdMillis: Int, model: String = "muse-spark-1.1",
		provider: String = "meta", input: Int = 100, output: Int = 20
	) throws -> Int {
		let db = try SQLiteDatabase(path: file.path)
		let data: [String: Any] = [
			"role": "assistant", "modelID": model, "providerID": provider,
			"tokens": ["input": input, "output": output, "reasoning": 0, "cache": ["read": 0, "write": 0]],
			"time": ["created": createdMillis, "completed": createdMillis + 1],
		]
		let stmt = try db.prepare(
			"INSERT OR REPLACE INTO message (id, session_id, time_created, time_updated, data) "
				+ "VALUES (?1, 'ses_1', ?2, ?2, ?3)")
		stmt.bind(1, id)
		stmt.bind(2, createdMillis)
		stmt.bind(3, String(decoding: try JSONSerialization.data(withJSONObject: data), as: UTF8.self))
		_ = try stmt.step()
		try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
		return createdMillis
	}

	// MARK: - Decode bound

	func testBoundedDecodeReturnsOnlyMessagesAtOrAfterTheWatermark() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		try insertMessage(into: file, id: "m1", createdMillis: 1_000)
		try insertMessage(into: file, id: "m2", createdMillis: 2_000)
		try insertMessage(into: file, id: "m3", createdMillis: 3_000)

		let all = MuseSparkProvider.decodeDatabase(fileURL: file, createdAtOrAfterMillis: 0)
		XCTAssertEqual(Set(all.events.map(\.messageId)), ["m1", "m2", "m3"])
		XCTAssertEqual(all.watermark, 3_000)

		// `>=` on purpose: the newest row is the one still being written, so it stays in range.
		let resumed = MuseSparkProvider.decodeDatabase(fileURL: file, createdAtOrAfterMillis: 3_000)
		XCTAssertEqual(resumed.events.map(\.messageId), ["m3"])
		XCTAssertEqual(resumed.watermark, 3_000)

		let empty = MuseSparkProvider.decodeDatabase(fileURL: file, createdAtOrAfterMillis: 9_000)
		XCTAssertTrue(empty.events.isEmpty)
	}

	/// The watermark tracks every assistant row VISITED, not just the spark rows that produced events,
	/// so a long non-spark tail is not rescanned on every refresh forever.
	func testWatermarkAdvancesPastNonSparkRows() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		try insertMessage(into: file, id: "m1", createdMillis: 1_000)
		try insertMessage(
			into: file, id: "m2", createdMillis: 5_000, model: "deepseek-v4", provider: "opencode")

		let scan = MuseSparkProvider.decodeDatabase(fileURL: file, createdAtOrAfterMillis: 0)
		XCTAssertEqual(scan.events.map(\.messageId), ["m1"])
		XCTAssertEqual(scan.watermark, 5_000)
	}

	/// [Regression guard] A bounded scan coming back empty means "no new turns", NOT "this DB has no
	/// message-level data" — only an unbounded scan licenses the cumulative session fallback. Switching
	/// granularity on an empty bounded scan would silently re-report lifetime session totals as new.
	func testEmptyBoundedScanDoesNotFallBackToTheSessionDecode() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		let db = try SQLiteDatabase(path: file.path)
		try db.execute(
			"UPDATE session SET model = '{\"id\":\"muse-spark-1.1\",\"providerID\":\"meta\"}', "
				+ "tokens_input = 9999 WHERE id = 'ses_1';")
		try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
		try insertMessage(into: file, id: "m1", createdMillis: 1_000)

		XCTAssertTrue(
			MuseSparkProvider.decodeDatabase(fileURL: file, createdAtOrAfterMillis: 9_000).events.isEmpty)
		// With no message rows at all, the unbounded decode still falls back to sessions (unchanged).
		let root2 = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root2) }
		let sessionOnly = try stage(root: root2)
		let db2 = try SQLiteDatabase(path: sessionOnly.path)
		try db2.execute(
			"UPDATE session SET model = '{\"id\":\"muse-spark-1.1\",\"providerID\":\"meta\"}', "
				+ "tokens_input = 42 WHERE id = 'ses_1';")
		try db2.execute("PRAGMA wal_checkpoint(TRUNCATE);")
		let fallback = MuseSparkProvider.decodeDatabase(fileURL: sessionOnly, createdAtOrAfterMillis: 0)
		XCTAssertEqual(fallback.events.map(\.messageId), ["ses_1"])
		XCTAssertEqual(fallback.watermark, 0, "session fallback must not pin a watermark")
	}

	// MARK: - Indexer integration

	func testRefreshReIngestsOnlyTheChangedRangeAndKeepsHistory() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		let indexPath = root.appendingPathComponent("usage.sqlite").path
		let index = try UsageIndex(path: indexPath)
		let indexer = UsageIndexer(index: index)
		let provider = MuseSparkProvider(root: root)

		for i in 1...5 { try insertMessage(into: file, id: "m\(i)", createdMillis: i * 1_000) }
		let first = try indexer.refresh(provider)
		XCTAssertEqual(first.eventsIngested, 5)
		XCTAssertEqual(index.eventCount(provider: .museSpark), 5)
		XCTAssertEqual(index.cursor(for: file.path, provider: .museSpark)?.offset, 5_000, "cursor carries the watermark")

		// A live-session write: one new message. The whole lifetime set must NOT be re-ingested.
		try insertMessage(into: file, id: "m6", createdMillis: 6_000)
		let second = try indexer.refresh(provider)
		XCTAssertEqual(
			second.eventsIngested, 2,
			"only the boundary row (m5, re-read because the bound is >=) and the new m6")
		XCTAssertEqual(index.eventCount(provider: .museSpark), 6, "history survives, nothing doubled")
		XCTAssertEqual(index.cursor(for: file.path, provider: .museSpark)?.offset, 6_000)

		// Still idempotent: a refresh with no change at all touches nothing.
		let third = try indexer.refresh(provider)
		XCTAssertEqual(third.filesSkipped, 1)
		XCTAssertEqual(index.eventCount(provider: .museSpark), 6)
	}

	/// The boundary row is re-read on every pass, so a mutating newest message still lands — this is
	/// what the `>=` bound plus keep-max-output upsert buys.
	func testMutatingNewestMessageIsStillPickedUp() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		let index = try UsageIndex(path: root.appendingPathComponent("usage.sqlite").path)
		let indexer = UsageIndexer(index: index)
		let provider = MuseSparkProvider(root: root)

		let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
		try insertMessage(into: file, id: "m1", createdMillis: nowMillis, input: 100, output: 10)
		_ = try indexer.refresh(provider)
		XCTAssertEqual(try index.rollup(provider: .museSpark).last7d.usage.input, 100)

		// Same message id and created time, larger token counts (a turn that finished streaming).
		try insertMessage(into: file, id: "m1", createdMillis: nowMillis, input: 900, output: 90)
		_ = try indexer.refresh(provider)
		XCTAssertEqual(try index.rollup(provider: .museSpark).last7d.usage.input, 900)
		XCTAssertEqual(index.eventCount(provider: .museSpark), 1)
	}

	// MARK: - Reset policy

	func testResetPolicySelection() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		XCTAssertEqual(MuseSparkProvider(root: root).resetPolicy, .watermark)
		try FileManager.default.removeItem(at: file)
		let logDir = root.appendingPathComponent("log", isDirectory: true)
		try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
		try "\n".write(
			to: logDir.appendingPathComponent("opencode.log"), atomically: true, encoding: .utf8)
		XCTAssertEqual(MuseSparkProvider(root: root).resetPolicy, .rereadWhole)
	}

	func testResetDeleteScoping() {
		// The default stays a full replace for every whole-file re-read.
		XCTAssertTrue(UsageIndexer.resetDeletesIndexedEvents(policy: .rereadWhole, from: 0))
		XCTAssertTrue(UsageIndexer.resetDeletesIndexedEvents(policy: .rereadWhole, from: 500))
		// A watermark provider replaces everything on its FIRST pass, then only adds.
		XCTAssertTrue(UsageIndexer.resetDeletesIndexedEvents(policy: .watermark, from: 0))
		XCTAssertFalse(UsageIndexer.resetDeletesIndexedEvents(policy: .watermark, from: 1))
		// An append-only JP-owned source never wipes its own warehouse history.
		XCTAssertFalse(
			UsageIndexer.resetDeletesIndexedEvents(policy: .rereadWholeRetainingIndexedEvents, from: 0))
	}

	/// The wholesale answer above is only half the contract: a resumed `.watermark` reset must delete
	/// the RANGE it is about to re-read, not nothing at all.
	func testResetDeletionSelectsTheRangeScopedDeleteWhenResuming() {
		XCTAssertEqual(UsageIndexer.resetDeletion(policy: .rereadWhole, from: 0), .wholeSourcePath)
		XCTAssertEqual(UsageIndexer.resetDeletion(policy: .rereadWhole, from: 500), .wholeSourcePath)
		XCTAssertEqual(UsageIndexer.resetDeletion(policy: .watermark, from: 0), .wholeSourcePath)
		XCTAssertEqual(UsageIndexer.resetDeletion(policy: .watermark, from: 1), .atOrAfterWatermark)
		XCTAssertEqual(
			UsageIndexer.resetDeletion(policy: .rereadWholeRetainingIndexedEvents, from: 0), .none)
	}

	/// The watermark is `$.time.created` in MILLISECONDS, and `decodeMessages` stamps each event with
	/// `Double(createdMillis) / 1000` — the delete bound must reproduce that exactly or the boundary
	/// row falls outside the range it is about to be re-ingested into.
	func testWatermarkTimestampMatchesTheEventStampBitForBit() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		let created = 1_783_000_123_456
		try insertMessage(into: file, id: "m1", createdMillis: created)
		let event = try XCTUnwrap(
			MuseSparkProvider.decodeDatabase(fileURL: file, createdAtOrAfterMillis: 0).events.first)
		let provider = MuseSparkProvider(root: root)
		XCTAssertEqual(
			provider.watermarkTimestamp(created)?.timeIntervalSince1970,
			event.timestamp.timeIntervalSince1970)
		// A meaningless watermark suppresses the delete rather than widening it to the whole file.
		XCTAssertNil(provider.watermarkTimestamp(0))
		XCTAssertNil(provider.watermarkTimestamp(-1))
	}

	/// [Correctness gap closed] A message that CHANGES at or above the watermark must be genuinely
	/// replaced. Here `m5` (the boundary row) has its model rewritten to a NON-spark one and its
	/// tokens moved onto `m6`: without a range-scoped delete the stale `m5` Muse Spark event survives
	/// forever, because the keep-max-output upsert can only revise a row that is re-emitted.
	func testAResumedResetReplacesTheReReadRangeInsteadOfLeavingStaleRows() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		let index = try UsageIndex(path: root.appendingPathComponent("usage.sqlite").path)
		let indexer = UsageIndexer(index: index)
		let provider = MuseSparkProvider(root: root)

		for i in 1...5 { try insertMessage(into: file, id: "m\(i)", createdMillis: i * 1_000) }
		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .museSpark), 5)

		// The boundary row switches away from Muse Spark; a newer row arrives.
		try insertMessage(
			into: file, id: "m5", createdMillis: 5_000, model: "deepseek-v4", provider: "opencode")
		try insertMessage(into: file, id: "m6", createdMillis: 6_000)
		_ = try indexer.refresh(provider)

		XCTAssertEqual(
			index.eventCount(provider: .museSpark), 5,
			"m5 is no longer a Muse Spark turn, so it must be gone — m1…m4 plus m6")
		// `now` is pinned just past the fixture's epoch-relative timestamps (m1…m6 sit at 1…6 seconds
		// after 1970), so the window really does span every retained row rather than none of them.
		XCTAssertEqual(
			try index.rollup(provider: .museSpark, days: 2, now: Date(timeIntervalSince1970: 10))
				.last7d.usage.input, 500,
			"the retained history below the watermark must survive untouched (5 turns x 100 input)")
	}

	/// The range-scoped delete must never reach below the watermark: a resumed reset that re-reads
	/// nothing new still leaves every earlier event in place.
	func testAResumedResetNeverDeletesHistoryBelowTheWatermark() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = try stage(root: root)
		let index = try UsageIndex(path: root.appendingPathComponent("usage.sqlite").path)
		let indexer = UsageIndexer(index: index)
		let provider = MuseSparkProvider(root: root)

		for i in 1...4 { try insertMessage(into: file, id: "m\(i)", createdMillis: i * 1_000) }
		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .museSpark), 4)

		// Touch the DB without adding any assistant turn — a `.reset` with nothing new in range.
		let db = try SQLiteDatabase(path: file.path)
		try db.execute("UPDATE session SET time_updated = time_updated + 1 WHERE id = 'ses_1';")
		try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
		_ = try indexer.refresh(provider)
		XCTAssertEqual(
			index.eventCount(provider: .museSpark), 4, "no history below the watermark may be deleted")
	}
}
