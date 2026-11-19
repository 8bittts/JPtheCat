import CryptoKit
import Foundation
import XCTest

@testable import JPtheCatCore

/// `feed/public/stable/*` on `main` is the update channel, served by raw.githubusercontent.com: the
/// Sparkle appcast (`Info.plist` `SUFeedURL`), the remote pricing table (`RemotePricingStore`), and the
/// Homebrew livecheck. Apps up to v1.161 read `jpthecat.com/stable/*`, which a Cloudflare redirect
/// rule sends to the same files, so the paths here must never move.
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
		XCTAssertTrue(cask.contains(#"url "https://raw.githubusercontent.com/8bittts/JPtheCat/main/feed/public/stable/appcast.xml""#))
		XCTAssertTrue(cask.contains("strategy :sparkle, &:short_version"))
	}

	/// The README is the public home page, so it carries the full Homebrew install path, including the
	/// `brew trust` step a third-party tap needs.
	func testReadmeCarriesTheHomebrewInstallPath() throws {
		let readme = try XCTUnwrap(String(data: data("README.md"), encoding: .utf8))
		XCTAssertTrue(readme.contains("brew tap 8bittts/jpthecat\nbrew trust 8bittts/jpthecat\nbrew install --cask jpthecat"))
	}

	/// Every URL the app bakes in points at a file this repository actually serves from `main`.
	func testBakedFeedURLsPointAtCommittedFeedFiles() throws {
		let base = "https://raw.githubusercontent.com/8bittts/JPtheCat/main/"
		let plist = try XCTUnwrap(
			PropertyListSerialization.propertyList(from: data("mac/Info.plist"), format: nil) as? [String: Any])
		let feedURL = try XCTUnwrap(plist["SUFeedURL"] as? String)
		XCTAssertEqual(feedURL, base + "feed/public/stable/appcast.xml")
		XCTAssertEqual(RemotePricingStore.defaultRemoteURL.absoluteString, base + "feed/public/stable/pricing-v1.json")

		for file in ["appcast.xml", "version.json", "pricing-v1.json", "pricing.json", "jpthecat.rb"] {
			XCTAssertTrue(
				FileManager.default.fileExists(atPath: root().appendingPathComponent("feed/public/stable/\(file)").path),
				"feed must serve stable/\(file)")
		}
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: root().appendingPathComponent("feed/vercel.json").path),
			"the feed is GitHub-hosted; no Vercel deployment config remains")
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
