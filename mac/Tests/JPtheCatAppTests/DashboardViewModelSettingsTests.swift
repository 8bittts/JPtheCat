import XCTest

@testable import JPtheCatApp

@MainActor
final class DashboardViewModelSettingsTests: XCTestCase {
	nonisolated(unsafe) private var suiteName = ""
	nonisolated(unsafe) private var defaults: UserDefaults!

	override func setUp() {
		super.setUp()
		suiteName = "jpc-dashboard-settings-\(UUID().uuidString)"
		defaults = UserDefaults(suiteName: suiteName)
	}

	override func tearDown() {
		defaults.removePersistentDomain(forName: suiteName)
		defaults = nil
		super.tearDown()
	}

	func testInitializesFromInjectedSettingsStoreTimeframe() {
		defaults.set(30, forKey: SettingsStore.Key.timeframeDays)
		let store = SettingsStore(defaults: defaults)

		let model = DashboardViewModel(index: nil, settingsStore: store)

		XCTAssertEqual(model.selectedDays, 30)
	}

	func testInjectedSettingsStoreFanoutUpdatesSelectedTimeframe() {
		let store = SettingsStore(defaults: defaults)
		let model = DashboardViewModel(index: nil, settingsStore: store)
		XCTAssertEqual(model.selectedDays, 14)

		store.timeframeDays = 30
		drainMainQueue()

		XCTAssertEqual(model.selectedDays, 30)

		store.timeframeDays = 12
		drainMainQueue()

		XCTAssertEqual(model.selectedDays, 14, "unsupported stored values normalize to the dashboard default")
	}

	func testProviderEnablementDefaultsOnAndPersists() {
		let store = SettingsStore(defaults: defaults)
		XCTAssertTrue(store.claudeProviderEnabled)
		XCTAssertTrue(store.codexProviderEnabled)
		XCTAssertTrue(SettingsStore.providerEnabled(.claude, defaults))
		XCTAssertTrue(SettingsStore.providerEnabled(.codex, defaults))

		store.codexProviderEnabled = false

		XCTAssertFalse(SettingsStore.providerEnabled(.codex, defaults))
		XCTAssertTrue(SettingsStore.providerEnabled(.claude, defaults))
	}

	private func drainMainQueue() {
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
	}
}
