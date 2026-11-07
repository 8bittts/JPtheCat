import XCTest

@testable import JPtheCatCore

/// [CRITICAL] The compact token ladder shipped THREE times and two of the copies disagreed: the
/// widget's rung was `%.0fK`, so 97,600 Copilot tokens read `97.6K` on the dashboard and in the
/// menu-bar pill but `98K tok` on the Medium widget grid cell — on surfaces this repo otherwise keeps
/// 1:1. `TokenFormatter` is now the only ladder; these literals are what the other two surfaces pin
/// themselves against.
///
/// Companion parity guards: `TokenFormatterParityTests` (app) and `WidgetTokenFormatParityTests`
/// (widget extension). Change an expectation here and both must be updated in the same change.
final class TokenFormatterTests: XCTestCase {
	/// The canonical ladder. Every surface must produce exactly these strings.
	static let cases: [(value: Int, expected: String)] = [
		(0, "0"),
		(7, "7"),
		(999, "999"),
		(1_000, "1.0K"),
		(1_500, "1.5K"),
		(53_600, "53.6K"),
		// The exact figure the widget used to render as "98K": one rounding rung, two different faces.
		(97_600, "97.6K"),
		(999_999, "1000.0K"),
		(1_000_000, "1.0M"),
		(1_234_567, "1.2M"),
		(-1_500, "-1.5K"),
		(-2_500_000, "-2.5M"),
	]

	func testCompactLadderIsPinned() {
		for (value, expected) in Self.cases {
			XCTAssertEqual(TokenFormatter.compact(value), expected, "compact(\(value))")
		}
	}

	func testSuffixIsAppendedWithoutChangingTheLadder() {
		for (value, expected) in Self.cases {
			XCTAssertEqual(
				TokenFormatter.compact(value, suffix: " tok"), expected + " tok",
				"compact(\(value), suffix:) must only append")
		}
	}

	/// The widget's snapshot stores every metric as a `Double`, so the two overloads must agree for a
	/// whole value — that difference is exactly where the `%.0fK` divergence hid.
	func testDoubleOverloadMatchesTheIntOverloadForWholeValues() {
		for (value, expected) in Self.cases {
			XCTAssertEqual(TokenFormatter.compact(Double(value)), expected, "compact(\(value).0)")
		}
	}

	/// Below 1,000 the `Double` overload rounds to a whole token; that rounding must NOT happen on the
	/// K/M rungs, where converting a large magnitude to `Int` first could trap.
	func testDoubleOverloadRoundsOnlyBelowTheThousandsRung() {
		XCTAssertEqual(TokenFormatter.compact(12.4), "12")
		XCTAssertEqual(TokenFormatter.compact(12.6), "13")
		XCTAssertEqual(TokenFormatter.compact(1_499.9), "1.5K")
		// Far beyond `Int.max` — must format, never trap.
		XCTAssertTrue(TokenFormatter.compact(1e30).hasSuffix("M"))
	}

	/// Uppercase K/M so a token figure and `MoneyFormatter.compactDollars` can sit in the same row.
	func testMagnitudeCasingMatchesCompactDollars() {
		XCTAssertTrue(TokenFormatter.compact(53_600).hasSuffix("K"))
		XCTAssertTrue(MoneyFormatter.compactDollars(53_600, locale: Locale(identifier: "en_US")).hasSuffix("K"))
		XCTAssertTrue(TokenFormatter.compact(1_234_567).hasSuffix("M"))
		XCTAssertTrue(MoneyFormatter.compactDollars(1_234_567, locale: Locale(identifier: "en_US")).hasSuffix("M"))
	}

	/// SURFACE 1 of 3 — the menu-bar tooltip's token fallback, formerly
	/// `MenuBarLabelRenderer.compactTokenCount`. The app and widget halves of this three-way agreement
	/// live in `TokenFormatterParityTests` and `WidgetTokenFormatParityTests`.
	func testMenuBarTooltipUsesTheSharedLadder() {
		let tooltip = MenuBarLabelRenderer.tooltip(
			aggregateToday: 0,
			windowTotal: nil,
			windowDays: 14,
			costBasis: .notionalListPrice,
			providerLimits: [
				MenuBarProviderLimitSummary(
					id: "copilot", name: "Copilot", primaryUsedPct: nil, primaryWindowMinutes: nil,
					secondaryUsedPct: nil, secondaryWindowMinutes: nil, isOfficial: false, planLabel: nil,
					estimatedUsedPct: 42, estimatedTokenCount: 97_600)
			],
			freshnessText: nil,
			locale: Locale(identifier: "en_US"))
		XCTAssertTrue(
			tooltip.contains("Copilot: \(TokenFormatter.compact(97_600)) tokens today · quota unavailable"),
			"menu-bar tooltip drifted from TokenFormatter; got:\n\(tooltip)")
		XCTAssertTrue(tooltip.contains("97.6K tokens today"), "expected the pinned 97.6K rung:\n\(tooltip)")
	}
}
