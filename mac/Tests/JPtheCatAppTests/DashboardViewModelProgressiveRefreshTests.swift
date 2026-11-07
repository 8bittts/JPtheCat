import Foundation
import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

/// Cold-launch profile (2026-09-02, live 934k-event DB): Claude skip-path reindex was 392 ms;
/// Codex `latestRateLimitState` on an empty process cache ran for minutes over ~2,200 rollout files
/// on the same `buildRefreshResult`. `onPartial` must fire with a Codex dollar row before that walk.
final class DashboardViewModelProgressiveRefreshTests: XCTestCase {
	func testPartialPublishIncludesCodexRowBeforeRateLimitWalk() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-progressive-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		final class PartialBox: @unchecked Sendable {
			private let lock = NSLock()
			private var values: [DashboardViewModel.RefreshBuild] = []
			func append(_ value: DashboardViewModel.RefreshBuild) {
				lock.lock()
				values.append(value)
				lock.unlock()
			}
			func snapshot() -> [DashboardViewModel.RefreshBuild] {
				lock.lock()
				defer { lock.unlock() }
				return values
			}
		}
		let box = PartialBox()
		let build = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(),
			codex: CodexProvider(root: root),
			grok: GrokProvider(),
			copilot: CopilotProvider(),
			museSpark: MuseSparkProvider(),
			index: nil, claudeEnabled: false, codexEnabled: true, grokEnabled: false,
			copilotEnabled: false, museSparkEnabled: false,
			previousRows: [], hadPreviousRefresh: false,
			onPartial: { partial in
				box.append(partial)
			})

		let captured = box.snapshot()
		XCTAssertEqual(captured.count, 1, "onPartial must fire exactly once, before the Codex walk returns")
		XCTAssertTrue(
			captured[0].rows.contains { $0.id == "codex" },
			"partial build must already include the Codex dollar row so first paint is not blocked")
		XCTAssertTrue(build.rows.contains { $0.id == "codex" })
		XCTAssertNil(captured[0].rows.first { $0.id == "codex" }?.usedPct)
		XCTAssertNil(build.rows.first { $0.id == "codex" }?.usedPct)
	}

	func testOmittingOnPartialStillReturnsASingleBuild() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-progressive-nil-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let build = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(),
			codex: CodexProvider(root: root),
			grok: GrokProvider(),
			copilot: CopilotProvider(),
			museSpark: MuseSparkProvider(),
			index: nil, claudeEnabled: false, codexEnabled: true, grokEnabled: false,
			copilotEnabled: false, museSparkEnabled: false,
			previousRows: [], hadPreviousRefresh: false)

		XCTAssertTrue(build.rows.contains { $0.id == "codex" })
	}

	func testWarmRefreshDoesNotPublishAPartialThatBlanksTheCodexGauge() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-progressive-warm-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		final class PartialBox: @unchecked Sendable {
			private let lock = NSLock()
			private var count = 0
			func append() {
				lock.lock()
				count += 1
				lock.unlock()
			}
			func snapshot() -> Int {
				lock.lock()
				defer { lock.unlock() }
				return count
			}
		}
		let box = PartialBox()
		for creditOnly in [false, true] {
			let previous = DashboardViewModel.ProviderRow(
				id: "codex", name: "Codex", tintHex: "#000000",
				today: 1, week: 10,
				todayUsage: TokenUsage(input: 1, output: 1),
				weekUsage: TokenUsage(input: 2, output: 2),
				todayEvents: 1, weekEvents: 2, series: [1, 9],
				notional: true, usedPct: creditOnly ? nil : 42, weeklyUsedPct: creditOnly ? nil : 18, usageOfficial: true,
				planLabel: nil, unpricedModels: [], byModel7d: [], cacheSavings7d: nil,
				resetsAt5h: nil, resetsAtWeekly: nil,
				windowMinutes5h: 300, windowMinutesWeekly: 10_080,
				codexCredits: creditOnly ? CodexCreditBalance(hasCredits: true, balance: 12) : nil)
			_ = DashboardViewModel.buildRefreshResult(
				reindex: false, days: 14,
				calculator: CostCalculator(pricing: .bundledDefault()),
				claude: ClaudeProvider(),
				codex: CodexProvider(root: root),
				grok: GrokProvider(),
				copilot: CopilotProvider(),
				museSpark: MuseSparkProvider(),
				index: nil, claudeEnabled: false, codexEnabled: true, grokEnabled: false,
				copilotEnabled: false, museSparkEnabled: false,
				previousRows: [previous], hadPreviousRefresh: true,
				onPartial: { _ in box.append() })
		}
		XCTAssertEqual(
			box.snapshot(), 0,
			"a warm refresh with official windows or credit-only data must not publish a snapshot-nil partial")
	}
}
