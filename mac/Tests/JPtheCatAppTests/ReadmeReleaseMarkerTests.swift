import Foundation
import XCTest

final class ReadmeReleaseMarkerTests: XCTestCase {
	func testReadmeCarriesReleaseMarkerPairs() throws {
		let readme = try String(contentsOf: repoRoot().appendingPathComponent("README.md"), encoding: .utf8)

		for marker in [
			"<!-- version-badge -->",
			"<!-- /version-badge -->",
			"<!-- download-link -->",
			"<!-- /download-link -->",
		] {
			XCTAssertTrue(readme.contains(marker), "README missing release marker: \(marker)")
		}
	}

	func testReleaseScriptRewritesReadmeMarkersAndCommitsReadme() throws {
		let script = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/release-jpthecat.sh"),
			encoding: .utf8)

		XCTAssertTrue(script.contains(#". "${REPO_ROOT}/scripts/release-readme.sh""#))
		XCTAssertTrue(script.contains(#"jptc_update_readme_release_markers "$RROOT/README.md" "$VERSION" "$DOWNLOAD_URL""#))
		XCTAssertTrue(script.contains("mac/Info.plist README.md Casks/jpthecat.rb web/public/stable"))
		XCTAssertTrue(script.contains("git -C \"$RROOT\" checkout -- mac/Info.plist README.md Casks/jpthecat.rb web/public/stable"))
		XCTAssertTrue(script.contains("cp \"$RROOT/README.md\" \"$REL_WORKTREE/README.md\""))
		XCTAssertTrue(script.contains("git -C \"$REL_WORKTREE\" add README.md Casks/jpthecat.rb mac/Info.plist web/public/stable"))
	}

	func testReadmeMarkerHelperRewritesOnlyMarkedBlocks() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

		let readme = directory.appendingPathComponent("README.md")
		try """
		# JPtheCat

		Keep this intro.

		<!-- version-badge -->
		old badge
		<!-- /version-badge -->

		<!-- download-link -->
		old link
		<!-- /download-link -->

		Keep this footer.
		""".write(to: readme, atomically: true, encoding: .utf8)

		try bash("jptc_update_readme_release_markers \(shellQuote(readme.path)) 0.128 https://api.jpthecat.com/releases/JPtheCat-0.128.dmg")
		let updated = try String(contentsOf: readme, encoding: .utf8)

		XCTAssertTrue(updated.contains("Keep this intro."))
		XCTAssertTrue(updated.contains("Keep this footer."))
		XCTAssertTrue(updated.contains("**Stable release:** `v0.128`"))
		XCTAssertTrue(updated.contains("**Download:** [JP the Cat v0.128 DMG](https://api.jpthecat.com/releases/JPtheCat-0.128.dmg)"))
		XCTAssertFalse(updated.contains("old badge"))
		XCTAssertFalse(updated.contains("old link"))
	}

	func testReadmeMarkerHelperFailsClosedWhenMarkersAreMissing() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

		let readme = directory.appendingPathComponent("README.md")
		try "# JPtheCat\n\nNo generated markers here.\n".write(to: readme, atomically: true, encoding: .utf8)

		XCTAssertThrowsError(
			try bash("jptc_update_readme_release_markers \(shellQuote(readme.path)) 0.128 https://example.com/JPtheCat-0.128.dmg")
		)
	}

	private func bash(_ command: String) throws {
		let process = Process()
		let output = Pipe()
		let error = Pipe()
		let helper = repoRoot().appendingPathComponent("mac/scripts/release-readme.sh")

		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-lc", "source \(shellQuote(helper.path)); \(command)"]
		process.standardOutput = output
		process.standardError = error

		try process.run()
		process.waitUntilExit()

		if process.terminationStatus != 0 {
			let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
			let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
			throw BashError(command: command, stdout: stdout, stderr: stderr, status: process.terminationStatus)
		}
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}

	private func shellQuote(_ value: String) -> String {
		"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}

	private struct BashError: Error {
		let command: String
		let stdout: String
		let stderr: String
		let status: Int32
	}
}
