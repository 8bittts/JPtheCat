import Foundation
import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

/// Every provider the Advanced Analytics sidebar lets you CHECK must also appear in the daily-trend small
/// multiples. Cursor shipped checkable-but-trendless because the trend order list was a hand-maintained
/// literal that nobody updated when the provider was added.
// [NOTE] The Advanced Analytics view types these read are `@MainActor`-isolated, so the suite is
// too — a nonisolated read is only a warning today and a hard error under a stricter mode.
@MainActor
final class AnalyticsProviderCoverageTests: XCTestCase {
	func testAllIndexedProvidersReachAnalyticsRowsAndRhythm() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		let ids = AdvancedAnalyticsTrayView.providerOptions.map(\.id).filter { $0 != .copilot }
		let events = ids.map { id in
			UsageEvent(messageId: id.rawValue, requestId: "fixture", provider: id, model: "mimo-v2.5",
				timestamp: Date().addingTimeInterval(-60), usage: TokenUsage(input: 100, output: 20), project: nil)
		}
		try index.ingest(events, sourcePath: "fixture")
		let result = AdvancedAnalyticsTrayView.loadData(index: index, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()), copilot: CopilotProvider(root: root))
		XCTAssertEqual(Set(result.rows.map(\.provider)), Set(ids))
		for id in ids { XCTAssertNotNil(result.rhythm[id], id.rawValue) }
	}

	func testEveryCheckableProviderHasATrendSlot() {
		let checkable = Set(AdvancedAnalyticsTrayView.providerOptions.map(\.id))
		let trended = Set(AdvancedAnalyticsTrayView.trendProviderOrder)
		XCTAssertEqual(checkable, trended, "sidebar checkboxes and daily-trend small multiples must match")
	}

	func testTrendColumnsAndNamesStayReadable() {
		XCTAssertEqual(AdvancedAnalyticsTrayView.trendMaxColumns, 4)
		XCTAssertEqual(AdvancedAnalyticsTrayView.visibleModelRowLimit(providerCount: 1), 7)
		XCTAssertEqual(AdvancedAnalyticsTrayView.visibleModelRowLimit(providerCount: 5), 5)
		XCTAssertEqual(AdvancedAnalyticsTrayView.visibleModelRowLimit(providerCount: 10), 3)
		for option in AdvancedAnalyticsTrayView.providerOptions {
			XCTAssertEqual(analyticsShortProviderName(option.id), ProviderCatalog.descriptor(for: option.id)?.shortName)
		}
	}

	func testTrendOrderHasNoDuplicates() {
		let order = AdvancedAnalyticsTrayView.trendProviderOrder
		XCTAssertEqual(order.count, Set(order).count)
	}

	/// The window is fixed-height with no internal scroll, so the model table must stay bounded — an
	/// uncapped table pushed the sidebar's Export button off the bottom edge.
	func testModelTableRowCapStaysBounded() {
		XCTAssertLessThanOrEqual(AdvancedAnalyticsTrayView.modelTableMaxRows, 8)
		XCTAssertGreaterThan(AdvancedAnalyticsTrayView.modelTableMaxRows, 0)
	}
}
