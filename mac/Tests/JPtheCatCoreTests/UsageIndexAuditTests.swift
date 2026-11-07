import Foundation
import XCTest

@testable import JPtheCatCore

final class UsageIndexAuditTests: XCTestCase {
	private let iso: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-audit-\(UUID().uuidString).sqlite").path
	}

	private func calendar(_ timeZoneID: String) -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: timeZoneID)!
		return calendar
	}

	private func event(
		_ id: String,
		_ timestamp: String,
		output: Int = 1_000_000,
		model: String = "claude-opus-4-8",
		provider: ProviderID = .claude
	) -> UsageEvent {
		UsageEvent(
			messageId: "m-\(id)",
			requestId: "r-\(id)",
			provider: provider,
			model: model,
			timestamp: iso.date(from: timestamp)!,
			usage: TokenUsage(output: output)
		)
	}

	func testDailyCostSeriesSurvivesNewYorkSpringForwardDSTAndMidnightBoundaries() throws {
		let index = try UsageIndex(path: tempDBPath())
		let newYork = calendar("America/New_York")
		let now = iso.date(from: "2026-03-10T16:00:00.000Z")!  // 2026-03-10 12:00 EDT

		try index.ingest([
			event("pre-window", "2026-03-07T04:59:59.000Z"),  // 2026-03-06 23:59:59 EST
			event("mar7-midnight", "2026-03-07T05:00:00.000Z"),  // 2026-03-07 00:00 EST
			event("mar8-after-midnight", "2026-03-08T05:30:00.000Z"),  // 2026-03-08 00:30 EST
			event("mar9-midnight", "2026-03-09T04:00:00.000Z"),  // 2026-03-09 00:00 EDT
			event("mar10-midnight", "2026-03-10T04:00:00.000Z"),  // 2026-03-10 00:00 EDT
		])

		let series = try index.dailyCostSeries(provider: .claude, days: 4, now: now, calendar: newYork)

		XCTAssertEqual(series.count, 4)
		for (actual, expected) in zip(series, [25.0, 25.0, 25.0, 25.0]) {
			XCTAssertEqual(actual, expected, accuracy: 1e-9)
		}
	}

	func testRightmostSeriesPointMatchesRollupTodayInUTCPlus9AndUTCMinus8() throws {
		for timeZoneID in ["Asia/Tokyo", "America/Los_Angeles"] {
			let index = try UsageIndex(path: tempDBPath())
			let calendar = calendar(timeZoneID)
			let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
			let startOfToday = calendar.startOfDay(for: now)
			let todayPlusOneHour = startOfToday.addingTimeInterval(60 * 60)
			let yesterday = calendar.date(byAdding: .day, value: -1, to: todayPlusOneHour)!

			try index.ingest([
				UsageEvent(
					messageId: "m-\(timeZoneID)-today", requestId: "r-\(timeZoneID)-today",
					provider: .claude, model: "claude-opus-4-8",
					timestamp: todayPlusOneHour, usage: TokenUsage(output: 1_000_000)),
				UsageEvent(
					messageId: "m-\(timeZoneID)-yesterday", requestId: "r-\(timeZoneID)-yesterday",
					provider: .claude, model: "claude-opus-4-8",
					timestamp: yesterday, usage: TokenUsage(output: 1_000_000)),
			])

			let rollup = try index.rollup(provider: .claude, now: now, calendar: calendar)
			let series = try index.dailyCostSeries(provider: .claude, days: 7, now: now, calendar: calendar)

			XCTAssertEqual(try XCTUnwrap(series.last), rollup.today.cost, accuracy: 1e-9, "timezone \(timeZoneID)")
		}
	}

	func testFutureDatedEventsDoNotMakeHeaderAndSeriesDisagree() throws {
		let index = try UsageIndex(path: tempDBPath())
		let utc = calendar("UTC")
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!

		try index.ingest([
			event("today", "2026-07-07T01:00:00.000Z"),
			event("tomorrow", "2026-07-08T01:00:00.000Z"),
		])

		let rollup = try index.rollup(provider: .claude, now: now, calendar: utc)
		let series = try index.dailyCostSeries(provider: .claude, days: 7, now: now, calendar: utc)

		XCTAssertEqual(try XCTUnwrap(series.last), rollup.today.cost, accuracy: 1e-9)
		XCTAssertEqual(series.reduce(0, +), rollup.last7d.cost, accuracy: 1e-9)
		XCTAssertEqual(rollup.today.cost, 25, accuracy: 1e-9)
		XCTAssertEqual(rollup.last7d.cost, 25, accuracy: 1e-9)
	}

	func testWindowSummariesScanLiveProvidersTogetherAndExcludeFutureRows() throws {
		let index = try UsageIndex(path: tempDBPath())
		let utc = calendar("UTC")
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!

		try index.ingest([
			event("claude-today", "2026-07-07T01:00:00.000Z", provider: .claude),
			event("codex-today", "2026-07-07T02:00:00.000Z", output: 1_000_000, model: "gpt-5-codex", provider: .codex),
			event("gemini-roadmap", "2026-07-07T03:00:00.000Z", output: 1_000_000, model: "gemini-2.5-pro", provider: .gemini),
			event("future", "2026-07-08T01:00:00.000Z", provider: .claude),
		])

		let summaries = try index.windowSummaries(providers: [.claude, .codex], days: 7, now: now, calendar: utc)

		XCTAssertEqual(summaries.providers[.claude]?.rollup.today.cost ?? -1, 25, accuracy: 1e-9)
		XCTAssertEqual(summaries.providers[.codex]?.rollup.today.cost ?? -1, 10, accuracy: 1e-9)
		XCTAssertNil(summaries.providers[.gemini])
		XCTAssertEqual(summaries.aggregate.rollup.today.cost, 35, accuracy: 1e-9)
		XCTAssertEqual(summaries.aggregate.dailyCostSeries[6], 35, accuracy: 1e-9)
	}

	func testWindowSummariesWindowBucketWidensWithSelectedDays() throws {
		let index = try UsageIndex(path: tempDBPath())
		let utc = calendar("UTC")
		let now = iso.date(from: "2026-07-15T12:00:00.000Z")!

		try index.ingest([
			event("today", "2026-07-15T01:00:00.000Z", provider: .claude),  // $25 today
			event("day10", "2026-07-05T01:00:00.000Z", provider: .claude),  // $25, 10 days ago
		])

		let sevenDay = try index.windowSummaries(providers: [.claude], days: 7, now: now, calendar: utc)
		XCTAssertEqual(sevenDay.aggregate.rollup.last7d.cost, 25, accuracy: 1e-9)  // only today
		XCTAssertEqual(sevenDay.aggregate.rollup.windowDays, 7)
		XCTAssertEqual(sevenDay.aggregate.dailyCostSeries.count, 7)

		let fourteenDay = try index.windowSummaries(providers: [.claude], days: 14, now: now, calendar: utc)
		XCTAssertEqual(fourteenDay.aggregate.rollup.last7d.cost, 50, accuracy: 1e-9)  // both events
		XCTAssertEqual(fourteenDay.aggregate.rollup.windowDays, 14)
		XCTAssertEqual(fourteenDay.aggregate.dailyCostSeries.count, 14)
		XCTAssertEqual(fourteenDay.aggregate.dailyCostSeries[3], 25, accuracy: 1e-9)  // day-10 point
		XCTAssertEqual(fourteenDay.aggregate.dailyCostSeries[13], 25, accuracy: 1e-9)  // today point
	}

	// multiWindowSummaries computes all requested day-counts from ONE scan; each returned window must
	// match what a standalone windowSummaries(days:) call produces for the same fixture data — proving
	// the shared single-scan implementation doesn't silently diverge from the existing per-window path.
	func testMultiWindowSummariesMatchesStandaloneWindowSummariesForEveryRequestedWindow() throws {
		let index = try UsageIndex(path: tempDBPath())
		let utc = calendar("UTC")
		let now = iso.date(from: "2026-07-15T12:00:00.000Z")!

		try index.ingest([
			event("today", "2026-07-15T01:00:00.000Z", provider: .claude),  // $25 today
			event("codex-today", "2026-07-15T02:00:00.000Z", output: 1_000_000, model: "gpt-5-codex", provider: .codex),
			event("day10", "2026-07-05T01:00:00.000Z", provider: .claude),  // $25, 10 days ago
			event("day60", "2026-05-16T01:00:00.000Z", provider: .claude),  // $25, 60 days ago
		])

		let multi = try index.multiWindowSummaries(
			providers: [.claude, .codex], windows: [7, 14, 30, 90], now: now, calendar: utc)
		XCTAssertEqual(Set(multi.byDays.keys), [7, 14, 30, 90])

		for days in [7, 14, 30, 90] {
			let standalone = try index.windowSummaries(providers: [.claude, .codex], days: days, now: now, calendar: utc)
			let fromMulti = try XCTUnwrap(multi.byDays[days])

			XCTAssertEqual(
				fromMulti.aggregate.rollup.last7d.cost, standalone.aggregate.rollup.last7d.cost, accuracy: 1e-9,
				"aggregate window total mismatch at \(days) days")
			XCTAssertEqual(fromMulti.aggregate.dailyCostSeries, standalone.aggregate.dailyCostSeries, "series mismatch at \(days) days")
			XCTAssertEqual(
				fromMulti.providers[.claude]?.rollup.last7d.cost ?? -1,
				standalone.providers[.claude]?.rollup.last7d.cost ?? -1, accuracy: 1e-9,
				"claude window total mismatch at \(days) days")
			XCTAssertEqual(
				fromMulti.providers[.codex]?.rollup.last7d.cost ?? -1,
				standalone.providers[.codex]?.rollup.last7d.cost ?? -1, accuracy: 1e-9,
				"codex window total mismatch at \(days) days")
		}

		// The 60-day-old event only clears the 90-day window; today's $35 (claude $25 + codex $10) is in
		// every window, day10's $25 clears 14/30/90, and day60's $25 clears only 90.
		XCTAssertEqual(multi.byDays[7]?.aggregate.rollup.last7d.cost ?? -1, 35, accuracy: 1e-9)
		XCTAssertEqual(multi.byDays[90]?.aggregate.rollup.last7d.cost ?? -1, 85, accuracy: 1e-9)
	}

	// The standalone `dailyCostSeries(provider:)` method is production-unused (only these audit tests +
	// UsageIndexTests call it) — a PARALLEL day-bucketing implementation that the TZ audit tests lean on
	// for correctness. Pin it to the PRODUCTION `windowSummaries` path so that coverage transitively
	// protects real code and the two can never silently diverge. Cross-provider totals belong on
	// `windowSummaries` (explicit allowlist); this locks the single-provider bucketing math across
	// timeframes, time zones, and priced + unpriced models.
	func testDailyCostSeriesMethodMatchesTheProductionWindowSummariesPathPerProvider() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-15T12:00:00.000Z")!
		try index.ingest([
			event("claude-today", "2026-07-15T01:00:00.000Z", provider: .claude),  // $25 today
			event("claude-day10", "2026-07-05T01:00:00.000Z", provider: .claude),  // clears 14/30/90
			event("claude-day60", "2026-05-16T01:00:00.000Z", provider: .claude),  // clears only 90
			event("codex-today", "2026-07-15T02:00:00.000Z", model: "gpt-5-codex", provider: .codex),
			event("codex-day3", "2026-07-12T23:30:00.000Z", model: "gpt-5-codex", provider: .codex),
			// An unpriced model: a cost-only series must OMIT it identically on both paths.
			event("claude-unpriced", "2026-07-14T06:00:00.000Z", model: "totally-unknown-model", provider: .claude),
		])

		for timeZoneID in ["UTC", "America/New_York", "Asia/Tokyo"] {
			let cal = calendar(timeZoneID)
			for days in [7, 14, 30, 90] {
				for provider in [ProviderID.claude, .codex] {
					let method = try index.dailyCostSeries(
						provider: provider, days: days, now: now, calendar: cal)
					let production = try XCTUnwrap(
						index.windowSummaries(providers: [provider], days: days, now: now, calendar: cal)
							.providers[provider]).dailyCostSeries
					XCTAssertEqual(
						method, production,
						"dailyCostSeries(\(provider.rawValue)) diverged from the windowSummaries path at \(days)d in \(timeZoneID)")
				}
			}
		}
	}

	func testWindowSummariesWithNoLiveProvidersDoesNotAggregateIndexedRows() throws {
		let index = try UsageIndex(path: tempDBPath())
		let utc = calendar("UTC")
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!

		try index.ingest([
			event("claude-today", "2026-07-07T01:00:00.000Z", provider: .claude),
			event("codex-today", "2026-07-07T02:00:00.000Z", output: 1_000_000, model: "gpt-5-codex", provider: .codex),
		])

		let summaries = try index.windowSummaries(providers: [], days: 7, now: now, calendar: utc)

		XCTAssertTrue(summaries.providers.isEmpty)
		XCTAssertEqual(summaries.aggregate.rollup.today.cost, 0, accuracy: 1e-9)
		XCTAssertEqual(summaries.aggregate.rollup.today.eventCount, 0)
		XCTAssertEqual(summaries.aggregate.dailyCostSeries, [0, 0, 0, 0, 0, 0, 0])
	}

	func testZeroDaySeriesRequestReturnsZeroPoints() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!

		try index.ingest([event("today", "2026-07-07T01:00:00.000Z")])

		XCTAssertEqual(try index.dailyCostSeries(provider: .claude, days: 0, now: now, calendar: calendar("UTC")), [])
	}

	func testUnpricedModelsAreVisibleInRollupButDroppedFromCostOnlySeries() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!

		try index.ingest([event("unknown", "2026-07-07T01:00:00.000Z", model: "unknown-future-model")])

		let rollup = try index.rollup(provider: .claude, now: now, calendar: calendar("UTC"))
		let series = try index.dailyCostSeries(provider: .claude, days: 7, now: now, calendar: calendar("UTC"))
		let summaries = try index.windowSummaries(providers: [.claude], days: 7, now: now, calendar: calendar("UTC"))

		XCTAssertEqual(rollup.today.eventCount, 1)
		XCTAssertEqual(rollup.today.unpricedModels, ["unknown-future-model"])
		XCTAssertEqual(summaries.providers[.claude]?.rollup.today.unpricedModels, ["unknown-future-model"])
		XCTAssertEqual(series.reduce(0, +), 0)
	}

	func testEmptyDatabaseSeriesIsAllZeroes() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!

		XCTAssertEqual(try index.dailyCostSeries(provider: .claude, days: 7, now: now, calendar: calendar("UTC")), [0, 0, 0, 0, 0, 0, 0])
	}
}
