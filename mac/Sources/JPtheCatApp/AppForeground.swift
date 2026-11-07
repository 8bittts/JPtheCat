import AppKit

/// One home for "actually raise this app above OTHER apps' windows".
///
/// **Why this exists (durable lesson).** For a menu-bar / accessory app that summons a window from the
/// background — a Sparkle update dialog that appears seconds after an async feed check, a tapped-alert
/// reveal, a status-item click — the surface MUST rise above whatever other app is frontmost. The
/// "modern" cooperative combo `NSApp.activate()` + `NSRunningApplication.current.activate(options:
/// [.activateAllWindows])` does NOT do that: `.activateAllWindows` only reorders THIS app's own windows
/// relative to each other; only the deprecated `.activateIgnoringOtherApps` (and the classic
/// `NSApp.activate(ignoringOtherApps:)`) actually rises above other apps. Relying on the modern combo
/// buried the Sparkle window behind the frontmost app — a real, user-visible regression.
///
/// Every other personal menu-bar app (movingpaper, dockishOS) uses `activate(ignoringOtherApps: true)`
/// for exactly this reason. It is only deprecated as of a FUTURE macOS (27.0), so it compiles
/// warning-free on the shipping SDK; this is the deliberate, documented exception to the app's
/// otherwise-strict "zero deprecated Apple APIs" rule. Revisit only when Apple ships a cooperative API
/// that genuinely foregrounds above other apps.
enum AppForeground {
	/// Bring the app (and its windows) in front of every other app's windows. Callers that also need to
	/// leave `.accessory` mode should flip the activation policy to `.regular` first.
	@MainActor
	static func raiseAboveOtherApps() {
		NSApp.activate(ignoringOtherApps: true)
	}
}
