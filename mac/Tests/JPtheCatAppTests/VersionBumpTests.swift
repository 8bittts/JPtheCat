import Foundation
import XCTest

final class VersionBumpTests: XCTestCase {
	func testPatchVersionBumpsAcrossDigitBoundaries() throws {
		XCTAssertEqual(try call("jptc_bump_patch_version", "0.001"), "0.002")
		XCTAssertEqual(try call("jptc_bump_patch_version", "0.009"), "0.010")
		XCTAssertEqual(try call("jptc_bump_patch_version", "0.099"), "0.100")
		XCTAssertEqual(try call("jptc_bump_patch_version", "1.042"), "1.043")
	}

	func testPatchVersionRollsOverAfter999() throws {
		XCTAssertEqual(try call("jptc_bump_patch_version", "0.999"), "1.000")
		XCTAssertEqual(try call("jptc_bump_patch_version", "2.999"), "3.000")
	}

	func testLatestPublishedBuildNumberReadsFirstNumericSparkleVersion() throws {
		let appcast = try writeAppcast("""
		<?xml version="1.0" encoding="utf-8"?>
		<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
			<channel>
				<item>
					<sparkle:version>151</sparkle:version>
				</item>
				<item>
					<sparkle:version>150</sparkle:version>
				</item>
			</channel>
		</rss>
		""")

		XCTAssertEqual(try call("jptc_latest_published_build_number", appcast.path), "151")
	}

	func testLatestPublishedBuildNumberFailsClosedForMissingOrInvalidAppcast() throws {
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathComponent("appcast.xml")
		let invalid = try writeAppcast("""
		<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
			<channel>
				<item><sparkle:version>not-a-build</sparkle:version></item>
			</channel>
		</rss>
		""")

		XCTAssertEqual(try call("jptc_latest_published_build_number", missing.path), "0")
		XCTAssertEqual(try call("jptc_latest_published_build_number", invalid.path), "0")
	}

	func testReleaseBuildNumberFloorsAbovePublishedAppcast() throws {
		XCTAssertEqual(try call("jptc_release_build_number", "128", "0", "0"), "129")
		XCTAssertEqual(try call("jptc_release_build_number", "128", "150", "0"), "151")
		XCTAssertEqual(try call("jptc_release_build_number", "128", "129", "3"), "131")
		XCTAssertEqual(try call("jptc_release_build_number", "128", "200", "3"), "201")
	}

	private func call(_ function: String, _ arguments: String...) throws -> String {
		let command = ([function] + arguments.map(shellQuote)).joined(separator: " ")
		return try bash(command)
	}

	private func bash(_ command: String) throws -> String {
		let process = Process()
		let output = Pipe()
		let error = Pipe()
		let helper = repoRoot().appendingPathComponent("mac/scripts/release-versioning.sh")

		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-lc", "source \(shellQuote(helper.path)); \(command)"]
		process.standardOutput = output
		process.standardError = error

		try process.run()
		process.waitUntilExit()

		let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		XCTAssertEqual(
			process.terminationStatus,
			0,
			"bash command failed: \(command)\nstdout:\n\(stdout)\nstderr:\n\(stderr)"
		)
		return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func writeAppcast(_ contents: String) throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		addTeardownBlock {
			try? FileManager.default.removeItem(at: directory)
		}

		let url = directory.appendingPathComponent("appcast.xml")
		try contents.write(to: url, atomically: true, encoding: .utf8)
		return url
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
}
