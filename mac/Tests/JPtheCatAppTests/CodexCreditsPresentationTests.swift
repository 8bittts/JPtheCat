import AppKit
import JPtheCatCore
import SwiftUI
import XCTest

@testable import JPtheCatApp

final class CodexCreditsPresentationTests: XCTestCase {
	private func buildRow() throws -> DashboardViewModel.ProviderRow {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("jp-credit-ui-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("rollout-2026-10-02T00-00-00-feedface-0000-0000-0000-000000000088.jsonl")
		let record = #"{"timestamp":"2026-10-02T12:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"pro","primary":{"used_percent":100,"window_minutes":10080,"resets_at":4102444800},"secondary":null,"credits":{"has_credits":true,"unlimited":false,"balance":"12345.6789000000"}}}}"#
		try (record + "\n").write(to: file, atomically: true, encoding: .utf8)
		let build = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14, calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(), codex: CodexProvider(root: root), grok: GrokProvider(),
			copilot: CopilotProvider(), museSpark: MuseSparkProvider(), index: nil,
			claudeEnabled: false, codexEnabled: true, grokEnabled: false,
			copilotEnabled: false, cursorEnabled: false, museSparkEnabled: false,
			enabledBrands: [], openCodeZenEnabled: false, openCodeGoEnabled: false,
			previousRows: [], hadPreviousRefresh: false)
		return try XCTUnwrap(build.rows.first { $0.id == "codex" })
	}

	@MainActor
	func testLiveShapedLogReachesDashboardAndLocalSnapshotWithoutChangingMoneyOrQuota() throws {
		let row = try buildRow()
		XCTAssertEqual(row.codexCredits?.displayValue, "12,345.67")
		XCTAssertEqual(row.weeklyUsedPct, 100)
		XCTAssertNil(row.usedPct)
		XCTAssertEqual(row.today, 0)
		XCTAssertEqual(row.week, 0)
		XCTAssertTrue(row.usageOfficial)
		let state = DashboardState(rows: [row], aggregateSeries: [], aggregateToday: 0,
			aggregateWeek: 0, aggregateCostProvenance: .notionalListPrice,
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 1_791_000_000)), selectedDays: 14)
		let snapshot = DashboardWidgetPublisher.makeAutomationSnapshot(from: state,
			now: Date(timeIntervalSince1970: 1_791_000_000))
		XCTAssertEqual(snapshot.rateLimits["codex"]?.credits, row.codexCredits)
		XCTAssertEqual(snapshot.rateLimits["codex"]?.capturedAt, row.creditsCapturedAt)
		XCTAssertEqual(snapshot.providers.first?.headroom.state, "official")
		XCTAssertEqual(snapshot.providers.first?.headroom.remainingPercent, 0)
		let expired = DashboardWidgetPublisher.makeAutomationSnapshot(from: state,
			now: Date(timeIntervalSince1970: 4_102_444_801))
		XCTAssertEqual(expired.providers.first?.headroom.state, "unknown")
		XCTAssertEqual(expired.rateLimits["codex"]?.credits, row.codexCredits)
		XCTAssertEqual(snapshot.totalToday, 0)
		XCTAssertEqual(snapshot.totalWindow, 0)
		let markdown = snapshot.markdownReport()
		XCTAssertTrue(markdown.contains("credits remaining (last reported): 12,345.67"))
		XCTAssertTrue(markdown.contains("weekly used 100% official"))
	}

	@MainActor
	func testCreditDetailFitsBothLayoutsAndThemes() throws {
		let row = try buildRow()
		let previous = JPTheme.current
		defer { JPTheme.current = previous }
		for theme in [JPTheme.sunlit, .midnight] {
			JPTheme.current = theme
			for layout in [DashboardLayout.oneColumn, .twoColumns] {
				let content = ProviderDetail(row: row, days: 14)
					.environment(\.dashboardLayout, layout)
					.environment(\.jpMotionPaused, true)
					.frame(width: layout.width)
					.background(JP.paper)
				let host = NSHostingController(rootView: content)
				host.view.layoutSubtreeIfNeeded()
				XCTAssertEqual(host.view.fittingSize.width, layout.width, accuracy: 1)
				XCTAssertGreaterThan(host.view.fittingSize.height, 0)
				guard ProcessInfo.processInfo.environment["JP_RENDER"] != nil else { continue }
				let renderer = ImageRenderer(content: content)
				renderer.scale = 2
				let image = try XCTUnwrap(renderer.nsImage)
				let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
				let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
				let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
					.deletingLastPathComponent().deletingLastPathComponent()
					.appendingPathComponent(".build/codex-credits-\(theme.id)-\(Int(layout.width)).png")
				try png.write(to: path)
				print("CREDIT_RENDER \(path.path) size=\(host.view.fittingSize)")
			}
		}
	}
}
