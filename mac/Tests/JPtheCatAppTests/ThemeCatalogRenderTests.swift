import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Brand-fidelity render harness for the complete theme catalog (AGENTS.md HARD
/// REQUIREMENT: any new color palette must be PROVEN with a real render before shipping, not just
/// contrast-tested). Renders the Dashboard front face, and Settings face
/// while each palette is active so the whole catalog can be reviewed side by side. Gated
/// behind `JP_RENDER=1` so the normal `swift test` run stays fast and file-write-free:
///
///     JP_RENDER=1 swift test --filter ThemeCatalogRenderTests
final class ThemeCatalogRenderTests: XCTestCase {
	@MainActor
	func testRenderCompleteThemeCatalog() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNGs")

		let themes = JPTheme.all.map { ($0.id, $0) }
		let outDir = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/theme-renders")
		try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

		let previousTheme = JPTheme.current
		defer { JPTheme.current = previousTheme }

		for (themeName, theme) in themes {
			JPTheme.current = theme
			let model = DashboardViewModel(index: nil)

			try render(DashboardView(model: model), name: "\(themeName)-dashboard", outDir: outDir)
			try render(SettingsBackView(model: model, onClose: {}), name: "\(themeName)-settings", outDir: outDir)
		}
		print("Wrote complete theme-catalog renders to \(outDir.path)")
	}

	@MainActor
	private func render(_ content: some View, name: String, outDir: URL) throws {
		let renderer = ImageRenderer(content: content)
		renderer.scale = 2
		guard let image = renderer.nsImage,
			let tiff = image.tiffRepresentation,
			let rep = NSBitmapImageRep(data: tiff),
			let png = rep.representation(using: .png, properties: [:])
		else {
			XCTFail("Failed to render \(name)")
			return
		}
		try png.write(to: outDir.appendingPathComponent("\(name).png"))
	}
}
