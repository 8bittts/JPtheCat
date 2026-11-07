import AppKit
import XCTest

@testable import JPtheCatApp

final class StatusPillMetricsTests: XCTestCase {
	func testStatusPillForcesHostedButtonRedrawAfterImageReplacement() throws {
		let applyPillTitle = try AppSourceScanner.body(of: "private func applyPillTitle(")

		XCTAssertTrue(applyPillTitle.contains("button.image = image"))
		XCTAssertTrue(applyPillTitle.contains("button.needsDisplay = true"))
		XCTAssertTrue(applyPillTitle.contains("button.displayIfNeeded()"))
	}

	/// [Regression guard] The drawing lives in the stateless `MenuBarPillRenderer` so it is
	/// pixel-testable (`MenuBarPillRendererTests`), but the shipped palette — a FIXED light chip that
	/// never follows the app theme, plus the border-only 80%/95% attention colors — stays on the
	/// controller. The renderer takes each color positionally by role, so a swapped argument label
	/// would silently paint the critical color at 80%; pin the mapping here, where the real call site
	/// is, since the pixel tests deliberately feed their own colors.
	func testTheControllerHandsItsFixedLightPaletteToTheRendererInTheRightRoles() throws {
		let applyPillTitle = try AppSourceScanner.body(of: "private func applyPillTitle(")

		XCTAssertTrue(applyPillTitle.contains("MenuBarPillRenderer.pillImage("))
		XCTAssertTrue(applyPillTitle.contains("ink: pillInk,"))
		XCTAssertTrue(applyPillTitle.contains("fill: pillFill,"))
		XCTAssertTrue(applyPillTitle.contains("borderNormal: pillBorder,"))
		XCTAssertTrue(applyPillTitle.contains("borderWarning: pillWarningBorder,"))
		XCTAssertTrue(applyPillTitle.contains("borderCritical: pillCriticalBorder,"))
		XCTAssertTrue(applyPillTitle.contains("thickness: NSStatusBar.system.thickness"))
	}

	/// The loading grid is likewise drawn by the renderer, but the animation state (`loadingPixelStep`,
	/// the reduced-motion full-grid shortcut) and the `Timer` stay in the controller.
	func testTheLoadingGridIsDrawnByTheRendererWithTheControllersAnimationState() throws {
		let render = try AppSourceScanner.body(of: "private func renderLoadingPixels(")

		XCTAssertTrue(render.contains("MenuBarPillRenderer.loadingPixelImage("))
		XCTAssertTrue(render.contains("cols: loadingPixelCols"))
		XCTAssertTrue(render.contains("rows: loadingPixelRows"))
		XCTAssertTrue(
			render.contains("reduceMotion ? loadingPixelCols * loadingPixelRows : loadingPixelStep"),
			"reduced motion must render the FULL grid once instead of animating")
	}

	func testMarkBleedsLeftAndVerticallyBeyondPill() {
		let layout = StatusPillMetrics.layout(textWidth: 52, statusBarThickness: 24)

		XCTAssertLessThan(layout.markRect.minX, layout.pillRect.minX)
		XCTAssertLessThan(layout.markRect.minY, layout.pillRect.minY)
		XCTAssertGreaterThan(layout.markRect.maxY, layout.pillRect.maxY)
		XCTAssertGreaterThanOrEqual(layout.pillRect.minX - layout.markRect.minX, 8)
		XCTAssertGreaterThanOrEqual(layout.pillRect.minY - layout.markRect.minY, 1)
		XCTAssertGreaterThanOrEqual(layout.markRect.maxY - layout.pillRect.maxY, 1)
		XCTAssertEqual(layout.markRect.minX, 0, accuracy: 0.001)
	}

	func testTextHasEqualWhitespaceOnBothSides() {
		// Permanent guard for "same space to the left and right of the text": the gap from the mark's
		// trailing edge (the mark draws full-size, so `markRect.maxX`) to the text must equal the gap
		// from the text to the pill's right edge. Regression this guards against: a mark art-inset or a
		// wider fixed slot stacking padding onto one side (once ~9pt left vs 5pt right).
		// Thickness-invariant: menu-bar height (22/24/notch) must never skew the horizontal balance.
		for thickness in [22.0, 24.0] as [CGFloat] {
			for width in [40.0, 75.0, 117.0] as [CGFloat] {
				let layout = StatusPillMetrics.layout(textWidth: width, statusBarThickness: thickness)
				let leftGap = layout.textOriginX - layout.markRect.maxX
				let rightGap = layout.pillRect.maxX - (layout.textOriginX + width)
				XCTAssertEqual(
					leftGap, rightGap, accuracy: 0.001,
					"text whitespace must be symmetric at width \(width), thickness \(thickness)")
				XCTAssertEqual(leftGap, StatusPillMetrics.textTrailingInset, accuracy: 0.001)
			}
		}
	}

	func testTrailingTextInsetIsTighterThanMarkAndTextCluster() {
		let textWidth: CGFloat = 52
		let layout = StatusPillMetrics.layout(textWidth: textWidth, statusBarThickness: 24)

		XCTAssertEqual(
			layout.pillRect.maxX - (layout.textOriginX + textWidth),
			StatusPillMetrics.textTrailingInset,
			accuracy: 0.001)
		XCTAssertLessThan(StatusPillMetrics.textTrailingInset, StatusPillMetrics.markSize / 2)
	}

	func testImageHugsPillOnTheRightWithNoGrayTail() {
		let layout = StatusPillMetrics.layout(textWidth: 52, statusBarThickness: 24)

		// Only a hairline of bleed past the pill's right edge — otherwise the status-item
		// highlight fills the empty space as a gray tail on click.
		XCTAssertEqual(
			layout.imageSize.width - layout.pillRect.maxX,
			StatusPillMetrics.trailingBleed,
			accuracy: 0.001)
		XCTAssertLessThanOrEqual(StatusPillMetrics.trailingBleed, 2)
	}

	func testStatusItemLengthMatchesRenderedPillImageWidth() {
		let layout = StatusPillMetrics.statusItemLayout(measuredTextWidth: 42, statusBarThickness: 24)

		XCTAssertEqual(StatusPillMetrics.statusItemLength(for: layout), layout.imageSize.width, accuracy: 0.001)
		XCTAssertLessThanOrEqual(
			StatusPillMetrics.statusItemLength(for: layout) - layout.pillRect.maxX,
			2.001)
	}

	func testStatusItemSizesTightToTheMeasuredTextWithNoFixedSlot() {
		// Tight fit: the pill follows the measured text exactly — a narrower value yields a narrower
		// pill, with NO reserved slot padding. Width still stays stable per value because the pill font
		// is monospaced-digit, but the image is never wider than its content.
		let narrow = StatusPillMetrics.statusItemLayout(measuredTextWidth: 30, statusBarThickness: 24)
		let wide = StatusPillMetrics.statusItemLayout(measuredTextWidth: 90, statusBarThickness: 24)

		XCTAssertLessThan(narrow.imageSize.width, wide.imageSize.width)
		XCTAssertEqual(wide.imageSize.width - narrow.imageSize.width, 60, accuracy: 0.001)
		// Identical to sizing straight from the measured text — proving no slot flooring is applied.
		XCTAssertEqual(
			narrow.imageSize.width,
			StatusPillMetrics.layout(textWidth: 30, statusBarThickness: 24).imageSize.width,
			accuracy: 0.001)
	}

	func testStatusItemLeavesNoDeadSpaceToTheRightOfTheText() {
		// Regression: the "Total + limit" format reserved a fixed 100pt slot wider than the content,
		// leaving a blank tail to the right of the total (the recurring bug). The only trailing gap is
		// now the constant text inset, at every content width.
		for width in [24.0, 42.0, 65.0, 100.0] as [CGFloat] {
			let layout = StatusPillMetrics.statusItemLayout(
				measuredTextWidth: width, statusBarThickness: 24)
			XCTAssertEqual(
				layout.pillRect.maxX - (layout.textOriginX + width),
				StatusPillMetrics.textTrailingInset,
				accuracy: 0.001,
				"text must hug the pill's right edge at width \(width) — no dead slot")
		}
	}

	func testPillHeightIncreasesFromPreviousCompactHeight() {
		let layout = StatusPillMetrics.layout(textWidth: 52, statusBarThickness: 24)

		XCTAssertEqual(layout.pillRect.height, 21.5, accuracy: 0.001)
	}

	func testStatusMarkCropIsCircular() {
		XCTAssertEqual(StatusPillMetrics.markClipRadius, StatusPillMetrics.markSize / 2, accuracy: 0.001)
	}
}
