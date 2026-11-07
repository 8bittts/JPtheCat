import XCTest

@testable import JPtheCatApp
import JPtheCatCore

private final class SettingsChangeCapture: @unchecked Sendable {
	private let lock = NSLock()
	private var storage: [SettingsStore.Change] = []

	func append(_ change: SettingsStore.Change) {
		lock.lock()
		storage.append(change)
		lock.unlock()
	}

	var values: [SettingsStore.Change] {
		lock.lock()
		defer { lock.unlock() }
		return storage
	}
}

private final class NotificationCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var storage = 0

	func increment() {
		lock.lock()
		storage += 1
		lock.unlock()
	}

	var value: Int {
		lock.lock()
		defer { lock.unlock() }
		return storage
	}
}

/// `SettingsStore` is the single namespaced source of truth for app settings. These tests pin its
/// contract against an ISOLATED UserDefaults suite (never `.standard`): defaults when empty, the
/// one-time legacy→namespaced migration (fold, retire, idempotent, no-clobber), and that an instance
/// write is visible to the nonisolated raw accessors the non-UI consumers use.
@MainActor
final class SettingsStoreTests: XCTestCase {
	nonisolated(unsafe) private var suiteName = ""
	nonisolated(unsafe) private var defaults: UserDefaults!

	override func setUp() {
		super.setUp()
		suiteName = "jpc-settings-\(UUID().uuidString)"
		defaults = UserDefaults(suiteName: suiteName)
	}

	override func tearDown() {
		defaults.removePersistentDomain(forName: suiteName)
		defaults = nil
		super.tearDown()
	}

	// MARK: - Defaults

	func testDefaultsWhenEmpty() {
		let store = SettingsStore(defaults: defaults)
		XCTAssertTrue(store.usageAlertsEnabled)
		XCTAssertTrue(store.alertBannerEnabled)
		XCTAssertTrue(store.alertSoundEnabled)
		XCTAssertTrue(store.interactiveSoundsEnabled)
		XCTAssertEqual(store.timeframeDays, 14)
		XCTAssertEqual(store.menuBarDisplayFormat, .total)
		XCTAssertEqual(store.refreshCadence, .balanced)
		XCTAssertEqual(store.dashboardLayout, .twoColumns)
		XCTAssertFalse(store.onboardingCompleted)
		// The empty-suite path still stamps the schema version so migration doesn't re-run forever.
		XCTAssertEqual(defaults.integer(forKey: SettingsStore.Key.schemaVersion), SettingsStore.currentSchemaVersion)
	}

	func testRawAccessorsReturnDefaultsWhenAbsent() {
		XCTAssertTrue(SettingsStore.usageAlertsEnabled(defaults))
		XCTAssertTrue(SettingsStore.interactiveSoundsEnabled(defaults))
		XCTAssertEqual(SettingsStore.timeframeDays(defaults), 14, "absent int key returns the default, not 0")
		XCTAssertEqual(SettingsStore.menuBarDisplayFormat(defaults), .total)
		XCTAssertEqual(SettingsStore.refreshCadence(defaults), .balanced)
		XCTAssertFalse(SettingsStore.onboardingCompleted(defaults))
	}

	// MARK: - Migration

	func testMigrationFoldsLegacyKeysIntoNamespaceAndRetiresThem() {
		// Seed the pre-namespace world (a user who saved choices before SettingsStore existed).
		defaults.set(false, forKey: "alerts.usageEnabled")
		defaults.set(false, forKey: "alerts.bannerEnabled")
		defaults.set(true, forKey: "alerts.soundEnabled")
		defaults.set(30, forKey: "dashboard.timeframeDays")

		SettingsStore.migrateIfNeeded(defaults: defaults)

		// Folded into the namespace…
		XCTAssertEqual(defaults.object(forKey: SettingsStore.Key.usageAlertsEnabled) as? Bool, false)
		XCTAssertEqual(defaults.object(forKey: SettingsStore.Key.alertBannerEnabled) as? Bool, false)
		XCTAssertEqual(defaults.object(forKey: SettingsStore.Key.alertSoundEnabled) as? Bool, true)
		XCTAssertEqual(defaults.integer(forKey: SettingsStore.Key.timeframeDays), 30)
		// …and the legacy keys retired.
		XCTAssertNil(defaults.object(forKey: "alerts.usageEnabled"))
		XCTAssertNil(defaults.object(forKey: "alerts.bannerEnabled"))
		XCTAssertNil(defaults.object(forKey: "alerts.soundEnabled"))
		XCTAssertNil(defaults.object(forKey: "dashboard.timeframeDays"))

		// A store built over the migrated suite reads the folded values.
		let store = SettingsStore(defaults: defaults)
		XCTAssertFalse(store.usageAlertsEnabled)
		XCTAssertFalse(store.alertBannerEnabled)
		XCTAssertTrue(store.alertSoundEnabled)
		XCTAssertEqual(store.timeframeDays, 30)
	}

	func testMigrationIsIdempotent() {
		defaults.set(false, forKey: "alerts.usageEnabled")
		SettingsStore.migrateIfNeeded(defaults: defaults)
		XCTAssertEqual(defaults.object(forKey: SettingsStore.Key.usageAlertsEnabled) as? Bool, false)

		// A stray legacy key reappears AFTER migration (e.g. an old build wrote it). Because the schema
		// version is already current, a second run must NOT re-fold it — the namespaced value stands.
		defaults.set(true, forKey: SettingsStore.Key.usageAlertsEnabled)  // user later turned it back on
		defaults.set(true, forKey: "alerts.usageEnabled")  // stale legacy write
		SettingsStore.migrateIfNeeded(defaults: defaults)

		XCTAssertEqual(
			defaults.object(forKey: SettingsStore.Key.usageAlertsEnabled) as? Bool, true,
			"a completed migration must not re-fold and clobber the newer namespaced value")
	}

	func testMigrationDoesNotClobberAnAlreadyNamespacedValue() {
		// Both a namespaced value AND a legacy value exist in the same (unmigrated) suite.
		defaults.set(true, forKey: SettingsStore.Key.alertSoundEnabled)
		defaults.set(false, forKey: "alerts.soundEnabled")

		SettingsStore.migrateIfNeeded(defaults: defaults)

		XCTAssertEqual(
			defaults.object(forKey: SettingsStore.Key.alertSoundEnabled) as? Bool, true,
			"the newer namespaced value wins; the legacy value is discarded")
		XCTAssertNil(defaults.object(forKey: "alerts.soundEnabled"), "legacy key is retired regardless")
	}

	func testMigrationWithNoLegacyKeysLeavesDefaults() {
		SettingsStore.migrateIfNeeded(defaults: defaults)
		XCTAssertNil(defaults.object(forKey: SettingsStore.Key.usageAlertsEnabled), "no fold, no write")
		XCTAssertNil(
			defaults.object(forKey: SettingsStore.Key.timeframeDays),
			"an absent legacy timeframe must not write a spurious 0")
		XCTAssertEqual(defaults.integer(forKey: SettingsStore.Key.schemaVersion), 1)
		XCTAssertTrue(SettingsStore.usageAlertsEnabled(defaults), "accessor still returns the default")
	}

	// MARK: - Writes / SoT coherence

	func testInstanceWritePersistsAndIsVisibleToRawAccessors() {
		let store = SettingsStore(defaults: defaults)
		store.usageAlertsEnabled = false
		store.interactiveSoundsEnabled = false
		store.timeframeDays = 90
		store.menuBarDisplayFormat = MenuBarDisplayFormat(kind: .limit)
		store.refreshCadence = .relaxed
		store.onboardingCompleted = true

		// The write reached UserDefaults, so the nonisolated accessors (used by non-UI consumers) agree.
		XCTAssertFalse(SettingsStore.usageAlertsEnabled(defaults))
		XCTAssertFalse(SettingsStore.interactiveSoundsEnabled(defaults))
		XCTAssertEqual(SettingsStore.timeframeDays(defaults), 90)
		XCTAssertEqual(SettingsStore.menuBarDisplayFormat(defaults), MenuBarDisplayFormat(kind: .limit))
		XCTAssertEqual(SettingsStore.refreshCadence(defaults), .relaxed)
		XCTAssertTrue(SettingsStore.onboardingCompleted(defaults))

		// A fresh store over the same suite reads the persisted values.
		let reopened = SettingsStore(defaults: defaults)
		XCTAssertFalse(reopened.usageAlertsEnabled)
		XCTAssertFalse(reopened.interactiveSoundsEnabled)
		XCTAssertEqual(reopened.timeframeDays, 90)
		XCTAssertEqual(reopened.menuBarDisplayFormat, MenuBarDisplayFormat(kind: .limit))
		XCTAssertEqual(reopened.refreshCadence, .relaxed)
		XCTAssertTrue(reopened.onboardingCompleted)
	}

	func testChangedBoolPostsSettingsChangeNotification() {
		let store = SettingsStore(defaults: defaults)
		let changes = SettingsChangeCapture()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { notification in
			if let change = SettingsStore.change(from: notification) {
				changes.append(change)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.alertBannerEnabled = false

		XCTAssertEqual(
			changes.values,
			[
				SettingsStore.Change(
					key: SettingsStore.Key.alertBannerEnabled,
					oldValue: .bool(true),
					newValue: .bool(false))
			])
	}

	func testChangedIntPostsSettingsChangeNotification() {
		let store = SettingsStore(defaults: defaults)
		let changes = SettingsChangeCapture()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { notification in
			if let change = SettingsStore.change(from: notification) {
				changes.append(change)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.timeframeDays = 30

		XCTAssertEqual(
			changes.values,
			[
				SettingsStore.Change(
					key: SettingsStore.Key.timeframeDays,
					oldValue: .int(14),
					newValue: .int(30))
			])
	}

	func testChangedMenuBarDisplayFormatPostsSettingsChangeNotification() {
		let store = SettingsStore(defaults: defaults)
		let changes = SettingsChangeCapture()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { notification in
			if let change = SettingsStore.change(from: notification) {
				changes.append(change)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.menuBarDisplayFormat = MenuBarDisplayFormat(kind: .totalAndLimit)

		XCTAssertEqual(
			changes.values,
			[
				SettingsStore.Change(
					key: SettingsStore.Key.menuBarDisplayFormat,
					oldValue: .string("total"),
					newValue: .string("totalAndLimit"))
			])
	}

	func testChangedInteractiveSoundsPostsSettingsChangeNotification() {
		let store = SettingsStore(defaults: defaults)
		let changes = SettingsChangeCapture()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { notification in
			if let change = SettingsStore.change(from: notification) {
				changes.append(change)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.interactiveSoundsEnabled = false

		XCTAssertEqual(
			changes.values,
			[
				SettingsStore.Change(
					key: SettingsStore.Key.interactiveSoundsEnabled,
					oldValue: .bool(true),
					newValue: .bool(false))
			])
	}

	func testChangedRefreshCadencePostsSettingsChangeNotification() {
		let store = SettingsStore(defaults: defaults)
		let changes = SettingsChangeCapture()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { notification in
			if let change = SettingsStore.change(from: notification) {
				changes.append(change)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.refreshCadence = .batterySaver

		XCTAssertEqual(
			changes.values,
			[
				SettingsStore.Change(
					key: SettingsStore.Key.refreshCadence,
					oldValue: .string("balanced"),
					newValue: .string("batterySaver"))
			])
	}

	func testDashboardLayoutPersistsAndPostsOneChangePerRealSwitch() {
		let store = SettingsStore(defaults: defaults)
		let changes = SettingsChangeCapture()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { notification in
			if let change = SettingsStore.change(from: notification) {
				changes.append(change)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.dashboardLayout = .oneColumn
		store.dashboardLayout = .oneColumn  // a redundant set is a no-op

		XCTAssertEqual(defaults.string(forKey: SettingsStore.Key.dashboardLayout), "oneColumn")
		XCTAssertEqual(SettingsStore.dashboardLayout(defaults), .oneColumn)
		XCTAssertEqual(SettingsStore(defaults: defaults).dashboardLayout, .oneColumn, "a relaunch keeps the choice")
		XCTAssertEqual(
			changes.values,
			[
				SettingsStore.Change(
					key: SettingsStore.Key.dashboardLayout,
					oldValue: .string("twoColumns"),
					newValue: .string("oneColumn"))
			])
	}

	func testUnknownStoredDashboardLayoutFallsBackToTheDefault() {
		defaults.set("threeColumns", forKey: SettingsStore.Key.dashboardLayout)
		XCTAssertEqual(SettingsStore.dashboardLayout(defaults), .twoColumns)
		XCTAssertEqual(SettingsStore(defaults: defaults).dashboardLayout, .twoColumns)
	}

	func testChangedOnboardingCompletedPostsSettingsChangeNotification() {
		let store = SettingsStore(defaults: defaults)
		let changes = SettingsChangeCapture()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { notification in
			if let change = SettingsStore.change(from: notification) {
				changes.append(change)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.onboardingCompleted = true

		XCTAssertEqual(
			changes.values,
			[
				SettingsStore.Change(
					key: SettingsStore.Key.onboardingCompleted,
					oldValue: .bool(false),
					newValue: .bool(true))
			])
	}

	func testInvalidStoredRefreshCadenceFallsBackToDefault() {
		defaults.set("oops", forKey: SettingsStore.Key.refreshCadence)

		XCTAssertEqual(SettingsStore.refreshCadence(defaults), .balanced)
		XCTAssertEqual(SettingsStore(defaults: defaults).refreshCadence, .balanced)
	}

	func testInvalidStoredMenuBarDisplayFormatFallsBackToDefault() {
		defaults.set("oops", forKey: SettingsStore.Key.menuBarDisplayFormat)

		XCTAssertEqual(SettingsStore.menuBarDisplayFormat(defaults), .total)
		XCTAssertEqual(SettingsStore(defaults: defaults).menuBarDisplayFormat, .total)
	}

	func testRedundantSetDoesNotPostSettingsChangeNotification() {
		let store = SettingsStore(defaults: defaults)
		let notificationCount = NotificationCounter()
		let observer = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: store, queue: nil
		) { _ in
			notificationCount.increment()
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		store.alertSoundEnabled = true

		XCTAssertEqual(notificationCount.value, 0)
	}

	func testEveryKeyIsNamespaced() {
		let keys = [
			SettingsStore.Key.schemaVersion,
			SettingsStore.Key.usageAlertsEnabled,
			SettingsStore.Key.alertBannerEnabled,
			SettingsStore.Key.alertSoundEnabled,
			SettingsStore.Key.interactiveSoundsEnabled,
			SettingsStore.Key.timeframeDays,
			SettingsStore.Key.menuBarDisplayFormat,
			SettingsStore.Key.refreshCadence,
			SettingsStore.Key.onboardingCompleted,
		]
		XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("JPtheCat.") })
		XCTAssertEqual(Set(keys).count, keys.count, "keys are distinct")
	}
}
