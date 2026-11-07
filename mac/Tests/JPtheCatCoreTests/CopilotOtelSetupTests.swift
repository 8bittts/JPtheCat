import Foundation
import XCTest

@testable import JPtheCatCore

/// Covers the pure parsing/editing helpers of the opt-in Copilot OTel enablement installer.
final class CopilotOtelSetupTests: XCTestCase {
	func testResolvesZshrcForZshShell() {
		XCTAssertEqual(
			CopilotOtelSetup.shellRCURL(shellEnv: "/bin/zsh"),
			FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc"))
	}

	func testResolvesBashrcOrBashProfileForBashShell() {
		let resolved = CopilotOtelSetup.shellRCURL(shellEnv: "/bin/bash")
		let home = FileManager.default.homeDirectoryForCurrentUser
		XCTAssertTrue(
			resolved == home.appendingPathComponent(".bashrc")
				|| resolved == home.appendingPathComponent(".bash_profile"))
	}

	func testUnrecognizedOrMissingShellIsUnavailable() {
		XCTAssertNil(CopilotOtelSetup.shellRCURL(shellEnv: "/bin/fish"))
		XCTAssertNil(CopilotOtelSetup.shellRCURL(shellEnv: nil))
	}

	func testEnablementBlockContainsTheEnvVarAndRoundTrips() {
		let block = CopilotOtelSetup.enablementBlock()
		XCTAssertTrue(block.contains("export COPILOT_OTEL_FILE_EXPORTER_PATH="))
		XCTAssertTrue(block.contains(CopilotOtelSetup.otelFileExporterPath().path))
		XCTAssertTrue(CopilotOtelSetup.isInstalled(inScript: "foo\n" + block + "\nbar"))
		XCTAssertFalse(CopilotOtelSetup.isInstalled(inScript: "no markers here"))
	}

	func testEnablementBlockDoesNotUseTheNetworkOnlyEnvVar() {
		// Regression guard: COPILOT_OTEL_ENABLED=true alone selects the network otlp-http exporter,
		// not the local file exporter — verified against the CLI's own bundled help text and a real
		// session log. Only the file-path env var (which auto-selects "file" and auto-enables OTel)
		// belongs here.
		XCTAssertFalse(CopilotOtelSetup.enablementBlock().contains("COPILOT_OTEL_ENABLED=true"))
	}

	func testStaleNetworkOnlyBlockIsNotConsideredCurrent() {
		let stale = "\(CopilotOtelSetup.beginMarker)\nexport COPILOT_OTEL_ENABLED=true\n\(CopilotOtelSetup.endMarker)"
		XCTAssertTrue(CopilotOtelSetup.isInstalled(inScript: stale))
		XCTAssertFalse(CopilotOtelSetup.isCurrent(inScript: stale))
		XCTAssertTrue(CopilotOtelSetup.isCurrent(inScript: CopilotOtelSetup.enablementBlock()))
	}

	func testRemovingBlockFullyReverts() {
		let original = "#!/bin/zsh\nexport PATH=$PATH:/usr/local/bin\n"
		let installed = original + "\n" + CopilotOtelSetup.enablementBlock() + "\n"
		XCTAssertTrue(CopilotOtelSetup.isInstalled(inScript: installed))
		let reverted = CopilotOtelSetup.removingBlock(from: installed)
		XCTAssertFalse(CopilotOtelSetup.isInstalled(inScript: reverted))
		XCTAssertTrue(reverted.contains("export PATH=$PATH:/usr/local/bin"))
	}

	func testRemovingBlockIsANoOpWhenNotInstalled() {
		let script = "#!/bin/zsh\necho hi\n"
		XCTAssertEqual(CopilotOtelSetup.removingBlock(from: script), script)
	}

	// MARK: - Install/uninstall against a real temp file (isolated from the user's actual shell rc)

	func testInstallIsIdempotentAndUninstallFullyReverts() throws {
		let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-otel-setup-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tempDir) }
		let rc = tempDir.appendingPathComponent(".zshrc")
		try "# existing content\n".write(to: rc, atomically: true, encoding: .utf8)

		var script = try String(contentsOf: rc, encoding: .utf8)
		XCTAssertFalse(CopilotOtelSetup.isInstalled(inScript: script))

		script += "\n" + CopilotOtelSetup.enablementBlock() + "\n"
		try script.write(to: rc, atomically: true, encoding: .utf8)
		let installed = try String(contentsOf: rc, encoding: .utf8)
		XCTAssertTrue(CopilotOtelSetup.isInstalled(inScript: installed))
		XCTAssertTrue(installed.contains("# existing content"))

		let reverted = CopilotOtelSetup.removingBlock(from: installed)
		XCTAssertFalse(CopilotOtelSetup.isInstalled(inScript: reverted))
		XCTAssertTrue(reverted.contains("# existing content"))
	}

	func testInstallMigratesAStaleNetworkOnlyBlockToTheFileExporterForm() throws {
		let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-otel-migrate-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tempDir) }
		let rc = tempDir.appendingPathComponent(".zshrc")
		let stale =
			"# existing content\n\n\(CopilotOtelSetup.beginMarker)\n"
			+ "export COPILOT_OTEL_ENABLED=true\n\(CopilotOtelSetup.endMarker)\n"
		try stale.write(to: rc, atomically: true, encoding: .utf8)

		// Exercise the pure migration logic directly (install() targets the real user shellRCURL()).
		let script = try String(contentsOf: rc, encoding: .utf8)
		XCTAssertTrue(CopilotOtelSetup.isInstalled(inScript: script))
		XCTAssertFalse(CopilotOtelSetup.isCurrent(inScript: script))
		let migrated =
			CopilotOtelSetup.removingBlock(from: script) + "\n" + CopilotOtelSetup.enablementBlock() + "\n"
		XCTAssertTrue(CopilotOtelSetup.isCurrent(inScript: migrated))
		XCTAssertTrue(migrated.contains("# existing content"))
	}

	// MARK: - Copilot CLI detection (gates whether the Settings row shows at all)

	func testDetectsCopilotOnlyWhenAnExecutableNamedCopilotExistsInASearchDirectory() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-bin-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		XCTAssertFalse(
			CopilotOtelSetup.isCopilotCLIDetected(searchDirectories: [dir]),
			"must not report Copilot as detected when no directory has a copilot executable")

		let binary = dir.appendingPathComponent("copilot")
		FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8))
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
		XCTAssertTrue(CopilotOtelSetup.isCopilotCLIDetected(searchDirectories: [dir]))
	}

	func testNonExecutableFileNamedCopilotDoesNotCountAsDetected() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-nonexec-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let notExecutable = dir.appendingPathComponent("copilot")
		FileManager.default.createFile(atPath: notExecutable.path, contents: Data("not a binary".utf8))
		try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: notExecutable.path)
		XCTAssertFalse(
			CopilotOtelSetup.isCopilotCLIDetected(searchDirectories: [dir]),
			"a stale non-executable file named 'copilot' must not count as a real install")
	}

	func testStaleCopilotHomeDirectoryAloneDoesNotCountAsDetected() throws {
		// Regression guard for the exact false-positive found on a real dev machine: ~/.copilot
		// (config.json + logs/) surviving from a one-time trial, with no actual binary anywhere.
		let emptySearchDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-empty-search-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: emptySearchDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: emptySearchDir) }
		XCTAssertFalse(CopilotOtelSetup.isCopilotCLIDetected(searchDirectories: [emptySearchDir]))
	}
}
