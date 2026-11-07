import AppKit
import XCTest

@testable import JPtheCatApp
import JPtheCatCore

/// [Regression guard — observer teardown in the tray child windows]
/// The Advanced Analytics, Live Data and Themes trays used to be three ~90% byte-identical controllers,
/// each with its OWN copy of `open()`/`close()`. The real cost was never the line count: it was that one
/// observer-teardown path had become three, and each had to independently keep registering exactly what
/// it removes. They now share `TrayChildWindowController`.
///
/// [CRITICAL] These assertions are on a COUNTING `NotificationCenter`, never on source text. A textual
/// "close() mentions removeObserver" guard passes for a tray that registers a FOURTH observer and forgets
/// it — the exact regression the duplication invited. Counting registrations against removals fails.
final class TrayChildWindowTests: XCTestCase {
	/// Records every block-observer token handed out and removes it again on `removeObserver(_:)`, so a
	/// non-zero `liveObserverCount` after `close()` means a leaked registration.
	private final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
		private let lock = NSLock()
		nonisolated(unsafe) private var live: Set<ObjectIdentifier> = []
		nonisolated(unsafe) private var registered = 0

		var liveObserverCount: Int {
			lock.lock()
			defer { lock.unlock() }
			return live.count
		}

		/// Total registrations ever made. Proves a "nothing leaked" assertion is not vacuously green
		/// because nothing was ever registered.
		var registrationCount: Int {
			lock.lock()
			defer { lock.unlock() }
			return registered
		}

		override func addObserver(
			forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?,
			using block: @escaping @Sendable (Notification) -> Void
		) -> NSObjectProtocol {
			let token = super.addObserver(forName: name, object: obj, queue: queue, using: block)
			lock.lock()
			live.insert(ObjectIdentifier(token))
			registered += 1
			lock.unlock()
			return token
		}

		override func removeObserver(_ observer: Any) {
			super.removeObserver(observer)
			guard let object = observer as AnyObject? else { return }
			lock.lock()
			live.remove(ObjectIdentifier(object))
			lock.unlock()
		}
	}

	private struct TrayCase {
		let name: String
		let controller: TrayChildWindowController
		/// Each case owns its OWN counting center. `registrationCount` is a lifetime total by design, so
		/// one center shared across the three controllers made the second and third cases compare a
		/// running total (6, then 10) against a per-controller expectation.
		let center: CountingNotificationCenter
		/// Observers this tray registers per open: three shared + any of its own.
		let expectedObservers: Int
	}

	@MainActor
	private func trayCases() -> [TrayCase] {
		let chrome = DashboardChromeState()
		let themesCenter = CountingNotificationCenter()
		let liveDataCenter = CountingNotificationCenter()
		let analyticsCenter = CountingNotificationCenter()
		return [
			TrayCase(
				name: "Themes",
				controller: ThemesWindowController(
					dashboardChrome: chrome, notificationCenter: themesCenter),
				center: themesCenter,
				expectedObservers: 3),
			TrayCase(
				name: "Live data",
				controller: LiveDataWindowController(
					model: DashboardViewModel(index: nil), dashboardChrome: chrome,
					notificationCenter: liveDataCenter),
				center: liveDataCenter,
				expectedObservers: 3),
			TrayCase(
				name: "Advanced Analytics",
				controller: AdvancedAnalyticsWindowController(
					index: nil, pricing: PricingTable(models: [:]), dashboardChrome: chrome,
					notificationCenter: analyticsCenter),
				center: analyticsCenter,
				expectedObservers: 3),
		]
	}

	@MainActor
	private func makeParentWindow() -> NSWindow {
		NSWindow(
			contentRect: NSRect(x: 200, y: 200, width: 420, height: 600),
			styleMask: [.titled, .closable], backing: .buffered, defer: true)
	}

	/// The invariant the three clones each had to uphold alone: every observer registered in `open()` is
	/// removed in `close()`, with nothing left live on the center.
	@MainActor
	func testEveryTrayControllerRemovesEveryObserverItRegistered() throws {
		for trayCase in trayCases() {
			let center = trayCase.center
			let parent = makeParentWindow()

			trayCase.controller.open(attachingTo: parent)
			XCTAssertTrue(trayCase.controller.isOpen, "\(trayCase.name) did not open")
			XCTAssertEqual(
				center.liveObserverCount, trayCase.expectedObservers,
				"\(trayCase.name) registered an unexpected number of observers")

			trayCase.controller.close()
			XCTAssertFalse(trayCase.controller.isOpen, "\(trayCase.name) stayed open after close()")
			XCTAssertEqual(
				center.liveObserverCount, 0,
				"""
				\(trayCase.name) leaked a notification observer across close(). Every observer registered \
				in open() must be removed in close() and its token nil'd — a subclass observer belongs in \
				willTearDown().
				""")
			XCTAssertEqual(
				center.registrationCount, trayCase.expectedObservers,
				"\(trayCase.name) registered nothing — the teardown assertion above would be vacuous")
		}
	}

	/// The same teardown must run when AppKit closes the window itself (red traffic light / Escape), not
	/// only when the controller is asked to close. `TrayWindow` is its own delegate for exactly this.
	@MainActor
	func testAppKitClosingTheWindowRunsTheSameTeardown() throws {
		for trayCase in trayCases() {
			let center = trayCase.center
			let parent = makeParentWindow()
			trayCase.controller.open(attachingTo: parent)

			let tray = try XCTUnwrap(
				parent.childWindows?.first, "\(trayCase.name) was not attached as a child window")
			tray.close()

			XCTAssertFalse(
				trayCase.controller.isOpen,
				"\(trayCase.name) kept stale state after AppKit's own close path")
			XCTAssertEqual(
				center.liveObserverCount, 0,
				"\(trayCase.name) leaked an observer when closed by AppKit rather than by the controller")
			// Re-entrant close must be a guaranteed no-op (`close()` nils `trayWindow` first).
			trayCase.controller.close()
			XCTAssertEqual(center.liveObserverCount, 0)
		}
	}

	/// Each tray is a real AppKit CHILD of the dashboard window (so Quit/Dock-hide/close/ordering
	/// propagate for free), and detaches cleanly on close.
	@MainActor
	func testEachTrayAttachesAndDetachesAsAChildWindow() throws {
		for trayCase in trayCases() {
			let parent = makeParentWindow()
			XCTAssertEqual(parent.childWindows?.count ?? 0, 0)

			trayCase.controller.open(attachingTo: parent)
			XCTAssertEqual(
				parent.childWindows?.count ?? 0, 1,
				"\(trayCase.name) must attach via addChildWindow(_:ordered:)")

			trayCase.controller.close()
			XCTAssertEqual(
				parent.childWindows?.count ?? 0, 0,
				"\(trayCase.name) must removeChildWindow on close")
		}
	}

	/// Opening twice must not stack a second window or a second set of observers.
	@MainActor
	func testReopeningAnAlreadyOpenTrayIsANoOp() throws {
		let center = CountingNotificationCenter()
		let controller = ThemesWindowController(
			dashboardChrome: DashboardChromeState(), notificationCenter: center)
		let parent = makeParentWindow()

		controller.open(attachingTo: parent)
		controller.open(attachingTo: parent)

		XCTAssertEqual(center.registrationCount, 3)
		XCTAssertEqual(parent.childWindows?.count ?? 0, 1)
		controller.close()
		XCTAssertEqual(center.liveObserverCount, 0)
	}

	/// The structural half: all three trays must keep sharing the ONE window implementation. A tray that
	/// re-inlines its own `NSPanel` + observer set is how the clone drift started.
	func testAllThreeTraysShareTheOneWindowImplementation() throws {
		for subclass in [
			"final class ThemesWindowController: TrayChildWindowController",
			"final class LiveDataWindowController: TrayChildWindowController",
			"final class AdvancedAnalyticsWindowController: TrayChildWindowController",
		] {
			XCTAssertEqual(
				try AppSourceScanner.occurrences(of: subclass), 1,
				"\(subclass) must stay a subclass of the shared tray controller")
		}

		XCTAssertEqual(
			try AppSourceScanner.occurrences(of: "class TrayWindow: NSPanel, NSWindowDelegate"), 1,
			"""
			Exactly ONE tray NSPanel implementation may exist. Three copies of it (and of the observer \
			teardown beside it) is the duplication this controller was collapsed to remove.
			""")
	}

	/// The Advanced Analytics provider chips render from inside a SwiftUI `body`, so a raw
	/// `NSImage(contentsOf:)` there re-decodes the SVG on every hover and every refresh. It must route
	/// through the memoized loader (`AppResourcesIconCacheTests` guards the loader itself).
	func testAnalyticsProviderMarkLoadsThroughTheMemoizedIconCache() throws {
		let body = try AppSourceScanner.member("var body: some View", of: "AnalyticsProviderMark")

		XCTAssertTrue(body.contains("AppResources.icon(named: resourceName)"))
		XCTAssertFalse(
			try AppSourceScanner.typeSurface("AnalyticsProviderMark").contains("NSImage(contentsOf:"),
			"AnalyticsProviderMark must never decode a provider mark itself")
	}
}
