import AppKit
import Foundation

enum DockIconPreference {
	static let showDockIconKey = "JPtheCat.showDockIcon"
	static let defaultShowDockIcon = true

	static func registerDefaults(defaults: UserDefaults = .standard) {
		defaults.register(defaults: [showDockIconKey: defaultShowDockIcon])
	}

	static func showDockIcon(defaults: UserDefaults = .standard) -> Bool {
		guard let value = defaults.object(forKey: showDockIconKey) as? Bool else {
			return defaultShowDockIcon
		}
		return value
	}

	static func setShowDockIcon(_ show: Bool, defaults: UserDefaults = .standard) {
		defaults.set(show, forKey: showDockIconKey)
	}

	static func activationPolicy(showDockIcon: Bool) -> NSApplication.ActivationPolicy {
		showDockIcon ? .regular : .accessory
	}

	@MainActor
	static func apply(to app: NSApplication = .shared, defaults: UserDefaults = .standard) {
		apply(to: app, showDockIcon: showDockIcon(defaults: defaults))
	}

	@MainActor
	static func apply(to app: NSApplication = .shared, showDockIcon: Bool) {
		app.setActivationPolicy(activationPolicy(showDockIcon: showDockIcon))
		// Modern macOS updates the Dock tile immediately when the policy changes, so no active-state
		// bounce is needed. When turning the icon back ON, re-activate so the freshly added tile and
		// the settings window take focus promptly. `activate()` is the modern, non-deprecated path
		// (never `activate(ignoringOtherApps:)`). We deliberately do NOT call `NSApp.deactivate()`
		// when hiding: deactivating the app from its own settings window proved disruptive (it could
		// drop/close the window), and it isn't necessary for the tile to disappear. At launch
		// (`main.swift`) the app isn't active yet, so this activate path is a no-op there.
		if showDockIcon {
			DispatchQueue.main.async { app.activate() }
		}
	}
}
