import XCTest

@testable import JPtheCatCore

final class ModelNameTests: XCTestCase {
	func testDropsSnapshotDatesVendorPrefixesAndRedundantFamilyTokens() {
		XCTAssertEqual(ModelName.short("claude-opus-4-5-20251101"), "opus-4-5")
		// A vendor prefix never changes the label: `anthropic/claude-x` reads like `claude-x`.
		XCTAssertEqual(ModelName.short("anthropic/claude-sonnet-4-5"), "sonnet-4-5")
		XCTAssertEqual(ModelName.short("openai/gpt-5.6-sol"), "5.6-sol")
		XCTAssertEqual(ModelName.short("openai/gpt-6-astra"), "6-astra")
		// The redundant `codex` token is dropped under the Codex family (gpt- already signals it).
		XCTAssertEqual(ModelName.short("openai/gpt-5.3-codex-spark"), "5.3-spark")
		XCTAssertEqual(ModelName.short("gpt-5.3-codex"), "5.3")
		XCTAssertEqual(ModelName.short("gpt-5.1-codex-max"), "5.1-max")
		XCTAssertEqual(ModelName.short("gpt-5-codex"), "5")
		// Both snapshot-date spellings and Claude Code's `[1m]` selector are decorators.
		XCTAssertEqual(ModelName.short("gpt-5.2-2025-12-11"), "5.2")
		XCTAssertEqual(ModelName.short("claude-opus-4-8[1m]"), "opus-4-8")
	}

	func testDropsOnlyADateShapedTail() {
		XCTAssertEqual(ModelName.short("gpt-5-20250131"), "5")
		XCTAssertEqual(ModelName.short("gpt-5.6-sol"), "5.6-sol")
		XCTAssertEqual(ModelName.short("grok-4.5"), "4.5")
		XCTAssertEqual(ModelName.short("grok-4.5-build"), "4.5")
		XCTAssertEqual(ModelName.short("grok-4.6"), "4.6")
		XCTAssertEqual(ModelName.short("grok-4.6-build"), "4.6")
		XCTAssertEqual(ModelName.short("model-1234567"), "model-1234567")  // 7 digits, not stripped
	}

	func testLeavesAlreadyShortNamesUnchanged() {
		XCTAssertEqual(ModelName.short("opus-4-5"), "opus-4-5")
		XCTAssertEqual(ModelName.short("gemini-2.5-flash"), "gemini-2.5-flash")
		XCTAssertEqual(ModelName.short(""), "")
	}

	/// OpenCode brand models keep their vendor name, and a free tier stays visibly free so an unpriced
	/// tile never reads as the paid model.
	func testOpenCodeModelsKeepVendorNameAndFreeMarker() {
		XCTAssertEqual(ModelName.short("nemotron-3-ultra-free"), "nemotron-3-ultra free")
		XCTAssertEqual(ModelName.short("mimo-v2.5-free"), "mimo-v2.5 free")
		XCTAssertEqual(ModelName.short("mimo-v2.5"), "mimo-v2.5")
		XCTAssertEqual(ModelName.short("deepseek-v4-flash-free"), "deepseek-v4-flash free")
		XCTAssertEqual(ModelName.short("deepseek-v4-flash"), "deepseek-v4-flash")
		XCTAssertEqual(ModelName.short("big-pickle"), "big-pickle")
	}

	/// Gateway accounting ids are parser-made rate selectors, not model names.
	func testGatewayAccountingSuffixesNeverReachTheLabel() {
		XCTAssertEqual(ModelName.short("deepseek-v4-flash-go-peak"), "deepseek-v4-flash")
		XCTAssertEqual(ModelName.short("deepseek-v4.1-flash-peak"), "deepseek-v4.1-flash")
		XCTAssertEqual(ModelName.short("grok-4.7-opencode"), "4.7")
		XCTAssertEqual(ModelName.short("gpt-5.1-codex-zen"), "5.1")
	}

	func testIsContentPreservingCaseExceptTheStrippedParts() {
		// Only the vendor prefix / trailing date are removed — the rest keeps its case.
		XCTAssertEqual(ModelName.short("claude-Opus-Preview-20251101"), "Opus-Preview")
	}

	func testCompactDisplayOrdersCodexCapabilityInsideNewestVersion() {
		let models = ["gpt-5.6-terra", "gpt-5.5", "gpt-5.6-luna", "gpt-5.6"]

		XCTAssertEqual(models.sorted(by: ModelName.sortsBeforeForCompactDisplay), [
			"gpt-5.6", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
		])
	}

	func testCompactDisplayCapabilityBeatsSnapshotDateInsideSameVersion() {
		let models = [
			"openai/gpt-5.6-luna-20260713",
			"openai/gpt-5.6-sol-2026-07-01",
			"openai/gpt-5.6-terra-2026-07-12",
		]

		XCTAssertEqual(models.sorted(by: ModelName.sortsBeforeForCompactDisplay), [
			"openai/gpt-5.6-sol-2026-07-01",
			"openai/gpt-5.6-terra-2026-07-12",
			"openai/gpt-5.6-luna-20260713",
		])
	}

	/// GPT-6 adds Astra above Sol, and Claude's Fable tier sits above Opus inside one version.
	func testCompactDisplayRanksNewerCelestialAndClaudeTiers() {
		XCTAssertEqual(
			["gpt-6-sol", "gpt-6.1-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol"].sorted(by: ModelName.sortsBeforeForCompactDisplay),
			["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol"])
		XCTAssertEqual(
			["claude-opus-5", "claude-sonnet-5-5", "claude-sonnet-5", "claude-fable-5"].sorted(by: ModelName.sortsBeforeForCompactDisplay),
			["claude-sonnet-5-5", "claude-fable-5", "claude-opus-5", "claude-sonnet-5"])
	}

	/// Ordering reads ids through `ModelIdentity`, so a `[1m]` selector, nested vendor prefix, or gateway
	/// route never adds a fake version component that outranks a stronger model.
	func testCompactDisplayOrdersDecoratedIDsLikeTheirPresentationID() {
		XCTAssertEqual(
			["claude-sonnet-4-5[1m]", "anthropic/claude-opus-4-5-20251101"].sorted(by: ModelName.sortsBeforeForCompactDisplay),
			["anthropic/claude-opus-4-5-20251101", "claude-sonnet-4-5[1m]"])
		XCTAssertEqual(
			["openrouter/openai/gpt-5.6-luna", "gpt-5.6-sol-zen"].sorted(by: ModelName.sortsBeforeForCompactDisplay),
			["gpt-5.6-sol-zen", "openrouter/openai/gpt-5.6-luna"])
	}

	func testCompactDisplayDoesNotApplyCodexTierWordsToUnrelatedModels() {
		let models = ["example-2.0-luna", "example-2.0-sol"]

		XCTAssertEqual(models.sorted(by: ModelName.sortsBeforeForCompactDisplay), [
			"example-2.0-sol", "example-2.0-luna",
		])
	}

	func testCompactDisplayUsesKnownCapabilityFamiliesWithoutRankingUnknownNames() {
		XCTAssertEqual([
			"claude-haiku-4-5", "claude-opus-4-5", "claude-sonnet-4-5",
		].sorted(by: ModelName.sortsBeforeForCompactDisplay), [
			"claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5",
		])
		XCTAssertEqual([
			"gemini-2.5-flash-lite", "gemini-2.5-pro", "gemini-2.5-flash",
		].sorted(by: ModelName.sortsBeforeForCompactDisplay), [
			"gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite",
		])
	}
}
