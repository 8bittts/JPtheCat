import XCTest

@testable import JPtheCatCore

final class ModelEffortTests: XCTestCase {
	// MARK: - Classification behavior

	func testModelKeyUsesThePricingIdentityRules() {
		XCTAssertEqual(ModelIdentity.modelKey("anthropic/Claude-Opus-4-8"), "claude-opus-4-8")
		XCTAssertEqual(ModelIdentity.modelKey("claude-opus-4-8-20260115"), "claude-opus-4-8")
		XCTAssertEqual(ModelIdentity.modelKey("claude-opus-4-8[1m]"), "claude-opus-4-8")
		XCTAssertEqual(ModelIdentity.modelKey("openai/gpt-5.6-sol-2026-01-01"), "gpt-5.6-sol")
		XCTAssertEqual(ModelIdentity.modelKey("gpt-5.6-terra"), "gpt-5.6-terra")
		XCTAssertEqual(ModelIdentity.modelKey("grok-4.5-build"), "grok-4.5")
		XCTAssertEqual(ModelIdentity.modelKey("grok-4.6-build"), "grok-4.6")
		XCTAssertEqual(ModelIdentity.modelKey("grok-4.7-build"), "grok-4.7")
		XCTAssertEqual(ModelIdentity.modelKey("grok-4.7-opencode"), "grok-4.7")
		XCTAssertEqual(ModelIdentity.modelKey("gpt-reserve"), "gpt-5.6-luna")
		XCTAssertEqual(ModelIdentity.modelKey("mimo-v2.5-free"), "mimo-v2.5")
		XCTAssertEqual(ModelIdentity.modelKey("muse-spark-1.3-contributor-free"), "muse-spark-1.3-contributor")
	}

	func testLevelLookupAndUnclassifiedModels() {
		XCTAssertEqual(ModelEffort.level(for: "claude-opus-4-8"), .high)
		XCTAssertEqual(ModelEffort.level(for: "claude-haiku-4-5"), .low)
		XCTAssertEqual(ModelEffort.level(for: "gpt-5-codex"), .medium)
		XCTAssertEqual(ModelEffort.level(for: "gpt-6-astra"), .high)
		XCTAssertEqual(ModelEffort.level(for: "gpt-5.6-sol"), .high)
		XCTAssertEqual(ModelEffort.level(for: "grok-4.5-build"), .high)
		XCTAssertEqual(ModelEffort.level(for: "grok-4.6-build"), .high)
		XCTAssertEqual(ModelEffort.level(for: "grok-4.7-build"), .high)
		XCTAssertEqual(ModelEffort.level(for: "claude-opus-5-5"), .high)
		// The same model reads the same tier on every route and alias.
		XCTAssertEqual(ModelEffort.level(for: "grok-4.7-opencode"), ModelEffort.level(for: "grok-4.7"))
		XCTAssertEqual(ModelEffort.level(for: "gpt-reserve"), ModelEffort.level(for: "gpt-5.6-luna"))
		XCTAssertEqual(ModelEffort.level(for: "mimo-v2.5-free"), .low)
		// An unmapped model has NO tier — never a guessed "Medium".
		XCTAssertNil(ModelEffort.level(for: "some-unknown-model-9"))
		XCTAssertNil(ModelEffort.level(for: "deepseek-v4-flash-go-peak"))
		XCTAssertNil(ModelEffort.level(for: "auto"))
	}

	func testRawValuesAreStableStrings() {
		XCTAssertEqual(ModelEffortLevel.low.rawValue, "low")
		XCTAssertEqual(ModelEffortLevel.medium.rawValue, "medium")
		XCTAssertEqual(ModelEffortLevel.high.rawValue, "high")
		XCTAssertEqual(ModelEffortLevel.high.label, "High")
	}
}
