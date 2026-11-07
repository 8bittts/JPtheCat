import XCTest

@testable import JPtheCatCore

/// The OpenCode console link needs the signed-in workspace ID, which only OpenCode's own log text
/// carries. Absent log, absent URL, or a malformed ID must all yield `nil` (no link), never a guess.
final class OpenCodeWorkspaceTests: XCTestCase {
	private func stage(_ lines: [String]) throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("jp-opencode-workspace-\(UUID().uuidString)", isDirectory: true)
		let logDir = root.appendingPathComponent("log", isDirectory: true)
		try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
		try lines.joined(separator: "\n").write(
			to: logDir.appendingPathComponent("opencode.log"), atomically: true, encoding: .utf8)
		return root
	}

	func testCleanFixtureHasNoWorkspace() throws {
		XCTAssertNil(OpenCodeWorkspace.currentID(root: URL(fileURLWithPath: "/nonexistent/jp-\(UUID())")))
		let root = try stage(["timestamp=2026-09-15T20:43:08.996Z level=INFO message=\"boot\""])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertNil(OpenCodeWorkspace.currentID(root: root))
	}

	func testReadsTheWorkspaceFromOpenCodeOwnQuotaError() throws {
		let root = try stage([
			"timestamp=2026-09-15T20:43:08.996Z level=ERROR message=\"stream error\" providerID=opencode error.error=\"AI_APICallError: No payment method. Add a payment method here: https://opencode.ai/workspace/wrk_01M1PV99CD5YN9VQK5QRN21P9V/billing\"",
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(OpenCodeWorkspace.currentID(root: root), "wrk_01M1PV99CD5YN9VQK5QRN21P9V")
	}

	func testNewestWorkspaceWinsAfterSwitchingAccounts() throws {
		let root = try stage([
			"a error.error=\"… https://opencode.ai/workspace/wrk_01AAAAAAAAAAAAAAAAAAAAAAAA/go\"",
			"b error.error=\"… https://opencode.ai/workspace/wrk_01BBBBBBBBBBBBBBBBBBBBBBBB/billing\"",
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(OpenCodeWorkspace.currentID(root: root), "wrk_01BBBBBBBBBBBBBBBBBBBBBBBB")
	}

	func testMalformedOrTruncatedIDIsRejected() throws {
		let root = try stage(["x https://opencode.ai/workspace/wrk_short/go\""])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertNil(OpenCodeWorkspace.currentID(root: root))
		XCTAssertFalse(OpenCodeWorkspace.isWellFormed("wrk_01m1pv99cd5yn9vqk5qrn21p9v"))
		XCTAssertTrue(OpenCodeWorkspace.isWellFormed("wrk_01M1PV99CD5YN9VQK5QRN21P9V"))
	}
}
