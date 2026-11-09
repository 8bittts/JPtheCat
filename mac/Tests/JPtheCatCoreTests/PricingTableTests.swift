import XCTest

@testable import JPtheCatCore

final class PricingTableTests: XCTestCase {
	let table = PricingTable.bundledDefault()
	let calc = CostCalculator()

	func testDecoratedFreeModelsNeverResolveToPaidContributorRates() {
		let table = PricingTable.bundledDefault()
		for id in ["muse-spark-1.3-contributor-free[1m]", "mimo-v2.6-pro-free-20260923", "mimo-v2.6-pro-free-2026-09-23"] {
			XCTAssertNil(table.price(for: id), id)
		}
		XCTAssertEqual(table.price(for: "muse-spark-1.3-contributor-20260923")?.inputCostPerToken, 0.0000001)
	}

	func testNormalizesProviderModelAliasesAndSuffixes() {
		XCTAssertEqual(ModelIdentity.pricingID("claude-opus-4-5-20251101", aliases: table.aliases), "claude-opus-4-5")
		XCTAssertEqual(ModelIdentity.pricingID("gpt-5.2-2025-12-11", aliases: table.aliases), "gpt-5.2")
		XCTAssertEqual(ModelIdentity.pricingID("claude-opus-4-8[1m]", aliases: table.aliases), "claude-opus-4-8")
		XCTAssertEqual(ModelIdentity.pricingID("claude-opus-5-20260724", aliases: table.aliases), "claude-opus-5")
		XCTAssertEqual(ModelIdentity.pricingID("claude-opus-5[1m]", aliases: table.aliases), "claude-opus-5")
		XCTAssertEqual(ModelIdentity.pricingID("gpt-5.6", aliases: table.aliases), "gpt-5.6-sol")
		XCTAssertEqual(ModelIdentity.pricingID("gpt-5.6-2026-06-01", aliases: table.aliases), "gpt-5.6-sol")
		XCTAssertEqual(ModelIdentity.pricingID("gpt-reserve", aliases: table.aliases), "gpt-5.6-luna")
		XCTAssertEqual(ModelIdentity.pricingID("composer-2.5-fast", aliases: table.aliases), "grok-composer-2.5-fast")
		XCTAssertEqual(ModelIdentity.pricingID("claude-opus-5-5[1m]", aliases: table.aliases), "claude-opus-5-5")
		XCTAssertEqual(ModelIdentity.pricingID("grok-4.7-build", aliases: table.aliases), "grok-4.7")
		XCTAssertEqual(ModelIdentity.pricingID("grok-4.7-high-fast", aliases: table.aliases), "grok-4.7-fast")
		XCTAssertEqual(ModelIdentity.pricingID("claude-opus-5-5-medium", aliases: table.aliases), "claude-opus-5-5")
		XCTAssertEqual(ModelIdentity.pricingID("grok-4.6-build", aliases: table.aliases), "grok-4.6")
		XCTAssertEqual(ModelIdentity.pricingID("grok-4.6-latest", aliases: table.aliases), "grok-4.6")
		XCTAssertEqual(ModelIdentity.pricingID("grok-4.5-build", aliases: table.aliases), "grok-4.5")
		XCTAssertEqual(ModelIdentity.pricingID("claude-opus-4-8", aliases: table.aliases), "claude-opus-4-8")
	}

	func testBundledCoversActivelyLoggedModels() {
		// Regression guard for new Claude families: real, logged models must never silently drop to $0.
		for model in [
			"claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-5", "claude-fable-5-2", "claude-fable-5-1", "claude-fable-5",
			"claude-mythos-5-1", "claude-mythos-5",
			"claude-sonnet-5", "claude-sonnet-4-5", "claude-haiku-4-5",
		] {
			XCTAssertNotNil(table.price(for: model), "\(model) must be priced")
			XCTAssertNotNil(calc.cost(model: model, usage: TokenUsage(input: 100)), "\(model) must cost")
		}
	}

	/// Opus 5.5 (platform.claude.com): $4 in / $20 out / $5 5m-write / $8 1h-write, and a cache READ
	/// of $0.20 per MTok — 0.05x input, NOT the standard 0.1x. Flat to 1M (no >200K tier).
	func testOpus55PricedWithItsOwnCacheReadMultiplier() {
		XCTAssertEqual(calc.cost(model: "claude-opus-5-5", usage: TokenUsage(input: 1_000_000))!, 4.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5-5", usage: TokenUsage(output: 1_000_000))!, 20.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5-5", usage: TokenUsage(cacheCreate5m: 1_000_000))!, 5.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5-5", usage: TokenUsage(cacheCreate1h: 1_000_000))!, 8.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5-5", usage: TokenUsage(cacheRead: 1_000_000))!, 0.2, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5-5[1m]", usage: TokenUsage(input: 300_000))!, 1.2, accuracy: 1e-9)
	}

	func testOpus5Priced() {
		// Official rates (platform.claude.com): $5 in / $25 out / $6.25 5m-write / $10 1h-write / $0.50 read per MTok.
		XCTAssertEqual(calc.cost(model: "claude-opus-5", usage: TokenUsage(input: 1_000_000))!, 5.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5", usage: TokenUsage(output: 1_000_000))!, 25.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5", usage: TokenUsage(cacheCreate5m: 1_000_000))!, 6.25, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5", usage: TokenUsage(cacheCreate1h: 1_000_000))!, 10.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5", usage: TokenUsage(cacheRead: 1_000_000))!, 0.5, accuracy: 1e-9)
		// Dated + [1m] variants normalize to the same price (no >200K tier — Opus is flat to 1M).
		XCTAssertEqual(calc.cost(model: "claude-opus-5-20260724", usage: TokenUsage(input: 1_000_000))!, 5.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-5[1m]", usage: TokenUsage(input: 300_000))!, 1.5, accuracy: 1e-9)
	}

	/// Fable 5.1 and Mythos 5.1 (platform.claude.com): $10 in / $50 out / $12.50 5m-write /
	/// $20 1h-write, and a cache READ of $0.25 per MTok — 0.025x input, NOT the 0.1x every other
	/// Claude model uses. A missing row would fall back to Fable 5's $1 read and overbill 4x.
	/// Fable 5.2 (platform.claude.com): $8 in / $40 out / $10 5m-write / $16 1h-write / $0.20 cache read.
	/// Cache reads stay 0.025x, but the base rate is lower than Fable 5.1, so this is its own row.
	func testFable52IsItsOwnRow() {
		XCTAssertEqual(calc.cost(model: "claude-fable-5-2", usage: TokenUsage(input: 1_000_000))!, 8.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-fable-5-2", usage: TokenUsage(output: 1_000_000))!, 40.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-fable-5-2", usage: TokenUsage(cacheCreate5m: 1_000_000))!, 10.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-fable-5-2", usage: TokenUsage(cacheCreate1h: 1_000_000))!, 16.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-fable-5-2", usage: TokenUsage(cacheRead: 1_000_000))!, 0.2, accuracy: 1e-9)
		XCTAssertEqual(ModelIdentity.pricingID("claude-fable-5-2", aliases: table.aliases), "claude-fable-5-2")
		XCTAssertEqual(ModelName.short("claude-fable-5-2"), "fable-5-2")
		XCTAssertEqual(ModelEffort.level(for: "claude-fable-5-2"), .high)
		// Cursor's effort suffix bills at Opus 5.5. Effort does not change Anthropic's per-token rate.
		XCTAssertEqual(calc.cost(model: "claude-opus-5-5-medium", usage: TokenUsage(input: 1_000_000))!, 4.0, accuracy: 1e-9)
		XCTAssertEqual(ModelEffort.level(for: "claude-opus-5-5-medium"), .high)
	}

	func testFable51AndMythos51PricedWithReducedCacheRead() {
		for model in ["claude-fable-5-1", "claude-mythos-5-1"] {
			XCTAssertEqual(calc.cost(model: model, usage: TokenUsage(input: 1_000_000))!, 10.0, accuracy: 1e-9)
			XCTAssertEqual(calc.cost(model: model, usage: TokenUsage(output: 1_000_000))!, 50.0, accuracy: 1e-9)
			XCTAssertEqual(calc.cost(model: model, usage: TokenUsage(cacheCreate5m: 1_000_000))!, 12.5, accuracy: 1e-9)
			XCTAssertEqual(calc.cost(model: model, usage: TokenUsage(cacheCreate1h: 1_000_000))!, 20.0, accuracy: 1e-9)
			XCTAssertEqual(calc.cost(model: model, usage: TokenUsage(cacheRead: 1_000_000))!, 0.25, accuracy: 1e-9)
		}
		// 5.1 is a DISTINCT row, never normalized onto 5 — the cache-read rates differ 4x.
		XCTAssertEqual(ModelIdentity.pricingID("claude-fable-5-1", aliases: table.aliases), "claude-fable-5-1")
		XCTAssertEqual(calc.cost(model: "claude-fable-5-1-20260812", usage: TokenUsage(cacheRead: 1_000_000))!, 0.25, accuracy: 1e-9)
	}

	func testFable5Priced() {
		XCTAssertEqual(calc.cost(model: "claude-fable-5", usage: TokenUsage(input: 1_000_000))!, 10.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-fable-5", usage: TokenUsage(output: 1_000_000))!, 50.0, accuracy: 1e-9)
	}

	func testMythos5Priced() {
		XCTAssertEqual(calc.cost(model: "claude-mythos-5", usage: TokenUsage(input: 1_000_000))!, 10.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-mythos-5", usage: TokenUsage(output: 1_000_000))!, 50.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-mythos-5", usage: TokenUsage(cacheCreate5m: 1_000_000))!, 12.5, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-mythos-5", usage: TokenUsage(cacheCreate1h: 1_000_000))!, 20.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-mythos-5", usage: TokenUsage(cacheRead: 1_000_000))!, 1.0, accuracy: 1e-9)
	}

	func testSonnet5StandardPricing() throws {
		// Anthropic made the $2/$10 intro rate standard on 2026-08-10 (no Sept 1 increase).
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-sonnet-5", usage: TokenUsage(input: 1_000_000))), 2.0, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-sonnet-5", usage: TokenUsage(output: 1_000_000))), 10.0, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-sonnet-5", usage: TokenUsage(cacheCreate5m: 1_000_000))), 2.5, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-sonnet-5", usage: TokenUsage(cacheCreate1h: 1_000_000))), 4.0, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-sonnet-5", usage: TokenUsage(cacheRead: 1_000_000))), 0.2, accuracy: 1e-9)
	}

	func testSonnet55ExactAndDecoratedIDsUseAllFiveFlatRates() throws {
		let buckets: [(TokenUsage, Double)] = [
			(TokenUsage(input: 1_000_000), 2), (TokenUsage(output: 1_000_000), 10),
			(TokenUsage(cacheCreate5m: 1_000_000), 2.5),
			(TokenUsage(cacheCreate1h: 1_000_000), 4), (TokenUsage(cacheRead: 1_000_000), 0.1),
		]
		for model in ["claude-sonnet-5-5", "anthropic/claude-sonnet-5-5[1m]",
			"claude-sonnet-5-5-20260928", "claude-sonnet-5-5-2026-09-28"] {
			for (usage, expected) in buckets {
				XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: usage)), expected, accuracy: 1e-9, model)
			}
		}
		XCTAssertNil(table.price(for: "claude-sonnet-5-5-free[1m]"))
		XCTAssertNil(calc.cost(model: "claude-sonnet-unannounced", usage: TokenUsage(input: 100)))
	}

	func testHaiku55UsesAllFiveRatesAndExclusive100kPromptBoundary() throws {
		let buckets: [(TokenUsage, Double, Double)] = [
			(TokenUsage(input: 1_000_000), 0.1, 0.5),
			(TokenUsage(output: 1_000_000), 0.5, 2.5),
			(TokenUsage(cacheCreate5m: 1_000_000), 0.125, 0.625),
			(TokenUsage(cacheCreate1h: 1_000_000), 0.2, 1),
			(TokenUsage(cacheRead: 1_000_000), 0.01, 0.05),
		]
		for model in ["claude-haiku-5-5", "anthropic/claude-haiku-5-5[1m]", "claude-haiku-5-5-20261007"] {
			for (usage, base, premium) in buckets {
				XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: usage, forceTier: false)), base, accuracy: 1e-12)
				XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: usage, forceTier: true)), premium, accuracy: 1e-12)
			}
		}
		// Every input bucket counts toward prompt length; output never counts.
		let boundary = TokenUsage(input: 25_000, output: 1_000, cacheCreate5m: 25_000, cacheCreate1h: 25_000, cacheRead: 25_000)
		let premium = TokenUsage(input: 25_001, output: 1_000, cacheCreate5m: 25_000, cacheCreate1h: 25_000, cacheRead: 25_000)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-haiku-5-5", usage: boundary)), 0.011375, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-haiku-5-5", usage: premium)), 0.0568755, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "claude-haiku-5-5-us-inference", usage: premium)), 0.06256305, accuracy: 1e-12)
		XCTAssertEqual(ModelName.short("claude-haiku-5-5"), "haiku-5-5")
		XCTAssertEqual(ModelEffort.level(for: "claude-haiku-5-5"), .medium)
		XCTAssertNil(table.price(for: "claude-haiku-5-5-free[1m]"))
		XCTAssertNil(table.price(for: "claude-haiku-unannounced"))
	}

	/// developers.openai.com/api/docs/pricing, checked 2026-10-30: GPT-6.1 Terra is $1 / $5 / cached $0.05,
	/// 30-minute write $1.25, 12-hour write $2.50, with 2x input and cache and 1.5x output above 272K.
	func testGPT61TerraUsesOfficialRatesAndExact272kBoundary() throws {
		let model = "gpt-6.1-terra"
		let buckets: [(TokenUsage, Double, Double)] = [
			(TokenUsage(input: 1_000_000), 1, 2), (TokenUsage(output: 1_000_000), 5, 7.5),
			(TokenUsage(cacheRead: 1_000_000), 0.05, 0.1),
			(TokenUsage(cacheCreate5m: 1_000_000), 1.25, 2.5),
			(TokenUsage(cacheCreate1h: 1_000_000), 2.5, 5),
		]
		for (usage, base, premium) in buckets {
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: usage, forceTier: false)), base, accuracy: 1e-9)
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: usage, forceTier: true)), premium, accuracy: 1e-9)
		}
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(input: 272_000))), 0.272, accuracy: 1e-9)
	}

	func testGPT61SolHasDistinctCacheRatesAndExact272kBoundary() throws {
		let model = "gpt-6.1-sol"
		let buckets: [(TokenUsage, Double, Double)] = [
			(TokenUsage(input: 1_000_000), 2, 4), (TokenUsage(output: 1_000_000), 10, 15),
			(TokenUsage(cacheRead: 1_000_000), 0.1, 0.2),
			(TokenUsage(cacheCreate5m: 1_000_000), 2.5, 5),
			(TokenUsage(cacheCreate1h: 1_000_000), 5, 10),
		]
		for (usage, base, premium) in buckets {
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: usage, forceTier: false)), base, accuracy: 1e-9)
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: usage, forceTier: true)), premium, accuracy: 1e-9)
		}
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(input: 272_000))), 0.544, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(input: 272_001))), 1.088004, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "openai/gpt-6.1-sol-2026-10-01", usage: TokenUsage(cacheRead: 100_000))), 0.01, accuracy: 1e-9)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "gpt-6-sol", usage: TokenUsage(cacheRead: 100_000))), 0.02, accuracy: 1e-9)
	}

	func testSonnet45Above200kIsWholeRequestSurcharge() {
		// <=200K context: base $3/MTok. >200K context: the WHOLE request bills at $6/MTok.
		XCTAssertEqual(calc.cost(model: "claude-sonnet-4-5", usage: TokenUsage(input: 100_000))!, 0.3, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-sonnet-4-5", usage: TokenUsage(input: 250_000))!, 1.5, accuracy: 1e-9)
	}

	func testFlatModelsHaveNo200kCliff() {
		// Opus 4.8 is flat to 1M — a 300K-input turn stays at base rate.
		XCTAssertEqual(calc.cost(model: "claude-opus-4-8", usage: TokenUsage(input: 300_000))!, 1.5, accuracy: 1e-9)
	}

	func testCacheCreationBilledAt5mRate() {
		// Older logs without the 5m/1h split route cache-creation to the 5m bucket (1.25x).
		XCTAssertEqual(calc.cost(model: "claude-opus-4-8", usage: TokenUsage(cacheCreate5m: 1_000_000))!, 6.25, accuracy: 1e-9)
	}

	func testCodexModelsPricedForNotionalCost() {
		// Every gpt/codex model seen in local rollouts must resolve to a (notional) list price,
		// never silently drop to $0/unpriced.
		for model in [
			"gpt-6-astra", "gpt-5.6-sol", "gpt-5.6", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-reserve", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
			"gpt-5.3-codex", "gpt-5.2", "gpt-5.2-codex",
			"gpt-5.3-codex-spark", "gpt-5.1-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini", "gpt-5-codex",
		] {
			XCTAssertNotNil(table.price(for: model), "\(model) must be priced")
		}
		// List-rate spot checks (OpenAI API prices): gpt-5.3-codex output $14/MTok, gpt-5.5 input
		// $5/MTok, and cached input billed at 0.1x input ($0.50/MTok for gpt-5.5).
		XCTAssertEqual(calc.cost(model: "gpt-5.3-codex", usage: TokenUsage(output: 1_000_000), forceTier: false)!, 14.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.5", usage: TokenUsage(input: 1_000_000), forceTier: false)!, 5.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.5", usage: TokenUsage(cacheRead: 1_000_000), forceTier: false)!, 0.5, accuracy: 1e-9)
		// OpenAI Standard pricing: 30-minute writes at 1.25x input, 12-hour writes at 2x that rate.
		for (model, rate) in [("gpt-6-astra", 12.5), ("gpt-5.6-sol", 5.0),
			("gpt-5.6-terra", 2.5), ("gpt-5.6-luna", 0.25)] {
			let price = table.price(for: model)
			XCTAssertEqual(price?.cacheCreationInputTokenCost, rate / 1_000_000)
			XCTAssertEqual(price?.cacheCreationInputTokenCostAbove1hr, rate * 2 / 1_000_000)
		}

		XCTAssertEqual(calc.cost(model: "gpt-6-astra", usage: TokenUsage(input: 1_000_000), forceTier: false)!, 10.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-6-astra", usage: TokenUsage(output: 1_000_000), forceTier: false)!, 50.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-6-astra", usage: TokenUsage(cacheRead: 1_000_000), forceTier: false)!, 1.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-sol", usage: TokenUsage(input: 1_000_000), forceTier: false)!, 4.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-sol", usage: TokenUsage(output: 1_000_000), forceTier: false)!, 20.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-sol", usage: TokenUsage(cacheRead: 1_000_000), forceTier: false)!, 0.4, accuracy: 1e-9)
		// OpenAI cut Luna and Terra before later applying promotional pricing to Sol.
		XCTAssertEqual(calc.cost(model: "gpt-5.6-luna", usage: TokenUsage(input: 1_000_000), forceTier: false)!, 0.2, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-luna", usage: TokenUsage(output: 1_000_000), forceTier: false)!, 1.2, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-luna", usage: TokenUsage(cacheRead: 1_000_000), forceTier: false)!, 0.02, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-terra", usage: TokenUsage(input: 1_000_000), forceTier: false)!, 2.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-terra", usage: TokenUsage(output: 1_000_000), forceTier: false)!, 12.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.6-terra", usage: TokenUsage(cacheRead: 1_000_000), forceTier: false)!, 0.2, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gpt-5.2-2025-12-11", usage: TokenUsage(output: 1_000_000), forceTier: false)!, 14.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "claude-opus-4-8[1m]", usage: TokenUsage(input: 1_000_000), forceTier: false)!, 5.0, accuracy: 1e-9)
		// This historical Codex Mini row has no published premium tier.
		XCTAssertEqual(calc.cost(model: "gpt-5.1-codex-mini", usage: TokenUsage(input: 300_000))!, 0.075, accuracy: 1e-9)
	}

	func testGrokApiModelsCarryThe200kWholeRequestPremium() {
		// docs.x.ai: "Requests whose prompt reaches 200k tokens are billed at the higher rate for ALL
		// tokens in the request." xAI's threshold is exactly CostCalculator's 200000 tier, so the
		// surcharge is modelled here (unlike OpenAI, whose cliff sits at 272K and is deliberately flat).
		XCTAssertEqual(calc.cost(model: "grok-4.6", usage: TokenUsage(input: 100_000))!, 0.2, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.6", usage: TokenUsage(input: 250_000))!, 1.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.6", usage: TokenUsage(output: 1_000_000))!, 6.0, accuracy: 1e-9)
		// Cached input is model-specific: 4.6 is $0.50/M, 4.5 is $0.30/M. Stay under 200k so
		// the base tier applies — 1M cache-read would reprice the whole request at the cliff.
		XCTAssertEqual(calc.cost(model: "grok-4.6", usage: TokenUsage(cacheRead: 100_000))!, 0.05, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.5", usage: TokenUsage(cacheRead: 100_000))!, 0.03, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.5", usage: TokenUsage(input: 100_000))!, 0.2, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.5", usage: TokenUsage(input: 250_000))!, 1.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.5", usage: TokenUsage(output: 1_000_000))!, 6.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.3", usage: TokenUsage(input: 250_000))!, 0.625, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-build-0.1", usage: TokenUsage(input: 250_000))!, 0.5, accuracy: 1e-9)
		// Locally emitted Grok Build ids normalize onto their version's tiered row.
		// grok-4.7 (docs.x.ai): $2 / $0.50 cached / $6, doubled at 200K.
		XCTAssertEqual(calc.cost(model: "grok-4.7-build", usage: TokenUsage(input: 100_000))!, 0.2, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7-build", usage: TokenUsage(input: 250_000))!, 1.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7-build", usage: TokenUsage(cacheRead: 100_000))!, 0.05, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7-build", usage: TokenUsage(output: 1_000_000))!, 6.0, accuracy: 1e-9)
		// Grok 4.7 Fast (docs.x.ai): 2x below 200K, 1.5x once the prompt exceeds 200K.
		// At exactly 200K the fast row stays on the short rate; direct grok-4.7 is already on the long rate.
		XCTAssertEqual(calc.cost(model: "grok-4.7-high-fast", usage: TokenUsage(input: 200_000))!, 0.8, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7-fast", usage: TokenUsage(input: 200_001))!, 1.200006, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7-fast", usage: TokenUsage(cacheRead: 100_000))!, 0.1, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7-fast", usage: TokenUsage(output: 1_000_000))!, 12.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7", usage: TokenUsage(input: 200_000))!, 0.8, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.7", usage: TokenUsage(input: 199_999))!, 0.399998, accuracy: 1e-9)
		XCTAssertNil(table.price(for: "cursor-grok-4.6-high-fast"))
		XCTAssertEqual(ModelName.short("grok-4.7-fast"), "4.7-fast")
		XCTAssertEqual(ModelEffort.level(for: "grok-4.7-high-fast"), .high)
		XCTAssertEqual(calc.cost(model: "grok-4.6-build", usage: TokenUsage(input: 250_000))!, 1.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.6-build", usage: TokenUsage(cacheRead: 100_000))!, 0.05, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-4.5-build", usage: TokenUsage(input: 250_000))!, 1.0, accuracy: 1e-9)
		// Cursor publishes no cliff for the composer ids, so they must stay flat rather than inherit one.
		XCTAssertEqual(calc.cost(model: "grok-composer-2.5", usage: TokenUsage(input: 250_000))!, 0.125, accuracy: 1e-9)
	}

	func testGrokComposerModelsPricedForNotionalCost() {
		for model in ["grok-composer-2.5-fast", "grok-composer-2.5", "composer-2.5-fast"] {
			XCTAssertNotNil(table.price(for: model), "\(model) must be priced")
		}
		XCTAssertEqual(calc.cost(model: "grok-composer-2.5-fast", usage: TokenUsage(input: 1_000_000))!, 3.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-composer-2.5-fast", usage: TokenUsage(output: 1_000_000))!, 15.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-composer-2.5-fast", usage: TokenUsage(cacheRead: 1_000_000))!, 0.3, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-composer-2.5", usage: TokenUsage(input: 1_000_000))!, 0.5, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "grok-composer-2.5", usage: TokenUsage(output: 1_000_000))!, 2.5, accuracy: 1e-9)
	}

	func testGeminiModelsPricedForNotionalCost() {
		// Every Gemini model string seen on disk must resolve to a (notional) list price, never $0.
		for model in [
			"gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite",
			"gemini-3-pro-preview", "gemini-3", "gemini-3-flash-preview",
		] {
			XCTAssertNotNil(table.price(for: model), "\(model) must be priced")
		}
		// List-rate spot checks (Google Gemini API), context kept <200K so the BASE tier applies:
		// 2.5-pro input $1.25/MTok, output $10/MTok, cached read $0.125/MTok; 3-flash output $3/MTok.
		XCTAssertEqual(calc.cost(model: "gemini-2.5-pro", usage: TokenUsage(input: 100_000))!, 0.125, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-2.5-pro", usage: TokenUsage(output: 100_000))!, 1.0, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-2.5-pro", usage: TokenUsage(cacheRead: 100_000))!, 0.0125, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-3-flash-preview", usage: TokenUsage(output: 100_000))!, 0.3, accuracy: 1e-9)
		// Gemini 2.5 Pro carries the >200K-context surcharge (cliff at 200K, matching the threshold):
		// a 250K-input turn bills the WHOLE request at $2.50/MTok, not $1.25.
		XCTAssertEqual(calc.cost(model: "gemini-2.5-pro", usage: TokenUsage(input: 250_000))!, 0.625, accuracy: 1e-9)
		// Flash is flat: a 300K-input turn stays at base $0.30/MTok.
		XCTAssertEqual(calc.cost(model: "gemini-2.5-flash", usage: TokenUsage(input: 300_000))!, 0.09, accuracy: 1e-9)
	}

	/// Rows added by the 2026-09-26 audit, where ai.google.dev and opencode.ai/docs/zen publish the SAME
	/// rates, so one row serves Gemini CLI and Zen-routed turns. Gemini 3.6-3.8 Flash stay unpriced
	/// because Google's promotional rate and Zen's rate differ until 2027.
	func testZenServedGeminiAndQwenRowsMatchPublishedRates() {
		// Gemini 3.1 Pro: $2 in / $12 out / $0.20 cached, whole request at $4 above 200K (exclusive).
		XCTAssertEqual(calc.cost(model: "gemini-3.1-pro", usage: TokenUsage(input: 200_000))!, 0.4, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-3.1-pro", usage: TokenUsage(input: 200_001))!, 0.800004, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-3.1-pro-preview", usage: TokenUsage(output: 1_000_000))!, 12, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-3.5-flash", usage: TokenUsage(output: 1_000_000))!, 9, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-3.5-flash-lite", usage: TokenUsage(cacheRead: 1_000_000))!, 0.03, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "gemini-3-flash", usage: TokenUsage(input: 1_000_000))!, 0.5, accuracy: 1e-9)
		XCTAssertEqual(calc.cost(model: "qwen3.5-plus", usage: TokenUsage(cacheCreate5m: 1_000_000))!, 0.25, accuracy: 1e-9)
		for unpriced in ["gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.6-flash", "space-bunny-free"] {
			XCTAssertNil(table.price(for: unpriced), unpriced)
		}
	}
}
