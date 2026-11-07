import XCTest

/// The one release-script invariant that has no other home: `release-jpthecat.sh` must read the
/// PUBLISHED `<sparkle:version>` and floor every new `CFBundleVersion` above it, in that order,
/// before stamping `Info.plist` (mac/AGENTS.md). Nothing asserts this at runtime — the script has no
/// `BUILD_NUMBER > LATEST_PUBLISHED_BUILD` check — and losing it means Sparkle silently never offers
/// the update.
///
/// Every other method that used to live here read a shell script as a `String` and asserted literal
/// substrings, which passes with the behavior broken and fails on harmless rewording. Those
/// invariants are now either self-enforcing under `set -euo pipefail` (each script `fail()`s on its
/// own), executed for real (`VersionBumpTests` runs the arithmetic through `/bin/bash`), or migrated
/// to a test that checks the actual value — `SingleInstanceGuardTests` parses `Info.plist`, and
/// `site-copy.test.ts` reads both published Homebrew casks.
final class ReleaseScriptWorkflowTests: XCTestCase {
	func testReleaseScriptFloorsBuildNumberAbovePublishedAppcast() throws {
		let source = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/release-jpthecat.sh"),
			encoding: .utf8)

		XCTAssertTrue(source.contains(#". "${REPO_ROOT}/scripts/release-versioning.sh""#))
		XCTAssertTrue(source.contains("jptc_latest_published_build_number"))
		XCTAssertTrue(source.contains(#"LATEST_PUBLISHED_BUILD="$(jptc_latest_published_build_number "${WEB_STABLE}/appcast.xml")""#))
		XCTAssertTrue(source.contains(#"BUILD_NUMBER="$(jptc_release_build_number "$CUR_BUILD" "$LATEST_PUBLISHED_BUILD" "$SKIPPED_TAGS")""#))

		let currentBuild = try XCTUnwrap(source.range(of: "CUR_BUILD="))
		let publishedBuild = try XCTUnwrap(source.range(of: "LATEST_PUBLISHED_BUILD="))
		let build = try XCTUnwrap(source.range(of: #"BUILD_NUMBER="$(jptc_release_build_number"#))
		let stamp = try XCTUnwrap(source.range(of: "Set :CFBundleVersion ${BUILD_NUMBER}"))

		XCTAssertLessThan(currentBuild.lowerBound, publishedBuild.lowerBound)
		XCTAssertLessThan(publishedBuild.lowerBound, build.lowerBound)
		XCTAssertLessThan(build.lowerBound, stamp.lowerBound)
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
