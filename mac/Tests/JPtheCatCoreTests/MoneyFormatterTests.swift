import XCTest

@testable import JPtheCatCore

final class MoneyFormatterTests: XCTestCase {
	private let enUS = Locale(identifier: "en_US")

	func testGroupsThousands() {
		XCTAssertEqual(MoneyFormatter.dollars(1123.37, locale: enUS), "$1,123.37")
		XCTAssertEqual(MoneyFormatter.dollars(1_234_567.5, locale: enUS), "$1,234,567.50")
	}

	func testSmallValuesUnchanged() {
		XCTAssertEqual(MoneyFormatter.dollars(12.34, locale: enUS), "$12.34")
		XCTAssertEqual(MoneyFormatter.dollars(0, locale: enUS), "$0.00")
	}

	func testRespectsDecimalOverride() {
		XCTAssertEqual(MoneyFormatter.dollars(1234.5, decimals: 0, locale: enUS), "$1,234")
		XCTAssertEqual(MoneyFormatter.dollars(1.2345, decimals: 3, locale: enUS), "$1.234")
	}

	func testAmountHasNoSymbol() {
		XCTAssertEqual(MoneyFormatter.amount(1123.37, locale: enUS), "1,123.37")
	}

	func testRespectsNonUSDCurrency() {
		// EUR symbol + grouping under en_US.
		XCTAssertEqual(MoneyFormatter.currency(1123.37, code: "EUR", locale: enUS), "€1,123.37")
		// JPY has zero fraction digits by rule.
		XCTAssertEqual(MoneyFormatter.currency(1123, code: "JPY", locale: enUS), "¥1,123")
	}

	func testLocalizesGroupingSeparators() {
		// A German locale groups with "." and decimals with ","; the amount is still USD.
		let de = Locale(identifier: "de_DE")
		XCTAssertEqual(MoneyFormatter.amount(1123.37, locale: de), "1.123,37")
	}
}
