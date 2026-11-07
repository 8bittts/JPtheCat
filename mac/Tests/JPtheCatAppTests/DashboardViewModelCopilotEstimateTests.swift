import Foundation
import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

/// Regression coverage for the menu-bar-rotation fix: a fully-unpriced Copilot window (every model
/// this window saw has no known price, so its dollar total is a dead $0.00) must still produce a
/// self-relative `estimatedSharePct` by falling back to TOKEN counts — the dollar-only formula this
/// shipped with first silently returned nil on a real machine with zero priced Copilot events.
final class DashboardViewModelCopilotEstimateTests: XCTestCase {
	private func stageCopilot(_ lines: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-estimate-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		try (lines.joined(separator: "\n") + "\n").write(
			to: root.appendingPathComponent("export.jsonl"), atomically: true, encoding: .utf8)
		return root
	}

	private func chatLine(
		session: String, endTime: Date, inputTokens: Int, outputTokens: Int, aiuNano: Int = 0
	) -> String {
		var attrs: [String: Any] = [
			"gen_ai.operation.name": "chat",
			// A model id guaranteed absent from the bundled pricing table, so its cost stays unpriced —
			// the exact condition (`isFullyUnpriced`) the token fallback must trigger on.
			"gen_ai.request.model": "gpt-definitely-unpriced-test-model",
			"session.id": session,
			"gen_ai.usage.input_tokens": inputTokens,
			"gen_ai.usage.output_tokens": outputTokens,
		]
		if aiuNano > 0 { attrs["github.copilot.nano_aiu"] = aiuNano }
		// `endTime` must always be present — the parser only recognizes a record as valid (vs. an
		// unrelated log line) when it carries endTime/duration/kind; omitting it drops the event.
		let record: [String: Any] = [
			"name": "chat", "attributes": attrs, "endTime": [Int(endTime.timeIntervalSince1970), 0],
		]
		let data = try! JSONSerialization.data(withJSONObject: record)
		return String(decoding: data, as: UTF8.self)
	}

	func testFullyUnpricedCopilotWindowFallsBackToATokenBasedEstimate() throws {
		let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
		let root = try stageCopilot([
			// Today: 300 tokens. Earlier this week: 700 tokens. Both unpriced → dollar total is $0.00,
			// so only the token-based fallback can produce a non-nil estimate.
			chatLine(session: "today", endTime: Date(), inputTokens: 250, outputTokens: 50),
			chatLine(session: "earlier", endTime: threeDaysAgo, inputTokens: 600, outputTokens: 100),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let build = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
			copilot: CopilotProvider(root: root), museSpark: MuseSparkProvider(),
			index: nil, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
			copilotEnabled: true, museSparkEnabled: false,
			previousRows: [], hadPreviousRefresh: false)

		guard let copilotRow = build.rows.first(where: { $0.id == "copilot" }) else {
			return XCTFail("expected a Copilot row")
		}
		XCTAssertEqual(copilotRow.today, 0)
		XCTAssertEqual(copilotRow.week, 0)
		XCTAssertTrue(copilotRow.isFullyUnpriced)
		XCTAssertNil(copilotRow.usedPct, "Copilot exposes no trustworthy official 5-hour quota")
		XCTAssertNil(copilotRow.weeklyUsedPct, "Copilot exposes no trustworthy official weekly quota")
		XCTAssertFalse(copilotRow.usageOfficial)
		// 300 tokens today / 1000 tokens over the week = 30%, never nil.
		XCTAssertEqual(copilotRow.estimatedSharePct ?? -1, 30, accuracy: 0.5)
		// No AIU attribute on these events → no AIU signal → nil (never a fabricated 0).
		XCTAssertNil(copilotRow.aiuWindow)
	}

	func testCopilotRowCarriesWindowedAIUConsumptionWhenPresent() throws {
		let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
		let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
		let root = try stageCopilot([
			chatLine(session: "today", endTime: Date(), inputTokens: 250, outputTokens: 50, aiuNano: 250_000_000),
			chatLine(session: "earlier", endTime: threeDaysAgo, inputTokens: 600, outputTokens: 100, aiuNano: 500_000_000),
			// 10 days old → outside a 7-day window, excluded from the sum.
			chatLine(session: "old", endTime: tenDaysAgo, inputTokens: 100, outputTokens: 10, aiuNano: 900_000_000),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let build = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 7,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
			copilot: CopilotProvider(root: root), museSpark: MuseSparkProvider(),
			index: nil, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
			copilotEnabled: true, museSparkEnabled: false,
			previousRows: [], hadPreviousRefresh: false)

		guard let copilotRow = build.rows.first(where: { $0.id == "copilot" }) else {
			return XCTFail("expected a Copilot row")
		}
		// (250M + 500M) nano = 0.75 AIU over the 7-day window; the 10-day-old 0.9 AIU sample is excluded.
		XCTAssertEqual(try XCTUnwrap(copilotRow.aiuWindow), 0.75, accuracy: 1e-9)
	}
}
