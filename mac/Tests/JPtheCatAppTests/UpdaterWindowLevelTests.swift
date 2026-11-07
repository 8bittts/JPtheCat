import AppKit
import XCTest

@testable import JPtheCatApp

/// A Sparkle update session elevates every window that becomes key to `.floating` and restores each
/// one when the session ends. `UpdateSessionWindowLevels` owns what gets remembered, factored out of
/// `Updater` so the rule is testable without constructing Sparkle's updater.
final class UpdaterWindowLevelTests: XCTestCase {
	/// Stands in for an `NSWindow` identity; only `ObjectIdentifier` is ever used.
	private final class WindowStandIn {}

	/// [Regression guard] The reachable bug this fixes: with a Sparkle session open, clicking the
	/// menu-bar icon runs `StatusBarController.prepareDashboardWindowLevelForReveal`, which promotes
	/// an UNPINNED dashboard to `.floating` for 250 ms, and the `makeKeyAndOrderFront` on the very next
	/// line fires `didBecomeKey` INSIDE that window. Snapshotting the live level there recorded the
	/// TRANSIENT `.floating` as the window's "original", so the end-of-session restore put the
	/// dashboard back to `.floating` — above every other app, with the pin toggle OFF, until something
	/// else reset it.
	func testATransientRevealFloatIsNeverRecordedAsTheOriginalLevel() {
		let dashboard = ObjectIdentifier(WindowStandIn())
		var session = UpdateSessionWindowLevels()

		// Unpinned dashboard sitting at .normal, then revealed: the controller floats it for 250 ms...
		var level = NSWindow.Level.normal
		level = .floating  // prepareDashboardWindowLevelForReveal
		// ...and makeKeyAndOrderFront fires didBecomeKey right inside that window.
		if session.noteWillFloat(dashboard, currentLevel: level) { level = .floating }
		// The controller's asyncAfter lands and drops it back.
		level = .normal

		XCTAssertNil(
			session.levelToRestore(dashboard),
			"a transient .floating must never be captured as the level to restore")

		// End of the Sparkle session: nothing to restore, so the window keeps the level the controller
		// legitimately left it at.
		if let restore = session.levelToRestore(dashboard) { level = restore }
		XCTAssertEqual(
			level, .normal,
			"an unpinned dashboard must NOT be left floating above every other app after an update session")
	}

	func testAWindowAtNormalIsElevatedAndRestoredExactly() {
		let window = ObjectIdentifier(WindowStandIn())
		var session = UpdateSessionWindowLevels()
		var level = NSWindow.Level.normal

		XCTAssertTrue(session.noteWillFloat(window, currentLevel: level))
		level = .floating
		XCTAssertEqual(session.levelToRestore(window), .normal)

		if let restore = session.levelToRestore(window) { level = restore }
		XCTAssertEqual(level, .normal)
	}

	/// A PINNED dashboard is genuinely `.floating` and must stay that way after the session — the same
	/// skip that fixes the transient case is the correct behavior here too: nothing to elevate,
	/// nothing to restore.
	func testAPinnedFloatingWindowIsNeitherElevatedNorRestored() {
		let window = ObjectIdentifier(WindowStandIn())
		var session = UpdateSessionWindowLevels()
		var level = NSWindow.Level.floating

		XCTAssertFalse(session.noteWillFloat(window, currentLevel: level))
		XCTAssertNil(session.levelToRestore(window))

		if let restore = session.levelToRestore(window) { level = restore }
		XCTAssertEqual(level, .floating, "a pinned window must stay pinned after the update session")
	}

	/// Sparkle's own panels legitimately sit above `.normal`; whatever level they arrive at is the one
	/// that must come back, and only the FIRST reading counts — later key events see the level the
	/// session itself imposed.
	func testTheFirstRecordedLevelWinsAcrossRepeatedKeyEvents() {
		let window = ObjectIdentifier(WindowStandIn())
		var session = UpdateSessionWindowLevels()

		XCTAssertTrue(session.noteWillFloat(window, currentLevel: .statusBar))
		XCTAssertEqual(session.levelToRestore(window), .statusBar)
		// Session dropped it to .normal in between; the original must not be overwritten.
		XCTAssertTrue(session.noteWillFloat(window, currentLevel: .normal))
		XCTAssertEqual(session.levelToRestore(window), .statusBar)
	}

	func testEachWindowIsTrackedIndependentlyAndClearedWithTheSession() {
		// Hold both stand-ins alive: a freed object's address can be reused, and the two identifiers
		// would then collide.
		let firstWindow = WindowStandIn()
		let secondWindow = WindowStandIn()
		let first = ObjectIdentifier(firstWindow)
		let second = ObjectIdentifier(secondWindow)
		var session = UpdateSessionWindowLevels()

		XCTAssertTrue(session.noteWillFloat(first, currentLevel: .normal))
		XCTAssertTrue(session.noteWillFloat(second, currentLevel: .modalPanel))
		XCTAssertEqual(session.levelToRestore(first), .normal)
		XCTAssertEqual(session.levelToRestore(second), .modalPanel)

		session.removeAll()
		XCTAssertNil(session.levelToRestore(first))
		XCTAssertNil(session.levelToRestore(second))
		withExtendedLifetime((firstWindow, secondWindow)) {}
	}

	/// The snapshot must not creep back into `Updater` as a raw `window.level` read: the whole bug was
	/// that a live level reading is not the same thing as an "original" level.
	func testUpdaterRoutesTheFloatDecisionThroughThePolicyRatherThanReadingTheLiveLevel() throws {
		let float = try AppSourceScanner.body(of: "private func floatForUpdateSession(")
		XCTAssertTrue(float.contains("noteWillFloat("))
		XCTAssertFalse(
			float.contains("] = window.level"),
			"never snapshot the live level directly — route it through UpdateSessionWindowLevels")

		let stop = try AppSourceScanner.body(of: "private func stopFloatingWindows(")
		XCTAssertTrue(stop.contains("levelToRestore("))
	}

	/// The premise of the interleaving: the reveal float really is transient and really does happen
	/// before the key notification. If either half changes, this test should be re-read, not deleted.
	func testTheDashboardRevealFloatIsTransientAndPrecedesTheKeyNotification() throws {
		let prepare = try AppSourceScanner.body(of: "private func prepareDashboardWindowLevelForReveal(")
		XCTAssertTrue(prepare.contains("window.level = .floating"))
		XCTAssertTrue(prepare.contains("window.level = .normal"))

		let reveal = try AppSourceScanner.body(of: "func showDashboardWindow(")
		let floatCall = try XCTUnwrap(reveal.range(of: "prepareDashboardWindowLevelForReveal(window)"))
		let keyCall = try XCTUnwrap(reveal.range(of: "window.makeKeyAndOrderFront(nil)"))
		XCTAssertLessThan(
			floatCall.lowerBound, keyCall.lowerBound,
			"the transient float is applied BEFORE the window is made key — that ordering is the bug's trigger")
	}
}
