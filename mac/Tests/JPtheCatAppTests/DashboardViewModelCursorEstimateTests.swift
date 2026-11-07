import XCTest
@testable import JPtheCatCore

final class DashboardViewModelCursorEstimateTests: XCTestCase {
	func testRawSourcesProjectIntoOneGrokSummaryWithoutLosingOrDoubleCountingHistory() throws {
		let index = try UsageIndex(path: ":memory:")
		let now = Date()
		let events: [UsageEvent] = [.grok, .cursor].map { id in
			UsageEvent(messageId: "same-opaque-id", requestId: "same-request-id", provider: id,
				model: "grok-4.7-high-fast", timestamp: now, usage: TokenUsage(input: 1000, output: 200))
		}
		try index.ingest(events)
		try index.ingest(events)
		let result = try index.windowSummaries(providers: [.grok, .cursor], now: now)
		XCTAssertEqual(Set(result.providers.keys), [.grok])
		XCTAssertEqual(result.providers[.grok]?.rollup.last7d.eventCount, 2)
		XCTAssertEqual(result.aggregate.rollup.last7d.eventCount, 2)
		XCTAssertEqual(index.eventCount(provider: .cursor), 1, "Do not rewrite persisted source IDs")
		let noCursor = try index.windowSummaries(providers: [.grok], now: now)
		XCTAssertEqual(noCursor.aggregate.rollup.last7d.eventCount, 1, "Opt-out must exclude the raw source")
		let multi = try index.multiWindowSummaries(providers: [.grok, .cursor], now: now)
		for value in multi.byDays.values { XCTAssertEqual(value.providers[.grok]?.rollup.last7d.eventCount, 2) }
		let oracle = try index.multiWindowSummariesPerEvent(providers: [.grok, .cursor], now: now)
		for days in [7, 14, 30, 90] {
			XCTAssertEqual(multi.byDays[days]?.providers[.grok]?.rollup.last7d.cost,
				oracle.byDays[days]?.providers[.grok]?.rollup.last7d.cost)
		}
		let bins = try index.hourWeekdayBins(providers: [.grok, .cursor], days: 14, now: now)
		XCTAssertEqual(Set(bins.keys), [.grok])
		XCTAssertEqual(bins[.grok]?.cells.flatMap { $0 }.reduce(0) { $0 + $1.events }, 2)
		let rows = try index.modelDaySummaries(providers: [.grok, .cursor], days: 14, now: now)
		XCTAssertEqual(Set(rows.map(\.provider)), [.grok])
		XCTAssertEqual(rows.reduce(0) { $0 + $1.eventCount }, 2)
	}
}
