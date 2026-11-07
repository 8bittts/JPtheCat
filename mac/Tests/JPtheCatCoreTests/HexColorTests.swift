import XCTest

@testable import JPtheCatCore

final class HexColorTests: XCTestCase {
	func testParsesSixDigitHexWithAndWithoutHash() {
		let withHash = HexColor.components("#DF7A2E")
		let withoutHash = HexColor.components("DF7A2E")
		XCTAssertNotNil(withHash)
		XCTAssertNotNil(withoutHash)
		// 0xDF=223, 0x7A=122, 0x2E=46
		XCTAssertEqual(withHash?.red ?? -1, 223.0 / 255, accuracy: 1e-9)
		XCTAssertEqual(withHash?.green ?? -1, 122.0 / 255, accuracy: 1e-9)
		XCTAssertEqual(withHash?.blue ?? -1, 46.0 / 255, accuracy: 1e-9)
		XCTAssertEqual(withHash?.red, withoutHash?.red)
		XCTAssertEqual(withHash?.green, withoutHash?.green)
		XCTAssertEqual(withHash?.blue, withoutHash?.blue)
	}

	func testRejectsMalformedInput() {
		XCTAssertNil(HexColor.components(""))
		XCTAssertNil(HexColor.components("#FFF"))  // 3-digit shorthand not supported
		XCTAssertNil(HexColor.components("GGGGGG"))  // non-hex
		XCTAssertNil(HexColor.components("DF7A2E00"))  // 8 digits
		XCTAssertNil(HexColor.components("#DF7A2"))  // 5 digits
	}

	func testFallbackIsTheCanonicalInkSoftValue() {
		// #6C6253 == (0.424, 0.384, 0.325). This is the single source of truth the app
		// Color(hex:)/NSColor(jpHex:) and the widget Color(hex:) all degrade to.
		XCTAssertEqual(HexColor.fallback.red, 0.424, accuracy: 1e-9)
		XCTAssertEqual(HexColor.fallback.green, 0.384, accuracy: 1e-9)
		XCTAssertEqual(HexColor.fallback.blue, 0.325, accuracy: 1e-9)
	}

	func testComponentsOrFallbackDegradesToFallback() {
		let bad = HexColor.componentsOrFallback("not-a-color")
		XCTAssertEqual(bad.red, HexColor.fallback.red)
		XCTAssertEqual(bad.green, HexColor.fallback.green)
		XCTAssertEqual(bad.blue, HexColor.fallback.blue)

		let good = HexColor.componentsOrFallback("#000000")
		XCTAssertEqual(good.red, 0)
		XCTAssertEqual(good.green, 0)
		XCTAssertEqual(good.blue, 0)
	}
}
