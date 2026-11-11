import AppKit
import JPtheCatCore
import XCTest

@testable import JPtheCatApp

/// Pixel-level guards for the two menu-bar faces. These exist because the drawing was extracted out
/// of `StatusBarController` into the stateless `MenuBarPillRenderer` precisely so it could be
/// rendered and inspected without a live `NSStatusItem` — geometry-only assertions
/// (`StatusPillMetricsTests`) never proved a single pixel actually landed where the layout said.
///
/// The palette is supplied per-render, so every test here passes its OWN unmistakable colors: an
/// assertion then reads as "the renderer honored the color it was handed in that role", never as a
/// restatement of the shipped palette (which lives on `StatusBarController` and is theme-independent
/// on purpose).
final class MenuBarPillRendererTests: XCTestCase {
	private let opaqueWhite = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
	private let opaqueBlack = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
	private let pureRed = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
	private let pureGreen = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
	private let pureBlue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

	private func pill(
		_ text: String,
		attention: MenuBarAttentionState = .normal,
		mark: NSImage? = nil,
		thickness: CGFloat = 24
	) -> NSImage {
		MenuBarPillRenderer.pillImage(
			text: text,
			attention: attention,
			mark: mark,
			ink: opaqueBlack,
			fill: opaqueWhite,
			borderNormal: pureRed,
			borderWarning: pureGreen,
			borderCritical: pureBlue,
			thickness: thickness)
	}

	// MARK: - Geometry, actually rendered

	func testRenderedPillImageMatchesTheStatusPillMetricsLayoutExactly() throws {
		for thickness in [22.0, 24.0, 25.0] as [CGFloat] {
			let text = "$12.34"
			let image = pill(text, thickness: thickness)
			let expected = StatusPillMetrics.statusItemLayout(
				measuredTextWidth: ceil(measuredWidth(of: text)), statusBarThickness: thickness)
			XCTAssertEqual(image.size.width, expected.imageSize.width, accuracy: 0.001)
			XCTAssertEqual(
				image.size.height, thickness, accuracy: 0.001,
				"the pill must fill the menu bar's exact thickness, never a fixed height")
		}
	}

	func testWiderTextProducesAProportionallyWiderPillWithNoFixedSlot() throws {
		let narrow = pill("$1.00")
		let wide = pill("$1,234.56")
		let widthDelta = ceil(measuredWidth(of: "$1,234.56")) - ceil(measuredWidth(of: "$1.00"))
		XCTAssertEqual(wide.size.width - narrow.size.width, widthDelta, accuracy: 0.001)
	}

	func testRenderingIsDeterministic() throws {
		let first = try XCTUnwrap(pill("$42.00", attention: .critical).tiffRepresentation)
		let second = try XCTUnwrap(pill("$42.00", attention: .critical).tiffRepresentation)
		XCTAssertEqual(first, second)
	}

	func testAMissingMarkStillRendersTheChipAtTheSameSize() throws {
		let mark = try XCTUnwrap(menuBarMark())
		XCTAssertEqual(pill("$5.00", mark: nil).size, pill("$5.00", mark: mark).size)
		// And the mark actually draws: the two bitmaps must differ.
		XCTAssertNotEqual(
			try XCTUnwrap(pill("$5.00", mark: nil).tiffRepresentation),
			try XCTUnwrap(pill("$5.00", mark: mark).tiffRepresentation))
	}

	// MARK: - The 80% / 95% attention signal is BORDER-ONLY

	/// [Regression guard] Attention (warning >=80%, critical >=95%) is a BORDER color and nothing
	/// else. Sampling the pill's stroke proves each state paints the color it was handed in that
	/// role — a swapped argument label at the call site shows up here as the wrong dominant channel.
	func testEachAttentionStatePaintsItsOwnBorderColor() throws {
		let cases: [(MenuBarAttentionState, NSColor)] = [
			(.normal, pureRed), (.warning, pureGreen), (.critical, pureBlue),
		]
		for (attention, expected) in cases {
			let image = pill("$12.34", attention: attention)
			let layout = layoutFor("$12.34")
			let sampled = try sample(
				image, atPoint: NSPoint(x: layout.pillRect.minX + 0.5, y: layout.pillRect.midY))
			assertDominantChannelMatches(sampled, expected, label: "\(attention)")
		}
	}

	/// The same sample point INSIDE the chip — clear of the mark and past the text's trailing edge —
	/// must be byte-identical across all three attention states. A future "let's tint the fill at
	/// 95%" change fails right here, which is the point: the menu-bar chip is a fixed light card.
	func testAttentionNeverTintsTheChipFill() throws {
		let layout = layoutFor("$12.34")
		// Between the text's right edge and the border stroke: always plain fill.
		let interior = NSPoint(x: layout.pillRect.maxX - 2.5, y: layout.pillRect.midY)
		let normal = try sample(pill("$12.34", attention: .normal), atPoint: interior)
		let warning = try sample(pill("$12.34", attention: .warning), atPoint: interior)
		let critical = try sample(pill("$12.34", attention: .critical), atPoint: interior)

		assertColorsEqual(normal, warning, label: "normal vs warning fill")
		assertColorsEqual(normal, critical, label: "normal vs critical fill")
		assertColorsEqual(normal, opaqueWhite, label: "fill honors the supplied paper color")
	}

	// MARK: - Loading grid

	func testLoadingGridIsMarkPlusGapPlusTheCellGrid() {
		// 18pt mark + 4pt gap + (4 cells * 2pt + 3 gaps * 1pt).
		let image = MenuBarPillRenderer.loadingPixelImage(
			filled: 0, cols: 4, rows: 4, mark: nil, thickness: 24)
		XCTAssertEqual(image.size.width, 18 + 4 + 11, accuracy: 0.001)
		XCTAssertEqual(image.size.height, 24, accuracy: 0.001)
	}

	/// [Regression guard] The grid fills bottom→top, left→right per row (`r == 0` is the BOTTOM row).
	/// An "on" cell is drawn at full ink alpha, an "off" cell at 0.18 — so alpha at the cell center is
	/// the signal, and it is appearance-independent (the ink is the adaptive `labelColor`).
	func testLoadingGridFillsBottomUpAndLeftToRight() throws {
		let onAlphaFloor: CGFloat = 0.5
		let offAlphaCeiling: CGFloat = 0.3

		let one = MenuBarPillRenderer.loadingPixelImage(
			filled: 1, cols: 4, rows: 4, mark: nil, thickness: 24)
		XCTAssertGreaterThan(
			try sample(one, atPoint: cellCentre(row: 0, col: 0)).alphaComponent, onAlphaFloor,
			"the FIRST filled cell must be the bottom-left one")
		XCTAssertLessThan(
			try sample(one, atPoint: cellCentre(row: 0, col: 1)).alphaComponent, offAlphaCeiling)
		XCTAssertLessThan(
			try sample(one, atPoint: cellCentre(row: 1, col: 0)).alphaComponent, offAlphaCeiling,
			"row 1 sits ABOVE row 0 and must stay empty while only one cell is filled")

		let five = MenuBarPillRenderer.loadingPixelImage(
			filled: 5, cols: 4, rows: 4, mark: nil, thickness: 24)
		for col in 0..<4 {
			XCTAssertGreaterThan(
				try sample(five, atPoint: cellCentre(row: 0, col: col)).alphaComponent, onAlphaFloor,
				"the whole bottom row fills before row 1 starts (col \(col))")
		}
		XCTAssertGreaterThan(
			try sample(five, atPoint: cellCentre(row: 1, col: 0)).alphaComponent, onAlphaFloor)
		XCTAssertLessThan(
			try sample(five, atPoint: cellCentre(row: 1, col: 1)).alphaComponent, offAlphaCeiling)

		let full = MenuBarPillRenderer.loadingPixelImage(
			filled: 16, cols: 4, rows: 4, mark: nil, thickness: 24)
		for row in 0..<4 {
			for col in 0..<4 {
				XCTAssertGreaterThan(
					try sample(full, atPoint: cellCentre(row: row, col: col)).alphaComponent, onAlphaFloor,
					"reduced-motion renders the FULL grid (r\(row) c\(col))")
			}
		}
	}

	func testLoadingGridIsVerticallyCentredAtEveryMenuBarThickness() throws {
		for thickness in [22.0, 24.0, 25.0] as [CGFloat] {
			let image = MenuBarPillRenderer.loadingPixelImage(
				filled: 16, cols: 4, rows: 4, mark: nil, thickness: thickness)
			let gridHeight: CGFloat = 11  // 4 cells * 2pt + 3 gaps * 1pt
			let originY = (thickness - gridHeight) / 2
			// Symmetric slack above and below by construction; assert the top and bottom cell centers
			// are equidistant from the image edges.
			let bottomCentre = originY + 1
			let topCentre = originY + 3 * 3 + 1
			XCTAssertEqual(
				bottomCentre, thickness - topCentre, accuracy: 0.001,
				"grid must be optically centered at thickness \(thickness)")
			XCTAssertEqual(image.size.height, thickness, accuracy: 0.001)
		}
	}

	// MARK: - Helpers

	private func menuBarMark() -> NSImage? {
		let image = AppResources.image(forResource: "jp-menubar")
		image?.size = NSSize(width: 18, height: 18)
		return image
	}

	private func measuredWidth(of text: String) -> CGFloat {
		NSAttributedString(
			string: text,
			attributes: [.font: JPAppFont.statusPillFont, .foregroundColor: opaqueBlack]
		).size().width
	}

	private func layoutFor(_ text: String, thickness: CGFloat = 24) -> StatusPillMetrics.Layout {
		StatusPillMetrics.statusItemLayout(
			measuredTextWidth: ceil(measuredWidth(of: text)), statusBarThickness: thickness)
	}

	/// Cell center in the loading grid's POINT coordinates (bottom-left origin), for `thickness == 24`.
	private func cellCentre(row: Int, col: Int) -> NSPoint {
		let originX: CGFloat = 18 + 4
		let originY: CGFloat = (24 - 11) / 2
		return NSPoint(
			x: originX + CGFloat(col) * 3 + 1,
			y: originY + CGFloat(row) * 3 + 1)
	}

	/// Samples the rendered bitmap at a point in the image's own (bottom-left origin) coordinates,
	/// converting to the rep's top-left pixel grid at whatever backing scale the run produced.
	private func sample(_ image: NSImage, atPoint point: NSPoint) throws -> NSColor {
		let data = try XCTUnwrap(image.tiffRepresentation, "image produced no bitmap")
		let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
		let scaleX = CGFloat(rep.pixelsWide) / image.size.width
		let scaleY = CGFloat(rep.pixelsHigh) / image.size.height
		let x = min(max(Int(point.x * scaleX), 0), rep.pixelsWide - 1)
		let y = min(max(Int((image.size.height - point.y) * scaleY), 0), rep.pixelsHigh - 1)
		let color = try XCTUnwrap(rep.colorAt(x: x, y: y), "no pixel at \(point)")
		return color.usingColorSpace(.sRGB) ?? color
	}

	/// Antialiasing and the fill underneath shift the exact stroke color, so the assertion is on the
	/// DOMINANT channel — unambiguous for the pure primaries these tests feed in, and immune to the
	/// blending the real (semi-transparent) shipped border colors would introduce.
	private func assertDominantChannelMatches(
		_ actual: NSColor, _ expected: NSColor, label: String, file: StaticString = #filePath,
		line: UInt = #line
	) {
		let a = [actual.redComponent, actual.greenComponent, actual.blueComponent]
		let e = [expected.redComponent, expected.greenComponent, expected.blueComponent]
		let expectedIndex = try? XCTUnwrap(e.firstIndex(of: e.max() ?? 0))
		guard let expectedIndex else { return XCTFail("bad expectation", file: file, line: line) }
		for other in 0..<3 where other != expectedIndex {
			XCTAssertGreaterThan(
				a[expectedIndex], a[other],
				"\(label): channel \(expectedIndex) must dominate channel \(other) — got \(a)",
				file: file, line: line)
		}
	}

	private func assertColorsEqual(
		_ lhs: NSColor, _ rhs: NSColor, label: String, file: StaticString = #filePath, line: UInt = #line
	) {
		XCTAssertEqual(lhs.redComponent, rhs.redComponent, accuracy: 0.01, label, file: file, line: line)
		XCTAssertEqual(
			lhs.greenComponent, rhs.greenComponent, accuracy: 0.01, label, file: file, line: line)
		XCTAssertEqual(
			lhs.blueComponent, rhs.blueComponent, accuracy: 0.01, label, file: file, line: line)
		XCTAssertEqual(
			lhs.alphaComponent, rhs.alphaComponent, accuracy: 0.01, label, file: file, line: line)
	}
}
