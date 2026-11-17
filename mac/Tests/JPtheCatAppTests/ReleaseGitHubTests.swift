import Foundation
import XCTest

/// Runs the REAL `scripts/release-github.sh` helpers against a fake `gh` on PATH. The release script
/// publishes through these functions, so a regression here would ship a release to the wrong host,
/// overwrite published bytes, or upload to a repository nobody can download from.
final class ReleaseGitHubTests: XCTestCase {
	private var sandbox: URL!

	override func setUpWithError() throws {
		sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-release-github-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(
			at: sandbox.appendingPathComponent("bin"), withIntermediateDirectories: true)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: sandbox)
	}

	func testAssetURLsUseThePerTagReleasePrefix() throws {
		let result = try run(
			fakeGh: "exit 0",
			"jptc_release_asset_url 1.161 JPtheCat-1.161.dmg; jptc_release_download_prefix 1.161")
		XCTAssertEqual(result.status, 0, result.output)
		XCTAssertEqual(
			result.output.split(separator: "\n").map(String.init),
			[
				"https://github.com/8bittts/JPtheCat/releases/download/v1.161/JPtheCat-1.161.dmg",
				"https://github.com/8bittts/JPtheCat/releases/download/v1.161/",
			])
	}

	func testRepositoryMustBePublicAndPushable() throws {
		XCTAssertEqual(try run(fakeGh: #"printf 'public\ttrue\n'"#, "jptc_verify_release_repo").status, 0)
		let privateRepo = try run(fakeGh: #"printf 'private\ttrue\n'"#, "jptc_verify_release_repo")
		XCTAssertNotEqual(privateRepo.status, 0)
		XCTAssertTrue(privateRepo.output.contains("not public"), privateRepo.output)
		let noPush = try run(fakeGh: #"printf 'public\tfalse\n'"#, "jptc_verify_release_repo")
		XCTAssertNotEqual(noPush.status, 0)
		XCTAssertTrue(noPush.output.contains("cannot push"), noPush.output)
		XCTAssertNotEqual(try run(fakeGh: "exit 1", "jptc_verify_release_repo").status, 0)
	}

	func testPublishedReleaseIsNeverOverwritten() throws {
		let result = try run(
			fakeGh: #"[ "$2" = view ] && { echo false; exit 0; }; echo "UNEXPECTED $*" >> "$LOG"; exit 0"#,
			"jptc_prepare_draft_release v1.161 'JP the Cat 1.161'")
		XCTAssertNotEqual(result.status, 0)
		XCTAssertTrue(result.output.contains("already published"), result.output)
		XCTAssertFalse(try log().contains("UNEXPECTED"))
	}

	func testLeftoverDraftIsReplacedAndAbsentReleaseIsCreatedAsDraft() throws {
		let draft = try run(
			fakeGh: #"echo "$*" >> "$LOG"; [ "$2" = view ] && { echo true; exit 0; }; exit 0"#,
			"jptc_prepare_draft_release v1.161 'JP the Cat 1.161'")
		XCTAssertEqual(draft.status, 0, draft.output)
		let calls = try log()
		XCTAssertTrue(calls.contains("release delete v1.161"), calls)
		XCTAssertTrue(calls.contains("release create v1.161 --repo 8bittts/JPtheCat --draft"), calls)

		try "".write(to: sandbox.appendingPathComponent("gh.log"), atomically: true, encoding: .utf8)
		let absent = try run(
			fakeGh: #"echo "$*" >> "$LOG"; [ "$2" = view ] && { echo 'release not found' >&2; exit 1; }; exit 0"#,
			"jptc_prepare_draft_release v1.161 'JP the Cat 1.161'")
		XCTAssertEqual(absent.status, 0, absent.output)
		let absentCalls = try log()
		XCTAssertFalse(absentCalls.contains("release delete"), absentCalls)
		XCTAssertTrue(absentCalls.contains("--draft"), absentCalls)
	}

	func testUnreadableReleaseFailsClosed() throws {
		let result = try run(
			fakeGh: #"[ "$2" = view ] && { echo 'HTTP 401: Bad credentials' >&2; exit 1; }; echo "UNEXPECTED" >> "$LOG"; exit 0"#,
			"jptc_prepare_draft_release v1.161 'JP the Cat 1.161'")
		XCTAssertNotEqual(result.status, 0)
		XCTAssertFalse(try log().contains("UNEXPECTED"))
	}

	func testReleaseScriptsUseOnlyTheGitHubHelper() throws {
		for path in ["mac/scripts/release-jpthecat.sh", "mac/scripts/generate-appcast.sh"] {
			let script = try String(contentsOf: repoRoot().appendingPathComponent(path), encoding: .utf8)
			XCTAssertTrue(script.contains("scripts/release-github.sh"), path)
			XCTAssertFalse(script.contains("supabase storage"), path)
			XCTAssertFalse(script.contains("api.jpthecat.com"), path)
		}
	}

	// MARK: Helpers

	private func log() throws -> String {
		(try? String(contentsOf: sandbox.appendingPathComponent("gh.log"), encoding: .utf8)) ?? ""
	}

	private func run(fakeGh: String, _ command: String) throws -> (status: Int32, output: String) {
		let gh = sandbox.appendingPathComponent("bin/gh")
		try "#!/bin/bash\n\(fakeGh)\n".write(to: gh, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
		let helper = repoRoot().appendingPathComponent("mac/scripts/release-github.sh")
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-c", "set -euo pipefail; source '\(helper.path)'; \(command)"]
		var environment = ProcessInfo.processInfo.environment
		environment["PATH"] = "\(sandbox.appendingPathComponent("bin").path):\(environment["PATH"] ?? "/usr/bin:/bin")"
		environment["LOG"] = sandbox.appendingPathComponent("gh.log").path
		environment.removeValue(forKey: "JPTHECAT_RELEASE_REPO")
		process.environment = environment
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatAppTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.deletingLastPathComponent()  // repo root
	}
}
