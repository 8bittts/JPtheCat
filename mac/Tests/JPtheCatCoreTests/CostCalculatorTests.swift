import XCTest

@testable import JPtheCatCore

final class CostCalculatorTests: XCTestCase {
	let calc = CostCalculator() // bundled default pricing

	func testGrokIncludesThePublished200kBoundary() throws {
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "grok-4.7", usage: TokenUsage(input: 199_999))), 0.399998, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "grok-4.7", usage: TokenUsage(input: 200_000))), 0.8, accuracy: 1e-12)
	}

	func testPublishedContextCliffsAndNewModels() throws {
		for (model, threshold, base, premium) in [
			("gpt-6-luna", 272_000, 0.10, 0.20),
			("gpt-6-sol", 272_000, 2.0, 4.0),
			("gpt-reserve", 272_000, 0.20, 0.40),
			("qwen3.6-plus", 256_000, 0.50, 2.0),
			("qwen3.7-plus", 256_000, 0.40, 1.20),
		] {
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(input: threshold))),
				Double(threshold) * base / 1_000_000, accuracy: 1e-12, model)
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(input: threshold + 1))),
				Double(threshold + 1) * premium / 1_000_000, accuracy: 1e-12, model)
		}
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "mimo-v2.6-pro", usage: TokenUsage(input: 1_000_000))), 0.435, accuracy: 1e-12)
		XCTAssertNil(calc.cost(model: "mimo-v2.6-flash-free", usage: TokenUsage(input: 1_000_000)))
	}

	func testOpus48CostWithExplicitCacheSplit() {
		let usage = TokenUsage(
			input: 1000, output: 200, cacheCreate5m: 400, cacheCreate1h: 100, cacheRead: 2000)
		let cost = try? XCTUnwrap(calc.cost(model: "claude-opus-4-8", usage: usage))
		// 1000*5e-6 + 200*25e-6 + 400*6.25e-6 + 100*10e-6 + 2000*0.5e-6
		// = 0.005 + 0.005 + 0.0025 + 0.001 + 0.001 = 0.0145
		XCTAssertEqual(cost ?? -1, 0.0145, accuracy: 1e-9)
	}

	func test1hCacheCostsMoreThan5m() {
		// The load-bearing #899 fix: 1-hour cache writes (2x) must cost more than 5-minute (1.25x).
		let fiveMin = calc.cost(model: "claude-opus-4-8", usage: TokenUsage(cacheCreate5m: 1000))!
		let oneHour = calc.cost(model: "claude-opus-4-8", usage: TokenUsage(cacheCreate1h: 1000))!
		XCTAssertGreaterThan(oneHour, fiveMin)
		XCTAssertEqual(oneHour / fiveMin, 10.0 / 6.25, accuracy: 1e-9)
	}

	func testDatedModelIdFallsBackToDatelessAlias() {
		// Logs carry the dated snapshot; pricing is keyed by the alias.
		let cost = calc.cost(model: "claude-opus-4-5-20251101", usage: TokenUsage(input: 1_000_000))
		XCTAssertEqual(cost ?? -1, 5.0, accuracy: 1e-9) // Opus 4.5 input = $5 / MTok
	}

	func testUnknownModelReturnsNilNotZero() {
		XCTAssertNil(calc.cost(model: "gpt-9-imaginary", usage: TokenUsage(input: 100)))
	}

	func testReasoningNotDoubleCountedConvention() {
		// output already includes reasoning; we price `output` once at the output rate.
		let cost = calc.cost(model: "claude-haiku-4-5", usage: TokenUsage(output: 1_000_000))
		XCTAssertEqual(cost ?? -1, 5.0, accuracy: 1e-9) // Haiku 4.5 output = $5 / MTok
	}

	func testCacheReadSavingsIsInputMinusCacheReadRate() {
		// Opus 4.8: input $5 / MTok, cache-read $0.5 / MTok → each cached token saves $4.5 / MTok.
		let saved = calc.cacheReadSavings(model: "claude-opus-4-8", usage: TokenUsage(cacheRead: 2000))
		XCTAssertEqual(saved ?? -1, 2000 * 4.5e-6, accuracy: 1e-12) // = 0.009
	}

	func testCacheReadSavingsIgnoresNonCacheTokens() {
		// Only cacheRead drives the saving; input/output/writes don't change it.
		let a = calc.cacheReadSavings(model: "claude-opus-4-8", usage: TokenUsage(cacheRead: 1000))
		let b = calc.cacheReadSavings(
			model: "claude-opus-4-8",
			usage: TokenUsage(input: 9_999, output: 9_999, cacheCreate5m: 9_999, cacheRead: 1000))
		XCTAssertEqual(a ?? -1, b ?? -2, accuracy: 1e-12)
	}

	func testCacheReadSavingsNilWithoutCacheReadsOrPrice() {
		XCTAssertNil(calc.cacheReadSavings(model: "claude-opus-4-8", usage: TokenUsage(input: 5000)))
		XCTAssertNil(calc.cacheReadSavings(model: "gpt-9-imaginary", usage: TokenUsage(cacheRead: 5000)))
	}

	// MARK: - forceTier primitive (backs the window-summary grouped scan)

	func testExceedsContextTierSumsContextTokensNotOutput() {
		// Context = input + cacheRead + cacheCreate5m + cacheCreate1h; output is excluded.
		XCTAssertFalse(CostCalculator.exceedsContextTier(TokenUsage(input: 200_000, output: 9_000_000)))
		XCTAssertTrue(CostCalculator.exceedsContextTier(TokenUsage(input: 100_000, cacheRead: 100_001)))
		XCTAssertFalse(CostCalculator.exceedsContextTier(TokenUsage(input: 100_000, cacheRead: 100_000)))
	}

	func testForceTierMatchesAutoDerivedTierBelowAndAboveCliff() {
		// Sonnet 4.5 carries a real >200K tier. The auto `cost` must equal `forceTier:` fed the SAME
		// per-event decision on both sides of the cliff.
		let below = TokenUsage(input: 150_000, output: 1_000)
		let above = TokenUsage(input: 250_000, output: 1_000)
		XCTAssertEqual(
			calc.cost(model: "claude-sonnet-4-5", usage: below)!,
			calc.cost(model: "claude-sonnet-4-5", usage: below, forceTier: false)!, accuracy: 1e-12)
		XCTAssertEqual(
			calc.cost(model: "claude-sonnet-4-5", usage: above)!,
			calc.cost(model: "claude-sonnet-4-5", usage: above, forceTier: true)!, accuracy: 1e-12)
	}

	func testForceTierTrueCostsMoreThanFalseForATieredModel() {
		let usage = TokenUsage(input: 300_000, output: 50_000)
		let base = calc.cost(model: "claude-sonnet-4-5", usage: usage, forceTier: false)!
		let surcharged = calc.cost(model: "claude-sonnet-4-5", usage: usage, forceTier: true)!
		XCTAssertGreaterThan(surcharged, base)
	}

	func testForceTierIsInertForAModelWithoutAn200kTier() {
		// Opus 4.8 has no above-200K pricing → both flags must price identically, so splitting such a
		// model across both grouped buckets is harmless.
		let usage = TokenUsage(input: 500_000, output: 10_000, cacheRead: 100_000)
		XCTAssertEqual(
			calc.cost(model: "claude-opus-4-8", usage: usage, forceTier: false)!,
			calc.cost(model: "claude-opus-4-8", usage: usage, forceTier: true)!, accuracy: 1e-12)
	}

	func testForceTierAggregationEqualsPerEventSumAcrossTheCliff() {
		// The core invariant: summing per-event costs == pricing the summed tokens ONCE with the
		// pre-decided tier, split into a sub-200K bucket and a >200K bucket. This is exactly what the
		// grouped scan does; a naive "sum then re-derive tier" would over-bill the sub-200K bucket.
		let model = "claude-sonnet-4-5"
		let subEvents = [
			TokenUsage(input: 40_000, output: 500),
			TokenUsage(input: 60_000, output: 700, cacheRead: 10_000),
			TokenUsage(input: 30_000, output: 200),
		]
		let overEvents = [
			TokenUsage(input: 260_000, output: 3_000),
			TokenUsage(input: 500_000, output: 9_000, cacheCreate5m: 20_000),
		]
		let perEvent = (subEvents + overEvents).reduce(0.0) { $0 + calc.cost(model: model, usage: $1)! }

		func sum(_ xs: [TokenUsage]) -> TokenUsage { xs.reduce(TokenUsage()) { $0 + $1 } }
		let grouped =
			calc.cost(model: model, usage: sum(subEvents), forceTier: false)!
			+ calc.cost(model: model, usage: sum(overEvents), forceTier: true)!

		XCTAssertEqual(grouped, perEvent, accuracy: 1e-9)
		// And prove the naive approach (sum everything, re-derive tier) does NOT match — the exact trap.
		let naive = calc.cost(model: model, usage: sum(subEvents + overEvents))!
		XCTAssertNotEqual(naive, perEvent, accuracy: 1e-6)
	}
}
