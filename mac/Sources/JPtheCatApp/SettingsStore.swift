import Foundation
import JPtheCatCore

/// The single, namespaced source of truth for app settings.
///
/// UserDefaults-backed `ObservableObject` singleton: SwiftUI binds directly to its `@Published`
/// properties, while non-UI readers (`UsageAlertCenter`, `DashboardViewModel`) read the SAME
/// `JPtheCat.*`-namespaced keys through the `nonisolated static` accessors — so a toggle and its
/// consumer can never disagree about a value. Every key lives under the `JPtheCat.` namespace,
/// matching `DockIconPreference` (`JPtheCat.showDockIcon`) and `Theme` (`JPtheCat.themeID`).
///
/// A one-time schema migration (`migrateIfNeeded`) folds the earlier UN-namespaced keys (`alerts.*`,
/// `dashboard.timeframeDays`) into the namespace and retires them. It is idempotent (guarded by a
/// stored schema version) and runs at launch (`main.swift`) BEFORE anything reads a setting, so a
/// user's existing choices are never silently lost to a default.
@MainActor
final class SettingsStore: ObservableObject {
	static let shared = SettingsStore()

	/// UserDefaults keys — all under the `JPtheCat.` namespace. (Nested enum ⇒ nonisolated.)
	enum Key {
		static let schemaVersion = "JPtheCat.settingsSchemaVersion"
		static let usageAlertsEnabled = "JPtheCat.alerts.usageEnabled"
		static let alertBannerEnabled = "JPtheCat.alerts.bannerEnabled"
		static let alertSoundEnabled = "JPtheCat.alerts.soundEnabled"
		static let interactiveSoundsEnabled = "JPtheCat.sounds.interactiveEnabled"
		static let timeframeDays = "JPtheCat.dashboard.timeframeDays"
		static let dashboardLayout = "JPtheCat.dashboard.layout"
		static let menuBarDisplayFormat = "JPtheCat.menuBar.displayFormat"
		static let refreshCadence = "JPtheCat.refresh.cadence"
		static let onboardingCompleted = "JPtheCat.onboarding.completed"
		/// Last time `UsageIndex.compactIfNeeded` actually ran. Persisted so a whole-file VACUUM can
		/// never fire on consecutive launches — it is maintenance, not a routine tick.
		static let lastIndexCompaction = "JPtheCat.index.lastCompaction"
		/// The app version the post-update feedback prompt last ran for. Absent on a fresh install, which
		/// `PostUpdateFeedbackGate` treats as "record, don't prompt".
		static let feedbackPromptedVersion = "JPtheCat.feedback.promptedVersion"
		/// Set by "Don't ask again" in the post-update feedback sheet; suppresses it for every version.
		static let feedbackOptedOut = "JPtheCat.feedback.optedOut"
		static let providerClaudeEnabled = "JPtheCat.provider.claude.enabled"
		static let providerCodexEnabled = "JPtheCat.provider.codex.enabled"
		static let providerGrokEnabled = "JPtheCat.provider.grok.enabled"
		static let providerUnifiedGrokEnabled = "JPtheCat.provider.grok.unified.enabled"
		static let providerGrokBotEnabled = "JPtheCat.provider.grokBot.enabled"
		static let providerOpenCodeZenEnabled = "JPtheCat.provider.opencodeZen.enabled"
		static let providerOpenCodeGoEnabled = "JPtheCat.provider.opencodeGo.enabled"
		static let providerMuseSparkEnabled = "JPtheCat.provider.museSpark.enabled"
		static let providerNemotronEnabled = "JPtheCat.provider.nemotron.enabled"
		static let providerMiMoEnabled = "JPtheCat.provider.mimo.enabled"
		static let providerBigPickleEnabled = "JPtheCat.provider.bigPickle.enabled"
		static let providerDeepSeekEnabled = "JPtheCat.provider.deepSeek.enabled"
	}

	enum Value: Equatable, Sendable {
		case bool(Bool)
		case int(Int)
		case string(String)
	}

	struct Change: Equatable, Sendable {
		let key: String
		let oldValue: Value
		let newValue: Value
	}

	nonisolated static let didChangeNotification = Notification.Name("com.8bittts.jpthecat.settings.didChange")
	nonisolated static let changeUserInfoKey = "change"

	/// Bump when a new fold is added; `migrateIfNeeded` only runs while the stored version is behind.
	nonisolated static let currentSchemaVersion = 1

	nonisolated static let defaultUsageAlertsEnabled = true
	nonisolated static let defaultAlertBannerEnabled = true
	nonisolated static let defaultAlertSoundEnabled = true
	nonisolated static let defaultInteractiveSoundsEnabled = true
	nonisolated static let defaultTimeframeDays = 14
	nonisolated static let defaultRefreshCadence: RefreshCadence = .balanced
	nonisolated static let defaultOnboardingCompleted = false
	nonisolated static let defaultProviderEnabled = true

	private let defaults: UserDefaults

	// Guarded `didSet`: persist ONLY on a real change (a redundant set is a no-op). This is also the
	// single choke point where NotificationCenter fan-out posts from, so non-SwiftUI consumers see the
	// same committed value that SwiftUI bindings wrote.
	@Published var usageAlertsEnabled: Bool {
		didSet { commit(usageAlertsEnabled, oldValue, Key.usageAlertsEnabled) }
	}
	@Published var alertBannerEnabled: Bool {
		didSet { commit(alertBannerEnabled, oldValue, Key.alertBannerEnabled) }
	}
	@Published var alertSoundEnabled: Bool {
		didSet { commit(alertSoundEnabled, oldValue, Key.alertSoundEnabled) }
	}
	@Published var interactiveSoundsEnabled: Bool {
		didSet { commit(interactiveSoundsEnabled, oldValue, Key.interactiveSoundsEnabled) }
	}
	/// Not `@Published`: nothing in the UI observes it, and it is written from a background task.
	var lastIndexCompaction: Date? {
		get {
			let t = defaults.double(forKey: Key.lastIndexCompaction)
			return t > 0 ? Date(timeIntervalSince1970: t) : nil
		}
		set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.lastIndexCompaction) }
	}

	@Published var timeframeDays: Int {
		didSet { commit(timeframeDays, oldValue, Key.timeframeDays) }
	}
	@Published var menuBarDisplayFormat: MenuBarDisplayFormat {
		didSet { commit(menuBarDisplayFormat, oldValue, Key.menuBarDisplayFormat) }
	}
	@Published var dashboardLayout: DashboardLayout {
		didSet { commit(dashboardLayout, oldValue, Key.dashboardLayout) }
	}
	@Published var refreshCadence: RefreshCadence {
		didSet { commit(refreshCadence, oldValue, Key.refreshCadence) }
	}
	@Published var onboardingCompleted: Bool {
		didSet { commit(onboardingCompleted, oldValue, Key.onboardingCompleted) }
	}
	@Published var claudeProviderEnabled: Bool {
		didSet { commit(claudeProviderEnabled, oldValue, Key.providerClaudeEnabled) }
	}
	@Published var codexProviderEnabled: Bool {
		didSet { commit(codexProviderEnabled, oldValue, Key.providerCodexEnabled) }
	}
	@Published var grokProviderEnabled: Bool {
		didSet { commit(grokProviderEnabled, oldValue, Key.providerUnifiedGrokEnabled) }
	}
	/// OpenCode Zen (pay-as-you-go gateway) — auto-detected from `opencode.db`, default ON.
	@Published var openCodeZenProviderEnabled: Bool {
		didSet { commit(openCodeZenProviderEnabled, oldValue, Key.providerOpenCodeZenEnabled) }
	}
	/// OpenCode Go ($10/month subscription gateway) — auto-detected, default ON.
	@Published var openCodeGoProviderEnabled: Bool {
		didSet { commit(openCodeGoProviderEnabled, oldValue, Key.providerOpenCodeGoEnabled) }
	}
	@Published var museSparkProviderEnabled: Bool {
		didSet { commit(museSparkProviderEnabled, oldValue, Key.providerMuseSparkEnabled) }
	}
	@Published var nemotronProviderEnabled: Bool {
		didSet { commit(nemotronProviderEnabled, oldValue, Key.providerNemotronEnabled) }
	}
	@Published var mimoProviderEnabled: Bool {
		didSet { commit(mimoProviderEnabled, oldValue, Key.providerMiMoEnabled) }
	}
	@Published var bigPickleProviderEnabled: Bool {
		didSet { commit(bigPickleProviderEnabled, oldValue, Key.providerBigPickleEnabled) }
	}
	@Published var deepSeekProviderEnabled: Bool {
		didSet { commit(deepSeekProviderEnabled, oldValue, Key.providerDeepSeekEnabled) }
	}

	/// The enabled OpenCode model-brand rows as one set, so the dashboard refresh and the Live Data
	/// window drive the same `OpenCodeBrand` table instead of four parallel flags.
	var enabledOpenCodeBrands: Set<OpenCodeBrand> {
		Set(OpenCodeBrand.allCases.filter { isBrandEnabled($0) })
	}

	func isBrandEnabled(_ brand: OpenCodeBrand) -> Bool {
		switch brand {
		case .mimo: mimoProviderEnabled
		case .nemotron: nemotronProviderEnabled
		case .deepseek: deepSeekProviderEnabled
		case .bigPickle: bigPickleProviderEnabled
		}
	}

	func setBrandEnabled(_ brand: OpenCodeBrand, _ enabled: Bool) {
		switch brand {
		case .mimo: mimoProviderEnabled = enabled
		case .nemotron: nemotronProviderEnabled = enabled
		case .deepseek: deepSeekProviderEnabled = enabled
		case .bigPickle: bigPickleProviderEnabled = enabled
		}
	}

	/// `defaults` is injectable so tests run against an isolated suite. `init` runs the migration
	/// (idempotent) then seeds each `@Published` from the post-migration store.
	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		Self.migrateIfNeeded(defaults: defaults)
		usageAlertsEnabled = Self.bool(Key.usageAlertsEnabled, default: Self.defaultUsageAlertsEnabled, defaults)
		alertBannerEnabled = Self.bool(Key.alertBannerEnabled, default: Self.defaultAlertBannerEnabled, defaults)
		alertSoundEnabled = Self.bool(Key.alertSoundEnabled, default: Self.defaultAlertSoundEnabled, defaults)
		interactiveSoundsEnabled = Self.bool(
			Key.interactiveSoundsEnabled, default: Self.defaultInteractiveSoundsEnabled, defaults)
		timeframeDays = Self.int(Key.timeframeDays, default: Self.defaultTimeframeDays, defaults)
		menuBarDisplayFormat = Self.menuBarDisplayFormat(defaults)
		dashboardLayout = Self.dashboardLayout(defaults)
		refreshCadence = Self.refreshCadence(defaults)
		onboardingCompleted = Self.onboardingCompleted(defaults)
		claudeProviderEnabled = Self.providerEnabled(.claude, defaults)
		codexProviderEnabled = Self.providerEnabled(.codex, defaults)
		grokProviderEnabled = Self.providerEnabled(.grok, defaults)
		openCodeZenProviderEnabled = Self.providerEnabled(.opencode, defaults)
		openCodeGoProviderEnabled = Self.providerEnabled(.opencodego, defaults)
		museSparkProviderEnabled = Self.providerEnabled(.museSpark, defaults)
		nemotronProviderEnabled = Self.providerEnabled(.nemotron, defaults)
		mimoProviderEnabled = Self.providerEnabled(.mimo, defaults)
		bigPickleProviderEnabled = Self.providerEnabled(.bigPickle, defaults)
		deepSeekProviderEnabled = Self.providerEnabled(.deepseek, defaults)
	}

	private func commit(_ newValue: Bool, _ oldValue: Bool, _ key: String) {
		guard newValue != oldValue else { return }
		defaults.set(newValue, forKey: key)
		postChange(key: key, oldValue: .bool(oldValue), newValue: .bool(newValue))
	}

	private func commit(_ newValue: Int, _ oldValue: Int, _ key: String) {
		guard newValue != oldValue else { return }
		defaults.set(newValue, forKey: key)
		postChange(key: key, oldValue: .int(oldValue), newValue: .int(newValue))
	}

	private func commit(_ newValue: MenuBarDisplayFormat, _ oldValue: MenuBarDisplayFormat, _ key: String) {
		guard newValue != oldValue else { return }
		defaults.set(newValue.rawValue, forKey: key)
		postChange(key: key, oldValue: .string(oldValue.rawValue), newValue: .string(newValue.rawValue))
	}

	private func commit(_ newValue: DashboardLayout, _ oldValue: DashboardLayout, _ key: String) {
		guard newValue != oldValue else { return }
		defaults.set(newValue.rawValue, forKey: key)
		postChange(key: key, oldValue: .string(oldValue.rawValue), newValue: .string(newValue.rawValue))
	}

	private func commit(_ newValue: RefreshCadence, _ oldValue: RefreshCadence, _ key: String) {
		guard newValue != oldValue else { return }
		defaults.set(newValue.rawValue, forKey: key)
		postChange(key: key, oldValue: .string(oldValue.rawValue), newValue: .string(newValue.rawValue))
	}

	private func postChange(key: String, oldValue: Value, newValue: Value) {
		NotificationCenter.default.post(
			name: Self.didChangeNotification,
			object: self,
			userInfo: [Self.changeUserInfoKey: Change(key: key, oldValue: oldValue, newValue: newValue)])
	}

	nonisolated static func change(from notification: Notification) -> Change? {
		notification.userInfo?[changeUserInfoKey] as? Change
	}

	// MARK: - Nonisolated raw reads (UserDefaults is thread-safe) for non-main-actor consumers

	/// Bool read that honors "unset ⇒ default" via `object(forKey:)` (not `bool(forKey:)`, which can't
	/// distinguish a stored `false` from an absent key).
	nonisolated static func bool(_ key: String, default fallback: Bool, _ defaults: UserDefaults = .standard) -> Bool {
		(defaults.object(forKey: key) as? Bool) ?? fallback
	}

	/// Int read that returns `fallback` when the key is absent (never a spurious `0`).
	nonisolated static func int(_ key: String, default fallback: Int, _ defaults: UserDefaults = .standard) -> Int {
		defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : fallback
	}

	nonisolated static func usageAlertsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
		bool(Key.usageAlertsEnabled, default: defaultUsageAlertsEnabled, defaults)
	}
	nonisolated static func alertBannerEnabled(_ defaults: UserDefaults = .standard) -> Bool {
		bool(Key.alertBannerEnabled, default: defaultAlertBannerEnabled, defaults)
	}
	nonisolated static func alertSoundEnabled(_ defaults: UserDefaults = .standard) -> Bool {
		bool(Key.alertSoundEnabled, default: defaultAlertSoundEnabled, defaults)
	}
	nonisolated static func interactiveSoundsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
		bool(Key.interactiveSoundsEnabled, default: defaultInteractiveSoundsEnabled, defaults)
	}
	nonisolated static func timeframeDays(_ defaults: UserDefaults = .standard) -> Int {
		int(Key.timeframeDays, default: defaultTimeframeDays, defaults)
	}
	nonisolated static func menuBarDisplayFormat(_ defaults: UserDefaults = .standard) -> MenuBarDisplayFormat {
		MenuBarDisplayFormat.normalized(defaults.string(forKey: Key.menuBarDisplayFormat))
	}
	nonisolated static func dashboardLayout(_ defaults: UserDefaults = .standard) -> DashboardLayout {
		DashboardLayout.normalized(defaults.string(forKey: Key.dashboardLayout))
	}
	nonisolated static func refreshCadence(_ defaults: UserDefaults = .standard) -> RefreshCadence {
		RefreshCadence.normalized(defaults.string(forKey: Key.refreshCadence), default: defaultRefreshCadence)
	}
	nonisolated static func onboardingCompleted(_ defaults: UserDefaults = .standard) -> Bool {
		bool(Key.onboardingCompleted, default: defaultOnboardingCompleted, defaults)
	}
	/// Post-update feedback bookkeeping. Not `@Published`: only the prompt itself reads these, once, on
	/// the dashboard's `onAppear` — nothing re-renders off them.
	nonisolated static func feedbackPromptedVersion(_ defaults: UserDefaults = .standard) -> String? {
		defaults.string(forKey: Key.feedbackPromptedVersion)
	}
	nonisolated static func setFeedbackPromptedVersion(_ version: String, _ defaults: UserDefaults = .standard) {
		defaults.set(version, forKey: Key.feedbackPromptedVersion)
	}
	nonisolated static func feedbackOptedOut(_ defaults: UserDefaults = .standard) -> Bool {
		bool(Key.feedbackOptedOut, default: false, defaults)
	}
	nonisolated static func setFeedbackOptedOut(_ optedOut: Bool, _ defaults: UserDefaults = .standard) {
		defaults.set(optedOut, forKey: Key.feedbackOptedOut)
	}

	/// Preserve explicitly saved opt-ins while giving the unified switch an independent key so
	/// disabling it cannot be overridden by a legacy Grok Bot setting on the next launch.
	nonisolated static func unifiedGrokEnabled(_ defaults: UserDefaults, legacySourceEnabled: Bool = false) -> Bool {
		if defaults.object(forKey: Key.providerUnifiedGrokEnabled) != nil {
			return defaults.bool(forKey: Key.providerUnifiedGrokEnabled)
		}
		let old = [Key.providerGrokEnabled, Key.providerGrokBotEnabled, "JPtheCat.provider.cursor.enabled"]
			.filter { defaults.object(forKey: $0) != nil }
		return legacySourceEnabled || (old.isEmpty ? defaultProviderEnabled : old.contains { defaults.bool(forKey: $0) })
	}

	nonisolated static func providerEnabled(_ provider: ProviderID, _ defaults: UserDefaults = .standard) -> Bool {
		switch provider {
		case .claude:
			return bool(Key.providerClaudeEnabled, default: defaultProviderEnabled, defaults)
		case .codex:
			return bool(Key.providerCodexEnabled, default: defaultProviderEnabled, defaults)
		case .grok, .grokBot, .cursor:
			// Older Cursor capture/plan controls had no master provider preference. Preserve their
			// explicit opt-ins even when the unrelated Grok Build row had been turned off.
			// Isolated defaults suites never consult the real user's capture markers.
			let isStandard = defaults === UserDefaults.standard
			let cursorAllowed = defaults.object(forKey: "JPtheCat.provider.cursor.enabled") == nil
				|| defaults.bool(forKey: "JPtheCat.provider.cursor.enabled")
			let botAllowed = defaults.object(forKey: Key.providerGrokBotEnabled) == nil
				|| defaults.bool(forKey: Key.providerGrokBotEnabled)
			let sourceEnabled = isStandard && (
				(cursorAllowed && (CursorHookSetup.state() == .active || CursorPlanUsageStore.isEnabled()))
				|| (botAllowed && GrokBotPlanUsageStore.isEnabled()))
			return unifiedGrokEnabled(defaults, legacySourceEnabled: sourceEnabled)
		case .opencode:
			return bool(Key.providerOpenCodeZenEnabled, default: defaultProviderEnabled, defaults)
		case .opencodego:
			return bool(Key.providerOpenCodeGoEnabled, default: defaultProviderEnabled, defaults)
		case .museSpark:
			return bool(Key.providerMuseSparkEnabled, default: defaultProviderEnabled, defaults)
		case .nemotron:
			return bool(Key.providerNemotronEnabled, default: defaultProviderEnabled, defaults)
		case .mimo:
			return bool(Key.providerMiMoEnabled, default: defaultProviderEnabled, defaults)
		case .bigPickle:
			return bool(Key.providerBigPickleEnabled, default: defaultProviderEnabled, defaults)
		case .deepseek:
			return bool(Key.providerDeepSeekEnabled, default: defaultProviderEnabled, defaults)
		default:
			return true
		}
	}

	// MARK: - Migration

	/// Fold legacy un-namespaced keys into `JPtheCat.*` once, then retire them. Idempotent: the stored
	/// schema-version guard makes calling this at launch AND in `init` safe.
	nonisolated static func migrateIfNeeded(defaults: UserDefaults = .standard) {
		guard defaults.integer(forKey: Key.schemaVersion) < currentSchemaVersion else { return }
		// v0 → v1: the three alert toggles and the dashboard timeframe were stored un-namespaced.
		foldBool("alerts.usageEnabled", into: Key.usageAlertsEnabled, defaults)
		foldBool("alerts.bannerEnabled", into: Key.alertBannerEnabled, defaults)
		foldBool("alerts.soundEnabled", into: Key.alertSoundEnabled, defaults)
		foldInt("dashboard.timeframeDays", into: Key.timeframeDays, defaults)
		defaults.set(currentSchemaVersion, forKey: Key.schemaVersion)
	}

	/// Copy a legacy value into the namespace only if the user actually had one AND the namespaced key
	/// isn't already set (never clobber a newer value), then retire the legacy key either way.
	private nonisolated static func foldBool(_ legacy: String, into namespaced: String, _ defaults: UserDefaults) {
		if defaults.object(forKey: namespaced) == nil, let value = defaults.object(forKey: legacy) as? Bool {
			defaults.set(value, forKey: namespaced)
		}
		defaults.removeObject(forKey: legacy)
	}

	private nonisolated static func foldInt(_ legacy: String, into namespaced: String, _ defaults: UserDefaults) {
		if defaults.object(forKey: namespaced) == nil, defaults.object(forKey: legacy) != nil {
			defaults.set(defaults.integer(forKey: legacy), forKey: namespaced)
		}
		defaults.removeObject(forKey: legacy)
	}
}
