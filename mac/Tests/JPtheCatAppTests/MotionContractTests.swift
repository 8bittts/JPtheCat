import XCTest

/// [NOTE] Every slice below used to be a "from marker X to marker Y" range inside a literal-path read
/// of `DashboardView.swift` / `SettingsBackView.swift`, which froze both files — an extraction would
/// have emptied the slice and turned each `XCTAssertFalse` into a vacuous pass. Slices are now
/// brace-matched declarations resolved by `AppSourceScanner` wherever they live, and a missing anchor
/// throws instead of yielding empty text.
final class MotionContractTests: XCTestCase {
	func testDashboardContinuousLoopsUseTimelineInsteadOfRepeatForever() throws {
		// Scanned across every app source, so a split cannot smuggle a `repeatForever` loop into a new
		// file — strictly stronger than the old single-file read.
		XCTAssertFalse(
			try AppSourceScanner.joined().contains(".repeatForever("),
			"Dashboard looping motion must be clock-derived via TimelineView, not state-driven repeatForever.")

		// One shared TimelineView in `ThoughtBubbles` drives every `FloatingBubble` (no per-bubble loop);
		// the slice spans both (plus the `BubbleSpec` the original marker range covered) so it still
		// proves the bubble field is clock-derived, not @State/onAppear.
		// The `paused:` argument is the occlusion gate (see `DashboardMotionGate`); asserting the gated
		// form keeps this contract honest AND stops an ungated timeline being reintroduced here.
		let bubbles = try AppSourceScanner.bodies(of: [
			"struct ThoughtBubbles",
			"struct BubbleSpec",
			"struct FloatingBubble",
		])
		XCTAssertTrue(bubbles.contains("TimelineView(.animation(paused: motionPaused))"))
		XCTAssertFalse(bubbles.contains("@State"))
		XCTAssertFalse(bubbles.contains(".onAppear"))

		let ticker = try AppSourceScanner.body(of: "struct TickerTapeText")
		XCTAssertTrue(ticker.contains("TimelineView(.animation(paused: motionPaused))"))
		XCTAssertTrue(ticker.contains("tickerOffset(at:"))
		XCTAssertFalse(ticker.contains("@State"))
		XCTAssertFalse(ticker.contains("withAnimation"))

		let chart = try AppSourceScanner.body(of: "struct SparkChart: View {")
		XCTAssertTrue(chart.contains("TimelineView(.animation(paused: motionPaused))"))
		XCTAssertFalse(chart.contains("@State private var pulse"))
		XCTAssertFalse(chart.contains("withAnimation"))
	}

	func testProviderSelectorMetersDoNotReplayAnEntranceAnimationOnRefresh() throws {
		let selectorMeter = try AppSourceScanner.body(of: "var selectorMeter")

		XCTAssertFalse(
			selectorMeter.contains(".animation("),
			"Provider meter rows are rebuilt on refresh; attaching animation to their fill replays from zero.")
	}

	func testUpdateDotButtonHonorsReduceMotion() throws {
		let button = try AppSourceScanner.body(of: "struct UpdateDotButton")

		XCTAssertTrue(button.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
		XCTAssertTrue(button.contains(".scaleEffect(hovering && !reduceMotion ? 1.18 : 1)"))
	}

	func testSettingsChromeHoverScalesHonorReduceMotion() throws {
		let updateDot = try AppSourceScanner.body(of: "struct UpdateDotButton")

		XCTAssertTrue(updateDot.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
		XCTAssertTrue(updateDot.contains(".scaleEffect(hovering && !reduceMotion ? 1.18 : 1)"))
	}

	func testThemePickerTileHonorsReduceMotion() throws {
		// `ThemeSwatchTile` is internal (not `private`) since the Themes window reuses it via its `large`
		// variant; the reduce-motion contract below is unchanged.
		let tile = try AppSourceScanner.body(of: "struct ThemeSwatchTile")

		XCTAssertTrue(tile.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
		XCTAssertTrue(tile.contains(".scaleEffect(hovering && !reduceMotion ? 1.04 : 1)"))
		XCTAssertTrue(tile.contains(".animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)"))
	}
}
