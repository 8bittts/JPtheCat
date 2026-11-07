import Foundation
import XCTest

@testable import JPtheCatCore

final class SignatureInsightTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_000_000)

	private func compute(
		limitLikelyHit: Bool = false,
		usedPct: Double? = nil,
		resetsAt5h: Date? = nil,
		windowMinutes5h: Int? = nil,
		week: Double = 0,
		weekEvents: Int = 0,
		models: [SignatureInsight.ModelSpend] = []
	) -> SignatureInsight? {
		SignatureInsight.compute(
			limitLikelyHit: limitLikelyHit, usedPct: usedPct, resetsAt5h: resetsAt5h,
			windowMinutes5h: windowMinutes5h, week: week, weekEvents: weekEvents, models: models, now: now)
	}

	func testNothingHonestlyComputableReturnsNil() {
		XCTAssertNil(compute())
	}

	func testLimitLikelyHitTakesPriorityAndIsAnEstimate() {
		let insight = compute(limitLikelyHit: true, usedPct: 92)
		XCTAssertEqual(insight, .limitFrozen(usedPct: 92))
		XCTAssertTrue(insight?.isEstimate == true)
	}

	func testLimitLikelyHitWithoutAReadingFallsThrough() {
		// No usedPct → no frozen insight; with nothing else it collapses.
		XCTAssertNil(compute(limitLikelyHit: true, usedPct: nil))
	}

	func testBurnPaceVerdictBands() {
		// Window is 300 min; reset 150 min out → 50% elapsed. pace = (used/100) / 0.5.
		let reset = now.addingTimeInterval(150 * 60)
		// used 80 → pace 1.6 → running hot.
		XCTAssertEqual(
			compute(usedPct: 80, resetsAt5h: reset, windowMinutes5h: 300),
			.burnPace(usedPct: 80, windowElapsedFraction: 0.5, verdict: .runningHot))
		// used 50 → pace 1.0 → on pace.
		XCTAssertEqual(
			compute(usedPct: 50, resetsAt5h: reset, windowMinutes5h: 300),
			.burnPace(usedPct: 50, windowElapsedFraction: 0.5, verdict: .onPace))
		// used 30 → pace 0.6 → well under pace.
		XCTAssertEqual(
			compute(usedPct: 30, resetsAt5h: reset, windowMinutes5h: 300),
			.burnPace(usedPct: 30, windowElapsedFraction: 0.5, verdict: .wellUnderPace))
	}

	func testBurnPaceNeedsMoreThanFivePercentElapsed() {
		// Reset 297 min out of a 300-min window → 1% elapsed → too little to judge, falls through to nil.
		let reset = now.addingTimeInterval(297 * 60)
		XCTAssertNil(compute(usedPct: 50, resetsAt5h: reset, windowMinutes5h: 300))
	}

	func testCostConcentrationNeedsAModelOverTheTenPointCushion() {
		// Opus: 20% of turns, 60% of bill → 0.40 gap (> 0.10). Haiku: the rest.
		let models = [
			SignatureInsight.ModelSpend(model: "claude-opus-4-8", cost: 6, eventCount: 2),
			SignatureInsight.ModelSpend(model: "claude-haiku-4-5", cost: 4, eventCount: 8),
		]
		XCTAssertEqual(
			compute(week: 10, weekEvents: 10, models: models),
			.costConcentration(model: "claude-opus-4-8", turnShare: 0.2, billShare: 0.6))
		XCTAssertFalse(compute(week: 10, weekEvents: 10, models: models)?.isEstimate == true)
	}

	func testCostConcentrationBelowCutoffReturnsNil() {
		// Each model's bill share ≈ its turn share → no gap over 0.10.
		let models = [
			SignatureInsight.ModelSpend(model: "a", cost: 5, eventCount: 5),
			SignatureInsight.ModelSpend(model: "b", cost: 5, eventCount: 5),
		]
		XCTAssertNil(compute(week: 10, weekEvents: 10, models: models))
	}

	func testCostConcentrationNeedsAtLeastTwoPricedModels() {
		let models = [SignatureInsight.ModelSpend(model: "solo", cost: 10, eventCount: 1)]
		XCTAssertNil(compute(week: 10, weekEvents: 10, models: models))
	}
}
