import Foundation
import XCTest

/// JP the Cat must never read a Keychain item another app owns.
///
/// `PlanDetector` used to `SecItemCopyMatching` Claude Code's `Claude Code-credentials` generic
/// password to label the rate-limit gauge "Max 20x". On the legacy file Keychain a cross-app read is
/// gated by the ITEM's ACL trusted-app list, which JP the Cat is not on — so macOS showed the login
/// password dialog. It came back roughly daily (Claude Code rewrites the item on OAuth token refresh,
/// replacing the ACL and wiping any "Always Allow") and after every Sparkle update (the ACL grant is
/// pinned to our code signature). Users read it as JP the Cat demanding a password to read their
/// usage files. The label was cosmetic — the gauge itself comes from the opt-in statusline capture —
/// so the read was deleted rather than gated behind a toggle.
///
/// JP the Cat makes no Security-framework Keychain access at all. The one reviewed exception to
/// "another app's item" is the opt-in Cursor plan
/// usage: `CursorAuthToken` reads Cursor's own sign-in through `/usr/bin/security`, which Cursor's
/// item already trusts, so it can never raise the password prompt described above.
final class PlanTierKeychainReadTests: XCTestCase {
	func testNoSourceReadsAnotherAppsKeychainItem() throws {
		let banned = ["Claude Code-credentials", "PlanDetector"]
		for (path, source) in try swiftSources() {
			for needle in banned {
				XCTAssertFalse(
					source.contains(needle),
					"\(path) references \(needle): reading another app's Keychain item prompts for the login password")
			}
		}
	}

	func testNoSourceReadsTheKeychainDirectly() throws {
		let readers = try swiftSources()
			.filter { $0.source.contains("SecItemCopyMatching") }
			.map { ($0.path as NSString).lastPathComponent }
			.sorted()
		XCTAssertEqual(
			readers, [],
			"JP no longer stores anything in the Keychain; a new reader needs its own review")
	}

	/// The one sanctioned read of another app's sign-in: Cursor's own token, for the opt-in Cursor
	/// plan-usage fetch. It lives in ONE file, goes through `/usr/bin/security` (whose access Cursor's
	/// item already grants, so no password prompt), and never through `SecItemCopyMatching`.
	func testCursorSignInTokenIsReadOnlyByTheOptInPlanUsageSource() throws {
		let readers = try swiftSources()
			.filter {
				$0.source.contains("cursorAuth/accessToken")
					|| $0.source.contains(#"keychainService = "cursor-access-token""#)
			}
			.map { ($0.path as NSString).lastPathComponent }
		XCTAssertEqual(readers, ["CursorPlanUsageClient.swift"])
		let source = try XCTUnwrap(try swiftSources().first { $0.path.hasSuffix("CursorPlanUsageClient.swift") }?.source)
		XCTAssertTrue(source.contains("\"/usr/bin/security\""))
		XCTAssertFalse(source.contains("SecItemCopyMatching"))
		XCTAssertFalse(source.contains("refreshToken"), "JP must never use Cursor's refresh token")
	}

	func testGrokBotSignInTokenIsReadOnlyByTheOptInPlanUsageSource() throws {
		let readers = try swiftSources()
			.filter { $0.source.contains("Grok Bot Safe Storage") }
			.map { ($0.path as NSString).lastPathComponent }
		XCTAssertEqual(readers, ["GrokBotAuthToken.swift"])
		let source = try XCTUnwrap(try swiftSources().first { $0.path.hasSuffix("GrokBotAuthToken.swift") }?.source)
		XCTAssertTrue(source.contains("\"/usr/bin/security\""))
		XCTAssertFalse(source.contains("SecItemCopyMatching"))
		XCTAssertFalse(source.contains("refresh-token"), "JP must never use Grok Bot's refresh token")
	}

	private func swiftSources() throws -> [(path: String, source: String)] {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatAppTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.appendingPathComponent("Sources")
		guard let walker = FileManager.default.enumerator(atPath: root.path) else {
			XCTFail("Sources/ not found at \(root.path)")
			return []
		}
		var out: [(String, String)] = []
		for case let relative as String in walker where relative.hasSuffix(".swift") {
			let url = root.appendingPathComponent(relative)
			out.append((relative, try String(contentsOf: url, encoding: .utf8)))
		}
		XCTAssertGreaterThan(out.count, 20, "scan found almost no sources — the guard would pass vacuously")
		return out
	}
}
