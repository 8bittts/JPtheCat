import XCTest

/// [NOTE] The chrome-order guard used to read `SettingsBackView.swift` by literal path, which froze
/// that file. It now resolves the host source from the anchor itself through `AppSourceScanner`, so a
/// split moves the guard with the controls and separating them fails loudly.
final class WidgetGalleryButtonTests: XCTestCase {
	func testSettingsTopBarPlacesWidgetButtonBeforeTheDashboardBackControl() throws {
		// Relative order is only meaningful inside ONE source; require both controls to still share it.
		let host = try AppSourceScanner.file(containing: "WidgetGalleryButton()")
		let source = host.text
		let widgetButton = try XCTUnwrap(source.range(of: "WidgetGalleryButton()"))
		let dashboardBack = try XCTUnwrap(
			source.range(of: "DashboardBackLink(action: onClose)"),
			"the settings chrome row must stay in one source (\(host.name))")
		let button = try AppSourceScanner.body(of: "struct WidgetGalleryButton: View {")

		XCTAssertLessThan(widgetButton.lowerBound, dashboardBack.lowerBound)
		XCTAssertTrue(button.contains(".help(\"How to add the widget\")"))
		XCTAssertTrue(button.contains(".accessibilityLabel(\"How to add the widget\")"))
	}

	// macOS has no public API to open the widget gallery, and launching NotificationCenter.app is a
	// silent no-op on modern macOS. The button must instead reload timelines and show reliable, honest
	// add-the-widget guidance — never pretend to open Notification Center via NSWorkspace.
	func testWidgetGalleryOpenerReloadsTimelinesAndShowsGuidance() throws {
		let source = try AppSourceScanner.source(named: "WidgetGalleryOpener.swift")

		XCTAssertTrue(source.contains("WidgetCenter.shared.reloadAllTimelines()"))
		XCTAssertTrue(source.contains("NSAlert"))
		XCTAssertTrue(source.contains("Edit Widgets"))
		// Must NOT resurrect the no-op NotificationCenter.app launch.
		XCTAssertFalse(source.contains("NotificationCenter.app"))
		XCTAssertFalse(source.contains("openApplication"))
	}
}
