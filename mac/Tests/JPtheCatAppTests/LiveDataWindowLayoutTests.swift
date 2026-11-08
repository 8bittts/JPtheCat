import AppKit
import JPtheCatCore
import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Deterministic layout coverage for the Live Data window (`LiveDataWindowContent` hosted by
/// `LiveDataWindowController`): fixed width, intrinsic height, no `ScrollView`.
///
/// [Regression guard — shipped] `SettingsToggleRow` clamped every subtitle to ONE line with
/// `minimumScaleFactor(0.8)`, so the OpenCode Zen / Go accounting copy shrank and then ellipsized
/// ("Gateway view, not in totals · excluded from combined…"). The window's height is measured from
/// `NSHostingView.fittingSize`, so the fix had to make the WRAPPED height reach that measurement
/// (`fixedSize(horizontal: false, vertical: true)`) rather than hide the overflow behind padding.
///
/// Row visibility is driven through `LiveDataWindowContent.Detection` — a test may only pick which
/// detectors read "true"; the production gates and `ProviderOptInRow`'s own state probe are untouched.
/// SwiftUI exposes no row frames in-process (the hosting view's accessibility tree is empty without an
/// assistive client), so every assertion below is height arithmetic on the SAME `fittingSize` the
/// controller sizes the window from.
@MainActor
final class LiveDataWindowLayoutTests: XCTestCase {
	/// The longest enabled subtitle the window renders today (OpenCode Go).
	private static let longestSubtitle =
		"Gateway view · not in totals or alerts · measured 5-hour & weekly usage vs Go's caps"
	/// Two explicit caption lines: the exact two-line row height every Live Data subtitle must fit.
	private static let twoLineProbe = "line one\nline two"

	/// Rows under `.everything`: Claude + Claude limits, Codex, Grok + limits + Cursor + plan usage,
	/// Muse Spark, four brands, Zen, Go, Copilot.
	private static let maximumRowCount = 15
	/// Claude, Claude live limits, Codex — the only rows with no detection gate.
	private static let ungatedRowCount = 3
	/// A row is at least chip/title + one caption line + vertical padding; never less than this.
	private static let minimumRowHeight: CGFloat = 40

	// MARK: - One row

	private func rowHeight(subtitle: String, wraps: Bool, indented: Bool = false) -> CGFloat {
		let row = SettingsToggleRow(
			icon: "gauge.with.dots.needle.33percent", title: "OpenCode Go", subtitle: subtitle,
			providerMark: ("provider-opencodego", JPAppColor.openCodeGoTintHex),
			layout: wraps ? .liveData : .settingsFace, indented: indented, isOn: .constant(true)
		)
		// The well's inner width: window width minus the body's horizontal panel inset.
		.frame(width: JPAppSpacing.liveDataWindowW - 2 * JPAppSpacing.panelX)
		let host = NSHostingView(rootView: row)
		host.layoutSubtreeIfNeeded()
		return host.fittingSize.height
	}

	/// A long subtitle in a wrapping row adds whole caption lines to the row's fitting height — the
	/// height the window is sized from — instead of shrinking and ellipsizing inside a one-line slot.
	func testLongSubtitleWrapsAndGrowsTheRowInsteadOfTruncating() {
		let oneLine = rowHeight(subtitle: "Short", wraps: true)
		let wrapped = rowHeight(subtitle: Self.longestSubtitle, wraps: true)
		// `JPAppFont.caption` is 11pt, so one additional line is at least 12pt of extra height.
		XCTAssertGreaterThanOrEqual(wrapped - oneLine, 12, "the long subtitle must add at least one caption line")
		let twoLines = rowHeight(subtitle: Self.twoLineProbe, wraps: true)
		XCTAssertLessThanOrEqual(wrapped, twoLines + 0.5, "an ~85-character caption must wrap to two lines, not more")
		// The Settings-face default (no wrap) can only SHRINK the same text — it never grows the row,
		// which is the behavior the intrinsic-height, no-scroll Settings face relies on.
		let clamped = rowHeight(subtitle: Self.longestSubtitle, wraps: false)
		XCTAssertLessThanOrEqual(clamped, oneLine + 0.5, "the Settings face stays one line per subtitle")
	}

	/// The dependent-row inset narrows the text column, so an indented row may wrap one line earlier,
	/// never fewer: its height is never below the flush row's.
	func testIndentedRowNeverLosesHeightToTheInset() {
		let flush = rowHeight(subtitle: Self.longestSubtitle, wraps: true)
		let indented = rowHeight(subtitle: Self.longestSubtitle, wraps: true, indented: true)
		XCTAssertGreaterThanOrEqual(indented, flush)
		XCTAssertLessThanOrEqual(indented, rowHeight(subtitle: Self.twoLineProbe, wraps: true, indented: true) + 0.5, "indented, the longest subtitle still fits two lines")
	}

	// MARK: - The real window

	private struct OpenedWindow {
		let controller: LiveDataWindowController
		let parent: NSWindow
		let window: NSWindow
		let host: NSView
	}

	private func openLiveData(_ detection: LiveDataWindowContent.Detection) throws -> OpenedWindow {
		let parent = NSWindow(
			contentRect: NSRect(x: 600, y: 200, width: 384, height: 600),
			styleMask: [.titled, .closable], backing: .buffered, defer: false)
		parent.orderFront(nil)
		let controller = LiveDataWindowController(
			model: DashboardViewModel(index: nil), dashboardChrome: DashboardChromeState(),
			detection: detection)
		controller.open(attachingTo: parent)
		let window = try XCTUnwrap(parent.childWindows?.first, "the Live Data window attaches as a child")
		let host = try XCTUnwrap(window.contentViewController?.view)
		host.layoutSubtreeIfNeeded()
		return OpenedWindow(controller: controller, parent: parent, window: window, host: host)
	}

	private func close(_ opened: OpenedWindow) {
		opened.controller.close()
		opened.parent.orderOut(nil)
	}

	private func windowHeight(_ detection: LiveDataWindowContent.Detection) throws -> CGFloat {
		let opened = try openLiveData(detection)
		defer { close(opened) }
		return opened.window.frame.height
	}

	/// With EVERY detection gate open, the window is exactly as tall as the content it hosts — the
	/// measurement is stable across a second layout pass (a wrapped caption that measured one line
	/// and rendered two would move it) — and tall enough for fifteen full rows plus the body insets.
	/// That is what "the last row fits" means for an intrinsic-height window: there is no separate
	/// clip to escape, only a height that must account for every wrapped line.
	func testEveryRowFitsInsideTheIntrinsicWindowForTheMaximumDetectedSet() throws {
		let opened = try openLiveData(.everything)
		defer { close(opened) }
		let window = opened.window

		XCTAssertEqual(window.frame.width, JPAppSpacing.liveDataWindowW)
		XCTAssertFalse(window.styleMask.contains(.resizable), "intrinsic height: the user never resizes it")
		XCTAssertNil(opened.host.enclosingScrollView, "no ScrollView — the contract is intrinsic height")

		let measured = opened.host.fittingSize.height
		XCTAssertEqual(
			window.frame.height, measured, accuracy: 0.5,
			"the window is exactly as tall as the content it hosts — no dead space, no clipped tail")
		opened.host.needsLayout = true
		opened.host.layoutSubtreeIfNeeded()
		XCTAssertEqual(opened.host.fittingSize.height, measured, accuracy: 0.5, "a second layout pass must not change the height")

		// Chrome row + hairline + body insets + the well's fifteen rows and their dividers.
		let chrome = JPAppSpacing.chromeHeight + 1
		let bodyInsets = 2 * JPAppSpacing.settingsBodyY
		let floor = chrome + bodyInsets + CGFloat(Self.maximumRowCount) * Self.minimumRowHeight
		XCTAssertGreaterThanOrEqual(measured, floor, "fifteen rows cannot fit in \(measured)pt")
		// And no row runs past three lines: fifteen rows at a generous 3-line budget bound the top.
		XCTAssertLessThanOrEqual(measured, chrome + bodyInsets + CGFloat(Self.maximumRowCount) * 80)
	}

	/// With NO detector reading true, only the three ungated rows render: the window shrinks by at least
	/// twelve rows, so a fixture cannot leak a gated row and a screenshot cannot "show every row" by
	/// weakening detection.
	func testDetectionGatesHideEveryOptionalRowOnAnEmptyFixture() throws {
		let everything = try windowHeight(.everything)
		let nothing = try windowHeight(LiveDataWindowContent.Detection())
		let hiddenRows = CGFloat(Self.maximumRowCount - Self.ungatedRowCount)
		XCTAssertGreaterThanOrEqual(everything - nothing, hiddenRows * Self.minimumRowHeight)
		// The three ungated rows alone: chrome + insets + three rows, each under three lines.
		let chrome = JPAppSpacing.chromeHeight + 1 + 2 * JPAppSpacing.settingsBodyY
		XCTAssertGreaterThanOrEqual(nothing, chrome + CGFloat(Self.ungatedRowCount) * Self.minimumRowHeight)
		XCTAssertLessThanOrEqual(nothing, chrome + CGFloat(Self.ungatedRowCount) * 80)
	}

	/// A single provider group: the Grok enable row plus its three dependents and one divider. The
	/// window grows by exactly those rows' worth — no gated sibling slips in with them.
	func testGrokGroupRendersOnlyItsOwnDependents() throws {
		let nothing = try windowHeight(LiveDataWindowContent.Detection())
		var detection = LiveDataWindowContent.Detection()
		detection.grokBuild = true
		detection.cursorCLI = true
		detection.grokBot = true
		let grokGroup = try windowHeight(detection)
		let added = grokGroup - nothing
		XCTAssertGreaterThanOrEqual(added, 4 * Self.minimumRowHeight, "Grok + 3 dependents must render")
		XCTAssertLessThanOrEqual(added, 4 * 80 + 1, "only the Grok group may render for a Grok-only fixture")
	}

	/// Each enable row's disabled line and every opt-in subtitle must fit two caption lines at the
	/// window width, so the window's growth stays bounded as providers are detected.
	func testEveryLiveDataSubtitleFitsTwoLinesAtWindowWidth() throws {
		let twoLineBudget = rowHeight(subtitle: Self.twoLineProbe, wraps: true, indented: true) + 0.5
		var subtitles: [String] = SettingsBackView.brandRows.map(\.subtitle)
		for descriptor in [
			SettingsBackView.claudeLiveLimits, SettingsBackView.grokLiveLimits, SettingsBackView.cursorLiveData,
			SettingsBackView.grokPlanUsage, SettingsBackView.copilotLiveData,
		] {
			subtitles += [
				descriptor.subtitle(.active, true), descriptor.subtitle(.active, false),
				descriptor.subtitle(.installable, false), descriptor.subtitle(.unavailable, false),
			]
		}
		// The enable-row literals live in the view body; scan them out so a new row is covered too.
		let content = try AppSourceScanner.body(of: "struct LiveDataWindowContent")
		let literal = try NSRegularExpression(pattern: #"(?:enabled|disabled): (?:String = )?"([^"]+)""#)
		for match in literal.matches(in: content, range: NSRange(content.startIndex..., in: content)) {
			if let range = Range(match.range(at: 1), in: content) { subtitles.append(String(content[range])) }
		}
		XCTAssertGreaterThanOrEqual(subtitles.count, 30)
		for subtitle in subtitles {
			let indented = rowHeight(subtitle: subtitle, wraps: true, indented: true)
			XCTAssertLessThanOrEqual(indented, twoLineBudget, "subtitle runs past two lines: \(subtitle)")
		}
	}
}
