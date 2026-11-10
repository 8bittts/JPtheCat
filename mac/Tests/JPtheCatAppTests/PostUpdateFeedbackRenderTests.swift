import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Brand-fidelity render harness for the post-update feedback sheet (AGENTS.md HARD REQUIREMENT: a
/// visual change is proven with a real render, never eyeballed intent). Writes the empty, typed, and
/// send-failed states in both themes. Gated behind `JP_RENDER=1`:
///
///     JP_RENDER=1 swift test --filter PostUpdateFeedbackRenderTests
final class PostUpdateFeedbackRenderTests: XCTestCase {
	@MainActor
	func testRenderPostUpdateFeedbackSheetToPNG() throws {
		try XCTSkipUnless(
			ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
			"Render harness — set JP_RENDER=1 to emit PNGs")

		let cases: [(String, String, PostUpdateFeedbackStatus?)] = [
			("empty", "", nil),
			("typed", "The menu bar pill is a little wide on a 13\" screen — could it drop the cents?", nil),
			("failed", "Offline right now.", .failed),
		]
		let themes: [(String, JPTheme)] = [("sunlit", .sunlit), ("midnight", .midnight)]
		let outDir = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/feedback-renders")
		try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

		let previousTheme = JPTheme.current
		defer { JPTheme.current = previousTheme }

		for (themeName, theme) in themes {
			JPTheme.current = theme
			for (name, message, status) in cases {
				let content = PostUpdateFeedbackSheetBody(
					version: "1.091",
					message: .constant(message),
					contactEmail: .constant(""),
					status: status)

				let renderer = ImageRenderer(content: content)
				renderer.scale = 2
				guard let image = renderer.nsImage,
					let tiff = image.tiffRepresentation,
					let rep = NSBitmapImageRep(data: tiff),
					let png = rep.representation(using: .png, properties: [:])
				else {
					XCTFail("Failed to render \(themeName)/\(name)")
					continue
				}
				try png.write(to: outDir.appendingPathComponent("feedback-\(themeName)-\(name).png"))
			}
		}
		print("Wrote post-update feedback renders to \(outDir.path)")
	}
}
