import CryptoKit
import Foundation
import XCTest

/// `https://jpthecat.com/stable/*` is the update channel every installed copy reads: the Sparkle
/// appcast (`Info.plist` `SUFeedURL`), the remote pricing table (`RemotePricingStore`), and the
/// Homebrew livecheck. The website is retired and the rest of the domain redirects to GitHub, so
/// `feed/` must keep serving these files byte-for-byte.
final class UpdateFeedTests: XCTestCase {
	/// `RemotePricingStore` merges the hosted table OVER the bundled one, so any drift reprices real
	/// usage. Regenerate by copying `pricing-default.json`, never by hand-editing the hosted copy.
	func testHostedPricingIsByteIdenticalToTheBundledTable() throws {
		let bundled = try data("mac/Sources/JPtheCatCore/Resources/pricing-default.json")
		let hosted = try data("feed/public/stable/pricing-v1.json")
		XCTAssertEqual(hosted, bundled)

		let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: hosted) as? [String: Any])
		XCTAssertEqual(parsed["pricing_revision"] as? Int, 2)
		XCTAssertFalse((parsed["models"] as? [String: Any] ?? [:]).isEmpty)
	}

	/// Apps up to v1.125 read the unversioned feed and cannot negotiate context thresholds.
	func testLegacyPricingFeedStaysFrozen() throws {
		let digest = SHA256.hash(data: try data("feed/public/stable/pricing.json"))
		let hex = digest.map { String(format: "%02x", $0) }.joined()
		XCTAssertEqual(hex, "2ee20713d7a73c62473dbdebb5e2e650a6977c820adce06cd82bfbe7eaa31f54")
	}

	/// The repo cask, the hosted cask, and the public tap stay one file; a literal version stops
	/// auto-updating and a broken appcast URL makes `brew upgrade` a no-op.
	func testBothPublishedCasksMatchAndKeepTheirTemplates() throws {
		let repoCask = try data("Casks/jpthecat.rb")
		XCTAssertEqual(try data("feed/public/stable/jpthecat.rb"), repoCask)

		let cask = try XCTUnwrap(String(data: repoCask, encoding: .utf8))
		XCTAssertTrue(cask.contains(#"name "JP the Cat""#))
		XCTAssertTrue(cask.contains(#"homepage "https://github.com/8bittts/JPtheCat""#))
		XCTAssertTrue(
			cask.contains(#"url "https://github.com/8bittts/JPtheCat/releases/download/v#{version}/JPtheCat-#{version}.dmg""#))
		XCTAssertTrue(cask.contains(#"url "https://jpthecat.com/stable/appcast.xml""#))
		XCTAssertTrue(cask.contains("strategy :sparkle, &:short_version"))
	}

	/// The README is the public home page, so it carries the full Homebrew install path, including the
	/// `brew trust` step a third-party tap needs.
	func testReadmeCarriesTheHomebrewInstallPath() throws {
		let readme = try XCTUnwrap(String(data: data("README.md"), encoding: .utf8))
		XCTAssertTrue(readme.contains("brew tap 8bittts/jpthecat\nbrew trust 8bittts/jpthecat\nbrew install --cask jpthecat"))
	}

	/// The feed serves `/stable/*` from disk and redirects everything else, so the filesystem route
	/// must come before the catch-all redirect, and installed apps up to v1.160 must still get a real
	/// failure from the retired support endpoint.
	func testFeedRoutesServeStableFilesBeforeTheGitHubRedirect() throws {
		let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data("feed/vercel.json")) as? [String: Any])
		XCTAssertEqual(config["outputDirectory"] as? String, "public")
		let routes = try XCTUnwrap(config["routes"] as? [[String: Any]])

		let filesystem = try XCTUnwrap(routes.firstIndex { $0["handle"] as? String == "filesystem" })
		let catchAll = try XCTUnwrap(routes.lastIndex { $0["src"] as? String == "/(.*)" })
		XCTAssertLessThan(filesystem, catchAll)
		XCTAssertEqual(routes[catchAll]["status"] as? Int, 308)
		XCTAssertEqual(
			(routes[catchAll]["headers"] as? [String: String])?["Location"], "https://github.com/8bittts/JPtheCat")

		let support = try XCTUnwrap(routes.first { ($0["src"] as? String)?.hasPrefix("/api/support-report") == true })
		XCTAssertEqual(support["status"] as? Int, 410)

		for file in ["appcast.xml", "version.json", "pricing-v1.json", "pricing.json", "jpthecat.rb"] {
			XCTAssertTrue(
				FileManager.default.fileExists(atPath: root().appendingPathComponent("feed/public/stable/\(file)").path),
				"feed must serve stable/\(file)")
		}
	}

	private func data(_ path: String) throws -> Data {
		try Data(contentsOf: root().appendingPathComponent(path))
	}

	private func root() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
