import XCTest

@testable import JPtheCatCore

final class ProviderDashboardOrderTests: XCTestCase {
	private func ordered(_ ids: [String]) -> [String] {
		let names = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
		return ids.sorted { lhs, rhs in
			ProviderDashboardOrder.sortsBefore(lhs, rhs, rowIDs: ids) { names[$0] ?? $0 }
		}
	}

	func testGrokBotSortsImmediatelyAfterGrokWhenBothPresent() {
		let shuffled = ["copilot", "grok_bot", "muse_spark", "grok", "claude", "codex"]
		XCTAssertEqual(
			ordered(shuffled),
			["claude", "codex", "grok", "grok_bot", "muse_spark", "copilot"])
	}

	func testGrokBotKeepsNormalPositionWhenGrokAbsent() {
		let shuffled = ["cursor", "grok_bot", "opencode", "claude"]
		XCTAssertEqual(ordered(shuffled), ["claude", "cursor", "grok_bot", "opencode"])
	}

	func testOtherProvidersKeepRelativeOrderWhenGrokPairPresent() {
		let shuffled = ["deepseek", "nemotron", "grok", "grok_bot", "mimo", "big_pickle"]
		XCTAssertEqual(
			ordered(shuffled),
			["grok", "grok_bot", "nemotron", "mimo", "big_pickle", "deepseek"])
	}
}
