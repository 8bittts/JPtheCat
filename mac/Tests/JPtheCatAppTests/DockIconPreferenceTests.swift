import AppKit
import XCTest

@testable import JPtheCatApp

final class DockIconPreferenceTests: XCTestCase {
	func testDefaultsToShowingDockIcon() {
		let defaults = temporaryDefaults()

		XCTAssertTrue(DockIconPreference.showDockIcon(defaults: defaults))
		XCTAssertEqual(DockIconPreference.activationPolicy(showDockIcon: true), .regular)
	}

	func testPersistsHiddenDockIconPreference() {
		let defaults = temporaryDefaults()

		DockIconPreference.setShowDockIcon(false, defaults: defaults)

		XCTAssertFalse(DockIconPreference.showDockIcon(defaults: defaults))
		XCTAssertEqual(DockIconPreference.activationPolicy(showDockIcon: false), .accessory)

		DockIconPreference.setShowDockIcon(true, defaults: defaults)

		XCTAssertTrue(DockIconPreference.showDockIcon(defaults: defaults))
	}

	private func temporaryDefaults() -> UserDefaults {
		let suite = "JPtheCatTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defaults.removePersistentDomain(forName: suite)
		return defaults
	}
}
