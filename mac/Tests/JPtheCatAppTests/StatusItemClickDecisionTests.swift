import XCTest

@testable import JPtheCatApp

/// Guards the status-item plain-click toggle rule against both shipped regressions:
/// - keyed on `NSWindow.isVisible` alone, a click closed a dashboard BURIED behind another app, so a
///   second click was needed to reveal it;
/// - keyed on `NSApp.isActive` alone, macOS 27 never reported JP active after a status-item click,
///   so a click on the dashboard in front re-revealed it instead of closing it.
final class StatusItemClickDecisionTests: XCTestCase {
	func testDismissesWhenFrontmostAppWithVisibleDashboard() {
		XCTAssertTrue(
			StatusItemClickDecision.shouldDismiss(
				isVisible: true, isMiniaturized: false, appActive: true, coveredByOtherApp: false))
	}

	func testDismissesUncoveredDashboardEvenWhenAppNeverBecameActive() {
		// macOS 27: the status-item click does not activate JP, but the dashboard is in front.
		XCTAssertTrue(
			StatusItemClickDecision.shouldDismiss(
				isVisible: true, isMiniaturized: false, appActive: false, coveredByOtherApp: false))
	}

	func testRevealsBuriedDashboardInsteadOfClosingIt() {
		XCTAssertFalse(
			StatusItemClickDecision.shouldDismiss(
				isVisible: true, isMiniaturized: false, appActive: false, coveredByOtherApp: true))
	}

	func testRevealsMiniaturizedOrClosedDashboard() {
		XCTAssertFalse(
			StatusItemClickDecision.shouldDismiss(
				isVisible: true, isMiniaturized: true, appActive: true, coveredByOtherApp: false))
		XCTAssertFalse(
			StatusItemClickDecision.shouldDismiss(
				isVisible: false, isMiniaturized: false, appActive: true, coveredByOtherApp: false))
		XCTAssertFalse(
			StatusItemClickDecision.shouldDismiss(
				isVisible: false, isMiniaturized: false, appActive: false, coveredByOtherApp: false))
	}

	private let dashboard = CGRect(x: 1000, y: 30, width: 400, height: 600)
	private let ownPID: pid_t = 42

	func testOtherAppNormalWindowOverlappingDashboardCoversIt() {
		let above = [StatusItemClickDecision.WindowAbove(ownerPID: 7, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1200, height: 800))]
		XCTAssertTrue(StatusItemClickDecision.isCovered(frame: dashboard, by: above, ownPID: ownPID))
	}

	func testMenuBarDockOwnWindowsAndNonOverlappingWindowsDoNotCover() {
		let above = [
			// Menu bar / status items sit on higher layers.
			StatusItemClickDecision.WindowAbove(ownerPID: 7, layer: 25, bounds: CGRect(x: 0, y: 0, width: 3000, height: 40)),
			// JP's own Advanced Analytics tray.
			StatusItemClickDecision.WindowAbove(ownerPID: ownPID, layer: 0, bounds: dashboard),
			// Another app's window beside the dashboard, not over it.
			StatusItemClickDecision.WindowAbove(ownerPID: 7, layer: 0, bounds: CGRect(x: 0, y: 0, width: 900, height: 800)),
			// Fully transparent overlay.
			StatusItemClickDecision.WindowAbove(ownerPID: 7, layer: 0, alpha: 0, bounds: dashboard),
		]
		XCTAssertFalse(StatusItemClickDecision.isCovered(frame: dashboard, by: above, ownPID: ownPID))
	}

	func testWindowInfoDictionaryDecodes() {
		let info: [String: Any] = [
			kCGWindowOwnerPID as String: 7,
			kCGWindowLayer as String: 0,
			kCGWindowAlpha as String: 1.0,
			kCGWindowBounds as String: CGRect(x: 1, y: 2, width: 3, height: 4).dictionaryRepresentation,
		]
		XCTAssertEqual(
			StatusItemClickDecision.WindowAbove(info: info),
			StatusItemClickDecision.WindowAbove(ownerPID: 7, layer: 0, bounds: CGRect(x: 1, y: 2, width: 3, height: 4)))
	}
}
