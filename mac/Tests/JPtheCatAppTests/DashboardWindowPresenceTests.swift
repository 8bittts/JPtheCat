import AppKit
import XCTest

@testable import JPtheCatApp

/// Clicking another app must not hide or bury the dashboard. The menu-bar item stays the quick
/// show and hide control. `DashboardWindowPresence` is the one configuration the dashboard and its
/// child windows apply, so a tray cannot drift back to "hide on deactivate" or a single Space.
final class DashboardWindowPresenceTests: XCTestCase {
	func testPinnedDashboardStaysAboveEveryScreenAndDoesNotHideOnClickAway() {
		let presence = DashboardWindowPresence.configuration(isPinned: true)

		XCTAssertEqual(presence.level, .floating)
		XCTAssertTrue(presence.collectionBehavior.contains(.canJoinAllSpaces))
		XCTAssertTrue(presence.collectionBehavior.contains(.fullScreenAuxiliary))
		XCTAssertFalse(presence.hidesOnDeactivate)
	}

	@MainActor
	func testApplyWritesPresenceOntoTheWindow() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
			styleMask: [.titled],
			backing: .buffered,
			defer: true)
		DashboardWindowPresence.apply(DashboardWindowPresence.configuration(isPinned: true), to: window)
		XCTAssertEqual(window.level, .floating)
		XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
		XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
		XCTAssertFalse(window.hidesOnDeactivate)

		DashboardWindowPresence.apply(DashboardWindowPresence.configuration(isPinned: false), to: window)
		XCTAssertEqual(window.level, .normal)
		XCTAssertEqual(window.collectionBehavior, [.managed])
		XCTAssertFalse(window.hidesOnDeactivate)
	}

	func testUnpinnedDashboardDropsBehindOnTheCurrentSpaceOnly() {
		let presence = DashboardWindowPresence.configuration(isPinned: false)

		XCTAssertEqual(presence.level, .normal)
		XCTAssertEqual(presence.collectionBehavior, [.managed])
		XCTAssertFalse(presence.collectionBehavior.contains(.canJoinAllSpaces))
		XCTAssertFalse(presence.hidesOnDeactivate)
	}

	func testDashboardStartsPinnedSoClickAwayDoesNotRemoveIt() throws {
		let source = try AppSourceScanner.body(of: "final class DashboardChromeState {")
		XCTAssertTrue(
			source.contains("var isPinned = true"),
			"the dashboard must start above every screen; the Settings pin is the opt-out")
	}

	func testDashboardAndTraysShareOnePresenceConfiguration() throws {
		let dashboard = try AppSourceScanner.body(of: "private func applyDashboardWindowLevel(")
		let tray = try AppSourceScanner.body(of: "func applyPinnedLevel(")
		let open = try AppSourceScanner.body(of: "func open(attachingTo parent: NSWindow)")

		XCTAssertTrue(dashboard.contains("DashboardWindowPresence.apply("))
		XCTAssertTrue(tray.contains("DashboardWindowPresence.apply("))
		XCTAssertTrue(open.contains("DashboardWindowPresence.apply("))
		XCTAssertFalse(
			open.contains("window.level ="),
			"the tray must not set its own level and skip the shared Space behavior")
	}
}
