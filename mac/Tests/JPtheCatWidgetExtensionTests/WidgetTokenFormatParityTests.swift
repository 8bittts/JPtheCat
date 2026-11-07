import JPtheCatCore
import XCTest

@testable import JPtheCatWidgetExtension

/// SURFACE 3 of 3 in the compact-token three-way agreement (see `TokenFormatterTests` in Core and
/// `TokenFormatterParityTests` in the app).
///
/// [CRITICAL] The widget carried its OWN compact ladder whose thousands rung was `%.0fK`, so 97,600
/// tokens rendered `97.6K` on the dashboard and in the menu-bar pill but `98K tok` on the Medium
/// widget grid cell and gauge rows — a visible inconsistency on surfaces this repo otherwise keeps
/// 1:1. `WidgetValueFormatter` now routes tokens through Core's `TokenFormatter`; do not re-add a
/// local ladder. The widget's `" tok"` unit suffix is deliberate (its cells carry no other unit
/// context) and is the ONLY difference from the dashboard string.
final class WidgetTokenFormatParityTests: XCTestCase {
	private let usd = MoneyFormatter.baseCurrencyCode

	/// The fix itself: the thousands rung keeps one decimal place, exactly like the other two surfaces.
	func testThousandsRungKeepsOneDecimalPlace() {
		XCTAssertEqual(
			WidgetValueFormatter.string(97_600, metric: .tokens, code: usd), "97.6K tok",
			"the widget must not round tokens to a whole K — that was the 97.6K/98K divergence")
		XCTAssertEqual(WidgetValueFormatter.string(53_600, metric: .tokens, code: usd), "53.6K tok")
	}

	/// Every rung, pinned against Core so the two can never diverge again.
	func testTokenMetricMatchesCoreTokenFormatter() {
		for value in [0, 7, 999, 1_000, 1_500, 53_600, 97_600, 999_999, 1_000_000, 1_234_567, -1_500] {
			XCTAssertEqual(
				WidgetValueFormatter.string(Double(value), metric: .tokens, code: usd),
				TokenFormatter.compact(value, suffix: " tok"),
				"widget token formatting drifted from TokenFormatter at \(value)")
		}
	}

	/// The dollars metric is untouched by the token fix — still `MoneyFormatter`, still grouped.
	func testDollarMetricStillRoutesThroughMoneyFormatter() {
		XCTAssertEqual(
			WidgetValueFormatter.string(1123.37, metric: .dollars, code: usd),
			MoneyFormatter.dollars(1123.37, code: usd))
	}
}
