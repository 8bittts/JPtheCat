import Foundation
import XCTest

@testable import JPtheCatCore

/// Index-level retention + source-path invariants — the regression safety net for the Analytics
/// Warehouse's "durable history beyond provider retention" work. These pin the exact behaviors that
/// change (Phase 3 stops deleting events whose source file the provider rotated away): that the
/// `PRIMARY KEY (provider, msg_id, req_id)` dedup can NEVER double-count the same event across source
/// files, that keep-max-output holds across paths, and that `deleteEvents(sourcePath:)` is scoped to
/// exactly one path. The existing `UsageIndexTests.testKeepMaxOutputUpsertIsOrderIndependent` covers
/// keep-max WITHOUT source paths; this file covers the cross-source-path / rotation dimension.
final class UsageIndexRetentionTests: XCTestCase {
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
			.appendingPathComponent("jpc-retain-\(UUID().uuidString).sqlite").path
	}
	private func event(
		_ msg: String, _ req: String, _ ts: String, output: Int, model: String = "claude-opus-4-8",
		provider: ProviderID = .claude
	) -> UsageEvent {
		UsageEvent(
			messageId: msg, requestId: req, provider: provider, model: model,
			timestamp: iso.date(from: ts)!, usage: TokenUsage(output: output))
	}

	/// The core anti-double-count guarantee: the SAME event (provider, msg_id, req_id) ingested from two
	/// DIFFERENT source files collapses to ONE row (keep-max-output) — so Phase 3 can retain events from
	/// a rotated-away file without any risk that re-seeing that event under a new path inflates totals.
	func testSameEventFromTwoSourcePathsIsCountedOnceKeepingMaxOutput() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let ts = "2026-06-30T10:00:00.000Z"
		try index.ingest([event("m", "r", ts, output: 40)], sourcePath: "/logs/a.jsonl")
		try index.ingest([event("m", "r", ts, output: 90)], sourcePath: "/logs/b.jsonl")

		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		let rollup = try index.rollup(provider: .claude, now: now, calendar: utc())
		XCTAssertEqual(rollup.last7d.eventCount, 1)
		XCTAssertEqual(rollup.last7d.usage.output, 90)
	}

	/// `deleteEvents(sourcePath:)` removes ONLY the given file's events — the mechanism Phase 3 stops
	/// invoking for rotated-away files. Pinned so that change stays deliberate and scoped.
	func testDeleteEventsRemovesOnlyTheGivenSourcePath() throws {
		let index = try UsageIndex(path: tempDBPath())
		let ts = "2026-06-30T10:00:00.000Z"
		try index.ingest([event("m1", "r1", ts, output: 10)], sourcePath: "/logs/a.jsonl")
		try index.ingest([event("m2", "r2", ts, output: 20)], sourcePath: "/logs/b.jsonl")
		XCTAssertEqual(index.eventCount(provider: .claude), 2)

		_ = try index.deleteEvents(sourcePath: "/logs/a.jsonl")

		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		XCTAssertEqual(try index.sourcePaths(provider: .claude), ["/logs/b.jsonl"])
	}

	/// When a provider rotates a log and the same event re-appears (with more output) under the NEW
	/// file, the upsert repoints the row's `source_path` to that new file — so deleting the OLD, now-gone
	/// path leaves the event intact. This is the retention path Phase 3 makes robust for the unchanged-
	/// output case too; here it documents the current coalesce behavior the safety net rests on.
	func testReingestUnderNewPathRepointsSourcePathAwayFromTheRotatedFile() throws {
		let index = try UsageIndex(path: tempDBPath())
		let ts = "2026-06-30T10:00:00.000Z"
		try index.ingest([event("m", "r", ts, output: 40)], sourcePath: "/logs/old.jsonl")
		try index.ingest([event("m", "r", ts, output: 90)], sourcePath: "/logs/new.jsonl")
		XCTAssertEqual(try index.sourcePaths(provider: .claude), ["/logs/new.jsonl"])

		_ = try index.deleteEvents(sourcePath: "/logs/old.jsonl")

		XCTAssertEqual(index.eventCount(provider: .claude), 1)
	}

	// MARK: - Phase 3 cursor-provider scoping (bounds the durable-retention sweep)

	/// `cursorPaths(provider:)` returns ONLY that provider's cursors — the isolation that lets the
	/// retention sweep drop a Claude file without ever touching a Codex cursor (the exact bug the
	/// per-cursor `provider` column prevents: a Claude refresh's `currentPaths` never includes Codex
	/// files, so an unscoped all-provider cursor set would sweep Codex's cursors as "stale").
	func testCursorPathsAreScopedPerProvider() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.setCursor(path: "/c/a.jsonl", size: 1, mtime: 1, offset: 1, provider: .claude)
		try index.setCursor(path: "/c/b.jsonl", size: 1, mtime: 1, offset: 1, provider: .claude)
		try index.setCursor(path: "/x/roll.jsonl", size: 1, mtime: 1, offset: 1, provider: .codex)

		XCTAssertEqual(try index.cursorPaths(provider: .claude), ["/c/a.jsonl", "/c/b.jsonl"])
		XCTAssertEqual(try index.cursorPaths(provider: .codex), ["/x/roll.jsonl"])

		// Simulate the sweep for a Claude refresh whose only live file is a.jsonl: b.jsonl is stale,
		// the Codex cursor is NEVER a candidate.
		let claudeStale = try index.cursorPaths(provider: .claude).subtracting(["/c/a.jsonl"])
		XCTAssertEqual(claudeStale, ["/c/b.jsonl"])
	}

	/// With composite PK (path, provider), a write with no provider creates a SEPARATE row
	/// with empty provider string. This is the intended behavior for shared-source-path providers.
	func testSetCursorWithNoProviderCreatesSeparateRow() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.setCursor(path: "/c/a.jsonl", size: 1, mtime: 1, offset: 1, provider: .claude)
		// A later write that omits provider creates a separate row with provider = ''
		try index.setCursor(path: "/c/a.jsonl", size: 2, mtime: 2, offset: 2, provider: nil)
		// The claude row is unchanged
		XCTAssertEqual(index.cursor(for: "/c/a.jsonl", provider: .claude)?.provider, ProviderID.claude.rawValue)
		XCTAssertEqual(index.cursor(for: "/c/a.jsonl", provider: .claude)?.size, 1, "claude row unchanged")
		// We can't directly query the empty-provider row (no ProviderID with empty string),
		// but we can verify it doesn't affect the claude row
	}

	/// A FRESH insert with no provider stores `''`; `setCursorProvider` then stamps it (the one-time
	/// backfill primitive), making the row scopeable by `cursorPaths(provider:)`.
	func testFreshInsertStoresEmptyProviderThenSetCursorProviderBackfills() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.setCursor(path: "/c/a.jsonl", size: 1, mtime: 1, offset: 1, provider: nil)
		// The empty-provider row is separate from any provider-specific row
		// We can't query it directly via cursor(for:provider:) since no ProviderID has empty string
		// but cursorPaths(provider: .claude) should be empty because the empty-provider row doesn't scope to claude
		XCTAssertTrue(try index.cursorPaths(provider: .claude).isEmpty)

		try index.setCursorProvider(path: "/c/a.jsonl", provider: .claude)
		// Now the empty-provider row is updated to provider = 'claude'
		XCTAssertEqual(index.cursor(for: "/c/a.jsonl", provider: .claude)?.provider, ProviderID.claude.rawValue)
		XCTAssertEqual(try index.cursorPaths(provider: .claude), ["/c/a.jsonl"])

		// Backfill is deliberately one-way: a later provider must not steal an already-scoped path.
		try index.setCursorProvider(path: "/c/a.jsonl", provider: .codex)
		XCTAssertEqual(index.cursor(for: "/c/a.jsonl", provider: .claude)?.provider, ProviderID.claude.rawValue)
		XCTAssertTrue(try index.cursorPaths(provider: .codex).isEmpty)
	}
}
