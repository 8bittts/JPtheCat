import AppKit
import Sparkle

/// Sparkle-driven auto-update controller. Reads its feed URL + EdDSA public key from the bundled
/// `Info.plist` (`SUFeedURL` / `SUPublicEDKey`), so there is no extra runtime configuration.
///
/// Held as a singleton because Sparkle needs a long-lived updater object to run its scheduled
/// check timer (`SUEnableAutomaticChecks`). Touching `.shared` from `applicationDidFinishLaunching`
/// is enough to init it and start the timer.
///
/// It is also an `ObservableObject`: a silent background probe (`checkForUpdatesInBackground`)
/// asks Sparkle whether a newer build exists without showing any UI, and publishes the result via
/// `updateAvailable` / `latestVersion` so the Settings status dot and the menu-bar update row can
/// reflect it.
@MainActor
final class Updater: NSObject, ObservableObject {
	static let shared = Updater()

	/// True once a silent probe (or a user-initiated check) found a newer build on the feed.
	@Published private(set) var updateAvailable = false
	/// The newest version string reported by the feed, if any.
	@Published private(set) var latestVersion: String?

	private var controller: SPUStandardUpdaterController?
	private var activationPolicyBeforeUpdate: NSApplication.ActivationPolicy?
	private var elevatedWindowLevels = UpdateSessionWindowLevels()
	private var windowObserver: Any?

	private override init() {
		super.init()
		controller = SPUStandardUpdaterController(
			startingUpdater: true,
			updaterDelegate: self,
			userDriverDelegate: self
		)
	}

	/// User-initiated check (the "Check for Updates…" menu item).
	@objc func checkForUpdates() {
		presentSparkleUI()
		controller?.checkForUpdates(nil)
	}

	/// Silent probe: asks the feed whether a newer build exists without showing any Sparkle UI.
	/// The `SPUUpdaterDelegate` callbacks below publish the result. Safe to call repeatedly.
	func checkForUpdatesInBackground() {
		controller?.updater.checkForUpdateInformation()
	}

	/// True only when running from a real `.app` bundle that carries a Sparkle feed. `swift run`
	/// builds have no `SUFeedURL`. Static so callers can gate on it *without* constructing the
	/// updater (touching `.shared`) in dev builds.
	static var isConfigured: Bool {
		Bundle.main.infoDictionary?["SUFeedURL"] != nil
	}

	/// The Settings "Automatic updates" toggle binds directly here. Sparkle owns and persists this
	/// value in ITS own UserDefaults — never mirror it in `SettingsStore`, or the two sources drift.
	/// Reads `false` when the updater isn't configured (dev builds with no feed); the settings row is
	/// gated on `isConfigured` so it never renders a dead toggle. Changing it makes Sparkle reset its
	/// update cycle automatically (no manual re-scheduling needed).
	var automaticallyChecksForUpdates: Bool {
		get { controller?.updater.automaticallyChecksForUpdates ?? false }
		set { controller?.updater.automaticallyChecksForUpdates = newValue }
	}

	private func presentSparkleUI() {
		promoteToForegroundIfNeeded()
		startFloatingWindows()
	}

	private func promoteToForegroundIfNeeded() {
		let currentPolicy = NSApp.activationPolicy()
		if currentPolicy != .regular, activationPolicyBeforeUpdate == nil {
			activationPolicyBeforeUpdate = currentPolicy
			NSApp.setActivationPolicy(.regular)
		}
		// Sparkle's window appears seconds after an async feed check with no user-gesture context, so the
		// cooperative `NSApp.activate()` (+ `.activateAllWindows`, which only reorders our OWN windows)
		// cannot rise above the frontmost OTHER app and the dialog hides. Use the reliable foregrounding
		// call shared with `StatusBarController`'s reveal path (see `AppForeground`).
		AppForeground.raiseAboveOtherApps()
	}

	private func restoreActivationPolicyIfNeeded() {
		guard let activationPolicyBeforeUpdate else { return }
		NSApp.setActivationPolicy(activationPolicyBeforeUpdate)
		self.activationPolicyBeforeUpdate = nil
	}

	private func startFloatingWindows() {
		guard windowObserver == nil else { return }
		windowObserver = NotificationCenter.default.addObserver(
			forName: NSWindow.didBecomeKeyNotification,
			object: nil,
			queue: .main
		) { [weak self] notification in
			// Observer runs on `.main`; assume the main actor synchronously to reach the @MainActor helper.
			guard let window = notification.object as? NSWindow else { return }
			MainActor.assumeIsolated { self?.floatForUpdateSession(window) }
		}
	}

	private func floatForUpdateSession(_ window: NSWindow) {
		guard
			elevatedWindowLevels.noteWillFloat(
				ObjectIdentifier(window), currentLevel: window.level)
		else { return }
		window.level = .floating
	}

	private func stopFloatingWindows() {
		if let windowObserver {
			NotificationCenter.default.removeObserver(windowObserver)
			self.windowObserver = nil
		}
		for window in NSApp.windows {
			if let originalLevel = elevatedWindowLevels.levelToRestore(ObjectIdentifier(window)) {
				window.level = originalLevel
			}
		}
		elevatedWindowLevels.removeAll()
	}
}

/// The levels an update session elevated, so `stopFloatingWindows` can put each window back exactly
/// where it was. Factored out of `Updater` so the rule — and its interleaving with
/// `StatusBarController`'s reveal float — is unit-testable without constructing Sparkle's updater
/// (`UpdaterWindowLevelTests`).
///
/// [CRITICAL — regression guard] A window ALREADY at `.floating` must never have that level recorded
/// as its "original". `StatusBarController.prepareDashboardWindowLevelForReveal` promotes the
/// unpinned dashboard to `.floating` for 250 ms on EVERY reveal, and `makeKeyAndOrderFront` fires
/// `didBecomeKey` INSIDE that window. With a Sparkle session open, snapshotting the live level there
/// captured the TRANSIENT `.floating`, and the end-of-session "restore" then pinned the dashboard
/// above every other app with the pin toggle OFF. Skipping the record is also right for a genuinely
/// PINNED window: it is already floating, needs no elevation, and must stay floating afterwards.
struct UpdateSessionWindowLevels {
	private var levels: [ObjectIdentifier: NSWindow.Level] = [:]

	/// Records `currentLevel` as the window's pre-session level and reports whether the caller should
	/// now elevate it to `.floating`. An already-floating window is neither recorded nor re-elevated;
	/// a level already recorded for this session wins over any later reading.
	mutating func noteWillFloat(_ id: ObjectIdentifier, currentLevel: NSWindow.Level) -> Bool {
		guard currentLevel != .floating else { return false }
		if levels[id] == nil { levels[id] = currentLevel }
		return true
	}

	/// The level to restore at end of session, or nil when this window was never elevated.
	func levelToRestore(_ id: ObjectIdentifier) -> NSWindow.Level? { levels[id] }

	mutating func removeAll() { levels.removeAll() }
}

// Sparkle invokes these delegate callbacks on the main thread (SPUStandardUpdaterController + the
// standard user driver run their UI on main), so each is `nonisolated` to satisfy the non-isolated
// Sparkle protocols and hops back onto the main actor via `assumeIsolated` to touch the @Published
// state / @MainActor helpers. `assumeIsolated` would trap (surfacing a real bug) rather than race if
// Sparkle ever called off-main.
extension Updater: SPUUpdaterDelegate {
	nonisolated func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
		MainActor.assumeIsolated {
			updateAvailable = true
			latestVersion = item.displayVersionString
		}
	}

	nonisolated func updaterDidNotFindUpdate(_: SPUUpdater) {
		MainActor.assumeIsolated { updateAvailable = false }
	}
}

extension Updater: SPUStandardUserDriverDelegate {
	nonisolated func standardUserDriverWillShowModalAlert() {
		MainActor.assumeIsolated { presentSparkleUI() }
	}

	nonisolated func standardUserDriverWillHandleShowingUpdate(
		_ handleShowingUpdate: Bool,
		forUpdate _: SUAppcastItem,
		state _: SPUUserUpdateState
	) {
		guard handleShowingUpdate else { return }
		MainActor.assumeIsolated { presentSparkleUI() }
	}

	nonisolated func standardUserDriverWillFinishUpdateSession() {
		MainActor.assumeIsolated {
			stopFloatingWindows()
			restoreActivationPolicyIfNeeded()
		}
	}
}
