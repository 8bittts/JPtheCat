import AppKit
import AVFoundation
import JPtheCatCore
// UserNotifications isn't fully Sendable-annotated by Apple; `@preconcurrency` keeps its non-Sendable
// completion-handler captures (UNUserNotificationCenter / UNNotificationRequest) from tripping the
// strict-concurrency warnings under Swift 6 language mode.
@preconcurrency import UserNotifications

/// Fires a standard macOS notification banner + a JP meow as a provider's usage window ESCALATES: the
/// first crossing of 80% (warning), the first crossing of 95% (critical), and — for Claude only — the
/// inferred "you're likely frozen at the limit" (see `UsageAlertGate`). Two independent output channels
/// sit under one master switch, all user-toggleable in Settings and defaulting on: `usageEnabled` is the
/// master ("watch for crossings"), `bannerEnabled` is the on-screen visual banner, and `soundEnabled`
/// is the meow gated by the global interactive-sounds master. Turning the banner off leaves meow-only
/// alerts when sounds are globally enabled, and vice versa. Evaluated once per refresh by
/// `StatusBarController`. A singleton so Settings (test meow / re-request authorization) and the refresh
/// loop share the gates + one cached sound. Every escalation rides these SAME toggles — no new Settings
/// row, no new entitlement, and authorization stays `[.alert]`-only (the banner is deliberately silent).
final class UsageAlertCenter: NSObject, UNUserNotificationCenterDelegate {
	nonisolated(unsafe) static let shared = UsageAlertCenter()
	static let testMeowNotificationTitle = "JP the Cat"
	static let testMeowNotificationBody = "JP says meow. Test sound worked."
	static let testMeowNotificationIdentifierPrefix = "jpthecat.test-meow."

	/// First crossing of this % raises the warning alert; the critical alert escalates at the higher
	/// tier. Mirrors the pill's attention thresholds (`MenuBarLabelRenderer.attentionState`).
	static let warningThreshold: Double = 80
	static let criticalThreshold: Double = 95
	/// The gate window-tag for Claude's inferred frozen-at-limit alert (never a real 5h/weekly window).
	static let limitHitWindowTag = "limit-hit"

	// Three independent rising-edge gates so an escalating provider fires at MOST one banner per tier per
	// window: 80% (warning), 95% (critical), and Claude's inferred frozen-at-limit. Each owns its own
	// fired-set, so a shared `(id, window, reset)` key never cross-suppresses between tiers.
	private var warningGate = UsageAlertGate(threshold: UsageAlertCenter.warningThreshold)
	private var criticalGate = UsageAlertGate(threshold: UsageAlertCenter.criticalThreshold)
	private var limitHitGate = UsageAlertGate(threshold: 1)
	private var meowPlayer: AVAudioPlayer?
	private var authRequested = false
	private let notificationsSupported: Bool
	/// Set by `StatusBarController` so tapping an alert opens the dashboard (handling the notification
	/// response is the other half of the `UNUserNotificationCenterDelegate` contract).
	var onActivate: (() -> Void)?

	static func supportsUserNotifications(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
		bundleURL.pathExtension == "app"
	}

	private override init() {
		notificationsSupported = Self.supportsUserNotifications()
		super.init()
		guard notificationsSupported else { return }
		UNUserNotificationCenter.current().delegate = self
		// Defer the initial auth request onto the main actor. Reach it through the (app-lifetime)
		// singleton rather than capturing `self`, so this non-Sendable type isn't sent across the hop;
		// the Task body runs after init returns, by which point `shared` is assigned.
		Task { @MainActor in UsageAlertCenter.shared.requestBannerAuthorizationIfNeeded() }
	}

	// Read the alert toggles from the single source of truth (`SettingsStore`'s namespaced keys, with
	// their defaults). The nonisolated static accessors keep this non-main-actor type off the main actor.
	var usageEnabled: Bool { SettingsStore.usageAlertsEnabled() }
	var bannerEnabled: Bool { SettingsStore.alertBannerEnabled() }
	var soundEnabled: Bool { Self.soundOutputEnabled() }

	static func shouldRequestBannerAuthorization(usageEnabled: Bool, bannerEnabled: Bool) -> Bool {
		usageEnabled && bannerEnabled
	}

	static func soundOutputEnabled(defaults: UserDefaults = .standard) -> Bool {
		SettingsStore.interactiveSoundsEnabled(defaults) && SettingsStore.alertSoundEnabled(defaults)
	}

	/// Ask once (idempotent). Called only through `requestBannerAuthorizationIfNeeded()` so we never
	/// prompt for notification permission unless the user actually wants the visual banner.
	func requestAuthorization() {
		guard notificationsSupported, !authRequested else { return }
		authRequested = true
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
	}

	/// Requests notification authorization only when banners are actually wanted (master on + banner
	/// on). Idempotent; safe to call on launch and whenever the master or banner toggle flips.
	/// Meow-only users (banner off) are never shown a notification-permission prompt.
	@MainActor func requestBannerAuthorizationIfNeeded() {
		guard Self.shouldRequestBannerAuthorization(usageEnabled: usageEnabled, bannerEnabled: bannerEnabled)
		else { return }
		requestAuthorization()
	}

	/// Whether the "Show notification banner" row should warn that macOS is suppressing the banner. The
	/// user wants banners (master + banner on) AND macOS will silently drop them because EITHER the OS
	/// denied notifications OR — the subtler case — the app is still `.authorized`/`.provisional` but its
	/// on-screen alert style was set to "None" in System Settings (`UNAlertStyle.none`), so nothing ever
	/// appears. Pure so it is asserted without spinning up `UNUserNotificationCenter`.
	static func bannerDenialWarrants(
		authorizationStatus: UNAuthorizationStatus,
		alertStyle: UNAlertStyle,
		usageEnabled: Bool,
		bannerEnabled: Bool
	) -> Bool {
		guard usageEnabled, bannerEnabled else { return false }
		if authorizationStatus == .denied { return true }
		// Authorized/provisional but the on-screen style is "None" → the OS delivers nothing to the
		// screen even though we're technically allowed. `alertStyle` (NOT `alertSetting`, which stays
		// `.enabled` for the None style) carries this; see UNNotificationSettings.alertStyle.
		if (authorizationStatus == .authorized || authorizationStatus == .provisional),
			alertStyle == .none {
			return true
		}
		return false
	}

	/// Reads the live OS notification presentation state (authorization status + on-screen alert style)
	/// so the Settings face can surface a silently-suppressed banner. Returns `(.notDetermined, .none)`
	/// outside a real app bundle — raw SwiftPM/dev launches have no LaunchServices bundle proxy and must
	/// never touch `UNUserNotificationCenter.current()`. Returns only `Sendable` enums (never the
	/// non-Sendable `UNNotificationSettings`), and `.notDetermined` never warrants a warning, so a dev
	/// launch can't show a false affordance.
	func currentBannerPresentation() async -> (status: UNAuthorizationStatus, alertStyle: UNAlertStyle) {
		guard notificationsSupported else { return (.notDetermined, .none) }
		let settings = await UNUserNotificationCenter.current().notificationSettings()
		return (settings.authorizationStatus, settings.alertStyle)
	}

	/// One provider window eligible to raise a usage alert.
	struct AlertableWindow: Equatable {
		let id: String
		let name: String
		let window: String
		let pct: Double?
		let reset: Date?
	}

	/// The provider windows that may fire this refresh. ONLY fully-`available` rows qualify: an
	/// `unavailable` row carries no data, and a `stale` row carries last-good percentages whose window may
	/// already have rolled — neither may raise a fresh alert. Pure + `static` so the exclusion is asserted
	/// behaviorally without spinning up `UNUserNotificationCenter`.
	static func alertableWindows(rows: [DashboardViewModel.ProviderRow]) -> [AlertableWindow] {
		rows.filter { $0.availability == .available && $0.isAggregable }.flatMap { row in
			[
				AlertableWindow(id: row.id, name: row.name, window: "5-hour", pct: row.usedPct, reset: row.resetsAt5h),
				AlertableWindow(id: row.id, name: row.name, window: "weekly", pct: row.weeklyUsedPct, reset: row.resetsAtWeekly),
			]
		}
	}

	/// An escalating alert kind. Each maps to a DISTINCT notification-identifier suffix so the banners
	/// for one window are independent deliveries — Apple replaces a request whose identifier matches an
	/// already-delivered one, so a shared identifier would silently overwrite the earlier banner.
	enum AlertTier {
		case warning   // first crossing of 80%
		case critical  // first crossing of 95%
		case limitHit  // Claude inferred frozen-at-limit (statusline went quiet at a high reading)

		var identifierSuffix: String {
			switch self {
			case .warning: return ""  // unchanged from the original single-tier identifier
			case .critical: return ":95"
			case .limitHit: return ":limit-hit"
			}
		}

		func body(name: String, window: String, pct: Double) -> String {
			switch self {
			case .warning, .critical:
				return UsageAlertCenter.alertBody(name: name, window: window, pct: pct)
			case .limitHit:
				return "\(name): likely at your limit — the reading is frozen at \(Int(pct.rounded()))%."
			}
		}
	}

	/// The warning/critical banner body, whose trailing clause TIERS on the rounded percentage so a
	/// reading at 100% never reads "you're close to the limit". Uses the SAME `Int(pct.rounded())` the
	/// body prints, so the number and its phrasing can never disagree. Pure + static → unit-testable.
	static func alertBody(name: String, window: String, pct: Double) -> String {
		let rounded = Int(pct.rounded())
		let tail: String
		if rounded >= 100 { tail = "you're at your limit." }
		else if rounded >= 95 { tail = "you're basically out." }
		else if rounded >= 90 { tail = "you're almost out." }
		else { tail = "you're close to the limit." }
		return "\(name) \(window) usage at \(rounded)% — \(tail)"
	}

	/// The per-tier notification identifier — distinct across tiers for one window so warning / critical
	/// / limit-hit banners coexist instead of overwriting one another. Pure + static so the distinctness
	/// is asserted without the singleton; `.warning` intentionally preserves the original identifier.
	static func notificationIdentifier(
		tier: AlertTier, id: String, displayWindow: String, reset: Date?
	) -> String {
		UsageAlertGate.key(id: id, window: displayWindow + tier.identifierSuffix, reset: reset)
	}

	/// Checks every available provider's 5-hour and weekly window and raises an ESCALATING, one-shot
	/// alert: 80% (warning) then 95% (critical), plus Claude's inferred frozen-at-limit. All ride the
	/// same Alerts toggles; each tier fires at most once per window instance and re-arms when it rolls.
	/// Prunes already-reset window keys from EVERY tier's gate first so the `fired` sets stay bounded to
	/// the handful of currently-live windows on this app-lifetime singleton, instead of growing one dead
	/// key per crossing per tier for the life of the process (see `UsageAlertGate.pruneExpired`).
	@MainActor func evaluate(rows: [DashboardViewModel.ProviderRow], now: Date = Date()) {
		guard usageEnabled else { return }
		warningGate.pruneExpired(now: now)
		criticalGate.pruneExpired(now: now)
		limitHitGate.pruneExpired(now: now)
		for window in Self.alertableWindows(rows: rows) {
			// Consult the warning gate every refresh so its fired/re-arm state stays correct, but POST the
			// warning banner only in the 80–95 band: a cold launch already ≥95 then shows ONE (critical)
			// banner, not a redundant "close to the limit" + "basically out" pair.
			let warningArmed = warningGate.shouldFire(
				id: window.id, window: window.window, pct: window.pct, reset: window.reset)
			guard let pct = window.pct else { continue }
			if pct >= Self.criticalThreshold {
				if criticalGate.shouldFire(
					id: window.id, window: window.window, pct: window.pct, reset: window.reset) {
					postAlert(
						tier: .critical, name: window.name, id: window.id,
						displayWindow: window.window, pct: pct, reset: window.reset)
				}
			} else if warningArmed {
				postAlert(
					tier: .warning, name: window.name, id: window.id,
					displayWindow: window.window, pct: pct, reset: window.reset)
			}
		}
		// Claude only: when you actually hit the limit its statusline freezes at the last pre-limit % and
		// goes quiet, so the honest signal is "likely at your limit (reading frozen)" — the moment an
		// alert is most useful. Fire once per 5-hour window (its own gate + a distinct identifier); never
		// a repeating "still blocked" nag. Codex never sets `limitLikelyHit`, so this is Claude-scoped.
		for row in rows where row.availability == .available && row.limitLikelyHit {
			if limitHitGate.shouldFire(
				id: row.id, window: Self.limitHitWindowTag, pct: 100, reset: row.resetsAt5h) {
				postAlert(
					tier: .limitHit, name: row.name, id: row.id,
					displayWindow: "5-hour", pct: row.usedPct ?? 0, reset: row.resetsAt5h)
			}
		}
	}

	/// Fires one alert for a tier: JP's meow (when `soundEnabled`) and, when the visual banner is opted
	/// in (`bannerEnabled` + a real bundle), a SILENT macOS banner. Provider names use the SHORT label
	/// ("Claude", not "Claude Code") to match the menu-bar pill.
	private func postAlert(
		tier: AlertTier, name: String, id: String, displayWindow: String, pct: Double, reset: Date?
	) {
		if soundEnabled { playMeow() }
		// The visual banner is its own opt-out channel; meow-only alerts skip here.
		guard bannerEnabled, notificationsSupported else { return }
		let content = UNMutableNotificationContent()
		content.title = "JP the Cat"
		content.body = tier.body(name: ProviderDescriptor.shortName(forName: name), window: displayWindow, pct: pct)
		content.sound = nil  // JP's meow is the audible cue; keep the banner itself silent
		UNUserNotificationCenter.current().add(
			UNNotificationRequest(
				identifier: Self.notificationIdentifier(
					tier: tier, id: id, displayWindow: displayWindow, reset: reset),
				content: content, trigger: nil))
	}

	/// The packaged JP meow. Static so tests can assert the resource is bundled without touching the
	/// singleton (which would spin up UNUserNotificationCenter).
	static var meowSoundURL: URL? {
		AppResources.url(forResource: "jp-meow", withExtension: "m4a")
	}

	static func makeMeowPlayer() -> AVAudioPlayer? {
		guard let url = meowSoundURL else { return nil }
		do {
			let player = try AVAudioPlayer(contentsOf: url)
			player.numberOfLoops = 0
			player.volume = 1
			player.prepareToPlay()
			return player
		} catch {
			return nil
		}
	}

	/// Plays the packaged JP meow (`jp-meow.m4a`). Used for real alerts and the Settings "Test meow".
	@discardableResult
	func playMeow() -> Bool {
		if meowPlayer == nil {
			meowPlayer = Self.makeMeowPlayer()
		}
		guard let meowPlayer else { return false }
		if meowPlayer.isPlaying {
			meowPlayer.stop()
		}
		meowPlayer.currentTime = 0
		meowPlayer.prepareToPlay()
		return meowPlayer.play()
	}

	func playTestMeowFeedback() {
		// Test meow reproduces the real 80%/95% alert meow, so it gates on the alert's own
		// "Meow on alerts" toggle (alertSoundEnabled) — still under the global "Interactive sounds"
		// master, which can mute every cue. Gating on the master alone made Test meow silent for
		// users who kept "Meow on alerts" on but turned "Interactive sounds" off.
		if SettingsStore.alertSoundEnabled(), SettingsStore.interactiveSoundsEnabled() {
			playMeow()
		}
		postTestMeowNotification()
	}

	/// System Settings deep link to JP the Cat's notification pane (same route as the banner row's
	/// "Turn on in System Settings" affordance).
	static let notificationSettingsURL = URL(
		string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

	/// Posts the "Test meow" banner and — crucially — never fails SILENTLY. macOS only shows the banner
	/// when the user has authorized notifications, so route by the LIVE status: authorized → show;
	/// notDetermined → prompt then show (or route on refusal); denied → open System Settings so the user
	/// can turn banners on. Previously a `.denied` status just dropped the notification with zero
	/// feedback, which read as "Test meow does nothing" (the reported bug).
	private func postTestMeowNotification() {
		guard notificationsSupported else { return }
		let content = UNMutableNotificationContent()
		content.title = Self.testMeowNotificationTitle
		content.body = Self.testMeowNotificationBody
		content.sound = nil
		let request = UNNotificationRequest(
			identifier: "\(Self.testMeowNotificationIdentifierPrefix)\(UUID().uuidString)",
			content: content, trigger: nil)
		let center = UNUserNotificationCenter.current()
		center.getNotificationSettings { settings in
			switch settings.authorizationStatus {
			case .authorized, .provisional, .ephemeral:
				center.add(request)
			case .notDetermined:
				center.requestAuthorization(options: [.alert]) { granted, _ in
					if granted { center.add(request) } else { Self.openNotificationSettings() }
				}
			case .denied:
				Self.openNotificationSettings()
			@unknown default:
				center.add(request)
			}
		}
	}

	private static func openNotificationSettings() {
		DispatchQueue.main.async { NSWorkspace.shared.open(notificationSettingsURL) }
	}

	// Show the banner even when JPtheCat happens to be the frontmost app.
	func userNotificationCenter(
		_: UNUserNotificationCenter, willPresent _: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.banner, .list])
	}

	// Tapping the alert opens the dashboard. Must call the completion handler when done (Apple).
	func userNotificationCenter(
		_: UNUserNotificationCenter, didReceive _: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		// UNUserNotificationCenter invokes its delegate on the main thread (same as `willPresent` above,
		// which calls its handler synchronously), so run inline — no cross-thread send of the
		// non-Sendable completion handler.
		onActivate?()  // showDashboardWindow(forceForeground:) raises above other apps (AppForeground)
		completionHandler()
	}
}
