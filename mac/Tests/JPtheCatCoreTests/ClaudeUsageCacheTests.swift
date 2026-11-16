import Foundation
import XCTest

@testable import JPtheCatCore

/// Claude Code 2.1.325 no longer puts `rate_limits.model_scoped` on the statusline, so the Fable bar
/// comes from Claude Code's own usage cache in `~/.claude.json`. Every test uses fixture bytes or a
/// temp file, never the real `~/.claude.json`.
final class ClaudeUsageCacheTests: XCTestCase {
	private let account = "05e78f33-0000-4ee8-8fa8-000000000000"
	private let fetchedAtMs = 1_794_595_014_785.0

	/// The shape Claude Code 2.1.325 writes: a `weekly_all` row and a `weekly_scoped` Fable row.
	private func cacheJSON(account cacheAccount: String?, signedIn: String?, limits: String) -> Data {
		let cacheAccountField = cacheAccount.map { #","accountUuid":"\#($0)""# } ?? ""
		let oauth = signedIn.map { #","oauthAccount":{"accountUuid":"\#($0)","emailAddress":"x@example.com"}"# } ?? ""
		return """
			{"numStartups":3\(oauth),"cachedUsageUtilization":{"fetchedAtMs":\(fetchedAtMs)\(cacheAccountField),
			 "utilization":{"seven_day":{"utilization":100,"resets_at":"2026-11-14T16:59:59.705975+00:00"},
			 "limits":\(limits)}}}
			""".data(using: .utf8)!
	}

	private let realLimits = """
		[{"kind":"weekly_all","group":"weekly","percent":100,"severity":"critical",
		  "resets_at":"2026-11-14T16:59:59.705975+00:00","scope":null,"is_active":true},
		 {"kind":"weekly_scoped","group":"weekly","percent":73,"severity":"normal",
		  "resets_at":"2026-11-14T16:59:59.706135+00:00",
		  "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]
		"""

	func testReadsTheFableRowAndIgnoresThePlanWideRow() throws {
		let windows = ClaudeUsageCache.modelWindows(in: cacheJSON(account: account, signedIn: account, limits: realLimits))
		XCTAssertEqual(windows.map(\.label), ["Fable"])
		let fable = try XCTUnwrap(windows.first)
		XCTAssertEqual(fable.key, "model_scoped:Fable")
		XCTAssertEqual(fable.window.usedPercent, 73, accuracy: 0.001)
		XCTAssertEqual(fable.window.windowMinutes, 10080)
		XCTAssertEqual(fable.window.resetsAt?.timeIntervalSince1970 ?? 0, 1_794_675_599.706, accuracy: 0.01)
		XCTAssertEqual(fable.reportedAt?.timeIntervalSince1970 ?? 0, fetchedAtMs / 1000, accuracy: 0.001)
	}

	/// Claude Code drops a cache stamped for another account; JP does the same.
	func testAnotherAccountsCacheIsIgnored() {
		let other = "11111111-0000-4ee8-8fa8-000000000000"
		XCTAssertTrue(ClaudeUsageCache.modelWindows(in: cacheJSON(account: other, signedIn: account, limits: realLimits)).isEmpty)
		XCTAssertTrue(ClaudeUsageCache.modelWindows(in: cacheJSON(account: account, signedIn: nil, limits: realLimits)).isEmpty)
		XCTAssertTrue(ClaudeUsageCache.modelWindows(in: cacheJSON(account: nil, signedIn: account, limits: realLimits)).isEmpty)
		// No account on either side is not a match.
		XCTAssertTrue(ClaudeUsageCache.modelWindows(in: cacheJSON(account: nil, signedIn: nil, limits: realLimits)).isEmpty)
	}

	/// A cached row with no readable reset could never expire, so it is skipped.
	func testACachedRowWithoutAResetIsSkipped() {
		let limits = """
			[{"kind":"weekly_scoped","percent":40,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}},
			 {"kind":"weekly_scoped","percent":40,"resets_at":"soon","scope":{"model":{"display_name":"Sonnet"}}}]
			"""
		XCTAssertTrue(ClaudeUsageCache.modelWindows(in: cacheJSON(account: account, signedIn: account, limits: limits)).isEmpty)
	}

	/// A row with no model name or no numeric percent is skipped, never drawn as 0%.
	func testRowsWithoutANameOrPercentAreSkipped() {
		let limits = """
			[{"kind":"weekly_scoped","percent":40,"resets_at":null,"scope":{"model":{"display_name":"  "}}},
			 {"kind":"weekly_scoped","percent":null,"resets_at":null,"scope":{"model":{"display_name":"Sonnet"}}},
			 {"kind":"weekly_scoped","percent":12,"resets_at":null,"scope":{"surface":{"display_name":"Cowork"}}},
			 {"kind":"session","percent":9,"resets_at":null,"scope":{"model":{"display_name":"Haiku"}}}]
			"""
		XCTAssertTrue(ClaudeUsageCache.modelWindows(in: cacheJSON(account: account, signedIn: account, limits: limits)).isEmpty)
	}

	func testMissingFileOrCacheYieldsNothing() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		XCTAssertTrue(ClaudeUsageCache.modelWindows(url: dir.appendingPathComponent(".claude.json")).isEmpty)
		let bare = dir.appendingPathComponent("bare.json")
		try Data(#"{"numStartups":3}"#.utf8).write(to: bare)
		XCTAssertTrue(ClaudeUsageCache.modelWindows(url: bare).isEmpty)
		XCTAssertEqual(ClaudeUsageCache.defaultURL(home: dir).lastPathComponent, ".claude.json")
	}

	// MARK: Merge into the statusline capture

	/// The 2.1.325 statusline capture: weekly only, no `model_scoped`.
	private func writeCapture(_ dir: URL, extra: String = "") throws -> URL {
		let url = dir.appendingPathComponent("claude-rate-limits.json")
		try Data(#"{"capturedAt":1794839481,"seven_day":{"used_percentage":53,"resets_at":1795280400}\#(extra)}"#.utf8)
			.write(to: url)
		return url
	}

	private func tempDir() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
		return dir
	}

	private func fable(_ percent: Double, resetsAt: Double, reportedAt: Double? = 1_794_800_000) -> ModelScopedRateLimitWindow {
		ModelScopedRateLimitWindow(
			key: "model_scoped:Fable",
			window: RateLimitWindow(usedPercent: percent, windowMinutes: 10080, resetsAt: Date(timeIntervalSince1970: resetsAt)),
			displayName: "Fable", reportedAt: reportedAt.map { Date(timeIntervalSince1970: $0) })
	}

	func testCachedFableFillsTheBarUnderAllModels() throws {
		let url = try writeCapture(try tempDir())
		let now = Date(timeIntervalSince1970: 1_794_840_000)
		let snap = try XCTUnwrap(ClaudeRateLimitStore.load(
			now: now, url: url, fallbackModelWindows: [fable(62, resetsAt: 1_795_280_400)]))
		XCTAssertEqual(snap.secondary?.usedPercent ?? -1, 53, accuracy: 0.001)
		XCTAssertEqual(snap.modelWindows.map(\.label), ["Fable"])
		XCTAssertEqual(snap.modelWindows.first?.window.usedPercent ?? -1, 62, accuracy: 0.001)
		XCTAssertNotNil(snap.modelWindows.first?.reportedAt)
	}

	/// A statusline row is refreshed every turn, so it wins over the cached row for the same model.
	func testStatuslineFableWinsOverTheCachedOne() throws {
		let url = try writeCapture(
			try tempDir(),
			extra: #","model_scoped":[{"display_name":"Fable","utilization":88,"resets_at":"2026-11-21T17:00:00Z"}]"#)
		let snap = try XCTUnwrap(ClaudeRateLimitStore.load(
			now: Date(timeIntervalSince1970: 1_794_840_000), url: url,
			fallbackModelWindows: [fable(62, resetsAt: 1_795_280_400)]))
		XCTAssertEqual(snap.modelWindows.count, 1)
		XCTAssertEqual(snap.modelWindows.first?.window.usedPercent ?? -1, 88, accuracy: 0.001)
		XCTAssertNil(snap.modelWindows.first?.reportedAt)
	}

	/// A cached Fable row joins a different statusline model row; neither replaces the other.
	func testCachedFableJoinsADifferentStatuslineModel() throws {
		let url = try writeCapture(
			try tempDir(),
			extra: #","model_scoped":[{"display_name":"Sonnet","utilization":9,"resets_at":"2026-11-21T17:00:00Z"}]"#)
		let snap = try XCTUnwrap(ClaudeRateLimitStore.load(
			now: Date(timeIntervalSince1970: 1_794_840_000), url: url,
			fallbackModelWindows: [fable(62, resetsAt: 1_795_280_400)]))
		XCTAssertEqual(snap.modelWindows.map(\.label), ["Sonnet", "Fable"])
	}

	/// Last week's cached Fable row has passed its own reset, so it is hidden, never rolled forward.
	func testAnExpiredCachedRowIsHidden() throws {
		let url = try writeCapture(try tempDir())
		let snap = try XCTUnwrap(ClaudeRateLimitStore.load(
			now: Date(timeIntervalSince1970: 1_794_840_000), url: url,
			fallbackModelWindows: [fable(73, resetsAt: 1_794_675_599)]))
		XCTAssertTrue(snap.modelWindows.isEmpty)
	}

	/// The capture keeps its last `model_scoped` rows when a 2.1.325 payload omits the key, so an
	/// expired statusline Fable must not hide the current cached Fable.
	func testAnExpiredStatuslineFableDoesNotHideACurrentCachedFable() throws {
		let url = try writeCapture(
			try tempDir(),
			extra: #","model_scoped":[{"display_name":"Fable","utilization":97,"resets_at":"2026-11-14T17:00:00Z"}]"#)
		let snap = try XCTUnwrap(ClaudeRateLimitStore.load(
			now: Date(timeIntervalSince1970: 1_794_840_000), url: url,
			fallbackModelWindows: [fable(62, resetsAt: 1_795_280_400)]))
		XCTAssertEqual(snap.modelWindows.map(\.label), ["Fable"])
		XCTAssertEqual(snap.modelWindows.first?.window.usedPercent ?? -1, 62, accuracy: 0.001)
		XCTAssertNotNil(snap.modelWindows.first?.reportedAt)
	}

	/// The cache never creates a Claude gauge without the opt-in capture.
	func testTheCacheAloneCreatesNoSnapshot() throws {
		let missing = try tempDir().appendingPathComponent("claude-rate-limits.json")
		XCTAssertNil(ClaudeRateLimitStore.load(
			now: Date(timeIntervalSince1970: 1_794_840_000), url: missing,
			fallbackModelWindows: [fable(62, resetsAt: 1_795_280_400)]))
	}
}
