import Foundation
import XCTest

/// Runs the REAL `ensure_supabase_link` from `release-jpthecat.sh` inside a temporary repository and
/// worktree. A release started from a fresh worktree used to fail because the Supabase link lives in
/// the gitignored repo-root `supabase/.temp`, which a new worktree never has.
final class ReleaseSupabaseLinkTests: XCTestCase {
	private let projectRef = "duqpnrpzadrxqdbspjft"
	private var sandbox: URL!

	override func setUpWithError() throws {
		sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-release-link-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: sandbox)
	}

	func testFreshWorktreeInheritsTheMainCheckoutsLink() throws {
		let (main, worktree) = try makeRepository(mainRef: projectRef)
		XCTAssertEqual(try runEnsure(rroot: worktree).status, 0)
		XCTAssertEqual(try readRef(worktree), projectRef)
		XCTAssertEqual(try readRef(main), projectRef, "the main checkout's link must stay in place")
	}

	/// A main checkout linked to a DIFFERENT project is never copied; the reachability check then fails.
	func testMainCheckoutLinkedElsewhereIsNotCopied() throws {
		let (_, worktree) = try makeRepository(mainRef: "someotherproject000")
		XCTAssertEqual(try runEnsure(rroot: worktree).status, 0)
		XCTAssertFalse(FileManager.default.fileExists(
			atPath: worktree.appendingPathComponent("supabase/.temp/project-ref").path))
	}

	func testAnExistingLinkIsLeftUntouched() throws {
		let (_, worktree) = try makeRepository(mainRef: projectRef)
		let temp = worktree.appendingPathComponent("supabase/.temp", isDirectory: true)
		try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
		try "worktreeownlink0000".write(
			to: temp.appendingPathComponent("project-ref"), atomically: true, encoding: .utf8)
		XCTAssertEqual(try runEnsure(rroot: worktree).status, 0)
		XCTAssertEqual(try readRef(worktree), "worktreeownlink0000")
	}

	// MARK: Helpers

	private func makeRepository(mainRef: String) throws -> (main: URL, worktree: URL) {
		let main = sandbox.appendingPathComponent("repo", isDirectory: true)
		try FileManager.default.createDirectory(
			at: main.appendingPathComponent("supabase"), withIntermediateDirectories: true)
		try "".write(to: main.appendingPathComponent("supabase/config.toml"), atomically: true, encoding: .utf8)
		try ".temp/\n".write(to: main.appendingPathComponent("supabase/.gitignore"), atomically: true, encoding: .utf8)
		try git(["init", "-q", "-b", "main"], in: main)
		try git(["add", "."], in: main)
		try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"], in: main)
		let temp = main.appendingPathComponent("supabase/.temp", isDirectory: true)
		try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
		try mainRef.write(to: temp.appendingPathComponent("project-ref"), atomically: true, encoding: .utf8)
		let worktree = sandbox.appendingPathComponent("wt", isDirectory: true)
		try git(["worktree", "add", "-q", worktree.path, "-b", "wt"], in: main)
		return (main.resolvingSymlinksInPath(), worktree.resolvingSymlinksInPath())
	}

	private func readRef(_ root: URL) throws -> String {
		try String(contentsOf: root.appendingPathComponent("supabase/.temp/project-ref"), encoding: .utf8)
	}

	/// Extracts the function (and its project-ref constant) verbatim from the release script. Missing
	/// markers FAIL the test rather than skip it, so a rename cannot turn this guard into a false green.
	private func runEnsure(rroot: URL) throws -> (status: Int32, output: String) {
		let script = try String(
			contentsOf: repoRoot().appendingPathComponent("mac/scripts/release-jpthecat.sh"), encoding: .utf8)
		let start = try XCTUnwrap(script.range(of: "SUPABASE_PROJECT_REF="), "project-ref constant missing")
		let body = try XCTUnwrap(
			script.range(of: "ensure_supabase_link() {", range: start.upperBound..<script.endIndex),
			"ensure_supabase_link missing")
		let end = try XCTUnwrap(
			script.range(of: "\n}\n", range: body.upperBound..<script.endIndex), "function end missing")
		let function = String(script[start.lowerBound..<end.upperBound])
		let harness = """
			set -euo pipefail
			fail() { echo "FAIL: $1"; exit 1; }
			step() { echo "STEP: $1"; }
			RROOT=\(rroot.path)
			\(function)
			ensure_supabase_link
			"""
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-c", harness]
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}

	private func git(_ arguments: [String], in directory: URL) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = arguments
		process.currentDirectoryURL = directory
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try process.run()
		process.waitUntilExit()
		XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed")
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatAppTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.deletingLastPathComponent()  // repo root
	}
}
