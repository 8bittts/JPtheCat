import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Visual proof for the shared `ChromeTitleRow` consolidation (the six former hand-rolled chrome
/// rows). Renders both card faces, the real Themes window content, and the isolated row variants on
/// Sunlit + Midnight so the subtitle shade, trailing-control inset, and card background can be
/// eyeballed. Gated behind `JP_RENDER=1` so the normal `swift test` run stays fast and file-free:
///
///     JP_RENDER=1 swift test --filter ChromeTitleRowRenderTests
final class ChromeTitleRowRenderTests: XCTestCase {
	@MainActor
	func testRenderChromeRows() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNGs")

		let outDir = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/chrome-renders")
		try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

		let previousTheme = JPTheme.current
		defer { JPTheme.current = previousTheme }

		for theme in [JPTheme.sunlit, JPTheme.midnight] {
			JPTheme.current = theme
			let model = DashboardViewModel(index: nil)
			try render(DashboardView(model: model), name: "\(theme.id)-dashboard", outDir: outDir)
			try render(SettingsBackView(model: model, onClose: {}), name: "\(theme.id)-settings", outDir: outDir)
			try render(ThemesWindowContent(), name: "\(theme.id)-themes-window", outDir: outDir)
			try render(chromeSamples(), name: "\(theme.id)-chrome-samples", outDir: outDir)
		}
		print("Wrote chrome renders to \(outDir.path)")
	}

	/// The shared row in every shape it now serves: window+subtitle+trailing, window+subtitle only,
	/// and a face-style row with an icon-only trailing control.
	@MainActor private func chromeSamples() -> some View {
		VStack(spacing: 6) {
			ChromeTitleRow(subtitle: "— Advanced Analytics") {
				Text("14 days").font(JPAppFont.chip).foregroundStyle(JP.inkSoft)
			}
			ChromeTitleRow(subtitle: "— Live data")
			ChromeTitleRow(subtitle: "— Themes")
			ChromeTitleRow(windowChrome: false) {
				Image(systemName: "gearshape").font(JPAppFont.chromeIcon).foregroundStyle(JP.inkSoft)
			}
		}
		.frame(width: 384)
		.background(JP.paper)
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
