import XCTest
import JPtheCatCore
import UserNotifications

@testable import JPtheCatApp

final class UsageAlertGateTests: XCTestCase {
	func testFiresOnceOnFirstCrossingThenStaysQuiet() {
		var gate = UsageAlertGate()
		let reset = Date(timeIntervalSince1970: 1_000_000)
		XCTAssertFalse(gate.shouldFire(id: "codex", window: "5-hour", pct: 62, reset: reset))
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 80, reset: reset))  // crossing
		XCTAssertFalse(gate.shouldFire(id: "codex", window: "5-hour", pct: 91, reset: reset))  // steady
		XCTAssertFalse(gate.shouldFire(id: "codex", window: "5-hour", pct: 100, reset: reset))
	}

	func testNewWindowResetReArms() {
		var gate = UsageAlertGate()
		let first = Date(timeIntervalSince1970: 1_000_000)
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: first))
		// Same window → quiet.
		XCTAssertFalse(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: first))
		// Window rolled (new reset) → fires again.
		let next = Date(timeIntervalSince1970: 1_018_000)
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: next))
	}

	func testDroppingBelowReArmsSameWindow() {
		var gate = UsageAlertGate()
		let reset = Date(timeIntervalSince1970: 1_000_000)
		XCTAssertTrue(gate.shouldFire(id: "claude", window: "weekly", pct: 80, reset: reset))
		XCTAssertFalse(gate.shouldFire(id: "claude", window: "weekly", pct: 40, reset: reset))  // dropped, re-arm
		XCTAssertTrue(gate.shouldFire(id: "claude", window: "weekly", pct: 82, reset: reset))  // fires again
	}

	func testPruneExpiredDropsRolledWindowKeysSoTheSetStaysBounded() {
		var gate = UsageAlertGate()
		// Cross 80% in three successive 5-hour windows (each a new reset epoch). Without pruning, all
		// three keys linger forever on the app-lifetime singleton — one dead key per crossing.
		let r1 = Date(timeIntervalSince1970: 1_000_000)
		let r2 = Date(timeIntervalSince1970: 1_018_000)
		let r3 = Date(timeIntervalSince1970: 1_036_000)
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: r1))
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: r2))
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: r3))
		XCTAssertEqual(gate.fired.count, 3)

		// "now" is just past r2's reset: r1 and r2 have rolled, r3 is still live.
		gate.pruneExpired(now: Date(timeIntervalSince1970: 1_018_001))
		XCTAssertEqual(gate.fired.count, 1, "only the still-live window's key survives")
		XCTAssertTrue(gate.fired.contains(UsageAlertGate.key(id: "codex", window: "5-hour", reset: r3)))

		// Pruning rolled keys must NOT re-arm the still-live window (no duplicate alert).
		XCTAssertFalse(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: r3))
	}

	func testPruneExpiredKeepsWindowsWithNoResetTime() {
		var gate = UsageAlertGate()
		// A window with no reset time keys to epoch 0; it's bounded by (providers × windows) and must
		// survive pruning so a provider that never reports a reset doesn't re-alert every refresh.
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: nil))
		gate.pruneExpired(now: Date(timeIntervalSince1970: 5_000_000))
		XCTAssertEqual(gate.fired.count, 1)
		XCTAssertFalse(gate.shouldFire(id: "codex", window: "5-hour", pct: 85, reset: nil), "still armed")
	}

	func testNilPercentAndSeparateWindowsAreIndependent() {
		var gate = UsageAlertGate()
		XCTAssertFalse(gate.shouldFire(id: "claude", window: "5-hour", pct: nil, reset: nil))
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "5-hour", pct: 80, reset: nil))
		XCTAssertTrue(gate.shouldFire(id: "codex", window: "weekly", pct: 80, reset: nil))  // different window key
	}

	func testInteractiveSoundsToggleIsMasterForAlertMeows() {
		let suiteName = "jpc-alert-sound-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		XCTAssertTrue(UsageAlertCenter.soundOutputEnabled(defaults: defaults))
		defaults.set(false, forKey: SettingsStore.Key.interactiveSoundsEnabled)
		XCTAssertFalse(UsageAlertCenter.soundOutputEnabled(defaults: defaults))
		defaults.set(true, forKey: SettingsStore.Key.interactiveSoundsEnabled)
		defaults.set(false, forKey: SettingsStore.Key.alertSoundEnabled)
		XCTAssertFalse(UsageAlertCenter.soundOutputEnabled(defaults: defaults))
	}

	func testBannerAuthorizationPromptNeedsAlertsAndBannersOn() {
		XCTAssertFalse(UsageAlertCenter.shouldRequestBannerAuthorization(usageEnabled: false, bannerEnabled: true))
		XCTAssertFalse(UsageAlertCenter.shouldRequestBannerAuthorization(usageEnabled: true, bannerEnabled: false))
		XCTAssertTrue(UsageAlertCenter.shouldRequestBannerAuthorization(usageEnabled: true, bannerEnabled: true))
	}

	func testAlertableWindowsExcludeStaleUnavailableAndDisabledRows() {
		// Both non-available rows carry an over-threshold percentage on purpose — the exclusion must be by
		// availability, not by whether the data happens to be nil.
		let available = alertRow(id: "claude", availability: .available, usedPct: 85, weeklyUsedPct: 70)
		let stale = alertRow(id: "codex", availability: .stale, usedPct: 90, weeklyUsedPct: 88)
		let unavailable = alertRow(id: "gemini", availability: .unavailable, usedPct: 95, weeklyUsedPct: 95)
		let disabled = alertRow(id: "openai", availability: .disabled, usedPct: 99, weeklyUsedPct: 99)

		let windows = UsageAlertCenter.alertableWindows(rows: [available, stale, unavailable, disabled])

		XCTAssertEqual(Set(windows.map(\.id)), ["claude"], "only fully-available rows may raise an alert")
		XCTAssertEqual(windows.count, 2, "an available row contributes its 5-hour and weekly windows")
		XCTAssertEqual(
			windows.first { $0.window == "5-hour" }?.pct, 85)
		XCTAssertEqual(
			windows.first { $0.window == "weekly" }?.pct, 70)
	}

	private func alertRow(
		id: String,
		availability: DashboardProviderAvailability,
		usedPct: Double?,
		weeklyUsedPct: Double?
	) -> DashboardViewModel.ProviderRow {
		DashboardViewModel.ProviderRow(
			id: id, name: id.capitalized, tintHex: "#000000", availability: availability,
			today: 1, week: 5, todayUsage: TokenUsage(), weekUsage: TokenUsage(), todayEvents: 0, weekEvents: 0,
			series: [1, 4], notional: false, usedPct: usedPct, weeklyUsedPct: weeklyUsedPct, usageOfficial: true,
			planLabel: nil, unpricedModels: [], byModel7d: [], cacheSavings7d: nil,
			resetsAt5h: nil, resetsAtWeekly: nil, windowMinutes5h: 300, windowMinutesWeekly: 10080)
	}

	func testMeowSoundIsBundled() {
		// The 80%-alert meow must ship in the app bundle, or alerts would be silent.
		XCTAssertNotNil(UsageAlertCenter.meowSoundURL)
	}

	func testPackagedMeowCanBePreparedForPlayback() throws {
		let player = try XCTUnwrap(UsageAlertCenter.makeMeowPlayer())

		XCTAssertGreaterThan(player.duration, 1)
		XCTAssertEqual(player.numberOfLoops, 0)
	}

	func testTestMeowNotificationCopyIsJPBrandedVisualFeedback() {
		XCTAssertEqual(UsageAlertCenter.testMeowNotificationTitle, "JP the Cat")
		XCTAssertEqual(UsageAlertCenter.testMeowNotificationBody, "JP says meow. Test sound worked.")
		XCTAssertEqual(UsageAlertCenter.testMeowNotificationIdentifierPrefix, "jpthecat.test-meow.")
	}

	func testBannerDenialWarrantsOnlyWhenBannersWantedAndOSDenied() {
		// Warn only when the user wants banners (master + banner on) AND macOS has DENIED notifications —
		// that's the silent-failure case the Settings row surfaces a System Settings route for.
		XCTAssertTrue(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .denied, alertStyle: .banner, usageEnabled: true, bannerEnabled: true))
		// Authorized with a real on-screen style / not-yet-asked: no warning.
		XCTAssertFalse(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .authorized, alertStyle: .banner, usageEnabled: true, bannerEnabled: true))
		XCTAssertFalse(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .notDetermined, alertStyle: .none, usageEnabled: true, bannerEnabled: true))
		// Banner off (meow-only) or master off: the banner isn't wanted, so denial is irrelevant — no nag.
		XCTAssertFalse(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .denied, alertStyle: .banner, usageEnabled: true, bannerEnabled: false))
		XCTAssertFalse(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .denied, alertStyle: .banner, usageEnabled: false, bannerEnabled: true))
	}

	func testBannerDenialWarrantsWhenAuthorizedButAlertStyleNone() {
		// The subtle silent-drop case: macOS keeps us authorized but the user set the alert style to
		// "None", so nothing appears on screen. `.banner`/`.alert` styles must NOT warrant; `.none` must.
		XCTAssertTrue(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .authorized, alertStyle: .none, usageEnabled: true, bannerEnabled: true))
		XCTAssertTrue(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .provisional, alertStyle: .none, usageEnabled: true, bannerEnabled: true))
		XCTAssertFalse(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .authorized, alertStyle: .alert, usageEnabled: true, bannerEnabled: true))
		// Style None but banners not wanted → still no nag.
		XCTAssertFalse(
			UsageAlertCenter.bannerDenialWarrants(
				authorizationStatus: .authorized, alertStyle: .none, usageEnabled: true, bannerEnabled: false))
	}

	func testAlertBodyTiersTrailingClauseOnPercent() {
		// The trailing clause must match the printed %, tiering up so a 100% reading never says "close".
		XCTAssertEqual(
			UsageAlertCenter.alertBody(name: "Claude", window: "5-hour", pct: 82),
			"Claude 5-hour usage at 82% — you're close to the limit.")
		XCTAssertEqual(
			UsageAlertCenter.alertBody(name: "Claude", window: "5-hour", pct: 90),
			"Claude 5-hour usage at 90% — you're almost out.")
		XCTAssertEqual(
			UsageAlertCenter.alertBody(name: "Codex", window: "weekly", pct: 95),
			"Codex weekly usage at 95% — you're basically out.")
		XCTAssertEqual(
			UsageAlertCenter.alertBody(name: "Codex", window: "5-hour", pct: 100),
			"Codex 5-hour usage at 100% — you're at your limit.")
		// The tier follows the ROUNDED percent, so 99.6 → 100 → "at your limit" (number and phrasing agree).
		XCTAssertEqual(
			UsageAlertCenter.alertBody(name: "Codex", window: "5-hour", pct: 99.6),
			"Codex 5-hour usage at 100% — you're at your limit.")
	}

	func testAlertTierIdentifiersAreDistinctSoBannersCoexist() {
		// warning / critical / limit-hit for the SAME window must produce distinct notification
		// identifiers — a shared identifier would make Apple overwrite the earlier banner. Warning keeps
		// the original identifier (backward compatible with the single-tier scheme).
		let reset = Date(timeIntervalSince1970: 1_000_000)
		let warning = UsageAlertCenter.notificationIdentifier(
			tier: .warning, id: "codex", displayWindow: "5-hour", reset: reset)
		let critical = UsageAlertCenter.notificationIdentifier(
			tier: .critical, id: "codex", displayWindow: "5-hour", reset: reset)
		let limitHit = UsageAlertCenter.notificationIdentifier(
			tier: .limitHit, id: "codex", displayWindow: "5-hour", reset: reset)
		XCTAssertEqual(Set([warning, critical, limitHit]).count, 3, "each tier needs its own identifier")
		XCTAssertEqual(
			warning, UsageAlertGate.key(id: "codex", window: "5-hour", reset: reset),
			"warning must keep the original single-tier identifier")
	}

	func testCriticalGateFiresAtNinetyFiveNotEighty() {
		// The escalation gate is independent of the 80% gate: it only fires at/after 95%.
		var critical = UsageAlertGate(threshold: UsageAlertCenter.criticalThreshold)
		let reset = Date(timeIntervalSince1970: 1_000_000)
		XCTAssertFalse(critical.shouldFire(id: "codex", window: "5-hour", pct: 80, reset: reset))
		XCTAssertFalse(critical.shouldFire(id: "codex", window: "5-hour", pct: 94, reset: reset))
		XCTAssertTrue(critical.shouldFire(id: "codex", window: "5-hour", pct: 96, reset: reset))  // crossing
		XCTAssertFalse(critical.shouldFire(id: "codex", window: "5-hour", pct: 100, reset: reset))  // steady
	}

	func testLimitHitGateFiresOncePerWindowAndReArmsOnNewReset() {
		// Claude's frozen-at-limit alert: one shot per 5h window (fed pct 100 when likelyHit), re-armed
		// only when the window rolls. Its "limit-hit" tag is independent of the "5-hour" 80% key.
		var limitHit = UsageAlertGate(threshold: 1)
		let first = Date(timeIntervalSince1970: 1_000_000)
		XCTAssertTrue(
			limitHit.shouldFire(id: "claude", window: UsageAlertCenter.limitHitWindowTag, pct: 100, reset: first))
		XCTAssertFalse(
			limitHit.shouldFire(id: "claude", window: UsageAlertCenter.limitHitWindowTag, pct: 100, reset: first))
		let next = Date(timeIntervalSince1970: 1_018_000)
		XCTAssertTrue(
			limitHit.shouldFire(id: "claude", window: UsageAlertCenter.limitHitWindowTag, pct: 100, reset: next))
	}

	func testUserNotificationsOnlyRunInsideAnAppBundle() {
		XCTAssertTrue(
			UsageAlertCenter.supportsUserNotifications(
				bundleURL: URL(fileURLWithPath: "/Applications/JPtheCat.app")))
		XCTAssertFalse(
			UsageAlertCenter.supportsUserNotifications(
				bundleURL: URL(fileURLWithPath: "/tmp/jpthecat/.build/debug/")))
		XCTAssertFalse(
			UsageAlertCenter.supportsUserNotifications(
				bundleURL: URL(fileURLWithPath: "/tmp/jpthecat/.build/debug/JPtheCat")))
	}
}
