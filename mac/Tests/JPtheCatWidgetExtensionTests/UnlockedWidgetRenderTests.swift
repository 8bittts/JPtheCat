import AppKit
import JPtheCatCore
import SwiftUI
import WidgetKit
import XCTest

@testable import JPtheCatWidgetExtension

/// [CI GUARD] Renders the REAL unlocked Small / Medium / Large faces at their exact macOS point sizes
/// with the representative preview snapshot and asserts each produces a NON-BLANK raster.
///
/// This is the guard that would have caught the blank Small/Large gallery previews: before this, only
/// the LOCKED face had a render test, so a regression that made an unlocked face render nothing only
/// ever surfaced as a user "my widget is blank" report. It also feeds `MiniSparkline` degenerate series
/// (empty / single-point / all-equal) to prove the one theoretical blank/crash path stays closed —
/// the sparkline is the ONLY element unique to Small+Large (Medium omits it), so it was the prime
/// suspect. Runs in normal `swift test` (NOT gated) so it actually guards CI.
final class UnlockedWidgetRenderTests: XCTestCase {
	/// #FFFDF7 — the widget card cream. We render each face on it and count pixels that differ from it;
	/// a blank face (background only) yields ~0, drawn content (header text, `$` total, sparkline) yields
	/// many. Rendering on an explicit background (rather than clear) mirrors the real card and makes the
	/// blank-vs-drawn distinction unambiguous.
	private let cardColor = Color(.sRGB, red: 1, green: 0.992, blue: 0.969, opacity: 1)
	private let cardNSColor = NSColor(srgbRed: 1, green: 0.992, blue: 0.969, alpha: 1)

	/// Returns the count of sampled pixels that differ meaningfully from the card background, or -1 when
	/// `ImageRenderer` produced no image at all (a hard render failure the guard must also catch).
	@MainActor
	private func drawnPixelCount(_ view: some View, size: CGSize) -> Int {
    let content =
      view
			.frame(width: size.width, height: size.height, alignment: .topLeading)
			.background(cardColor)
			.environment(\.colorScheme, .light)

		let renderer = ImageRenderer(content: content)
		renderer.scale = 2
		guard let image = renderer.nsImage,
			let tiff = image.tiffRepresentation,
			let rep = NSBitmapImageRep(data: tiff)
		else {
			return -1
		}

		var drawn = 0
		let stepX = max(1, rep.pixelsWide / 70)
		let stepY = max(1, rep.pixelsHigh / 70)
		for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
			for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        else { continue }
        let delta =
          abs(color.redComponent - cardNSColor.redComponent)
					+ abs(color.greenComponent - cardNSColor.greenComponent)
					+ abs(color.blueComponent - cardNSColor.blueComponent)
				if delta > 0.08 { drawn += 1 }
			}
		}
		return drawn
	}

	private func previewEntry() -> JPtheCatWidgetEntry {
		JPtheCatWidgetEntry(
			date: Date(),
			configuration: JPtheCatWidgetConfigurationIntent(),
			snapshot: WidgetPreviewData.snapshot,
			isPreview: true)
	}

  @MainActor
  func testProviderBadgeUsesSharedCompactHeight() {
    for word in ["real", "notional", "local"] {
      let host = NSHostingView(rootView: ProviderBasisBadge(text: word))
      XCTAssertEqual(host.fittingSize.height, LabelBadgeMetrics.height, accuracy: 0.01)
    }
  }

  @MainActor
  func testRenderEveryUnlockedFaceToPNG() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["JP_RENDER"] != nil,
      "Render harness — set JP_RENDER=1 to emit PNGs")
    let outDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/unlocked-widget-renders")
    try FileManager.default.createDirectory(
      at: outDir, withIntermediateDirectories: true)
    let entry = previewEntry()
    let cases: [(String, AnyView, CGSize)] = [
      (
        "small", AnyView(SmallSpendWidget(entry: entry)),
        CGSize(width: 170, height: 170)
      ),
      (
        "medium", AnyView(MediumSpendWidget(entry: entry)),
        CGSize(width: 364, height: 170)
      ),
      (
        "large", AnyView(LargeSpendWidget(entry: entry)),
        CGSize(width: 364, height: 382)
      ),
    ]
    for scheme in [ColorScheme.light, .dark] {
      for (name, face, size) in cases {
        let renderer = ImageRenderer(
          content: face.frame(width: size.width, height: size.height)
            .background(WidgetPalette.card(scheme)).environment(
              \.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
        else { return XCTFail("Failed to render \(name) \(scheme)") }
        try png.write(
          to: outDir.appendingPathComponent("\(name)-\(scheme).png"))
      }
    }
    print("Wrote unlocked-widget renders to \(outDir.path)")
  }

	@MainActor
	func testRenderUnifiedPlanOnlyFacesWithoutDailySpendCaptions() throws {
		try XCTSkipUnless(ProcessInfo.processInfo.environment["JP_RENDER"] != nil, "Set JP_RENDER=1")
		let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent(".build/unlocked-widget-renders")
		try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
		for weekly in [true, false] {
			let provider = WidgetProviderSnapshot(id: "grok", name: "Grok", tintHex: "#111111",
				today: 30, window: 30, metric: .percent, basis: .notionalListPrice,
				usedPercent: nil, weeklyUsedPercent: weekly ? 30 : nil, usageOfficial: true, series: [])
			let snapshot = WidgetSnapshot(generatedAt: Date(), access: .premium, title: "Grok",
				totalToday: 30, totalWindow: 30, metric: .percent, windowDays: 14,
				basis: .notionalListPrice, series: [], providers: [provider],
				staleAfter: Date().addingTimeInterval(300), errorMessage: nil)
			XCTAssertFalse(snapshot.disclosesNotionalBasis)
			XCTAssertFalse(snapshot.heroAccessibilitySummary(amount: "30%").contains("today"))
			let entry = JPtheCatWidgetEntry(date: Date(), configuration: JPtheCatWidgetConfigurationIntent(),
				snapshot: snapshot, isPreview: true)
			let faces: [(String, AnyView, CGSize)] = [
				("small", AnyView(SmallSpendWidget(entry: entry)), CGSize(width: 170, height: 170)),
				("medium", AnyView(MediumSpendWidget(entry: entry)), CGSize(width: 364, height: 170)),
				("large", AnyView(LargeSpendWidget(entry: entry)), CGSize(width: 364, height: 382))]
			for scheme in [ColorScheme.light, .dark] {
				for (name, face, size) in faces {
					let renderer = ImageRenderer(content: face.frame(width: size.width, height: size.height)
						.background(WidgetPalette.card(scheme)).environment(\.colorScheme, scheme))
					renderer.scale = 2
					let image = try XCTUnwrap(renderer.nsImage)
					let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
					let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
					try png.write(to: out.appendingPathComponent("grok-\(weekly ? "weekly" : "monthly")-\(name)-\(scheme).png"))
				}
			}
		}
	}

	@MainActor
	func testEveryUnlockedFaceRendersNonBlank() {
		// Negative control: a genuinely blank face (nothing but the card) must score at/near zero, proving
		// the pixel metric actually discriminates blank from drawn — otherwise the assertions below would
		// pass vacuously even if a face regressed to blank.
		let blank = drawnPixelCount(Color.clear, size: CGSize(width: 170, height: 170))
    XCTAssertNotEqual(
      blank, -1, "ImageRenderer produced no image for the blank control")
    XCTAssertLessThanOrEqual(
      blank, 25, "Blank control scored \(blank) — the metric can't detect blank")

		let entry = previewEntry()
		// (name, face, exact WidgetKit point size). Small 170×170, Medium 364×170, Large 364×382.
		let cases: [(String, AnyView, CGSize)] = [
      (
        "small", AnyView(SmallSpendWidget(entry: entry)),
        CGSize(width: 170, height: 170)
      ),
      (
        "medium", AnyView(MediumSpendWidget(entry: entry)),
        CGSize(width: 364, height: 170)
      ),
      (
        "large", AnyView(LargeSpendWidget(entry: entry)),
        CGSize(width: 364, height: 382)
      ),
		]
		for (name, face, size) in cases {
			let drawn = drawnPixelCount(face, size: size)
      XCTAssertNotEqual(
        drawn, -1, "ImageRenderer produced no image for the \(name) face")
			// A blank card is ~0 non-background pixels; every face paints header + total (+ sparkline on
			// Small/Large), which is dozens of sampled pixels. 25 is a comfortable floor below real content.
			XCTAssertGreaterThan(
        drawn, 25,
        "The \(name) widget face rendered blank (\(drawn) non-background pixels)"
      )
		}
	}

	// A non-default per-widget Timeframe selection must still render non-blank at the exact Large frame —
	// the "last 90 days" string is longer than the default "last 14 days" and must not clip/overflow.
	@MainActor
	func testLargeFaceRendersNonBlankAtNinetyDayTimeframe() {
		let configuration = JPtheCatWidgetConfigurationIntent()
		configuration.timeframe = .ninetyDays
		let entry = JPtheCatWidgetEntry(
			date: Date(),
			configuration: configuration,
			snapshot: WidgetPreviewData.snapshot.selectingWindow(days: 90),
			isPreview: true)

    let drawn = drawnPixelCount(
      LargeSpendWidget(entry: entry), size: CGSize(width: 364, height: 382))
    XCTAssertNotEqual(
      drawn, -1, "ImageRenderer produced no image for the 90-day large face")
    XCTAssertGreaterThan(
      drawn, 25,
      "The 90-day large face rendered blank (\(drawn) non-background pixels)")
	}

	@MainActor
	func testMiniSparklineSurvivesDegenerateSeries() {
		let size = CGSize(width: 140, height: 24)
		// Empty, single-point, and all-equal series are the inputs that could produce a NaN/Inf path or a
		// divide-by-zero. The guard just proves each renders (no crash, no nil image); the sparkline is
		// allowed to draw very little for a flat/empty series — what matters is it never blanks the face.
		for values in [[Double](), [500.0], [300.0, 300.0, 300.0]] {
      let drawn = drawnPixelCount(
        MiniSparkline(values: values, tintHex: "#D6783F"), size: size)
			XCTAssertNotEqual(
        drawn, -1,
        "MiniSparkline produced no image for degenerate series \(values)")
		}
	}
}
