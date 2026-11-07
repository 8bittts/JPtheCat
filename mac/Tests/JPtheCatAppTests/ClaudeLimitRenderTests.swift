import JPtheCatCore
import SwiftUI
import XCTest

@testable import JPtheCatApp

final class ClaudeLimitRenderTests: XCTestCase {
	@MainActor
	func testRenderFrozenClaudeLimitAsEstimatedFull() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNG")

		var row = DashboardViewModel.ProviderRow(
			id: "claude",
			name: "Claude Code",
			tintHex: JPAppColor.claudeTintHex,
			today: 205.38,
			week: 205.38,
			todayUsage: TokenUsage(input: 1, output: 1),
			weekUsage: TokenUsage(input: 2, output: 2),
			todayEvents: 1,
			weekEvents: 2,
			series: [150, 205.38],
			notional: false,
			usedPct: 86,
			weeklyUsedPct: 9,
			usageOfficial: true,
			planLabel: "Max 5x",
			unpricedModels: [],
			byModel7d: [],
			cacheSavings7d: nil,
			resetsAt5h: Date().addingTimeInterval(4 * 3600),
			resetsAtWeekly: Date().addingTimeInterval(3 * 24 * 3600),
			windowMinutes5h: 300,
			windowMinutesWeekly: 10080)
		row.limitLikelyHit = true

		let content = ProviderDetail(row: row, days: 7)
			.frame(width: DashboardLayout.twoColumns.width, alignment: .topLeading)
			.background(JP.paper)
		let renderer = ImageRenderer(content: content)
		renderer.scale = 2
		guard let image = renderer.nsImage,
			let tiff = image.tiffRepresentation,
			let rep = NSBitmapImageRep(data: tiff),
			let png = rep.representation(using: .png, properties: [:])
		else {
			return XCTFail("Failed to render frozen Claude limit detail")
		}

		let output = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/claude-limit-estimated-full.png")
		try png.write(to: output)
		print("Wrote Claude limit render to \(output.path)")
	}

	/// The per-model weekly bars ("Fable" / "Sonnet") stacked under the plan-wide gauges. This cannot be
	/// captured from a live run — Claude's statusline feed does not carry these windows today — so the
	/// harness is the only way to see the surface, using the shape a real capture WOULD decode into.
	@MainActor
	func testRenderPerModelWeeklyWindows() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNG")

		let weekReset = Date().addingTimeInterval(3 * 24 * 3600)
		var row = DashboardViewModel.ProviderRow(
			id: "claude",
			name: "Claude Code",
			tintHex: JPAppColor.claudeTintHex,
			today: 41.20,
			week: 205.38,
			todayUsage: TokenUsage(input: 1, output: 1),
			weekUsage: TokenUsage(input: 2, output: 2),
			todayEvents: 1,
			weekEvents: 2,
			series: [150, 205.38],
			notional: false,
			usedPct: 42,
			weeklyUsedPct: 87,
			usageOfficial: true,
			planLabel: nil,
			unpricedModels: [],
			byModel7d: [],
			cacheSavings7d: nil,
			resetsAt5h: Date().addingTimeInterval(4 * 3600),
			resetsAtWeekly: weekReset,
			windowMinutes5h: 300,
			windowMinutesWeekly: 10080)
		row.modelWindows = [
			ModelScopedRateLimitWindow(
				key: "seven_day_opus",
				window: RateLimitWindow(
					usedPercent: 100, windowMinutes: 10080, resetsAt: weekReset.addingTimeInterval(-60))),
			ModelScopedRateLimitWindow(
				key: "seven_day_sonnet",
				window: RateLimitWindow(usedPercent: 12, windowMinutes: 10080, resetsAt: weekReset)),
		]

		let content = ProviderDetail(row: row, days: 7)
			.frame(width: DashboardLayout.twoColumns.width, alignment: .topLeading)
			.background(JP.paper)
		let renderer = ImageRenderer(content: content)
		renderer.scale = 2
		guard let image = renderer.nsImage,
			let tiff = image.tiffRepresentation,
			let rep = NSBitmapImageRep(data: tiff),
			let png = rep.representation(using: .png, properties: [:])
		else {
			return XCTFail("Failed to render per-model weekly windows")
		}

		let output = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/claude-limit-per-model-windows.png")
		try png.write(to: output)
		print("Wrote per-model window render to \(output.path)")
	}
}
