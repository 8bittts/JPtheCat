import XCTest

@testable import JPtheCatCore

/// [CRITICAL] Pins the FULL `ProviderID` -> `ProviderBasis` table.
///
/// Pins the AGENTS.md "Providers" `isAggregable` rule.
///
/// `ProviderBasis.of(_:)` has a `default: .real` arm, so a new `ProviderID` case would otherwise land
/// in `.real` (aggregable, real-dollar) with every test still green. This table is exhaustive on
/// purpose: adding a case to `ProviderID` without classifying it here FAILS.
final class ProviderBasisTests: XCTestCase {
	/// Every provider the catalog can emit, and the basis it must resolve to.
	private static let expected: [ProviderID: ProviderBasis] = [
		.claude: .real,
		.codex: .notional,
		.gemini: .real,
		.copilot: .estimate,
		.opencode: .gateway,
		.amp: .real,
		.factory: .real,
		.codebuff: .real,
		.kilo: .real,
		.kimi: .real,
		.hermes: .real,
		.piAgent: .real,
		.goose: .real,
		.openclaw: .real,
		.qwen: .real,
		.qoder: .real,
		.codebuddy: .real,
		.cursor: .notional,
		.openai: .real,
		.azureopenai: .real,
		.opencodego: .gateway,
		.alibaba: .real,
		.alibabatokenplan: .real,
		.antigravity: .real,
		.devin: .real,
		.zai: .real,
		.minimax: .real,
		.manus: .real,
		.kiro: .real,
		.vertexai: .real,
		.augment: .real,
		.jetbrains: .real,
		.kimik2: .real,
		.moonshot: .real,
		.t3chat: .real,
		.ollama: .real,
		.synthetic: .real,
		.openrouter: .real,
		.elevenlabs: .real,
		.warp: .real,
		.windsurf: .real,
		.zed: .real,
		.perplexity: .real,
		.doubao: .real,
		.sakana: .real,
		.abacus: .real,
		.mistral: .real,
		.crof: .real,
		.venice: .real,
		.commandcode: .real,
		.stepfun: .real,
		.bedrock: .real,
		.grok: .notional,
		.grokBot: .notional,
		.groq: .real,
		.llmproxy: .real,
		.litellm: .real,
		.deepgram: .real,
		.poe: .real,
		.chutes: .real,
		.aider: .real,
		.museSpark: .notional,
		.nemotron: .notional,
		.mimo: .notional,
		.bigPickle: .notional,
		.deepseek: .notional,
	]

	func testEveryProviderIsExplicitlyClassified() {
		XCTAssertEqual(
			Set(ProviderID.allCases), Set(Self.expected.keys),
			"""
			A `ProviderID` was added or removed without classifying it in this table. Decide the basis \
			deliberately — `ProviderBasis.of(_:)` defaults new ids to `.real`, i.e. real dollars folded \
			into every `$` aggregate and alert.
			""")
		for id in ProviderID.allCases {
			guard let want = Self.expected[id] else { continue }
			XCTAssertEqual(ProviderBasis.of(id), want, "\(id.rawValue) resolved to the wrong basis")
		}
	}

	/// The one rule the whole table exists to enforce.
	func testOnlyEstimatesAndGatewaysAreNonAggregable() {
		let nonAggregable = ProviderID.allCases.filter { !ProviderBasis.of($0).isAggregable }
		// Copilot is `.estimate`; OpenCode Zen/Go are `.gateway`; unified Grok sources are notional.
		XCTAssertEqual(Set(nonAggregable), [.copilot, .opencode, .opencodego])
		let showsTokens = ProviderID.allCases.filter { ProviderBasis.of($0).showsTokens }
		XCTAssertEqual(Set(showsTokens), [.copilot])
	}

	func testNotionalFlagFollowsTheBasis() {
		XCTAssertFalse(ProviderBasis.real.isNotional)
		XCTAssertTrue(ProviderBasis.notional.isNotional)
		// An estimate row's dollars are list-price at best; it is never "real spend".
		XCTAssertTrue(ProviderBasis.estimate.isNotional)
		// A gateway rollup is list-price too — never asserted as real billed spend.
		XCTAssertTrue(ProviderBasis.gateway.isNotional)
		XCTAssertFalse(ProviderBasis.officialPlan.isNotional)
	}

	/// The badge vocabulary the dashboard selector rows and the Advanced Analytics sidebar BOTH render.
	func testBadgeVocabularyIsPinned() {
		XCTAssertEqual(ProviderBasis.real.badge, "real")
		XCTAssertEqual(ProviderBasis.notional.badge, "notional")
		XCTAssertEqual(ProviderBasis.estimate.badge, "estimate")
		XCTAssertEqual(ProviderBasis.gateway.badge, "gateway")
		XCTAssertEqual(ProviderBasis.officialPlan.badge, "official")
	}

	/// Dashboard rows carry the raw `ProviderID` rawValue as a `String`, so the string lookup must agree
	/// with the enum lookup — including `muse_spark`, whose rawValue differs from its case name.
	/// The Advanced Analytics BASIS key derives its wording from here; pin it so a new basis cannot
	/// ship with an empty explanation.
	func testKeyMeaningIsPinnedForEveryBasis() {
		XCTAssertEqual(ProviderBasis.real.keyMeaning, "real $")
		XCTAssertEqual(ProviderBasis.notional.keyMeaning, "notional list price")
		XCTAssertEqual(ProviderBasis.estimate.keyMeaning, "estimate (tokens)")
		XCTAssertEqual(ProviderBasis.gateway.keyMeaning, "gateway · shown, not summed")
		XCTAssertEqual(ProviderBasis.officialPlan.keyMeaning, "official plan usage")
		for basis in ProviderBasis.allCases {
			XCTAssertEqual(LocalAutomationCostBasis(basis).rawValue.isEmpty, false)
		}
		XCTAssertEqual(LocalAutomationCostBasis(.notional), .notionalListPrice)
		XCTAssertEqual(LocalAutomationCostBasis(.gateway), .gateway)
		XCTAssertEqual(LocalAutomationCostBasis(.estimate), .tokenEstimate)
		XCTAssertEqual(LocalAutomationCostBasis(.real), .realSpend)
		XCTAssertEqual(LocalAutomationCostBasis(.officialPlan), .officialPlan)
	}

	func testRawIDLookupMatchesTheEnumLookup() {
		for id in ProviderID.allCases {
			XCTAssertEqual(
				ProviderBasis.of(rawID: id.rawValue), ProviderBasis.of(id),
				"raw-id lookup disagreed for \(id.rawValue)")
		}
		XCTAssertEqual(ProviderBasis.of(rawID: "muse_spark"), .notional)
		// An unrecognized id degrades exactly like the enum switch's `default` arm.
		XCTAssertEqual(ProviderBasis.of(rawID: "not-a-provider"), .real)
	}
}
