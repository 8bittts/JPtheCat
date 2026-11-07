import AppKit
import XCTest

@testable import JPtheCatApp

/// The placeholder in a `JPTextEditorField` must sit exactly where the user's first character lands.
/// It shipped 5pt right and 5pt low once, which read as the placeholder JUMPING the moment you typed.
final class JPTextEditorFieldTests: XCTestCase {
	/// The offset the placeholder must carry BEYOND the editor's own padding is AppKit's
	/// `lineFragmentPadding`, which `TextEditor` neither exposes nor lets us zero. Assert against the
	/// live AppKit default rather than a copied number, so an OS change fails here instead of shipping
	/// a crooked placeholder.
	@MainActor
	func testPlaceholderInsetTracksAppKitsLiveLineFragmentPadding() {
		let liveDefault = NSTextContainer().lineFragmentPadding
		XCTAssertEqual(
			JPTextEditorFieldMetrics.lineFragmentPadding, liveDefault,
			"AppKit's default lineFragmentPadding changed — the placeholder inset must follow it")
		XCTAssertEqual(
			JPTextEditorFieldMetrics.placeholderInsetX,
			JPTextEditorFieldMetrics.editorInsetX + liveDefault)
	}

	/// Where the glyphs ACTUALLY land: the container adds `lineFragmentPadding` horizontally, nothing
	/// vertically. Both axes must resolve to `contentInset`, or the text sits closer to one border than
	/// the other — the shipped 1.090 field measured 10.5pt left against 5.5pt top.
	func testRenderedTextIsInsetEquallyFromTheLeftAndTopBorders() {
		let renderedLeft = JPTextEditorFieldMetrics.editorInsetX + JPTextEditorFieldMetrics.lineFragmentPadding
		let renderedTop = JPTextEditorFieldMetrics.editorInsetY
		XCTAssertEqual(renderedLeft, JPTextEditorFieldMetrics.contentInset)
		XCTAssertEqual(renderedTop, JPTextEditorFieldMetrics.contentInset)
		XCTAssertEqual(renderedLeft, renderedTop, "the well must be optically square-padded")
	}

	/// And the placeholder must land on that same spot, so it does not shift when the user types.
	func testPlaceholderLandsOnTheSameSpotAsTypedText() {
		XCTAssertEqual(JPTextEditorFieldMetrics.placeholderInsetX, JPTextEditorFieldMetrics.contentInset)
		XCTAssertEqual(JPTextEditorFieldMetrics.placeholderInsetY, JPTextEditorFieldMetrics.contentInset)
	}

	/// Both multi-line inputs in the app must route through the shared field — a hand-rolled
	/// `TextEditor` + overlay is exactly how the two drifted apart in the first place.
	func testNoSurfaceHandRollsItsOwnPlaceholderOverlay() throws {
		let sources = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/JPtheCatApp")
		let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
			.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "JPTextEditorField.swift" }
		XCTAssertGreaterThan(files.count, 20, "scan found almost no sources — the guard would pass vacuously")
		for file in files {
			let source = try String(contentsOf: file, encoding: .utf8)
			XCTAssertFalse(
				source.contains("TextEditor(text:"),
				"\(file.lastPathComponent) builds its own TextEditor — use JPTextEditorField instead")
		}
	}
}
