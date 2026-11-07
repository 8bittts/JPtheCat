import Foundation
import XCTest

@testable import JPtheCatCore

/// Claude US-only inference bills every token category at 1.1x on Claude 4.6 and later, stacked on
/// fast mode, and Claude Code logs where inference ran as `message.usage.inference_geo`.
/// Source: platform.claude.com/docs/en/build-with-claude/data-residency, checked 2026-10-06.
final class ClaudeUSInferenceTests: XCTestCase {
	private let calc = CostCalculator()

	private func line(model: String, geo: String?, speed: String? = nil) -> Data {
		let geoField = geo.map { ",\"inference_geo\":\"\($0)\"" } ?? ""
		let speedField = speed.map { ",\"speed\":\"\($0)\"" } ?? ""
		return Data(
			("{\"type\":\"assistant\",\"requestId\":\"req\",\"timestamp\":\"2026-10-06T10:00:00.000Z\","
				+ "\"message\":{\"id\":\"msg\",\"model\":\"\(model)\",\"usage\":{\"input_tokens\":1,"
				+ "\"output_tokens\":1\(geoField)\(speedField)}}}").utf8)
	}

	func testOnlyAUSGeoSelectsTheUSInferenceID() {
		XCTAssertEqual(ClaudeProvider.decode(line: line(model: "claude-sonnet-5-5", geo: "us"))?.model, "claude-sonnet-5-5-us-inference")
		XCTAssertEqual(
			ClaudeProvider.decode(line: line(model: "claude-opus-5-5[1m]", geo: "us", speed: "fast"))?.model,
			"claude-opus-5-5-fast-mode-us-inference")
		for geo in ["global", "not_available", nil] {
			XCTAssertEqual(ClaudeProvider.decode(line: line(model: "claude-sonnet-5-5", geo: geo))?.model, "claude-sonnet-5-5", geo ?? "nil")
		}
	}

	func testUSInferenceIsElevenTenthsOfTheTurnRateInEveryBucket() throws {
		let buckets = [
			TokenUsage(input: 1_000_000), TokenUsage(output: 1_000_000), TokenUsage(cacheCreate5m: 1_000_000),
			TokenUsage(cacheCreate1h: 1_000_000), TokenUsage(cacheRead: 1_000_000),
		]
		for base in ["claude-sonnet-5-5", "claude-opus-4-6", "claude-opus-5-5-fast-mode"] {
			for usage in buckets {
				let standard = try XCTUnwrap(calc.cost(model: base, usage: usage), base)
				let us = try XCTUnwrap(calc.cost(model: base + "-us-inference", usage: usage), base)
				XCTAssertEqual(us, standard * 1.1, accuracy: 1e-9, base)
			}
		}
		// Sonnet 5.5 at $2 input becomes $2.20; fast Opus 5.5 at $40 output becomes $44.
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-sonnet-5-5-us-inference", usage: TokenUsage(input: 1_000_000))), 2.2, accuracy: 1e-9)
		XCTAssertEqual(
			try XCTUnwrap(calc.cost(model: "claude-opus-5-5-fast-mode-us-inference", usage: TokenUsage(output: 1_000_000))), 44, accuracy: 1e-9)
	}

	/// The factor scales a context premium too, and keeps the row's threshold.
	func testMultiplierScalesTheContextTierAndKeepsItsThreshold() throws {
		let tiered = ModelPrice(
			inputCostPerToken: 1e-6, outputCostPerToken: 2e-6,
			cacheCreationInputTokenCost: nil, cacheCreationInputTokenCostAbove1hr: nil, cacheReadInputTokenCost: nil,
			contextTierThreshold: 100_000,
			inputCostPerTokenAbove200k: 3e-6, outputCostPerTokenAbove200k: nil,
			cacheCreationInputTokenCostAbove200k: nil, cacheCreationInputTokenCostAbove1hrAbove200k: nil,
			cacheReadInputTokenCostAbove200k: nil)
		let table = PricingTable(models: ["m": tiered], aliases: [:], rateMultipliers: ["-us-inference": 2])
		let scaled = try XCTUnwrap(table.price(for: "m-us-inference"))
		XCTAssertEqual(scaled.contextTierThreshold, 100_000)
		XCTAssertEqual(try XCTUnwrap(scaled.inputCostPerTokenAbove200k), 6e-6, accuracy: 1e-15)
		XCTAssertNil(scaled.cacheReadInputTokenCost, "A missing field stays missing so fallbacks scale with input.")
		let calc = CostCalculator(pricing: table)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "m-us-inference", usage: TokenUsage(input: 100_001))), 0.600006, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "m-us-inference", usage: TokenUsage(cacheRead: 50_000))), 0.01, accuracy: 1e-9)
	}

	func testUSInferenceOnAnUnpricedModelStaysUnpriced() {
		XCTAssertNil(calc.cost(model: "claude-opus-6-us-inference", usage: TokenUsage(input: 1)))
		XCTAssertNil(calc.cost(model: "mimo-v2.5-free-us-inference", usage: TokenUsage(input: 1)))
		XCTAssertNil(PricingTable.bundledDefault().price(for: "-us-inference"), "A bare suffix is not a model.")
	}

	func testUSInferenceFoldsIntoItsModelForDisplayEffortAndGrouping() {
		for id in ["claude-opus-5-5-us-inference", "claude-opus-5-5-fast-mode-us-inference"] {
			XCTAssertEqual(ModelIdentity.presentationID(id), "claude-opus-5-5")
			XCTAssertEqual(ModelIdentity.modelKey(id), "claude-opus-5-5")
			XCTAssertEqual(ModelName.short(id), ModelName.short("claude-opus-5-5"))
		}
	}

	/// Every bundled factor must key a suffix `presentationID` strips, or the turn would show as its own
	/// model tile.
	func testEveryBundledMultiplierIsAnAccountingSuffix() {
		let multipliers = PricingTable.bundledRateMultipliers
		XCTAssertEqual(multipliers, ["-us-inference": 1.1])
		XCTAssertTrue(PricingTable.rateMultipliersAreSound(multipliers))
		for suffix in multipliers.keys {
			XCTAssertEqual(ModelIdentity.presentationID("claude-opus-5-5" + suffix), "claude-opus-5-5", suffix)
		}
	}

	func testRemoteFeedRejectsAnUnsoundMultiplierAndKeepsBundledOnesWhenOmitted() throws {
		let row = #""models":{"grok-4.7":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000006}}"#
		for bad in [#"{"-us-inference":0}"#, #"{"-us-inference":-1.1}"#, #"{"-us-inference":12}"#, #"{"us-inference":1.1}"#] {
			let body = Data(#"{"pricing_revision":2,"rate_multipliers":\#(bad),\#(row)}"#.utf8)
			XCTAssertNil(RemotePricingStore.decodeTable(body), bad)
		}
		let raised = try XCTUnwrap(RemotePricingStore.decodeTable(Data(#"{"pricing_revision":2,"rate_multipliers":{"-us-inference":1.2},\#(row)}"#.utf8)))
		let merged = PricingTable.bundledDefault().merging(raised)
		XCTAssertEqual(
			try XCTUnwrap(CostCalculator(pricing: merged).cost(model: "claude-sonnet-5-5-us-inference", usage: TokenUsage(input: 1_000_000))),
			2.4, accuracy: 1e-9)
		let silent = try XCTUnwrap(RemotePricingStore.decodeTable(Data(#"{"pricing_revision":2,\#(row)}"#.utf8)))
		XCTAssertEqual(PricingTable.bundledDefault().merging(silent).rateMultipliers, ["-us-inference": 1.1])
	}
}
