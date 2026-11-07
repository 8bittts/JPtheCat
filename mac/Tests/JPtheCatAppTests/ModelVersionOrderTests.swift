import JPtheCatCore
import XCTest
@testable import JPtheCatApp

final class ModelVersionOrderTests: XCTestCase {
	func testModelBreakdownOrdersNewestVersionFirstRegardlessOfCost() {
		func line(_ model: String, cost: Double?) -> DashboardViewModel.ModelLine {
			DashboardViewModel.ModelLine(
				model: model,
				cost: cost,
				usage: TokenUsage(input: 1, output: 1),
				eventCount: 1)
		}

		let ordered = DashboardViewModel.orderedModelLines([
			line("gpt-5.5", cost: 100),
			line("gpt-5.3-codex-spark", cost: 50),
			line("gpt-5.4", cost: 25),
			line("gpt-5.6-sol", cost: 1),
		])

		XCTAssertEqual(ordered.map(\.model), [
			"gpt-5.6-sol",
			"gpt-5.5",
			"gpt-5.4",
			"gpt-5.3-codex-spark",
		])
	}

	func testModelBreakdownUsesNewestDatedVariantFirst() {
		let older = DashboardViewModel.ModelLine(
			model: "claude-opus-4-8-20260601", cost: 2,
			usage: TokenUsage(), eventCount: 1)
		let newer = DashboardViewModel.ModelLine(
			model: "claude-opus-4-8-20260701", cost: 1,
			usage: TokenUsage(), eventCount: 1)

		XCTAssertEqual(
			DashboardViewModel.orderedModelLines([older, newer]).map(\.model),
			["claude-opus-4-8-20260701", "claude-opus-4-8-20260601"])
	}

	func testModelBreakdownOrdersCodexCapabilityWithinVersion() {
		func line(_ model: String) -> DashboardViewModel.ModelLine {
			DashboardViewModel.ModelLine(
				model: model, cost: 1, usage: TokenUsage(input: 1, output: 1), eventCount: 1)
		}

		XCTAssertEqual(
			DashboardViewModel.orderedModelLines([
				line("gpt-5.6-terra"), line("gpt-5.6-luna"), line("gpt-5.6-sol"), line("gpt-5.5"),
			]).map(\.model),
			["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"])
	}

	func testModelBreakdownKeepsCodexSparkAfterCodexFamilyTiers() {
		func line(_ model: String) -> DashboardViewModel.ModelLine {
			DashboardViewModel.ModelLine(
				model: model, cost: 1, usage: TokenUsage(input: 1, output: 1), eventCount: 1)
		}

		let ordered = DashboardViewModel.orderedModelLines([
			line("gpt-5.6-luna"),
			line("gpt-5.6-terra"),
			line("gpt-5.6-sol"),
			line("gpt-5.3-codex-spark"),
			line("gpt-5.5"),
		])

		XCTAssertEqual(
			ordered.map(\.model),
			["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.3-codex-spark"])
	}
}
