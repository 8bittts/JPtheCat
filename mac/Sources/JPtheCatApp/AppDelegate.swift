import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusBar: StatusBarController?

	@MainActor
	func applicationDidFinishLaunching(_ notification: Notification) {
		guard !SingleInstanceGuard.shouldTerminateCurrentProcess() else {
			NSApp.terminate(nil)
			return
		}
		// Apple requires the UNUserNotificationCenter delegate to be assigned BEFORE the app finishes
		// launching (UNUserNotificationCenter.delegate docs). Touch the singleton here so its init sets
		// the delegate + requests authorization at launch, not lazily on the first refresh.
		_ = UsageAlertCenter.shared
		statusBar = StatusBarController()
		// JPtheCat is a normal Dock-visible app, so give it the standard top-of-screen menu bar
		// (bold "JP the Cat" app menu + Edit/Window/Help) instead of AppKit's bare default.
		NSApp.mainMenu = MainMenu.build(owner: self, includeUpdates: Updater.isConfigured)
		PerformanceInstrumentation.shared.markAppDidFinishLaunching()
		if DockIconPreference.showDockIcon() {
			statusBar?.showDashboardWindow()  // Dock-visible launch opens the main dashboard.
		}
		// Start Sparkle's scheduled-update timer, but only in a real bundle with a feed —
		// `swift run` has no SUFeedURL, so we don't construct the updater in dev.
		if Updater.isConfigured {
			_ = Updater.shared
		}
		// A Sparkle update relaunches the app but leaves the old widget extension running from its
		// deleted staging copy, so placed widgets keep the previous release's code. Retire it off-main.
		DispatchQueue.global(qos: .utility).async { WidgetExtensionRetirer.retireStaleProcesses() }
	}

	// Clicking the Dock icon always focuses the dashboard.
	@MainActor
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
		statusBar?.showDashboardWindow()
		return true
	}

	// Closing the window must NOT quit — the menu-bar item keeps the app alive.
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

	@MainActor
	func applicationWillTerminate(_ notification: Notification) {
		statusBar = nil
	}

	// Opt into secure coding for restorable state (silences the macOS 12+ Console warning).
	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

	// MARK: - Main-menu actions

	@MainActor
	@objc func checkForUpdatesFromMenu() {
		guard Updater.isConfigured else { return }
		Updater.shared.checkForUpdates()
	}

	/// Opens the dashboard window and flips it to the settings face — the standard
	/// ⌘, Settings… behavior for a Dock-visible app.
	@MainActor
	@objc func openSettingsFromMenu() {
		statusBar?.showDashboardWindow()
		NotificationCenter.default.post(name: .jpShowSettings, object: nil)
	}

	/// Help menu item — same destination as the dashboard footer help button.
	@MainActor
	@objc func openHelpFromMenu() {
		SettingsBackView.open("https://jpthecat.com")
	}
}

extension Notification.Name {
	/// Posted by the Settings… menu item; `DashboardView` flips to its settings face on receipt.
	static let jpShowSettings = Notification.Name("com.8bittts.jpthecat.showSettings")
}
