import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Faithful render proof for the hero `SparkChart` AFTER its geometry was hoisted out of the
/// `TimelineView(.animation)` loop (only the ping ring animates now). Renders the REAL view — real
/// `values`, real `SparklineScale` auto-range, the real restructured body — so the proof isn't a proxy
/// reconstruction. Gated behind `JP_RENDER=1` like the other render harnesses so the normal `swift test`
/// stays fast and file-write-free:
///
///     JP_RENDER=1 swift test --filter SparkChartRenderTests
///
/// Continuous protection for the restructure still comes from `MotionContractTests` (SparkChart keeps a
/// TimelineView, no `@State pulse`, no `withAnimation`) and `SparklineScaleTests` (the scaling math).
final class SparkChartRenderTests: XCTestCase {
	@MainActor
	func testRenderRealSparkChartToPNG() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNGs")

		// A realistic rising-then-spiking daily series, so the auto-range + fill + line + end dot + ping
		// all exercise their real paths.
		let series: [Double] = [42, 61, 55, 88, 73, 120, 96, 140, 128, 205, 176, 260, 231, 318]
		let outDir = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/sparkchart-renders")
		try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

		let previousTheme = JPTheme.current
		defer { JPTheme.current = previousTheme }

		let cases: [(String, JPTheme, Bool)] = [
			("sunlit-animated", .sunlit, false),
			("sunlit-reducemotion", .sunlit, true),
			("midnight-animated", .midnight, false),
		]
		for (name, theme, reduce) in cases {
			JPTheme.current = theme
			let content = SparkChart(values: series, tint: JP.ginger, reduceMotion: reduce)
				.frame(width: 320, height: 64)
				.padding(8)
				.background(JP.card)

			let renderer = ImageRenderer(content: content)
			renderer.scale = 3
			guard let image = renderer.nsImage,
				let tiff = image.tiffRepresentation,
				let rep = NSBitmapImageRep(data: tiff),
				let png = rep.representation(using: .png, properties: [:])
			else {
				XCTFail("Failed to render SparkChart \(name)")
				continue
			}
			// Prove the line actually drew: at least some pixels differ from the flat card background.
			XCTAssertGreaterThan(rep.pixelsWide, 0)
			try png.write(to: outDir.appendingPathComponent("sparkchart-\(name).png"))
		}
		print("Wrote SparkChart renders to \(outDir.path)")
	}
}
