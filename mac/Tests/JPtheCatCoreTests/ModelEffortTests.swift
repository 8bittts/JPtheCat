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

	func testRawValuesMatchTheWebStringUnion() {
		XCTAssertEqual(ModelEffortLevel.low.rawValue, "low")
		XCTAssertEqual(ModelEffortLevel.medium.rawValue, "medium")
		XCTAssertEqual(ModelEffortLevel.high.rawValue, "high")
		XCTAssertEqual(ModelEffortLevel.high.label, "High")
	}

	// MARK: - Cross-language parity

	/// The Core `ModelEffort.levels` table and the web `MODEL_EFFORT_LEVELS` map in
	/// `web/lib/library/pricing-registry.ts` MUST stay identical — a divergence means the app and the
	/// site disagree about a model's effort tier (the exact silent drift this extraction closes).
	func testCoreTableMatchesWebRegistry() throws {
		let source = try String(contentsOf: webRegistryURL(), encoding: .utf8)
		let webMap = try parseWebEffortMap(source)

		let coreMap = ModelEffort.levels.mapValues(\.rawValue)
		let coreKeys = Set(coreMap.keys)
		let webKeys = Set(webMap.keys)

		XCTAssertEqual(
			coreKeys, webKeys,
			"Model keys diverged.\n  Core-only: \(coreKeys.subtracting(webKeys).sorted())\n  Web-only: \(webKeys.subtracting(coreKeys).sorted())")
		for key in coreKeys.intersection(webKeys) {
			XCTAssertEqual(coreMap[key], webMap[key], "Effort tier for '\(key)' differs (Core=\(coreMap[key] ?? "?"), web=\(webMap[key] ?? "?"))")
		}
		XCTAssertFalse(webMap.isEmpty, "Parsed an empty web map — the parser (or the source block) changed shape.")
	}

	// MARK: - Helpers

	private func webRegistryURL() -> URL {
		// #filePath = mac/Tests/JPtheCatCoreTests/ModelEffortTests.swift → up 3 = mac/, up 1 more = repo root.
		let macRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		return macRoot.deletingLastPathComponent()
			.appendingPathComponent("web/lib/library/pricing-registry.ts")
	}

	/// Extract the `MODEL_EFFORT_LEVELS` object literal's `"key": "value"` entries.
	private func parseWebEffortMap(_ source: String) throws -> [String: String] {
		guard let blockStart = source.range(of: "MODEL_EFFORT_LEVELS")?.upperBound,
			let braceOpen = source.range(of: "{", range: blockStart..<source.endIndex)?.upperBound,
			let braceClose = source.range(of: "};", range: braceOpen..<source.endIndex)?.lowerBound
		else {
			// A skip here would report the parity suite green precisely when the web symbol is renamed —
			// the exact drift this guard exists to catch. Fail closed instead.
			XCTFail(
				"MODEL_EFFORT_LEVELS literal not found in \(webRegistryURL().path) — the mac↔web effort-parity guard cannot run.")
			return [:]
		}
		let body = String(source[braceOpen..<braceClose])
		var map: [String: String] = [:]
		// Keys may be quoted ("glm-5.3-flash") or bare identifiers (hy3) — Biome strips quotes when valid.
		let entry = try NSRegularExpression(pattern: #"(?:"([^"]+)"|([a-zA-Z_][a-zA-Z0-9_]*))\s*:\s*"(low|medium|high)""#)
		for match in entry.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
			let key = match.range(at: 1).location != NSNotFound
				? String(body[Range(match.range(at: 1), in: body)!])
				: String(body[Range(match.range(at: 2), in: body)!])
			guard let valueRange = Range(match.range(at: 3), in: body) else { continue }
			map[key] = String(body[valueRange])
		}
		return map
	}
}
