import Foundation
import XCTest

@testable import JPtheCatCore

final class ChromiumOSCryptTests: XCTestCase {
	override func setUpWithError() throws {
		#if !canImport(CommonCrypto)
		throw XCTSkip("Chromium safeStorage tests require CommonCrypto (macOS)")
		#endif
	}

	func testKeyDerivationMatchesChromiumCompatibilityVector() {
		let key = ChromiumOSCrypt.deriveKey(secret: Data("not-a-real-secret".utf8))
		XCTAssertEqual(
			key,
			[0x9b, 0xa5, 0xa2, 0x8a, 0x32, 0x39, 0xfe, 0xce, 0x3c, 0x5a, 0xe5, 0x70, 0xd6, 0x52, 0x3d, 0xcc])
	}

	func testRoundTripsPlaintextWithFixedVector() throws {
		let key = ChromiumOSCrypt.deriveKey(secret: Data("not-a-real-secret".utf8))
		let encrypted = "djEwykc2I53A+doQo9OF96du2A=="
		let plain = try XCTUnwrap(ChromiumOSCrypt.decrypt(key: key, valueBase64: encrypted))
		XCTAssertEqual(String(data: plain, encoding: .utf8), "same")
	}
}
