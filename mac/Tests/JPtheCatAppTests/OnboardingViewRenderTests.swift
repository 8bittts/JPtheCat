import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Brand-fidelity render harness for the first-run `OnboardingView` (AGENTS.md rule: any new
/// user-facing visual surface must be PROVEN with a real render, side-by-side with the homepage/app — not
/// just source-string contract-tested). Writes the onboarding card in both themes to PNGs so they can be
/// eyeballed against the homepage hero / menu-bar demo. Gated behind `JP_RENDER=1` so the normal
/// `swift test` run stays fast and file-write-free:
///
///     JP_RENDER=1 swift test --filter OnboardingViewRenderTests
final class OnboardingViewRenderTests: XCTestCase {
	@MainActor
	func testRenderOnboardingToPNG() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNGs")

		let themes: [(String, JPTheme)] = [("sunlit", .sunlit), ("midnight", .midnight)]
		let outDir = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/onboarding-renders")
		try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

		let previousTheme = JPTheme.current
		defer { JPTheme.current = previousTheme }

		for (themeName, theme) in themes {
			JPTheme.current = theme
			for layout in DashboardLayout.allCases {
				// Render at the card width over JP.card, no window chrome (the AppKit traffic-light
				// inset only applies in the live window), so the PNG matches what the user sees.
				let content = OnboardingView(
					windowChrome: false,
					onContinue: {}, onOpenSettings: {}, onRefresh: {}, onQuit: {}, onOpenWebsite: {})
					.environment(\.dashboardLayout, layout)

				let renderer = ImageRenderer(content: content)
				renderer.scale = 2
				guard let image = renderer.nsImage,
					let tiff = image.tiffRepresentation,
					let rep = NSBitmapImageRep(data: tiff),
					let png = rep.representation(using: .png, properties: [:])
				else {
					XCTFail("Failed to render onboarding \(themeName)/\(layout.rawValue)")
					continue
				}
				XCTAssertEqual(image.size.width, layout.width, accuracy: 1)
				try png.write(to: outDir.appendingPathComponent("onboarding-\(themeName)-\(layout.rawValue).png"))
			}
		}
		print("Wrote onboarding renders to \(outDir.path)")
	}
}
