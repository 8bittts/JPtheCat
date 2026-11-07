import XCTest

@testable import JPtheCatCore

/// Covers the shared parsing primitives every provider decoder uses (`ISOTimestamp`,
/// `JSONNumber`), extracted from four independently-duplicated copies (Claude/Codex/Gemini had a
/// byte-identical `int(_:)` + formatter pair; OpenCode had an equivalent date path). A regression
/// here would silently affect every provider's timestamp/token decoding at once.
final class ProviderParsingHelpersTests: XCTestCase {
	func testISOTimestampParsesFractionalSeconds() {
		let plain = ISOTimestamp.parse("2026-07-08T12:00:00Z")
		let fractional = ISOTimestamp.parse("2026-07-08T12:00:00.500Z")
		XCTAssertNotEqual(plain, .distantPast)
		XCTAssertNotEqual(fractional, .distantPast)
		// Both real-parsed dates land exactly 0.5s apart — proves the fractional formatter is
		// actually consuming the ".500" rather than silently truncating to the plain formatter.
		XCTAssertEqual(fractional.timeIntervalSince(plain), 0.5, accuracy: 0.001)
	}

	func testISOTimestampParsesPlainSecondsFallback() {
		// A plain-seconds string (no fractional component) must NOT fall through to `.distantPast` —
		// the fractional formatter fails to parse it, so the plain formatter must catch it.
		let date = ISOTimestamp.parse("2026-07-08T12:00:00Z")
		XCTAssertNotEqual(date, .distantPast)
	}

	func testISOTimestampFallsBackToDefaultOnMalformedOrMissingInput() {
		XCTAssertEqual(ISOTimestamp.parse(nil), .distantPast)
		XCTAssertEqual(ISOTimestamp.parse("not a date"), .distantPast)
		let customFallback = Date(timeIntervalSince1970: 1000)
		XCTAssertEqual(ISOTimestamp.parse(nil, fallback: customFallback), customFallback)
	}

	func testJSONNumberIntAcceptsIntDoubleAndNSNumber() {
		XCTAssertEqual(JSONNumber.int(42), 42)
		XCTAssertEqual(JSONNumber.int(42.9), 42)
		XCTAssertEqual(JSONNumber.int(NSNumber(value: 7)), 7)
	}

	func testJSONNumberIntFailsClosedToZeroOnNonNumericInput() {
		XCTAssertEqual(JSONNumber.int(nil), 0)
		XCTAssertEqual(JSONNumber.int("42"), 0)
	}

	func testJSONNumberDoubleAcceptsIntDoubleAndNSNumber() {
		XCTAssertEqual(JSONNumber.double(42), 42.0)
		XCTAssertEqual(JSONNumber.double(42.5), 42.5)
		XCTAssertEqual(JSONNumber.double(NSNumber(value: 7.25)), 7.25)
	}

	func testJSONNumberDoubleReturnsNilOnNonNumericInput() {
		// Unlike int(_:), double(_:) returns nil (not 0) so callers can tell "absent" from a real 0 —
		// e.g. an official rate-limit used_percent of 0 must survive as 0, while a missing field is nil.
		XCTAssertNil(JSONNumber.double(nil))
		XCTAssertNil(JSONNumber.double("42"))
		XCTAssertEqual(JSONNumber.double(0), 0.0)  // a real 0 is a value, not absence
	}
}
