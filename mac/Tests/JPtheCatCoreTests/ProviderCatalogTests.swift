import XCTest
@testable import JPtheCatCore

final class ProviderCatalogTests: XCTestCase {
	func testMenuBarShortNamesAvoidLongMarketingNames() {
		// The rotating menu-bar pill must read "Claude"/"Codex", never "Claude Code"/"Cx".
		XCTAssertEqual(ProviderDescriptor.shortName(forName: "Claude Code"), "Claude")
		XCTAssertEqual(ProviderDescriptor.shortName(forName: "Codex"), "Codex")
		// Unknown names fall through unchanged (never crash, never invent a label).
		XCTAssertEqual(ProviderDescriptor.shortName(forName: "Totally New Agent"), "Totally New Agent")
		// The Claude descriptor carries the explicit short name; most providers default to their name.
		XCTAssertEqual(ProviderCatalog.all.first { $0.id == .claude }?.shortName, "Claude")
		XCTAssertEqual(ProviderCatalog.all.first { $0.id == .codex }?.shortName, "Codex")
	}

	func testCatalogCoversCodexBarAndLocalSources() {
		XCTAssertEqual(ProviderCatalog.all.count, 64)
		XCTAssertEqual(ProviderCatalog.all.first?.id, .claude)
		XCTAssertEqual(Set(ProviderCatalog.all.map(\.id)).count, Set(ProviderID.allCases.map(\.consolidated)).count)
		XCTAssertEqual(Set(ProviderCatalog.all.map(\.name)).count, ProviderCatalog.all.count)

		let names = Set(ProviderCatalog.all.map(\.name))
		for expected in [
			"Claude Code",
			"Codex",
			"Gemini",
			"GitHub Copilot",
			"OpenCode Zen",
			"Amp",
			"Droid (Factory)",
			"Codebuff",
			"Hermes Agent",
			"pi-agent",
			"Goose",
			"OpenClaw",
			"Qwen",
			"Qoder",
			"CodeBuddy",
			"OpenRouter",
			"LiteLLM",
			"Aider",
		] {
			XCTAssertTrue(names.contains(expected), "Missing provider \(expected)")
		}
	}

	func testLiveSupportIsExplicitAndHonest() {
		// Claude Code, Codex, Grok Build, Muse Spark, and the two OpenCode gateways (Zen + Go) are live.
		// Gemini stays roadmap (its CLI is being sunset by Google); Antigravity — Gemini CLI's successor
		// — is a local tool we can't price yet.
		XCTAssertEqual(
			ProviderCatalog.live.map(\.id),
			[.claude, .codex, .grok, .opencode, .opencodego, .museSpark])
		XCTAssertEqual(ProviderCatalog.descriptor(for: .claude)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .codex)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .grok)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .museSpark)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .opencode)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .opencodego)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .gemini)?.support, .localRoadmap)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .antigravity)?.support, .localRoadmap)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .cursor)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .openai)?.support, .apiRoadmap)
	}

	func testGeminiParserStaysAuditOnlyUntilProviderPromotion() throws {
		let thisFile = URL(fileURLWithPath: #filePath)
		let packageRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
		let cliSource = try String(
			contentsOf: packageRoot.appendingPathComponent("Sources/jpthecat-cli/main.swift"),
			encoding: .utf8)

		XCTAssertFalse(ProviderCatalog.live.map(\.id).contains(.gemini))
		XCTAssertEqual(ProviderCatalog.descriptor(for: .gemini)?.support, .localRoadmap)
		XCTAssertTrue(cliSource.contains("gemini audit-only, copilot non-aggregable"))
		XCTAssertTrue(cliSource.contains("--gemini       audit Gemini"))
	}

	/// The OpenCode gateways were deliberately promoted to tier 4: Zen (pay-as-you-go) and Go (the
	/// $10/month subscription) are both `live` and both wired into the CLI.
	func testOpenCodeGatewaysAreLiveAndWired() throws {
		let thisFile = URL(fileURLWithPath: #filePath)
		let packageRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
		let cliSource = try String(
			contentsOf: packageRoot.appendingPathComponent("Sources/jpthecat-cli/main.swift"),
			encoding: .utf8)

		XCTAssertTrue(ProviderCatalog.live.map(\.id).contains(.opencode))
		XCTAssertTrue(ProviderCatalog.live.map(\.id).contains(.opencodego))
		XCTAssertEqual(ProviderCatalog.descriptor(for: .opencode)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .opencodego)?.support, .live)
		XCTAssertEqual(ProviderCatalog.descriptor(for: .opencode)?.name, "OpenCode Zen")
		XCTAssertTrue(cliSource.contains("--opencode     read OpenCode Zen"))
		XCTAssertTrue(cliSource.contains("--opencode-go  read OpenCode Go"))
	}

	func testCopilotParserStaysAuditOnlyUntilProviderPromotion() throws {
		let thisFile = URL(fileURLWithPath: #filePath)
		let packageRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
		let cliSource = try String(
			contentsOf: packageRoot.appendingPathComponent("Sources/jpthecat-cli/main.swift"),
			encoding: .utf8)

		XCTAssertFalse(ProviderCatalog.live.map(\.id).contains(.copilot))
		XCTAssertEqual(ProviderCatalog.descriptor(for: .copilot)?.support, .localRoadmap)
		XCTAssertTrue(cliSource.contains("gemini audit-only, copilot non-aggregable"))
		XCTAssertTrue(cliSource.contains("--copilot      audit GitHub Copilot CLI"))
		XCTAssertTrue(cliSource.contains("--cursor       legacy alias for the unified Grok view"))
		XCTAssertTrue(cliSource.contains("COPILOT_OTEL_FILE_EXPORTER_PATH=<path>"))
		XCTAssertFalse(cliSource.contains("COPILOT_OTEL_ENABLED=true"))
		XCTAssertTrue(cliSource.contains("let selectedCalculator =\n\tuseCopilot"))
		XCTAssertTrue(cliSource.contains("calculator: selectedCalculator"))
		// The legacy `cost_basis` label is DERIVED from Core's one `ProviderBasis` table (through the
		// snapshot vocabulary), never a per-provider if-chain — an if-chain once omitted the OpenCode
		// model-brand rows, which then read as real spend by omission.
		XCTAssertTrue(
			cliSource.contains("LocalAutomationCostBasis(ProviderBasis.of(selectedCLIProvider.id))"))
		XCTAssertFalse(cliSource.contains("output[\"cost_basis\"] = \"token_estimate\""))
		XCTAssertEqual(LocalAutomationCostBasis(ProviderBasis.of(.copilot)), .tokenEstimate)
		XCTAssertEqual(LocalAutomationCostBasis(ProviderBasis.of(.cursor)), .notionalListPrice)
	}

	func testLegacyCLIHeadroomRoutesThroughEverySelectedProvider() throws {
		let thisFile = URL(fileURLWithPath: #filePath)
		let packageRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
		let cliSource = try String(
			contentsOf: packageRoot.appendingPathComponent("Sources/jpthecat-cli/main.swift"),
			encoding: .utf8)

		XCTAssertTrue(cliSource.contains("GrokPlanUsageStore.rateLimits(fallback: baseProvider.latestRateLimits())"))
		XCTAssertTrue(cliSource.contains("ProviderHeadroom.resolve(from: selectedLimits)"))
		XCTAssertTrue(cliSource.contains("output[\"headroom\"] = hr"))
		XCTAssertFalse(
			cliSource.contains("if useCodex, let limits = codex.latestRateLimits()"),
			"headroom must not disappear for Claude or no-signal providers")
	}

	func testUpstreamSourceCountsStayCurrent() {
		XCTAssertEqual(ProviderCatalog.withSource(.codexBar).count, 51)
		XCTAssertEqual(ProviderCatalog.withSource(.ccusage).count, 15)
		XCTAssertEqual(ProviderCatalog.withSource(.codingAgentUsageTracker).count, 15)
		XCTAssertEqual(ProviderCatalog.withSource(.openIsland).count, 9)
		XCTAssertEqual(ProviderCatalog.withSource(.jpRoadmap).count, 8)
	}
}
