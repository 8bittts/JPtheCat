import AppKit
import JPtheCatCore

// JPtheCat is Dock-visible by default while still owning an NSStatusItem. Users can switch to a
// menu-bar-only accessory app from Settings.
// No @main / no SwiftUI App — a plain AppKit entry point.
let app = NSApplication.shared
// Drive the app appearance from the active theme rather than following the system. `ThemeManager`
// pins `.aqua` for a light theme (Sunlit Ledger) or `.darkAqua` for a dark one (Midnight Ledger) so
// the NSMenu, window chrome, and Sparkle dialogs always match the card instead of the OS setting.
// This is the foundation of the (premium) theme system — see Theme.swift. Launch runs on the main
// thread, so `assumeIsolated` lets this synchronous entry point reach the @MainActor ThemeManager.
MainActor.assumeIsolated { ThemeManager.shared.apply() }
let delegate = AppDelegate()
app.delegate = delegate
// Fold any legacy un-namespaced settings keys into the JPtheCat.* namespace ONCE, before
// UsageAlertCenter / DashboardViewModel read them (idempotent; also re-run from SettingsStore.init).
SettingsStore.migrateIfNeeded()
// Refresh an already-opted-in Claude capture block to the current revision at launch. Revision 2's
// 5-hour-only gate silently stopped writing once Claude Code began sending weekly-only payloads, and
// the Settings probe that also migrates only runs when the Live Data window opens. This never
// installs a block; it only rewrites one the user already enabled, inside its own markers.
StatuslineCapture.migrateIfNeeded()
DockIconPreference.registerDefaults()
DockIconPreference.apply(to: app)
app.run()
