import XCTest

/// [NOTE] These guards used to read `DashboardView.swift` / `SettingsBackView.swift` by literal path
/// and slice them with "from marker X to marker Y" ranges, which froze both files: any extraction
/// either broke the slice or silently emptied it, turning every `XCTAssertFalse` into a vacuous pass.
/// Each slice is now a brace-matched declaration resolved by `AppSourceScanner` wherever it lives, and
/// throws when the anchor is missing — a moved control fails loudly instead of going green.
final class DashboardChromePlacementTests: XCTestCase {
	func testDashboardFaceChromeShowsDisplayCycleLayoutThenGear() throws {
		let controls = try AppSourceScanner.member("var headerControls: some View", of: "DashboardView")

		XCTAssertTrue(controls.contains("SettingsLink"))
		XCTAssertTrue(controls.contains("MenuBarDisplayCycleButton("))
		let cycle = try XCTUnwrap(controls.range(of: "MenuBarDisplayCycleButton("))
		let layout = try XCTUnwrap(
			controls.range(of: "DashboardLayoutButton(layout: layout) { settings.dashboardLayout = layout.next }"))
		let settings = try XCTUnwrap(controls.range(of: "SettingsLink"))
		XCTAssertLessThan(cycle.lowerBound, layout.lowerBound)
		XCTAssertLessThan(layout.lowerBound, settings.lowerBound)
		XCTAssertFalse(controls.contains("DashboardBackLink"))
		XCTAssertFalse(controls.contains("PinButton("))
		XCTAssertFalse(controls.contains("WidgetGalleryButton"))
		XCTAssertFalse(controls.contains("ThemeToggleButton"))
		XCTAssertFalse(controls.contains("UpdateStatusDot"))
	}

	/// Refresh lives ONLY in the shared footer, never the top chrome row — a duplicate top-bar Refresh
	/// (redundant with the footer's) was removed. Settings' own top bar is the display cycle, layout,
	/// Pin, Widget, and the dashboard-back control last.
	func testSettingsTopBarPlacesDashboardControlLast() throws {
		// Relative order only means anything inside ONE source, so resolve the host from the anchor and
		// require every sibling control to still live there. Drifting apart fails loudly.
		let host = try AppSourceScanner.file(containing: "PinButton(isPinned: chrome.isPinned")
		let source = host.text
		let pin = try XCTUnwrap(source.range(of: "PinButton(isPinned: chrome.isPinned"))
		let cycle = try XCTUnwrap(
			source.range(of: "MenuBarDisplayCycleButton("),
			"the settings chrome row must stay in one source (\(host.name))")
		let widget = try XCTUnwrap(
			source.range(of: "WidgetGalleryButton()"),
			"the settings chrome row must stay in one source (\(host.name))")
		let layout = try XCTUnwrap(
			source.range(of: "DashboardLayoutButton(layout: layout) { settings.dashboardLayout = layout.next }"),
			"the settings chrome row must stay in one source (\(host.name))")
		let back = try XCTUnwrap(
			source.range(of: "DashboardBackLink(action: onClose)"),
			"the settings chrome row must stay in one source (\(host.name))")

		// ORDER is what this file owns — verify-app-demo-parity.sh uses order-blind `grep -Fq`, so it
		// cannot express these. `ChromeRefreshButton` absence is asserted there (:66) and not repeated.
		XCTAssertLessThan(cycle.lowerBound, layout.lowerBound)
		XCTAssertLessThan(layout.lowerBound, pin.lowerBound)
		XCTAssertLessThan(pin.lowerBound, widget.lowerBound)
		XCTAssertLessThan(widget.lowerBound, back.lowerBound)
	}

	func testDisplayCycleButtonUsesObviousMenuBarIconAndAccessibleCurrentValue() throws {
		let source = try AppSourceScanner.body(of: "struct MenuBarDisplayCycleButton: View {")
		XCTAssertTrue(source.contains(#"Image(systemName: "menubar.rectangle")"#))
		XCTAssertTrue(source.contains(#".accessibilityLabel("Cycle menu bar display")"#))
		XCTAssertTrue(source.contains("format.settingsTitle"))
	}

	func testLayoutButtonDrawsTheCurrentLayoutAndVoicesItsValue() throws {
		let source = try AppSourceScanner.body(of: "struct DashboardLayoutButton: View {")
		XCTAssertTrue(source.contains("Image(systemName: layout.systemImage)"))
		XCTAssertTrue(source.contains(#".accessibilityLabel("Dashboard layout")"#))
		XCTAssertTrue(source.contains(".accessibilityValue(layout.title)"))
		XCTAssertTrue(source.contains("JPTooltip.dashboardLayout(current: layout)"))
	}

	func testSettingsChromeUsesCompactUniformSlots() throws {
		let allSources = try AppSourceScanner.joined()
		// The uniform-slot counts are scoped to the chrome control declarations themselves rather than
		// to a file, so a split moves the count with the controls instead of halving it. Each anchor
		// throws if its control is renamed or deleted.
		let dashboardChrome = try AppSourceScanner.bodies(of: [
			"struct PinButton: View {",
			"struct MenuBarDisplayCycleButton: View {",
			"struct DashboardLayoutButton: View {",
			"struct SettingsLink: View {",
		])
		let settingsChrome = try AppSourceScanner.bodies(of: [
			"struct WidgetGalleryButton: View {",
			"struct DashboardBackLink: View {",
		])

		let settingsChromeRow = try AppSourceScanner.member(
			"var settingsChromeControls: some View", of: "SettingsBackView")

		XCTAssertTrue(allSources.contains("static let chromeControlGap: CGFloat = 4"))
		XCTAssertTrue(allSources.contains("static let chromeControlSize: CGFloat = 26"))
		XCTAssertTrue(settingsChromeRow.contains("HStack(spacing: JPAppSpacing.chromeControlGap)"))
		XCTAssertFalse(allSources.contains("HStack(spacing: 8) {\n      Text(\"JP the Cat"))
		XCTAssertGreaterThanOrEqual(
			dashboardChrome.components(separatedBy: "JPAppSpacing.chromeControlSize").count - 1, 4)
		XCTAssertGreaterThanOrEqual(
			settingsChrome.components(separatedBy: "JPAppSpacing.chromeControlSize").count - 1, 4)
	}

	/// Quit sits immediately before the JP mark/share button — not between Refresh and Help — so it
	/// reads as adjacent to the JP identity glyph, matching the main dashboard window's own chrome.
	func testSharedFooterCarriesRefreshAnalyticsHelpAccessoryQuitBeforeJPMark() throws {
		let footer = try AppSourceScanner.body(of: "struct DashboardCardFooter<Accessory: View>: View")
		let refresh = try XCTUnwrap(footer.range(of: #"systemImage: "arrow.clockwise""#))
		let analytics = try XCTUnwrap(footer.range(of: "AdvancedAnalyticsFooterButton("))
		let help = try XCTUnwrap(footer.range(of: #"systemImage: "questionmark.circle""#))
		let accessory = try XCTUnwrap(footer.range(of: "accessory()"))
		let quit = try XCTUnwrap(footer.range(of: #"systemImage: "power""#))
		let share = try XCTUnwrap(footer.range(of: "SocialShareButton()"))

		XCTAssertLessThan(refresh.lowerBound, analytics.lowerBound)
		XCTAssertLessThan(analytics.lowerBound, help.lowerBound)
		XCTAssertLessThan(help.lowerBound, accessory.lowerBound)
		XCTAssertLessThan(accessory.lowerBound, quit.lowerBound)
		XCTAssertLessThan(quit.lowerBound, share.lowerBound)
		XCTAssertTrue(footer.contains(#"helpText: "Refresh now""#))
		XCTAssertTrue(footer.contains(#"helpText: "Quit JP the Cat""#))
		XCTAssertTrue(footer.contains(#"helpText: "Open JP the Cat website""#))
	}

	/// Both faces share the exact same footer icon set — Settings previously omitted Refresh and the
	/// Advanced Analytics icon, which read as "missing" controls compared to the dashboard face.
	func testSettingsFooterMirrorsDashboardFooterIconSet() throws {
		// `var footer: some View` exists on BOTH faces, so it is resolved through the owning
		// type's surface rather than by file name.
		let footer = try AppSourceScanner.member("var footer: some View", of: "SettingsBackView")

		XCTAssertTrue(footer.contains("accessory: { UpdateStatusDot(currentVersion: appVersion) }"))
		XCTAssertTrue(footer.contains("onRefresh: { model.refresh() }"))
		XCTAssertTrue(footer.contains("onOpenAdvancedAnalytics: onOpenAdvancedAnalytics"))
	}

	/// The dashboard face previously omitted the update-notification dot, only visible after opening
	/// Settings — both faces must show it so an available update is never hidden behind a click.
	func testDashboardFooterAlsoHostsUpdateStatusDotAccessory() throws {
		let footer = try AppSourceScanner.member("var footer: some View", of: "DashboardView")

		XCTAssertTrue(footer.contains("accessory: { UpdateStatusDot(currentVersion: appVersion) }"))
	}

	func testFooterShareContractUsesCanonicalHeaderAndTwitterMention() throws {
		let source = try AppSourceScanner.bodies(of: [
			"struct SocialSharePopover: View",
			"struct SocialShareDestination: Identifiable",
		])

		XCTAssertTrue(source.contains(#"Text("Tell others about JP")"#))
		XCTAssertTrue(source.contains(#"title: "X / Twitter""#))
		XCTAssertTrue(source.contains(#"@8bit"#))
		XCTAssertTrue(source.contains(#"static let siteURL = "https://jpthecat.com""#))
		XCTAssertTrue(source.contains(#"NSPasteboard.general"#))
	}
}
