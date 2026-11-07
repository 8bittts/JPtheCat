import AppKit
import SwiftUI
import XCTest

@testable import JPtheCatApp

final class DashboardSizingTests: XCTestCase {
	/// `DashboardView` reads the shared store, so a test that picks a layout restores the stored value.
	@MainActor
	private func withDashboardLayout(_ layout: DashboardLayout, _ body: () throws -> Void) rethrows {
		let key = SettingsStore.Key.dashboardLayout
		let stored = UserDefaults.standard.object(forKey: key)
		let previous = SettingsStore.shared.dashboardLayout
		SettingsStore.shared.dashboardLayout = layout
		defer {
			SettingsStore.shared.dashboardLayout = previous
			if let stored {
				UserDefaults.standard.set(stored, forKey: key)
			} else {
				UserDefaults.standard.removeObject(forKey: key)
			}
		}
		try body()
	}

	@MainActor
	func testFirstRunDashboardPreferredHeightStaysCompact() {
		let previousOnboardingValue = UserDefaults.standard.object(forKey: SettingsStore.Key.onboardingCompleted)
		UserDefaults.standard.set(false, forKey: SettingsStore.Key.onboardingCompleted)
		defer {
			if let previousOnboardingValue {
				UserDefaults.standard.set(previousOnboardingValue, forKey: SettingsStore.Key.onboardingCompleted)
			} else {
				UserDefaults.standard.removeObject(forKey: SettingsStore.Key.onboardingCompleted)
			}
		}

		for layout in DashboardLayout.allCases {
			withDashboardLayout(layout) {
				let model = DashboardViewModel(index: nil)
				let host = NSHostingController(rootView: DashboardView(model: model))
				host.sizingOptions = .preferredContentSize
				host.view.layoutSubtreeIfNeeded()

				XCTAssertEqual(host.preferredContentSize.width, layout.width, accuracy: 1)
				XCTAssertGreaterThan(host.preferredContentSize.height, 0)
				XCTAssertLessThan(
					host.preferredContentSize.height, DashboardSurfaceMetrics.initialWindowSize(for: layout).height)
			}
		}
	}

	/// The chrome toggle writes the store; the live card must follow without a relaunch.
	@MainActor
	func testSwitchingLayoutResizesTheLiveCard() {
		withDashboardLayout(.twoColumns) {
			let model = DashboardViewModel(index: nil)
			let host = NSHostingController(rootView: DashboardView(model: model))
			host.sizingOptions = .preferredContentSize
			host.view.layoutSubtreeIfNeeded()
			XCTAssertEqual(host.preferredContentSize.width, 768, accuracy: 1)

			SettingsStore.shared.dashboardLayout = SettingsStore.shared.dashboardLayout.next
			host.view.layoutSubtreeIfNeeded()
			XCTAssertEqual(host.preferredContentSize.width, 384, accuracy: 1)

			SettingsStore.shared.dashboardLayout = SettingsStore.shared.dashboardLayout.next
			host.view.layoutSubtreeIfNeeded()
			XCTAssertEqual(host.preferredContentSize.width, 768, accuracy: 1)
		}
	}

	@MainActor
	func testSettingsFacePreferredHeightIsIntrinsic() {
		var heights: [DashboardLayout: CGFloat] = [:]
		for layout in DashboardLayout.allCases {
			let model = DashboardViewModel(index: nil)
			let host = NSHostingController(
				rootView: SettingsBackView(model: model, onClose: {}).environment(\.dashboardLayout, layout))
			host.sizingOptions = .preferredContentSize
			host.view.layoutSubtreeIfNeeded()
			heights[layout] = host.preferredContentSize.height

			XCTAssertEqual(host.preferredContentSize.width, layout.width, accuracy: 1)
			XCTAssertGreaterThan(host.preferredContentSize.height, 0)
			// Intrinsic (fits its sections: General + Live data + Alerts + a bottom "Appearance"
			// theme picker), not unbounded. The window resizes to this exact height on appear, so keep the
			// compact settings cleanup from regressing into the old tall face with Refresh/website rows.
			// 1260 is a CEILING, not a target: it guards against a return to the old tall SCROLLING
			// panel, so it is deliberately never tightened to the current measurement. A host that
			// detects a local Grok install renders an extra row and measures ~1221, so the ceiling
			// must clear that.
			XCTAssertLessThan(host.preferredContentSize.height, 1260)
		}
		// One column stacks the same four sections, so it is taller than the side-by-side face.
		XCTAssertGreaterThan(heights[.oneColumn] ?? 0, heights[.twoColumns] ?? 0)
	}

	/// The Advanced Analytics footer icon (`AdvancedAnalyticsFooterButton`, a fixed-size icon in the
	/// shared footer's icon row, not a separate banner row) must not blow the intrinsic-height budget
	/// or introduce scrolling — mirrors `testFirstRunDashboardPreferredHeightStaysCompact`'s exact
	/// measurement convention (a real `NSHostingController.preferredContentSize` read, not a guess).
	@MainActor
	func testAdvancedAnalyticsFooterIconDoesNotBreakTheIntrinsicHeightNoScrollContract() {
		let previousOnboardingValue = UserDefaults.standard.object(forKey: SettingsStore.Key.onboardingCompleted)
		UserDefaults.standard.set(true, forKey: SettingsStore.Key.onboardingCompleted)
		defer {
			if let previousOnboardingValue {
				UserDefaults.standard.set(previousOnboardingValue, forKey: SettingsStore.Key.onboardingCompleted)
			} else {
				UserDefaults.standard.removeObject(forKey: SettingsStore.Key.onboardingCompleted)
			}
		}

		for layout in DashboardLayout.allCases {
			withDashboardLayout(layout) {
				let model = DashboardViewModel(index: nil)
				let host = NSHostingController(rootView: DashboardView(model: model))
				host.sizingOptions = .preferredContentSize
				host.view.layoutSubtreeIfNeeded()

				XCTAssertEqual(host.preferredContentSize.width, layout.width, accuracy: 1)
				XCTAssertGreaterThan(host.preferredContentSize.height, 0)
				// Same ceiling as the first-run test: the empty-state front face plus the footer's Advanced
				// Analytics/update-dot icons stays well under the 700pt initial window size, i.e. no internal
				// scrolling was introduced.
				XCTAssertLessThan(
					host.preferredContentSize.height, DashboardSurfaceMetrics.initialWindowSize(for: layout).height)
			}
		}
	}

	/// A layout switch keeps the top and trailing edges, so the chrome toggle stays under the pointer.
	func testLayoutSwitchKeepsTopAndTrailingEdges() {
		let visible = NSRect(x: 0, y: 0, width: 2056, height: 1289)
		let wide = NSRect(x: 1200, y: 400, width: 768, height: 600)
		let narrow = DashboardWindowSizing.framePreservingTopTrailingEdges(
			currentFrame: wide, targetFrameSize: NSSize(width: 384, height: 700), visibleFrame: visible)
		XCTAssertEqual(narrow.maxX, wide.maxX, accuracy: 0.001)
		XCTAssertEqual(narrow.maxY, wide.maxY, accuracy: 0.001)
		XCTAssertEqual(narrow.size, NSSize(width: 384, height: 700))

		let back = DashboardWindowSizing.framePreservingTopTrailingEdges(
			currentFrame: narrow, targetFrameSize: wide.size, visibleFrame: visible)
		XCTAssertEqual(back, wide, "switching back restores the original frame")
	}

	/// AppKit resizes a hosting window keeping its top-left corner. The live fix re-anchors that
	/// resize on the frame captured before the switch; a height-only resize leaves the anchor pending.
	func testLayoutSwitchReanchorsAppKitsTopLeftResizeOnTheTrailingEdge() throws {
		let visible = NSRect(x: 0, y: 0, width: 2056, height: 1289)
		let before = NSRect(x: 1227, y: 5, width: 384, height: 1236)
		// What AppKit produced live: same top-left, twice the width, a shorter card.
		let appKit = NSRect(x: 1227, y: 163, width: 768, height: 1078)
		let fixed = try XCTUnwrap(
			DashboardWindowSizing.frameAfterLayoutSwitch(anchor: before, resizedFrame: appKit, visibleFrame: visible))
		XCTAssertEqual(fixed.maxX, before.maxX, accuracy: 0.001)
		XCTAssertEqual(fixed.maxY, before.maxY, accuracy: 0.001)
		XCTAssertEqual(fixed.size, appKit.size)

		let heightOnly = NSRect(x: 1227, y: 105, width: 384, height: 1136)
		XCTAssertNil(
			DashboardWindowSizing.frameAfterLayoutSwitch(anchor: before, resizedFrame: heightOnly, visibleFrame: visible))
	}

	/// Growing from one column near a display's leading edge shifts inside the display, including one
	/// with a negative origin, instead of hanging the card off-screen.
	func testWideningNearTheLeadingEdgeStaysOnTheDisplay() {
		for x: CGFloat in [-1512, 0] {
			let visible = NSRect(x: x, y: 0, width: 1512, height: 944)
			let narrow = NSRect(x: x + 20, y: 200, width: 384, height: 600)
			let result = DashboardWindowSizing.framePreservingTopTrailingEdges(
				currentFrame: narrow, targetFrameSize: NSSize(width: 768, height: 600), visibleFrame: visible)
			XCTAssertTrue(visible.contains(result))
			XCTAssertEqual(result.minX, visible.minX, accuracy: 0.001)
			XCTAssertEqual(result.maxY, narrow.maxY, accuracy: 0.001)
		}
	}

	func testGrowingDetailKeepsFooterInsideTheDisplay() {
		for x: CGFloat in [-2056, 0, 2056] {
			let visible = NSRect(x: x, y: -200, width: 2056, height: 1289)
			let result = DashboardWindowSizing.framePreservingTopTrailingEdges(
				currentFrame: NSRect(x: x + 1400, y: 300, width: 384, height: 500),
				targetFrameSize: NSSize(width: 768, height: 1173), visibleFrame: visible)
			XCTAssertTrue(visible.contains(result))
			XCTAssertEqual(result.size, NSSize(width: 768, height: 1173))
		}
	}

	func testWindowResizePreservesTopEdgeWhenContentShrinks() {
		let current = NSRect(x: 24, y: 120, width: 340, height: 620)
		let targetSize = NSSize(width: 340, height: 500)

		let resized = DashboardWindowSizing.framePreservingTopTrailingEdges(
			currentFrame: current,
			targetFrameSize: targetSize)

		XCTAssertEqual(resized.width, targetSize.width, accuracy: 0.001)
		XCTAssertEqual(resized.height, targetSize.height, accuracy: 0.001)
		XCTAssertEqual(resized.maxY, current.maxY, accuracy: 0.001)
		XCTAssertGreaterThan(resized.minY, current.minY)
	}
}
