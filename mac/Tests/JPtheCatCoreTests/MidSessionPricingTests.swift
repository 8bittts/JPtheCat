import Foundation
import XCTest

@testable import JPtheCatCore

/// Guards the "mid-session remote-pricing update" invariant: cost is READ-TIME and tokens are cached, so
/// swapping the pricing table re-derives EVERY dollar surface (headline, window bucket, per-model
/// breakdown, daily series, aggregate) from the SAME cached tokens — the whole surface reprices together
/// and can never be a mix of old- and new-priced figures. The `DashboardViewModel` threads one shared
/// `CostCalculator` through all of these paths and swaps it in `updatePricing(_:)`; this proves the
/// underlying `UsageIndex` recompute those figures depend on.
final class MidSessionPricingTests: XCTestCase {
	private let iso: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-midprice-\(UUID().uuidString).sqlite").path
	}

	private func utc() -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		return calendar
	}

	/// A flat model price at `inputPerToken`; everything else nil so cache/output/tier fields fall back.
	private func price(inputPerToken: Double) -> ModelPrice {
		ModelPrice(
			inputCostPerToken: inputPerToken, outputCostPerToken: 0,
			cacheCreationInputTokenCost: nil, cacheCreationInputTokenCostAbove1hr: nil,
			cacheReadInputTokenCost: nil,
			inputCostPerTokenAbove200k: nil, outputCostPerTokenAbove200k: nil,
			cacheCreationInputTokenCostAbove200k: nil, cacheCreationInputTokenCostAbove1hrAbove200k: nil,
			cacheReadInputTokenCostAbove200k: nil)
	}

	func testEveryCostSurfaceRepricesFromTheSameCachedTokensWhenPricingChanges() throws {
		let index = try UsageIndex(path: tempDBPath())
		let calendar = utc()
		let now = iso.date(from: "2026-07-03T12:00:00.000Z")!

		// 2,000,000 input tokens cached today across two events (one provider, one model).
		try index.ingest([
			UsageEvent(
				messageId: "m1", requestId: "r1", provider: .claude, model: "test-model",
				timestamp: iso.date(from: "2026-07-03T10:00:00.000Z")!,
				usage: TokenUsage(input: 1_000_000)),
			UsageEvent(
				messageId: "m2", requestId: "r2", provider: .claude, model: "test-model",
				timestamp: iso.date(from: "2026-07-03T11:00:00.000Z")!,
				usage: TokenUsage(input: 1_000_000)),
		])

		// $1.00 / 1M input, then a mid-session bump to $2.00 / 1M input.
		let calcOld = CostCalculator(pricing: PricingTable(models: ["test-model": price(inputPerToken: 1e-6)]))
		let calcNew = CostCalculator(pricing: PricingTable(models: ["test-model": price(inputPerToken: 2e-6)]))

		let old = try index.windowSummaries(providers: [.claude], days: 7, calculator: calcOld, now: now, calendar: calendar)
		let new = try index.windowSummaries(providers: [.claude], days: 7, calculator: calcNew, now: now, calendar: calendar)

		let oldRow = try XCTUnwrap(old.providers[.claude])
		let newRow = try XCTUnwrap(new.providers[.claude])

		// Old pricing: 2M × $1/1M = $2.00. New pricing: 2M × $2/1M = $4.00.
		XCTAssertEqual(oldRow.rollup.today.cost, 2.0, accuracy: 1e-9)

		// EVERY surface the dashboard reads must reflect the new price — none may stay on the old one.
		XCTAssertEqual(newRow.rollup.today.cost, 4.0, accuracy: 1e-9)  // headline $ today
		XCTAssertEqual(newRow.rollup.last7d.cost, 4.0, accuracy: 1e-9)  // selected-window bucket
		XCTAssertEqual(try XCTUnwrap(newRow.rollup.byModel7d["test-model"]).cost, 4.0, accuracy: 1e-9)  // per-model
		XCTAssertEqual(newRow.dailyCostSeries.reduce(0, +), 4.0, accuracy: 1e-9)  // chart series
		XCTAssertEqual(new.aggregate.rollup.today.cost, 4.0, accuracy: 1e-9)  // cross-provider aggregate

		// The tokens are cached, not the cost: identical token totals both times, only the price changed.
		XCTAssertEqual(oldRow.rollup.today.usage.input, 2_000_000)
		XCTAssertEqual(newRow.rollup.today.usage.input, 2_000_000)
	}
}
