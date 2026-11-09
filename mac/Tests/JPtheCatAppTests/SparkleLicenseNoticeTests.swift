import XCTest

/// Sparkle is MIT-licensed, and MIT requires its notice in every copy we distribute.
/// Both bundle builders must stage the vendored LICENSE into Contents/Resources, and the release
/// builder must fail closed rather than ship a bundle without it.
final class SparkleLicenseNoticeTests: XCTestCase {
	func testVendoredSparkleLicenseIsTheMITNotice() throws {
		let license = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/tools/sparkle/LICENSE"),
			encoding: .utf8)

		XCTAssertTrue(license.contains("Andy Matuschak"))
		XCTAssertTrue(license.contains("Permission is hereby granted, free of charge"))
	}

	func testReleaseBuilderShipsSparkleLicenseAndFailsClosed() throws {
		let buildScript = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/build-dmg.sh"),
			encoding: .utf8)

		XCTAssertTrue(buildScript.contains("SPARKLE_LICENSE_SOURCE=\"tools/sparkle/LICENSE\""))
		XCTAssertTrue(buildScript.contains("cp \"$SPARKLE_LICENSE_SOURCE\" \"$RESOURCES_DIR/Sparkle-LICENSE.txt\""))
		XCTAssertTrue(buildScript.contains("the shipped app must carry Sparkle's MIT notice"))

		// The notice must be in the bundle before the app is signed, or the signature would not seal it.
		let copy = try XCTUnwrap(buildScript.range(of: "Sparkle-LICENSE.txt"))
		let sign = try XCTUnwrap(buildScript.range(of: "Signed Sparkle.framework"))
		XCTAssertLessThan(copy.lowerBound, sign.lowerBound)
	}

	func testLocalBuilderShipsSparkleLicense() throws {
		let localScript = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/build_and_run.sh"),
			encoding: .utf8)

		XCTAssertTrue(localScript.contains("cp tools/sparkle/LICENSE \"$APP/Contents/Resources/Sparkle-LICENSE.txt\""))
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
