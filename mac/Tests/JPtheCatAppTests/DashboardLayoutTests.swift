import AppKit
import SwiftUI
import XCTest

@testable import JPtheCatApp

final class DashboardLayoutTests: XCTestCase {
	func testLayoutsCycleBothWays() {
		XCTAssertEqual(DashboardLayout.oneColumn.next, .twoColumns)
		XCTAssertEqual(DashboardLayout.twoColumns.next, .oneColumn)
		for layout in DashboardLayout.allCases {
			XCTAssertEqual(layout.next.next, layout)
		}
	}

	func testStoredValuesNormalizeToAKnownLayout() {
		XCTAssertEqual(DashboardLayout.normalized(nil), .twoColumns)
		XCTAssertEqual(DashboardLayout.normalized(""), .twoColumns)
		XCTAssertEqual(DashboardLayout.normalized("threeColumns"), .twoColumns)
		XCTAssertEqual(DashboardLayout.normalized("oneColumn"), .oneColumn)
		XCTAssertEqual(DashboardLayout.normalized("twoColumns"), .twoColumns)
	}

	func testGridsNeverGetMoreColumnsThanTheLayoutHas() {
		XCTAssertEqual(DashboardLayout.oneColumn.columns(upTo: 2), 1)
		XCTAssertEqual(DashboardLayout.oneColumn.columns(upTo: 1), 1)
		XCTAssertEqual(DashboardLayout.twoColumns.columns(upTo: 2), 2)
		XCTAssertEqual(DashboardLayout.twoColumns.columns(upTo: 1), 1)
		XCTAssertEqual(DashboardLayout.twoColumns.columns(upTo: 0), 1, "a grid always keeps one column")
	}

	func testEachLayoutHasItsOwnRealSystemSymbolAndPlainTitle() {
		XCTAssertNotEqual(DashboardLayout.oneColumn.systemImage, DashboardLayout.twoColumns.systemImage)
		for layout in DashboardLayout.allCases {
			XCTAssertNotNil(
				NSImage(systemSymbolName: layout.systemImage, accessibilityDescription: nil),
				"\(layout.systemImage) must be a real SF Symbol, or the chrome button draws blank")
		}
		XCTAssertEqual(DashboardLayout.oneColumn.title, "One column")
		XCTAssertEqual(DashboardLayout.twoColumns.title, "Two columns")
		XCTAssertEqual(JPTooltip.dashboardLayout(current: .twoColumns), "Two columns — click for one column")
		XCTAssertEqual(JPTooltip.dashboardLayout(current: .oneColumn), "One column — click for two columns")
	}

	/// The Settings chrome is the fuller row: the rotation light plus five uniform 26pt controls.
	/// All of it must fit beside the title inside the 384pt card.
	@MainActor
	func testTheFullerSettingsChromeFitsTheOneColumnCard() {
		let row = ChromeTitleRow(windowChrome: true) {
			HStack(spacing: JPAppSpacing.chromeControlGap) {
				RotationIndicatorLight(isRotating: true)
				ForEach(0..<5, id: \.self) { _ in
					Color.clear.frame(width: JPAppSpacing.chromeControlSize, height: JPAppSpacing.chromeControlSize)
				}
			}
		}
		.fixedSize()
		let host = NSHostingController(rootView: row)
		host.view.layoutSubtreeIfNeeded()
		XCTAssertLessThanOrEqual(host.view.fittingSize.width, DashboardLayout.oneColumn.width)
	}

	/// One column restores the compact card's reading order: selector rows stack in source order.
	@MainActor
	func testOneColumnSelectorStacksEveryProviderRow() {
		func height(_ layout: DashboardLayout) -> CGFloat {
			let view = DashboardSelectorLayout(columnCount: layout.columnCount) {
				Color.clear.frame(height: 20)
			} providers: {
				ForEach(0..<5, id: \.self) { _ in Color.clear.frame(height: 20) }
			}
			.frame(width: layout.width)
			let host = NSHostingController(rootView: view)
			host.view.layoutSubtreeIfNeeded()
			return host.view.fittingSize.height
		}
		let gap = DashboardSurfaceMetrics.selectorRowGap
		XCTAssertEqual(height(.oneColumn), 6 * 20 + 5 * gap, accuracy: 0.5)
		XCTAssertEqual(height(.twoColumns), 4 * 20 + 3 * gap, accuracy: 0.5, "odd counts add no filler row")
	}
}
