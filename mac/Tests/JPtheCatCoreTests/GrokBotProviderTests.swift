import Foundation
import XCTest

@testable import JPtheCatCore

final class GrokBotProviderTests: XCTestCase {
	func testIsAvailableWhenSecretsFileExists() throws {
		let home = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-home-\(UUID().uuidString)", isDirectory: true)
		let appSupport = GrokBotAuthToken.appSupportURL(home: home)
		try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: home) }
		let secrets = appSupport.appendingPathComponent(GrokBotAuthToken.secretsFileName)
		try Data("{}".utf8).write(to: secrets)
		XCTAssertTrue(GrokBotProvider(root: appSupport).isAvailable())
		XCTAssertTrue(GrokBotProvider.isGrokBotDetected(home: home))
	}

	func testIsUnavailableOnCleanFixture() {
		let empty = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-empty-\(UUID().uuidString)", isDirectory: true)
		XCTAssertFalse(GrokBotProvider(root: empty).isAvailable())
		XCTAssertFalse(GrokBotProvider.isGrokBotDetected(home: empty))
	}
}
