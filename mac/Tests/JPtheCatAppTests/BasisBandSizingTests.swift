import AppKit
import SwiftUI
import XCTest

@testable import JPtheCatApp

final class BasisBandSizingTests: XCTestCase {
	/// The basis-label band must render at the SAME height for every provider's label —
	/// short (Claude), medium (Codex), and long (All providers) — so switching the selected provider
	/// can't resize the header and, with it, the whole intrinsic-height dashboard window.
	@MainActor
	func testBasisBandHeightIsConstantAcrossProviderLabels() {
		let labels = [
			"REAL SPEND · TODAY",  // Claude — short
			"NOTIONAL LIST-PRICE · TODAY",  // Codex — medium
			"REAL + NOTIONAL LIST-PRICE · TODAY",  // All providers — long
		]
		let heights = labels.map { label -> CGFloat in
			let host = NSHostingController(
				rootView: BasisLabelChip(text: label, reduceMotion: true).frame(width: 348))
			host.sizingOptions = .preferredContentSize
			host.view.layoutSubtreeIfNeeded()
			return host.preferredContentSize.height
		}
		XCTAssertEqual(heights[0], heights[1], accuracy: 0.5, "band height drifts short→medium: \(heights)")
		XCTAssertEqual(heights[1], heights[2], accuracy: 0.5, "band height drifts medium→long: \(heights)")
		XCTAssertGreaterThan(heights[0], 0, "band collapsed to zero height: \(heights)")
	}
}
