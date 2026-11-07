import JPtheCatCore
import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Visual proof for the OpenCode Go gateway row: the measured usage-vs-cap bars (5-hour / weekly /
/// monthly, badged `measured`) in provider detail, and the same measured window owning a
/// quota-shaped meter in the dashboard selector — while OpenCode Zen, which publishes no usage window
/// at all, keeps its activity sparkline.
///
/// Not covered by the assertions in `DashboardStateTests`: those prove the numbers, not that the bar
/// and the badge actually draw. Run with `JP_RENDER=1 swift test --filter OpenCodeGoRenderTests`.
final class OpenCodeGoRenderTests: XCTestCase {
	@MainActor
	private func goRow() -> DashboardViewModel.ProviderRow {
		DashboardViewModel.ProviderRow(
			id: "opencodego",
			name: "OpenCode Go",
			tintHex: JPAppColor.openCodeGoTintHex,
			today: 0.38,
			week: 0.9,
			todayUsage: TokenUsage(input: 120_000, output: 20_000),
			weekUsage: TokenUsage(input: 420_000, output: 100_000),
			todayEvents: 14,
			weekEvents: 60,
			series: [0.1, 0.14, 0.12, 0.16, 0.13, 0.15, 0.1],
			notional: true,
			usedPct: 12,
			weeklyUsedPct: 5,
			usageOfficial: false,
			quotaIsMeasured: true,
			planLabel: "go",
			unpricedModels: [],
			// A classified model (High chip), an unclassified one (empty chip slot), and a free tier
			// (token amount and `free` label) share one grid so every tile state is in the render.
			byModel7d: [
				DashboardViewModel.ModelLine(
					model: "kimi-k3", cost: 0.52,
					usage: TokenUsage(input: 220_000, output: 60_000), eventCount: 22),
				DashboardViewModel.ModelLine(
					model: "deepseek-v4.1-flash", cost: 0.38,
					usage: TokenUsage(input: 200_000, output: 40_000), eventCount: 38),
				DashboardViewModel.ModelLine(
					model: "mimo-v2.5-free", cost: nil,
					usage: TokenUsage(input: 90_000, output: 10_000), eventCount: 9),
			],
			cacheSavings7d: nil,
			resetsAt5h: nil,
			resetsAtWeekly: nil,
			windowMinutes5h: 300,
			windowMinutesWeekly: 10080,
			monthlyUsedPct: 2,
			monthlyWindowMinutes: 43200,
			isAggregable: false,
			sourceScopeNote: "OpenCode Go gateway on this Mac · excluded from combined totals")
	}

	@MainActor
	private func zenRow() -> DashboardViewModel.ProviderRow {
		DashboardViewModel.ProviderRow(
			id: "opencode", name: "Zen", tintHex: JPAppColor.openCodeZenTintHex,
			today: 0, week: 0,
			todayUsage: TokenUsage(input: 600_000, output: 40_000),
			weekUsage: TokenUsage(input: 4_000_000, output: 300_000),
			todayEvents: 42, weekEvents: 280,
			series: [0, 0, 0, 0, 0, 0, 0],
			tokenSeries: [500_000, 620_000, 580_000, 700_000, 640_000, 660_000, 640_000],
			notional: true, usedPct: nil, weeklyUsedPct: nil, usageOfficial: false, planLabel: nil,
			unpricedModels: ["mimo-v2.5-free"],
			byModel7d: [
				DashboardViewModel.ModelLine(
					model: "mimo-v2.5-free", cost: nil,
					usage: TokenUsage(input: 4_000_000, output: 300_000), eventCount: 280),
			],
			cacheSavings7d: nil, resetsAt5h: nil, resetsAtWeekly: nil,
			windowMinutes5h: nil, windowMinutesWeekly: nil, isAggregable: false)
	}

	/// The one OpenCode row: Zen and Go break out as labeled sections under one scope note and one
	/// usage sentence. Run with `JP_RENDER=1 swift test --filter OpenCodeGoRenderTests`.
	@MainActor
	func testRenderUnifiedOpenCodeDetail() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNG")
		var go = goRow()
		go.name = "Go"
		let row = try XCTUnwrap(DashboardViewModel.unifiedOpenCodeRow(zen: zenRow(), go: go))
		XCTAssertEqual(row.sourceSections.map(\.name), ["Zen", "Go"])
		let content = ProviderDetail(row: row, days: 14)
			.frame(width: DashboardLayout.twoColumns.width, alignment: .topLeading)
			.background(JP.paper)
		let renderer = ImageRenderer(content: content)
		renderer.scale = 2
		guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
			let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
		else { return XCTFail("Failed to render the unified OpenCode detail") }
		let output = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/opencode-unified-detail.png")
		try png.write(to: output)
		print("Wrote unified OpenCode render to \(output.path)")
	}

	@MainActor
	func testRenderMeasuredGatewayDetailAndSelectorRows() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNG")

		let go = goRow()
		let detail = ProviderDetail(row: go, days: 14)
		let selector = VStack(spacing: 2) {
			SelectorRow(
				name: "OpenCode Go", tint: JP.hex(go.tintHex),
				vizTint: JP.providerTint(go.tintHex),
				amount: "$0.38", share: 0.12, selected: true, badge: "gateway",
				meterDescription:
					"Measured 12% of the 5-hour cap used — local usage, no provider reset reported",
				trendSeries: nil, iconName: "provider-opencodego", whiteGlyph: true) {}
			SelectorRow(
				name: "OpenCode Zen", tint: JP.hex(JPAppColor.openCodeZenTintHex),
				vizTint: JP.providerTint(JPAppColor.openCodeZenTintHex),
				amount: "4.3M tok", share: 0, selected: false, badge: "local",
				meterDescription: "Local token activity, last 14 days — quota unavailable",
				trendSeries: [500_000, 620_000, 580_000, 700_000, 640_000, 660_000, 640_000],
				iconName: "provider-opencode", whiteGlyph: true) {}
		}
		.padding(.horizontal, JPAppSpacing.selectorFooterX)
		.padding(.vertical, JPAppSpacing.footerY)

		let content = VStack(alignment: .leading, spacing: 0) {
			detail
			selector
		}
		.padding(.top, 12)
		.frame(width: DashboardLayout.twoColumns.width, alignment: .topLeading)
		.background(JP.paper)

		let renderer = ImageRenderer(content: content)
		renderer.scale = 2
		// NOTE: like `ClaudeLimitRenderTests`, this harness shows faint duplicated glyphs around the
		// view's `.fixedSize` text — `ImageRenderer` lays those out once unconstrained and again at the
		// frame width, so the first pass bleeds. It is a renderer characteristic of this view, not a
		// layout defect, and the bars/rows this capture exists to prove render exactly.
		guard let image = renderer.nsImage,
			let tiff = image.tiffRepresentation,
			let rep = NSBitmapImageRep(data: tiff),
			let png = rep.representation(using: .png, properties: [:])
		else {
			return XCTFail("Failed to render the OpenCode Go measured gateway row")
		}

		let output = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/opencode-go-measured-windows.png")
		try png.write(to: output)
		print("Wrote OpenCode Go measured-window render to \(output.path)")
	}
}
