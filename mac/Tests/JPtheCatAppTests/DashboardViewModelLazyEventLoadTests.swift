import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

final class DashboardViewModelLazyEventLoadTests: XCTestCase {
	private func pricedRollup(weekCost: Double, days: Int = 14) -> UsageRollup {
		var week = CostBucket()
		week.cost = weekCost
		week.eventCount = 1
		return UsageRollup(today: week, last7d: week, byModel7d: [:], windowDays: days)
	}

	func testSkipsEventLoadWhenIndexedSeriesAlreadyHasSignal() {
		let rollup = pricedRollup(weekCost: 42)
		let summary = UsageWindowSummary(
			rollup: rollup, dailyCostSeries: Array(repeating: 3.0, count: 14))
		var loadCount = 0
		let result = DashboardViewModel.resolveOfficialProviderInputs(
			summary: summary, days: 14, calculator: CostCalculator(pricing: .bundledDefault()),
			loadEvents: { loadCount += 1; return [] })
		XCTAssertEqual(loadCount, 0)
		XCTAssertTrue(result.events.isEmpty)
		XCTAssertEqual(result.rollup.last7d.cost, 42)
	}

	func testLoadsEventsOnlyForSparseIndexedSeriesWithPricedWindow() {
		let rollup = pricedRollup(weekCost: 0.02)
		let summary = UsageWindowSummary(rollup: rollup, dailyCostSeries: Array(repeating: 0, count: 14))
		var loadCount = 0
		let result = DashboardViewModel.resolveOfficialProviderInputs(
			summary: summary, days: 14, calculator: CostCalculator(pricing: .bundledDefault()),
			loadEvents: { loadCount += 1; return [] })
		XCTAssertEqual(loadCount, 1)
		XCTAssertTrue(result.events.isEmpty)
	}

	func testLoadsEventsWhenIndexedRollupMissing() {
		var loadCount = 0
		_ = DashboardViewModel.resolveOfficialProviderInputs(
			summary: nil, days: 14, calculator: CostCalculator(pricing: .bundledDefault()),
			loadEvents: { loadCount += 1; return [] })
		XCTAssertEqual(loadCount, 1)
	}
}