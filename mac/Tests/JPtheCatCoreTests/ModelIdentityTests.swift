import XCTest

@testable import JPtheCatCore

/// One model-id pipeline serves pricing, effort, display, and grouping. These tests read the SAME
/// fixture as `web/tests/model-identity.test.ts`, so the app and the website cannot label, group, or
/// classify an emitted id differently.
final class ModelIdentityTests: XCTestCase {
	private struct Fixture: Decodable {
		struct Case: Decodable {
			let model: String
			let presentation: String
			let short: String
			let analytics: String
			let effort: String?
		}
		let cases: [Case]
	}

	func testSharedFixtureMatchesPresentationLabelsAndEffort() throws {
		let fixture = try loadFixture()
		XCTAssertGreaterThan(fixture.cases.count, 20, "The shared fixture lost its cases.")
		for item in fixture.cases {
			XCTAssertEqual(ModelIdentity.presentationID(item.model), item.presentation, item.model)
			XCTAssertEqual(ModelName.short(item.model), item.short, item.model)
			XCTAssertEqual(ModelName.analyticsShort(item.model), item.analytics, item.model)
			XCTAssertEqual(ModelEffort.level(for: item.model)?.rawValue, item.effort, item.model)
		}
	}

	func testAccountingSuffixesStripOnlyForPresentationNeverForPricing() {
		let table = PricingTable.bundledDefault()
		// The route selects the rate, so pricing must see it...
		XCTAssertEqual(table.price(for: "deepseek-v4-flash-go-peak")?.inputCostPerToken, 3e-7)
		XCTAssertEqual(table.price(for: "deepseek-v4-flash-go")?.inputCostPerToken, 1.5e-7)
		XCTAssertEqual(table.price(for: "deepseek-v4-flash")?.inputCostPerToken, 1.4e-7)
		XCTAssertNil(table.price(for: "grok-4.7-opencode")?.contextTierInclusive)
		XCTAssertEqual(table.price(for: "grok-4.7-build")?.contextTierInclusive, true)
		// ...while display and grouping see one model.
		for route in ["deepseek-v4-flash-go-peak", "deepseek-v4-flash-go", "deepseek-v4-flash"] {
			XCTAssertEqual(ModelIdentity.presentationID(route), "deepseek-v4-flash")
		}
		XCTAssertEqual(ModelIdentity.presentationID("-go"), "-go", "A bare suffix is not a route.")
	}

	/// The alias map is data in `pricing-default.json`. Every target must be a real row, every key must
	/// be a live lookup id (undecorated, lowercase, not free-tier), no key may shadow a row, and no
	/// alias may point at another alias.
	func testBundledAliasesPointAtRealRowsOnly() {
		let table = PricingTable.bundledDefault()
		let aliases = ModelIdentity.bundledAliases
		XCTAssertFalse(aliases.isEmpty, "pricing-default.json lost its aliases map")
		XCTAssertEqual(table.aliases, aliases)
		XCTAssertEqual(PricingTable.aliasDefects(aliases, rows: table.knownModels), [])
		for (alias, target) in aliases {
			XCTAssertFalse(table.knownModels.contains(alias), "\(alias) shadows a priced row")
			XCTAssertNil(aliases[target], "\(alias) → \(target) chains through another alias")
			XCTAssertNotNil(table.price(for: alias), alias)
		}
	}

	/// Each rule a dead or harmful alias breaks is reported, so neither the bundled map nor a remote
	/// feed can carry a key that `pricingID` never reaches.
	func testAliasDefectsNameEveryDeadOrHarmfulKey() {
		let rows: Set<String> = ["gpt-5.5"]
		XCTAssertEqual(PricingTable.aliasDefects(["gpt-5.5-latest": "gpt-5.5"], rows: rows), [])
		XCTAssertEqual(
			PricingTable.aliasDefects([
				"gpt-ghost": "gpt-9",
				"gpt-5.5-free": "gpt-5.5",
				"GPT-5.5-LATEST": "gpt-5.5",
				"openai/gpt-5.5-latest": "gpt-5.5",
				"gpt-5.5-latest-20260101": "gpt-5.5",
				"gpt-5.5-latest[1m]": "gpt-5.5",
			], rows: rows),
			[
				"GPT-5.5-LATEST → gpt-5.5: key is not a lookup id",
				"gpt-5.5-free → gpt-5.5: key is a free-tier id",
				"gpt-5.5-latest-20260101 → gpt-5.5: key is not a lookup id",
				"gpt-5.5-latest[1m] → gpt-5.5: key is not a lookup id",
				"gpt-ghost → gpt-9: target has no row",
				"openai/gpt-5.5-latest → gpt-5.5: key is not a lookup id",
			])
	}

	/// Parsers and lookups share one vendor-prefix rule: the text after the LAST `/`, unless the id
	/// ends in `/`. `audit_model_coverage.py` mirrors the same edge cases.
	func testParserAndLookupShareOneVendorPrefixRule() {
		let cases = [
			("openrouter/deepseek/deepseek-v4-pro", "deepseek-v4-pro"),
			("meta/muse-spark-1.1", "muse-spark-1.1"),
			("deepseek/", "deepseek/"),
			("/", "/"),
			("gpt-5.5", "gpt-5.5"),
		]
		for (raw, expected) in cases {
			XCTAssertEqual(ModelIdentity.withoutVendorPrefix(raw), expected, raw)
			XCTAssertEqual(ProviderModelNormalization.strippingVendorPrefix(raw, fallback: "x"), expected, raw)
		}
		XCTAssertEqual(ProviderModelNormalization.strippingVendorPrefix(nil, fallback: "x"), "x")
		XCTAssertEqual(ProviderModelNormalization.strippingVendorPrefix("", fallback: "x"), "x")
	}

	/// The snapshot date is read with the same decorators `undecorated` removes, including a date that
	/// sits before `[1m]`.
	func testSnapshotDateUsesTheUndecoratedPipeline() {
		XCTAssertEqual(ModelIdentity.snapshotDate("anthropic/claude-opus-4-5-20251101[1m]"), 20_251_101)
		XCTAssertEqual(ModelIdentity.snapshotDate("gpt-5.2-2025-12-11"), 20_251_211)
		XCTAssertNil(ModelIdentity.snapshotDate("grok-code-fast-1-0825"))
		XCTAssertNil(ModelIdentity.snapshotDate("claude-opus-5-5[1m]"))
	}

	/// A free tier is recognized through decorators everywhere: pricing, the unpriced disclosure, and
	/// remote alias validation all call this one predicate.
	func testFreeTierSurvivesDecorators() {
		for id in ["mimo-v2.5-free", "muse-spark-1.3-contributor-free[1m]", "opencode/mimo-v2.6-pro-free-20260923"] {
			XCTAssertTrue(ModelIdentity.isFreeTier(id), id)
		}
		for id in ["mimo-v2.5", "free", "-free-model"] {
			XCTAssertFalse(ModelIdentity.isFreeTier(id), id)
		}
	}

	/// Lookup ids fold case like `modelKey` already does, so an id that resolves an effort tier and a
	/// Go cap never silently misses its price. The exact row still wins, and display keeps the case.
	func testPricingFoldsCaseLikeEffortAndCaps() {
		let table = PricingTable.bundledDefault()
		XCTAssertEqual(ModelIdentity.pricingID("OpenAI/GPT-5.6-2026-06-01", aliases: table.aliases), "gpt-5.6-sol")
		XCTAssertEqual(table.price(for: "Claude-Opus-4-8[1m]")?.inputCostPerToken, 5e-6)
		XCTAssertEqual(table.price(for: "MiMo-V2.5-Pro")?.inputCostPerToken, 4.35e-7)
		XCTAssertEqual(ModelEffort.level(for: "MiMo-V2.5-Pro"), ModelEffort.level(for: "mimo-v2.5-pro"))
		XCTAssertNil(table.price(for: "MiMo-V2.5-FREE"), "A free tier never folds onto a paid row.")
		XCTAssertEqual(ModelIdentity.presentationID("MiMo-V2.5-Pro"), "MiMo-V2.5-Pro")
	}

	/// One model split across a gateway route, a snapshot date, or `[1m]` shows as one row with the
	/// exact sum of its separately priced parts. A free tier keeps its own unpriced row.
	func testPresentedRollupMergesRoutesWithExactDollars() throws {
		func bucket(_ cost: Double?, model: String, input: Int) -> CostBucket {
			var b = CostBucket()
			b.add(
				UsageEvent(
					messageId: model, requestId: model, provider: .opencodego, model: model,
					timestamp: Date(timeIntervalSince1970: 0), usage: TokenUsage(input: input)),
				cost: cost)
			return b
		}
		let rollup = UsageRollup(
			today: CostBucket(), last7d: CostBucket(),
			byModel7d: [
				"deepseek-v4.1-flash": bucket(1.11, model: "deepseek-v4.1-flash", input: 100),
				"deepseek-v4.1-flash-peak": bucket(0.33, model: "deepseek-v4.1-flash-peak", input: 20),
				"mimo-v2.5": bucket(0.5, model: "mimo-v2.5", input: 10),
				"mimo-v2.5-free": bucket(nil, model: "mimo-v2.5-free", input: 7),
			])
		let merged = rollup.byPresentedModel7d
		XCTAssertEqual(Set(merged.keys), ["deepseek-v4.1-flash", "mimo-v2.5", "mimo-v2.5-free"])
		let flash = try XCTUnwrap(merged["deepseek-v4.1-flash"])
		XCTAssertEqual(flash.cost, 1.44, accuracy: 1e-9)
		XCTAssertEqual(flash.eventCount, 2)
		XCTAssertEqual(flash.usage.input, 120)
		XCTAssertTrue(flash.unpricedModels.isEmpty)
		XCTAssertEqual(merged["mimo-v2.5"]?.cost, 0.5)
		XCTAssertEqual(merged["mimo-v2.5-free"]?.unpricedModels, ["mimo-v2.5-free"])
	}

	/// Advanced Analytics rows fold routes the same way, after each event is priced under its own id.
	func testModelDayRowsFoldRoutesAfterPricingEachEvent() {
		let day = Date(timeIntervalSince1970: 1_790_000_000)
		let events = ["deepseek-v4-flash-go", "deepseek-v4-flash-go-peak"].map { model in
			UsageEvent(
				messageId: model, requestId: model, provider: .opencodego, model: model, timestamp: day,
				usage: TokenUsage(input: 1_000_000))
		}
		let rows = ModelDaySummary.bucketed(events: events, calculator: CostCalculator())
		XCTAssertEqual(rows.count, 1)
		XCTAssertEqual(rows.first?.model, "deepseek-v4-flash")
		XCTAssertEqual(rows.first?.eventCount, 2)
		XCTAssertEqual(rows.first?.cost ?? 0, 0.15 + 0.30, accuracy: 1e-9, "off-peak + peak input rates")
	}

	private func loadFixture() throws -> Fixture {
		// #filePath = mac/Tests/JPtheCatCoreTests/ModelIdentityTests.swift → up 3 = mac/, up 1 = repo root.
		let repoRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
		let url = repoRoot.appendingPathComponent("web/tests/fixtures/model-identity-cases.json")
		return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
	}
}
