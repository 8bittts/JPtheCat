import AppKit
import SwiftUI
import XCTest
import JPtheCatCore
@testable import JPtheCatApp

final class DashboardLayoutRenderTests: XCTestCase {
    private let names = ["Claude Code", "Codex", "Grok", "Muse Spark", "Nemotron", "MiMo", "Big Pickle", "DeepSeek", "Copilot", "Cursor", "OpenCode Zen", "OpenCode Go"]

    @MainActor private func sample(count: Int, columns: Int, days: Int) -> some View {
        DashboardSelectorLayout(columnCount: columns) {
            SelectorRow(name: "All providers", tint: JP.ginger, vizTint: JP.ginger,
                amount: "$99,999.99", share: 1, selected: true, badge: nil,
                meterDescription: "Activity pulse", iconName: "jp-menubar",
                whiteGlyph: false, iconMetrics: .allProviders, pulsing: true) {}
        } providers: {
            ForEach(Array(self.names.prefix(count).enumerated()), id: \.offset) { index, name in
                SelectorRow(name: name, tint: JP.ginger, vizTint: JP.ginger,
                    amount: index > 7 ? "999.9M tok" : "$99,999.99", share: 0.95,
                    selected: false, badge: index > 7 ? "local" : "notional",
                    meterDescription: "Fixture activity",
                    trendSeries: index % 2 == 0 ? (0..<days).map { Double($0 % 7) } : nil) {}
            }
        }
        .padding(.horizontal, JPAppSpacing.selectorFooterX)
        .padding(.vertical, JPAppSpacing.footerY)
        .background(JP.card)
        .environment(\.jpMotionPaused, true)
    }

    @MainActor func testTwoColumnsKeepEveryCountIntrinsicAndReduceFullCatalogHeight() throws {
        for count in [0, 1, 3, 12] {
            let compact = NSHostingController(rootView: sample(count: count, columns: 1, days: 14).frame(width: 384))
            let wide = NSHostingController(rootView: sample(count: count, columns: 2, days: 14).frame(width: 768))
            compact.view.layoutSubtreeIfNeeded()
            wide.view.layoutSubtreeIfNeeded()
            let before = compact.view.fittingSize
            let after = wide.view.fittingSize
            XCTAssertEqual(after.width, 768, accuracy: 1)
            XCTAssertGreaterThan(after.height, 0)
            XCTAssertLessThanOrEqual(after.height, before.height + 1)
            if count == 12 { XCTAssertLessThan(after.height, before.height * 0.65) }
            print("SELECTOR count=\(count) compact=\(before) wide=\(after)")
        }
    }

	@MainActor
	private func stressRow(short: Double? = 12, weekly: Double? = 5, monthly: Double? = 2) -> DashboardViewModel.ProviderRow {
		DashboardViewModel.ProviderRow(
			id: "opencodego",
			name: "OpenCode Go",
			tintHex: JPAppColor.openCodeGoTintHex,
			today: 99999.99,
			week: 999999.99,
			todayUsage: TokenUsage(input: 120_000, output: 20_000),
			weekUsage: TokenUsage(input: 420_000, output: 100_000),
			todayEvents: 14,
			weekEvents: 60,
			series: [0.1, 0.14, 0.12, 0.16, 0.13, 0.15, 0.1],
			notional: true,
			usedPct: short,
			weeklyUsedPct: weekly,
			usageOfficial: false,
			quotaIsMeasured: true,
			planLabel: "go",
			unpricedModels: ["future-model-with-a-long-unknown-deployment-name", "second-unknown-model"],
			byModel7d: (0..<5).map { index in
				DashboardViewModel.ModelLine(
					model: index == 0 ? "deepseek-v4.1-flash-long-deployment-name" : "sample-model-\(index)",
					cost: index == 2 ? nil : Double(index + 1) * 9999.99,
					usage: TokenUsage(input: (5 - index) * 120_000, output: 100_000), eventCount: 60)
			},
			cacheSavings7d: nil,
			resetsAt5h: nil,
			resetsAtWeekly: nil,
			windowMinutes5h: 300,
			windowMinutesWeekly: 10080,
			monthlyUsedPct: monthly,
			monthlyWindowMinutes: 43200,
			isAggregable: false,
			sourceScopeNote: "OpenCode Go gateway on this Mac · excluded from combined totals")
	}

    @MainActor func testLongDetailDisclosureWrapsWithinTheAcceptedCard() throws {
        let row = stressRow()
        var heights: [DashboardLayout: CGFloat] = [:]
        for layout in DashboardLayout.allCases {
            let view = ProviderDetail(row: row, days: 90)
                .frame(width: layout.width)
                .environment(\.dashboardLayout, layout)
            let host = NSHostingController(rootView: view)
            host.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.view.fittingSize.width, layout.width, accuracy: 1)
            XCTAssertGreaterThan(host.view.fittingSize.height, 0)
            heights[layout] = host.view.fittingSize.height
            guard ProcessInfo.processInfo.environment["JP_RENDER"] != nil else { continue }
            let previous = JPTheme.current
            defer { JPTheme.current = previous }
            for theme in [JPTheme.sunlit, .midnight] {
                JPTheme.current = theme
                let renderer = ImageRenderer(content: view.background(JP.card))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                let path = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("jp-detail-stress-\(layout.rawValue)-\(theme.id).png")
                try png.write(to: path)
                print("DETAIL RENDER \(path.path) size=\(image.size)")
            }
        }
        // One column stacks the same gauges and models, so the detail grows taller, never shorter.
        XCTAssertGreaterThan(heights[.oneColumn] ?? 0, heights[.twoColumns] ?? 0)
    }

    @MainActor func testRenderSinglePairedAndMonthlyWindows() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JP_RENDER"] != nil, "Set JP_RENDER=1")
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("jp-window-layout")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previous = JPTheme.current
        defer { JPTheme.current = previous }
        let cases: [(String, Double?, Double?, Double?)] = [
            ("none", nil, nil, nil), ("short", 67, nil, nil),
            ("weekly", nil, 68, nil), ("pair", 67, 62, nil),
            ("monthly", nil, nil, 31), ("monthly-weekly", nil, 62, 31),
            ("three", 67, 62, 31),
        ]
        for theme in [JPTheme.sunlit, .midnight] {
            JPTheme.current = theme
            for layout in DashboardLayout.allCases {
                for (name, short, weekly, monthly) in cases {
                    let view = ProviderDetail(row: stressRow(short: short, weekly: weekly, monthly: monthly), days: 14)
                        .frame(width: layout.width).background(JP.card)
                        .environment(\.dashboardLayout, layout)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, layout.width, accuracy: 1)
                    let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    let path = dir.appendingPathComponent("\(theme.id)-\(layout.rawValue)-\(name).png")
                    try png.write(to: path)
                    print("WINDOW RENDER \(path.path) size=\(image.size)")
                }
            }
        }
    }

    @MainActor func testRenderBaselineAndWideAcrossThemesAndTimeframes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JP_RENDER"] != nil, "Set JP_RENDER=1")
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("jp-wide-renders")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previous = JPTheme.current
        defer { JPTheme.current = previous }
        for theme in JPTheme.all.prefix(2) {
            JPTheme.current = theme
            for days in [7, 14, 30, 90] {
                for (width, columns) in [(384, 1), (768, 2)] {
                    let content = sample(count: 12, columns: columns, days: days).frame(width: CGFloat(width))
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    let tiff = try XCTUnwrap(image.tiffRepresentation)
                    let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
                    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    try png.write(to: dir.appendingPathComponent("\(theme.id)-\(days)-\(width).png"))
                    print("RENDER theme=\(theme.id) days=\(days) width=\(width) height=\(image.size.height)")
                }
            }
        }
        print("RENDERS \(dir.path)")
    }
}
