import AppKit
import XCTest

@testable import JPtheCatApp

final class StatusItemGeometryTests: XCTestCase {
	func testDashboardOriginUsesOffPrimaryDisplayFrame() throws {
		let primary = StatusItemGeometry.Display(
			frame: NSRect(x: 0, y: 0, width: 2056, height: 1329),
			visibleFrame: NSRect(x: 0, y: 0, width: 2056, height: 1289))
		let externalLeft = StatusItemGeometry.Display(
			frame: NSRect(x: -2560, y: -261, width: 2560, height: 1440),
			visibleFrame: NSRect(x: -2560, y: -261, width: 2560, height: 1440))
		let statusButton = NSRect(x: -92, y: 1155, width: 84, height: 24)
		let dashboardSize = NSSize(width: 384, height: 500)

		let origin = try XCTUnwrap(
			StatusItemGeometry.dashboardOriginBelowStatusItem(
				anchor: statusButton,
				windowSize: dashboardSize,
				preferredDisplay: nil,
				displays: [primary, externalLeft]))

		XCTAssertLessThan(origin.x, 0, "the dashboard must stay on the off-primary display")
		XCTAssertGreaterThanOrEqual(origin.x, externalLeft.visibleFrame.minX + 8)
		XCTAssertLessThanOrEqual(origin.x + dashboardSize.width, externalLeft.visibleFrame.maxX - 8)
		XCTAssertLessThan(origin.y + dashboardSize.height, statusButton.minY)
	}

	func testDashboardOriginPrefersButtonWindowDisplayWhenAnchorTouchesTwoDisplays() throws {
		let primary = StatusItemGeometry.Display(
			frame: NSRect(x: 0, y: 0, width: 2056, height: 1329),
			visibleFrame: NSRect(x: 0, y: 0, width: 2056, height: 1289))
		let externalLeft = StatusItemGeometry.Display(
			frame: NSRect(x: -2560, y: -261, width: 2560, height: 1440),
			visibleFrame: NSRect(x: -2560, y: -261, width: 2560, height: 1440))
		let straddlingStatusButton = NSRect(x: -10, y: 1155, width: 84, height: 24)
		let dashboardSize = NSSize(width: 384, height: 500)

		let origin = try XCTUnwrap(
			StatusItemGeometry.dashboardOriginBelowStatusItem(
				anchor: straddlingStatusButton,
				windowSize: dashboardSize,
				preferredDisplay: externalLeft,
				displays: [primary, externalLeft]))

		XCTAssertLessThan(origin.x, 0, "button.window.screen must win over primary-screen intersection")
		XCTAssertLessThanOrEqual(origin.x + dashboardSize.width, externalLeft.visibleFrame.maxX - 8)
	}

	func testWideDashboardFitsConstrainedAndNegativeOriginDisplaysAtEitherEdge() throws {
		for x: CGFloat in [-800, 0, 2056] {
			let display = StatusItemGeometry.Display(
				frame: NSRect(x: x, y: -200, width: 800, height: 900),
				visibleFrame: NSRect(x: x, y: -200, width: 800, height: 860))
			for edge in [x, x + 760] {
				let size = NSSize(width: DashboardLayout.twoColumns.width, height: 650)
				let origin = try XCTUnwrap(StatusItemGeometry.dashboardOriginBelowStatusItem(
					anchor: NSRect(x: edge, y: 660, width: 40, height: 24),
					windowSize: size, preferredDisplay: display, displays: [display]))
				XCTAssertTrue(display.visibleFrame.contains(NSRect(origin: origin, size: size)))
			}
		}
	}

	func testSecondaryClickHitTestUsesScreenCoordinatesWithNegativeOrigins() {
		let statusButton = NSRect(x: -92, y: 1155, width: 84, height: 24)

		XCTAssertTrue(
			StatusItemGeometry.statusButtonContains(
				mouseLocation: NSPoint(x: -50, y: 1167),
				statusButtonScreenFrame: statusButton))
		XCTAssertFalse(
			StatusItemGeometry.statusButtonContains(
				mouseLocation: NSPoint(x: 50, y: 1167),
				statusButtonScreenFrame: statusButton))
	}

	func testCompactMenuPopupPointIsButtonLocal() {
		let buttonBounds = NSRect(x: 0, y: 0, width: 84, height: 24)

		XCTAssertEqual(
			StatusItemGeometry.compactMenuPopupPoint(buttonBounds: buttonBounds),
			NSPoint(x: 0, y: 24))
	}
}
