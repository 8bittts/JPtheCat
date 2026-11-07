import Foundation
import XCTest

@testable import JPtheCatCore

final class GrokBotAuthTokenTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_790_260_000)

	private func jwt(exp: TimeInterval) -> String {
		let payload = try! JSONSerialization.data(withJSONObject: ["exp": exp, "type": "session"])
		let encoded = payload.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
		return "eyJhbGciOiJIUzI1NiJ9.\(encoded).signature"
	}

	func testLoadDecryptsAccessTokenFromSandSecrets() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-bot-secrets-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let token = jwt(exp: now.timeIntervalSince1970 + 86_400)
		let secrets = """
		{"cursor-accounts":{"active":"acct","accounts":{"acct":{"cursor-access-token":"ENC"}}}}
		"""
		let url = dir.appendingPathComponent(GrokBotAuthToken.secretsFileName)
		try XCTUnwrap(secrets.data(using: .utf8)).write(to: url)
		let loaded = GrokBotAuthToken.load(
			now: now,
			secretsFile: url,
			keychainSecret: { "not-a-real-secret" },
			decrypt: { key, blob in
				XCTAssertEqual(blob, "ENC")
				return Data(token.utf8)
			})
		XCTAssertEqual(loaded, token)
	}

	func testMacOSStringWrappedAccountsDecode() throws {
		let inner = #"{"active":"a","accounts":{"a":{"cursor-access-token":"x"}}}"#
		let root: [String: Any] = ["cursor-accounts": inner]
		let accounts = try XCTUnwrap(GrokBotAuthToken.parseAccounts(root))
		XCTAssertEqual(accounts["active"] as? String, "a")
	}
}
