import Foundation
import XCTest

@testable import JPtheCatCore

/// Locks `UsageIndex.hourWeekdayBins`: per-provider 7×24 punchcards, LOCAL-calendar weekday/hour
/// binning (matching the file's `startOfDay` convention, not a UTC `strftime` path), and the window
/// clamp (events outside `[windowStart, now]` are excluded). Mirrors `UsageIndexTests`' ingest style.
final class UsageIndexRhythmTests: XCTestCase {
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
			.appendingPathComponent("jpc-rhythm-\(UUID().uuidString).sqlite").path
	}
	private func event(_ msg: String, _ req: String, _ ts: String, model: String, provider: ProviderID, output: Int = 10)
		-> UsageEvent
	{
		UsageEvent(
			messageId: msg, requestId: req, provider: provider, model: model,
			timestamp: iso.date(from: ts)!, usage: TokenUsage(input: 100, output: output))
	}

	func testHourWeekdayBinsBinByLocalWeekdayHourWithWindowClampPerProvider() throws {
		let index = try UsageIndex(path: tempDBPath())
		try index.ingest([
			// In-window (5-day window ending 2026-07-09): Thu 15:00 twice, Mon 09:00 once for Claude.
			event("a", "r1", "2026-07-09T15:30:00.000Z", model: "claude-opus-4-8", provider: .claude),
			event("b", "r2", "2026-07-09T15:45:00.000Z", model: "claude-opus-4-8", provider: .claude),
			event("c", "r3", "2026-07-06T09:00:00.000Z", model: "claude-opus-4-8", provider: .claude),
			// Codex Tuesday 03:00 — separate provider matrix.
			event("d", "r4", "2026-07-07T03:00:00.000Z", model: "gpt-5-codex", provider: .codex),
			// OUT of the 5-day window (2026-07-01) — must be clamped away.
			event("e", "r5", "2026-07-01T12:00:00.000Z", model: "claude-opus-4-8", provider: .claude),
		])

		let now = iso.date(from: "2026-07-09T23:59:59.000Z")!
		let bins = try index.hourWeekdayBins(
			providers: [.claude, .codex], days: 5, calculator: CostCalculator(), now: now, calendar: utc())

		let claude = try XCTUnwrap(bins[.claude])
		XCTAssertEqual(claude.value(weekday: 5, hour: 15, measure: .events), 2, "Thu 15:00 accumulates both")
		XCTAssertEqual(claude.value(weekday: 2, hour: 9, measure: .events), 1, "Mon 09:00")
		// The 2026-07-01 event is outside the window → not counted anywhere.
		let claudeTotal = (1...7).reduce(0.0) { acc, wd in
			acc + (0..<24).reduce(0.0) { $0 + claude.value(weekday: wd, hour: $1, measure: .events) }
		}
		XCTAssertEqual(claudeTotal, 3, "only the 3 in-window Claude events, the out-of-window one clamped")

		let codex = try XCTUnwrap(bins[.codex])
		XCTAssertEqual(codex.value(weekday: 3, hour: 3, measure: .events), 1, "Codex Tue 03:00")
		XCTAssertEqual(codex.value(weekday: 5, hour: 15, measure: .events), 0, "Codex never sees Claude's bin")
	}

	func testEmptyProviderListReturnsEmpty() throws {
		let index = try UsageIndex(path: tempDBPath())
		XCTAssertTrue(try index.hourWeekdayBins(providers: [], days: 7).isEmpty)
	}
}
