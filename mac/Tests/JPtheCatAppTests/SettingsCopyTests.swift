import JPtheCatCore
import XCTest

@testable import JPtheCatApp

/// [NOTE] Every guard below used to read `Sources/JPtheCatApp/SettingsBackView.swift` by literal path,
/// which froze that one file's size: extracting a row would have made each `XCTAssertFalse` pass
/// VACUOUSLY. They now resolve their text through `AppSourceScanner` — whole-app scans for copy that
/// may live anywhere, brace-matched declaration slices for row-scoped contracts — so a moved surface
/// fails LOUDLY naming the anchor it could not find.
final class SettingsCopyTests: XCTestCase {
	func testVisibleSettingsCopyUsesDisplayNameNotIdentifierSpelling() throws {
		let source = try AppSourceScanner.joined()

		XCTAssertTrue(source.contains(#""Keep JP the Cat in the Dock and app switcher""#))
		XCTAssertTrue(source.contains(#""Start JP the Cat automatically when you sign in""#))
		XCTAssertTrue(source.contains(#""JP the Cat will append a small, clearly-marked block to your Claude statusline script that ""#))
		// Scanning EVERY app source makes each of these strictly stronger than the old single-file read:
		// the identifier spelling may now appear in NO user-facing source at all.
		XCTAssertFalse(source.contains(#"Open JPtheCat.com"#))
		XCTAssertFalse(source.contains(#"Keep JPtheCat in the Dock and app switcher"#))
		XCTAssertFalse(source.contains(#"Start JPtheCat automatically when you sign in"#))
		XCTAssertFalse(source.contains(#"JPtheCat will "#))
	}

	// `title: "Refresh now"`, `title: "Open JP the Cat website"`, `ChromeRefreshButton` and the
	// `onOpenWebsite:` call site are asserted by scripts/verify-app-demo-parity.sh, which
	// AppDemoParityGuardTests executes — the single owner, since those are mac/web parity pins.
	// Only the assertions with no other owner stay here.
	func testRefreshAndWebsiteAreFooterActionsNotSettingsRows() throws {
		// Scoped to the settings face's own surface (declaration + any extension of it, wherever they
		// live): `title: "Quit JP the Cat"` is legitimate in StatusBarController's NSMenuItem, so a
		// whole-app scan would misfire. `typeSurface` throws if the type disappears.
		let source = try AppSourceScanner.typeSurface("SettingsBackView")

		XCTAssertFalse(source.contains(#"section("About")"#))
		XCTAssertFalse(source.contains(#"title: "Quit JP the Cat""#))
		XCTAssertTrue(source.contains("NSApp.terminate(nil)"))
	}

	func testLaunchAtLoginRowUsesSystemReadBack() throws {
		let source = try AppSourceScanner.joined()

		XCTAssertTrue(source.contains(#"title: "Launch at login""#))
		// Toggling attempts the change, surfaces the real failure reason, then reads back system truth.
		XCTAssertTrue(source.contains("LoginItem.failureReason"))
		XCTAssertTrue(source.contains("LoginItem.isEnabled()"))
		XCTAssertTrue(source.contains("LoginItem.statusDescription"))
	}

	// The Alerts section must expose the visual banner and the meow as two independent toggles so a
	// user can turn OFF the on-screen notification while keeping (or dropping) the sound.
	func testAlertsSectionHasIndependentVisualAndSoundToggles() throws {
		let source = try AppSourceScanner.joined()

		XCTAssertTrue(source.contains(#"title: "Show notification banner""#))
		XCTAssertTrue(source.contains(#"title: "Meow on alerts""#))
		// The banner toggle binds to the single settings source of truth (its own distinct key).
		XCTAssertTrue(source.contains("$settings.alertBannerEnabled"))
	}

	func testInteractiveSoundsToggleSitsAboveTestMeow() throws {
		// Relative order is only meaningful inside ONE file, so resolve the host file from the anchor
		// and require both rows to still live there — drifting apart fails loudly.
		let host = try AppSourceScanner.file(containing: #"title: "Interactive sounds""#)
		let source = host.text
		let interactiveIndex = try XCTUnwrap(source.range(of: #"title: "Interactive sounds""#)?.lowerBound)
		let testMeowIndex = try XCTUnwrap(
			source.range(of: #"title: "Test meow""#)?.lowerBound,
			"`Test meow` must stay in the same settings source as `Interactive sounds` (\(host.name))")

		let allSources = try AppSourceScanner.joined()
		XCTAssertLessThan(interactiveIndex, testMeowIndex)
		XCTAssertTrue(allSources.contains("$settings.interactiveSoundsEnabled"))
		// Test meow must NOT be gated on the sound toggle at the call site — the notification has to fire
		// even when interactive sounds are off (the meow itself is gated inside playTestMeowFeedback).
		XCTAssertFalse(
			allSources.contains("if settings.interactiveSoundsEnabled"),
			"Test meow's notification must not be suppressed when Interactive sounds is off")
	}

	func testAlertToggleKeysAreDistinctAndNamespaced() {
		let keys = Set([
			SettingsStore.Key.usageAlertsEnabled,
			SettingsStore.Key.alertBannerEnabled,
			SettingsStore.Key.alertSoundEnabled,
			SettingsStore.Key.interactiveSoundsEnabled,
		])
		XCTAssertEqual(keys.count, 4, "the alert and interactive sound toggles must use distinct UserDefaults keys")
		XCTAssertEqual(SettingsStore.Key.alertBannerEnabled, "JPtheCat.alerts.bannerEnabled")
		XCTAssertEqual(SettingsStore.Key.interactiveSoundsEnabled, "JPtheCat.sounds.interactiveEnabled")
		XCTAssertTrue(
			keys.allSatisfy { $0.hasPrefix("JPtheCat.") }, "every settings key must be JPtheCat-namespaced")
	}

	// Root-cause guard for "Test meow shows no notification": macOS only shows the banner when the
	// user has authorized notifications, so the test path must ROUTE by live status (authorized → post;
	// notDetermined → prompt; denied → open System Settings) rather than silently dropping it.
	func testTestMeowNotificationNeverFailsSilently() throws {
		let source = try AppSourceScanner.source(named: "UsageAlertCenter.swift")
		XCTAssertTrue(source.contains("getNotificationSettings"), "must check the live authorization status")
		XCTAssertTrue(source.contains("openNotificationSettings"), "denial must route the user to enable banners")
		XCTAssertTrue(source.contains("com.apple.Notifications-Settings.extension"))
	}

	func testTestMeowUsesJPFaceActionNotGenericChevron() throws {
		let source = try AppSourceScanner.joined()

		XCTAssertTrue(source.contains("SettingsJPActionRow("))
		XCTAssertTrue(source.contains(#"AppResources.image(forResource: "jp-menubar")"#))
		XCTAssertTrue(source.contains("UsageAlertCenter.shared.playTestMeowFeedback()"))
		XCTAssertFalse(source.contains(#"SettingsRow(icon: "play.circle", title: "Test meow""#))
	}

	func testSettingsToggleRowsUseNormalizedSwitchSlot() throws {
		// Scoped to the row itself: `.accessibilityElement(children: .combine)` is legitimate elsewhere
		// (Advanced Analytics), so the ban is only meaningful inside this declaration.
		let source = try AppSourceScanner.body(of: "struct SettingsToggleRow")

		XCTAssertTrue(source.contains(".controlSize(.regular)"))
		XCTAssertTrue(source.contains(".frame(width: JPAppSpacing.settingsSwitchSlotWidth, alignment: .trailing)"))
		XCTAssertFalse(source.contains(".accessibilityElement(children: .combine)"))
		XCTAssertTrue(source.contains(".accessibilityLabel(title)"))
		XCTAssertTrue(source.contains(#".accessibilityValue(isOn ? "On" : "Off")"#))
	}

	// Cycle rows (SettingsRow: "Menu bar display", "Refresh rate") must SPEAK their current selection —
	// the subtitle carries the live value, so it is exposed as the accessibility value. A bare
	// .accessibilityLabel(title) dropped it and left VoiceOver users cycling blind.
	func testSettingsCycleRowsExposeCurrentValueToVoiceOver() throws {
		let rowSource = try AppSourceScanner.body(of: "struct SettingsRow")
		XCTAssertTrue(rowSource.contains(".accessibilityLabel(title)"))
		XCTAssertTrue(rowSource.contains(#".accessibilityValue(subtitle ?? "")"#))
	}

	// The four hand-copied provider opt-in rows (`ClaudeLimitsRow`, `GrokLimitsRow`, `CopilotOtelRow`,
	// `CursorHookRow`) collapsed into ONE `ProviderOptInRow` driven by four descriptors, so the two
	// guards below now assert over that single implementation. The ban on the cycle-row form is
	// STRONGER than before: it can no longer be satisfied by three rows while a fourth drifts.
	func testClaudeLiveLimitsUsesStandardToggleRow() throws {
		let rowSource = try AppSourceScanner.body(of: "struct ProviderOptInRow")

		XCTAssertTrue(rowSource.contains("SettingsToggleRow("))
		XCTAssertFalse(rowSource.contains("SettingsRow(icon: icon"))
		// Claude still reaches that row through its own descriptor, with its own copy. `typeSurface`
		// throws if `SettingsBackView` (which hosts the four descriptors) disappears.
		let descriptors = try AppSourceScanner.typeSurface("SettingsBackView")
		XCTAssertTrue(descriptors.contains("static let claudeLiveLimits"))
		XCTAssertTrue(descriptors.contains(#""Enable Claude live limits""#))
		XCTAssertTrue(descriptors.contains("StatuslineCapture.install()"))
	}

	func testCopilotOtelRowUsesStandardToggleRow() throws {
		// The original slice ran from `CopilotOtelRow` to the `// MARK: - Rows` banner, which also
		// covered `CursorHookRow`; both dynamic-title provider rows stay in scope (now as descriptors
		// feeding the one shared row) so the ban on the cycle-row form is no weaker than before.
		let rowSource = try AppSourceScanner.body(of: "struct ProviderOptInRow")
		XCTAssertTrue(rowSource.contains("SettingsToggleRow("))
		XCTAssertFalse(rowSource.contains("SettingsRow(icon: icon"))

		let descriptors = try AppSourceScanner.typeSurface("SettingsBackView")
		XCTAssertTrue(descriptors.contains("static let copilotLiveData"))
		XCTAssertTrue(descriptors.contains("CopilotOtelSetup.install()"))
		XCTAssertTrue(descriptors.contains("static let cursorLiveData"))
		XCTAssertTrue(descriptors.contains("CursorHookSetup.install()"))
	}

	@MainActor
	func testEverySettingsSwitchUsesSharedToggleRow() throws {
		let source = try AppSourceScanner.joined()
		let switches = [
			"Show Dock icon",
			"Launch at login",
			"Automatic updates",
			"Claude Code",
			"Codex",
			"Grok",
			"Muse Spark",
			"OpenCode Zen",
			"OpenCode Go",
			"Usage alerts at 80%",
			"Show notification banner",
			"Meow on alerts",
			"Interactive sounds",
		]

		// +1 for the ONE dynamic-title `SettingsToggleRow` inside `ProviderOptInRow`, which now renders
		// all four provider opt-ins (Claude/Grok live limits, Copilot/Cursor live data) from their
		// descriptors — it used to be +4, one per hand-copied row, and the four had already drifted.
		// Their titles change with install state, so they are not in the static `switches` list.
		// Counted across the WHOLE scanned set: a split that moved half the rows into a new file would
		// otherwise silently halve the count this pins.
		// +1 more for the ONE `SettingsToggleRow` inside the `SettingsBackView.brandRows` `ForEach`,
		// which renders every OpenCode model-brand row (Nemotron/MiMo/Big Pickle/DeepSeek) from the
		// `OpenCodeBrand` table — four hand-copied rows used to sit here and had already drifted.
		let toggleRowCallSites = try AppSourceScanner.occurrences(of: "SettingsToggleRow(")
		XCTAssertEqual(toggleRowCallSites, switches.count + 2)
		for title in switches {
			XCTAssertTrue(source.contains(#"title: "\#(title)""#), "\(title) must stay in SettingsToggleRow")
		}
		XCTAssertEqual(
			SettingsBackView.brandRows.map(\.brand.displayName),
			["Nemotron", "MiMo", "Big Pickle", "DeepSeek"])
		XCTAssertEqual(Set(SettingsBackView.brandRows.map(\.brand)), Set(OpenCodeBrand.allCases))
	}

	// "Refresh rate" is a cycle row (like "Menu bar display"), NOT a switch — it taps through the
	// RefreshCadence presets and writes the single settings source of truth.
	func testRefreshRateRowCyclesCadencePresets() throws {
		let source = try AppSourceScanner.joined()

		XCTAssertTrue(source.contains(#"title: "Refresh rate""#))
		XCTAssertTrue(source.contains("settings.refreshCadence = settings.refreshCadence.next"))
		XCTAssertTrue(source.contains("settings.refreshCadence.settingsTitle"))
	}

	// The "Automatic updates" toggle binds to Sparkle's OWN flag (never a mirrored SettingsStore key)
	// and is gated on `Updater.isConfigured` so dev builds don't show a dead toggle.
	func testAutomaticUpdatesTogglesSparkleOwnFlag() throws {
		let source = try AppSourceScanner.joined()

		XCTAssertTrue(source.contains(#"title: "Automatic updates""#))
		XCTAssertTrue(source.contains("Updater.shared.automaticallyChecksForUpdates"))
		XCTAssertTrue(source.contains("if Updater.isConfigured {"))
		// The auto-update flag lives in Sparkle, never a mirrored SettingsStore key (the two would drift).
		XCTAssertFalse(source.contains("JPtheCat.updates"))
	}

	// OS-level denial: when the user wants banners but macOS is suppressing them, the row offers a
	// route to System Settings instead of silently no-op'ing.
	func testNotificationDenialAffordanceRoutesToSystemSettings() throws {
		let source = try AppSourceScanner.joined()

		XCTAssertTrue(source.contains("showBannerDeniedAffordance"))
		XCTAssertTrue(source.contains("UsageAlertCenter.bannerDenialWarrants"))
		XCTAssertTrue(source.contains(#"title: "Turn on in System Settings""#))
		XCTAssertTrue(source.contains("com.apple.Notifications-Settings.extension"))
	}

	// The Settings face no longer carries an in-app "Privacy & data" row (removed to keep the card
	// tight). The least-privilege posture remains a shipped MARKETING claim on the homepage trust band /
	// install FAQ / llms.txt, guarded by `web/tests/site-copy.test.ts` — not the app settings face.
	func testSettingsFaceHasNoPrivacyRow() throws {
		// `typeSurface` throws if `SettingsBackView` itself vanishes, so this can never go vacuous.
		let source = try AppSourceScanner.typeSurface("SettingsBackView")
		XCTAssertFalse(source.contains(#"title: "Privacy & data""#))
	}

	/// JP is free: no source may bring back license, trial, or price copy in the app.
	func testAppCarriesNoLicenseTrialOrPriceCopy() throws {
		let source = try AppSourceScanner.joined()
		for banned in ["Free Trial", "JPC-", "$12.99", "$9.99", "JP Pro", "Enter your License Key", "Deactivate JP"] {
			XCTAssertFalse(source.contains(banned), "app source still carries paid-era copy: \(banned)")
		}
	}

	func testSettingsFaceHasSupportReportRowNotPromoCard() throws {
		let source = try AppSourceScanner.typeSurface("SettingsBackView")
		XCTAssertTrue(source.contains(#"title: "Support report""#))
		XCTAssertFalse(source.contains("SupportCardBody"))
		XCTAssertFalse(source.contains("Free · every feature"))
		XCTAssertFalse(source.contains("Something look off?"))
	}

	/// [Regression guard] `WidgetGalleryButton` was the ONLY chrome icon with an ALWAYS-ON background +
	/// border chip — every sibling only shows a chip on hover. Pin the hover-gated recipe so it can't
	/// silently regress back to a permanently-highlighted icon.
	func testWidgetGalleryButtonUsesHoverGatedBackgroundLikeItsSiblings() throws {
		let body = try AppSourceScanner.body(of: "struct WidgetGalleryButton: View {")

		XCTAssertTrue(body.contains("hovering ? JP.paper2.opacity(0.72) : .clear"))
		XCTAssertFalse(body.contains("JP.paper.opacity(0.72), in: RoundedRectangle"))
		XCTAssertFalse(body.contains("strokeBorder(JP.line.opacity(0.9)"))
	}
}
