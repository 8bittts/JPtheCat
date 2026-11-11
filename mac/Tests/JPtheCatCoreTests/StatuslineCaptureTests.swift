import Foundation
import XCTest

@testable import JPtheCatCore

/// Covers the pure parsing/editing helpers of the opt-in statusline capture installer.
final class StatuslineCaptureTests: XCTestCase {
	func testResolvesScriptPathFromBareAndLauncherCommands() {
		let bare = #"{"statusLine":{"type":"command","command":"~/.claude/statusline-command.sh"}}"#.data(using: .utf8)!
		XCTAssertEqual(
			StatuslineCapture.statuslineScriptPath(fromSettingsJSON: bare),
			FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/statusline-command.sh")

		let launcher = #"{"statusLine":{"command":"bash /opt/line.sh"}}"#.data(using: .utf8)!
		XCTAssertEqual(StatuslineCapture.statuslineScriptPath(fromSettingsJSON: launcher), "/opt/line.sh")

		XCTAssertNil(StatuslineCapture.statuslineScriptPath(fromSettingsJSON: #"{"other":1}"#.data(using: .utf8)!))
	}

	func testFindsStdinCaptureVariable() {
		XCTAssertEqual(StatuslineCapture.stdinVarName(inScript: "#!/bin/bash\ninput=$(cat)\necho hi"), "input")
		XCTAssertEqual(StatuslineCapture.stdinVarName(inScript: "  payload=$(cat)  "), "payload")
		XCTAssertNil(StatuslineCapture.stdinVarName(inScript: "echo hello\nx=5"))
	}

	func testCaptureBlockUsesDetectedVarAndRoundTrips() {
		let block = StatuslineCapture.captureBlock(varName: "input")
		XCTAssertTrue(block.contains("echo \"$input\""))
		XCTAssertTrue(StatuslineCapture.isInstalled(inScript: "foo\n" + block + "\nbar"))
		XCTAssertFalse(StatuslineCapture.isInstalled(inScript: "no markers here"))
	}

	/// The block must forward every `seven_day*` window and `model_scoped` (Fable), and keep writing
	/// atomically as a pure side effect (no stdout).
	func testCaptureBlockForwardsEveryWeeklyWindow() {
		let block = StatuslineCapture.captureBlock(varName: "input")
		XCTAssertTrue(block.contains(#"startswith("seven_day")"#))
		XCTAssertTrue(block.contains("model_scoped"))
		XCTAssertTrue(block.contains("claude-rate-limits.json"))
		XCTAssertTrue(block.contains("__jpc_file.tmp"))
		XCTAssertTrue(block.contains("mv -f"))
	}

	/// `isInstalled` is marker-only, so without a revision stamp an existing installer would keep the
	/// old block — and its narrower field set — forever. A stale block must be detected and replaced.
	func testStaleBlockIsDetectedForMigrationAndCurrentBlockIsNot() {
		let current = StatuslineCapture.captureBlock(varName: "input")
		XCTAssertFalse(StatuslineCapture.needsMigration(inScript: "x\n" + current))

		let legacy = """
			\(StatuslineCapture.beginMarker) (added by JPtheCat)
			echo "$input" | jq -c '{capturedAt:(now|floor), five_hour:.rate_limits.five_hour}'
			\(StatuslineCapture.endMarker)
			"""
		XCTAssertTrue(StatuslineCapture.needsMigration(inScript: "x\n" + legacy))

		// A script that never opted in must never be migrated INTO an install.
		XCTAssertFalse(StatuslineCapture.needsMigration(inScript: "#!/bin/bash\ninput=$(cat)\n"))
	}

	/// Revision 2's 5-hour-only gate is stale and must migrate; a block from a NEWER build must not be
	/// rewritten by this one, or two installed builds would fight and the older gate would return.
	func testMigrationOnlyMovesForward() {
		let stamped = { (revision: Int) in
			"""
			\(StatuslineCapture.beginMarker) (added by JPtheCat)
			# jpthecat-capture-revision: \(revision)
			\(StatuslineCapture.endMarker)
			"""
		}
		XCTAssertEqual(StatuslineCapture.installedRevision(inScript: stamped(2)), 2)
		XCTAssertTrue(StatuslineCapture.needsMigration(inScript: stamped(2)))
		XCTAssertFalse(StatuslineCapture.needsMigration(inScript: stamped(StatuslineCapture.blockRevision)))
		XCTAssertFalse(StatuslineCapture.needsMigration(inScript: stamped(StatuslineCapture.blockRevision + 1)))
	}

	/// Migration reuses `removingBlock` + re-append, so a stale install must round-trip to exactly the
	/// current block with the user's own script body untouched and no duplicated block.
	func testMigratingAStaleBlockLeavesExactlyOneCurrentBlock() {
		let legacy = """
			\(StatuslineCapture.beginMarker) (added by JPtheCat)
			echo "$input" | jq -c '{capturedAt:(now|floor), five_hour:.rate_limits.five_hour}'
			\(StatuslineCapture.endMarker)
			"""
		let script = "#!/bin/bash\ninput=$(cat)\necho hi\n\n" + legacy + "\n"
		var migrated = StatuslineCapture.removingBlock(from: script)
		migrated += "\n" + StatuslineCapture.captureBlock(varName: "input") + "\n"

		XCTAssertTrue(migrated.contains("echo hi"))
		XCTAssertFalse(StatuslineCapture.needsMigration(inScript: migrated))
		XCTAssertEqual(migrated.components(separatedBy: StatuslineCapture.beginMarker).count - 1, 1)
	}

	/// `mac/scripts/claude-statusline-capture.sh` is the copy-paste copy for users who install by hand,
	/// and it is a SECOND copy of the same jq expression. Nothing else forces the two to move together,
	/// so a capture improvement could silently ship to the in-app installer only. Pin the shared line.
	func testShippedSnippetMatchesTheInstalledBlocksJqExpression() throws {
		let scriptURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatCoreTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.appendingPathComponent("scripts/claude-statusline-capture.sh")
		let snippet = try String(contentsOf: scriptURL, encoding: .utf8)
		let block = StatuslineCapture.captureBlock(varName: "input")

		// Compare the jq PROGRAM itself (between `jq -c '` and its closing quote); the surrounding shell
		// line wraps differently in the two copies, which is not a divergence worth failing on.
		let jqProgram = { (text: String) -> String? in
			guard let start = text.range(of: "jq -c '") else { return nil }
			let rest = text[start.upperBound...]
			guard let end = rest.range(of: "'") else { return nil }
			return String(rest[rest.startIndex..<end.lowerBound])
		}
		XCTAssertNotNil(jqProgram(snippet))
		XCTAssertEqual(jqProgram(snippet), jqProgram(block))
		XCTAssertTrue(snippet.contains("jpthecat-capture-revision: \(StatuslineCapture.blockRevision)"))
	}

	/// The hand-install snippet must carry the same write GATE as the installed block, not just the
	/// same writer: revision 2 shipped a 5-hour-only gate in both copies.
	func testShippedSnippetMatchesTheInstalledBlocksGate() throws {
		let scriptURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("scripts/claude-statusline-capture.sh")
		let snippet = try String(contentsOf: scriptURL, encoding: .utf8)
		let block = StatuslineCapture.captureBlock(varName: "input")
		let gate = { (text: String) -> String? in
			guard let start = text.range(of: "jq -e '") else { return nil }
			let rest = text[start.upperBound...]
			guard let end = rest.range(of: "'") else { return nil }
			return String(rest[rest.startIndex..<end.lowerBound])
		}
		XCTAssertEqual(gate(block), StatuslineCapture.gateProgram)
		XCTAssertEqual(gate(snippet), gate(block))
	}

	/// Runs the REAL block through bash + jq with `HOME` pointed at a temp directory, so the written
	/// file is the exact bytes the app decodes. The weekly-only payload is the one Claude Code 2.1.318
	/// sends today; revision 2 skipped it and froze the gauge at a days-old 8% against a live 75%.
	func testBlockWritesAWeeklyOnlyPayloadThatDecodesToTheWeeklyWindow() throws {
		let reset = Date().addingTimeInterval(3 * 86_400).timeIntervalSince1970.rounded()
		let payload = #"{"rate_limits":{"seven_day":{"used_percentage":75,"resets_at":\#(Int(reset))}}}"#
		let home = try runCaptureBlock(payload: payload)
		defer { try? FileManager.default.removeItem(at: home) }

		let data = try Data(contentsOf: capturedFile(home: home))
		let snapshot = try XCTUnwrap(ClaudeRateLimitStore.decode(data))
		XCTAssertNil(snapshot.primary)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 75)
		XCTAssertEqual(snapshot.secondary?.windowMinutes, 10080)
		XCTAssertEqual(snapshot.secondary?.resetsAt, Date(timeIntervalSince1970: reset))
		XCTAssertNotNil(snapshot.capturedAt)
	}

	/// A payload with both windows still writes both, and per-model weekly windows still pass through.
	func testBlockStillWritesFiveHourAndPerModelWindows() throws {
		let reset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
		let payload = #"{"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":\#(reset)},"seven_day":{"used_percentage":8,"resets_at":\#(reset)},"seven_day_opus":{"used_percentage":100,"resets_at":\#(reset)},"spend_limit":{"used_percentage":5,"resets_at":\#(reset)}}}"#
		let home = try runCaptureBlock(payload: payload)
		defer { try? FileManager.default.removeItem(at: home) }

		let data = try Data(contentsOf: capturedFile(home: home))
		let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertEqual(Set(root.keys), ["capturedAt", "five_hour", "seven_day", "seven_day_opus"])
		let snapshot = try XCTUnwrap(ClaudeRateLimitStore.decode(data))
		XCTAssertEqual(snapshot.primary?.usedPercent, 0)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 8)
		XCTAssertEqual(snapshot.modelWindows.map(\.label), ["Fable"])
	}

	/// Claude Code 2.1.322 sends Fable as `model_scoped`, with a 0–100 `utilization` and an ISO reset.
	/// Extra fields on that row, and `spend_limit`, must not land in the file.
	func testBlockWritesModelScopedFableBesideAllModels() throws {
		let payload = #"{"rate_limits":{"seven_day":{"used_percentage":71,"resets_at":1794675600},"model_scoped":[{"display_name":"Fable","utilization":96,"resets_at":"2026-11-14T17:00:00.368647+00:00","note":"drop me"}],"spend_limit":{"used_percentage":5,"resets_at":1}}}"#
		let home = try runCaptureBlock(payload: payload)
		defer { try? FileManager.default.removeItem(at: home) }

		let data = try Data(contentsOf: capturedFile(home: home))
		let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertEqual(Set(root.keys), ["capturedAt", "seven_day", "model_scoped"])
		let rows = try XCTUnwrap(root["model_scoped"] as? [[String: Any]])
		XCTAssertEqual(Set(rows[0].keys), ["display_name", "utilization", "resets_at"])
		let snapshot = try XCTUnwrap(ClaudeRateLimitStore.decode(data, now: Date(timeIntervalSince1970: 1_794_413_343)))
		XCTAssertEqual(snapshot.secondary?.usedPercent, 71)
		XCTAssertEqual(snapshot.modelWindows.map(\.label), ["Fable"])
		XCTAssertEqual(snapshot.modelWindows.first?.window.usedPercent ?? -1, 96, accuracy: 0.001)
		XCTAssertEqual(
			snapshot.modelWindows.first?.window.resetsAt?.timeIntervalSince1970 ?? 0, 1_794_675_600.368647,
			accuracy: 0.001)
	}

	/// A later payload that only refreshes All models must not erase the Fable row already on disk.
	/// An explicit empty `model_scoped` array does clear it.
	func testLaterPayloadKeepsFableUntilAnEmptyModelScopedArrayClearsIt() throws {
		let withFable = #"{"rate_limits":{"seven_day":{"used_percentage":71,"resets_at":1794675600},"model_scoped":[{"display_name":"Fable","utilization":96,"resets_at":"2026-11-14T17:00:00Z"}]}}"#
		let home = try runCaptureBlock(payload: withFable)
		defer { try? FileManager.default.removeItem(at: home) }

		let weeklyOnly = #"{"rate_limits":{"seven_day":{"used_percentage":72,"resets_at":1794675600}}}"#
		_ = try runCaptureBlock(payload: weeklyOnly, home: home)
		let kept = try Data(contentsOf: capturedFile(home: home))
		let keptSnap = try XCTUnwrap(ClaudeRateLimitStore.decode(kept, now: Date(timeIntervalSince1970: 1_794_413_343)))
		XCTAssertEqual(keptSnap.secondary?.usedPercent, 72)
		XCTAssertEqual(keptSnap.modelWindows.map(\.label), ["Fable"])
		XCTAssertEqual(keptSnap.modelWindows.first?.window.usedPercent ?? -1, 96, accuracy: 0.001)

		let cleared = #"{"rate_limits":{"seven_day":{"used_percentage":73,"resets_at":1794675600},"model_scoped":[]}}"#
		_ = try runCaptureBlock(payload: cleared, home: home)
		let gone = try Data(contentsOf: capturedFile(home: home))
		let goneSnap = try XCTUnwrap(ClaudeRateLimitStore.decode(gone, now: Date(timeIntervalSince1970: 1_794_413_343)))
		XCTAssertEqual(goneSnap.secondary?.usedPercent, 73)
		XCTAssertEqual(goneSnap.modelWindows.count, 0)
	}

	/// No window means no write: a null feed (before the first response) or a gateway-only spend limit
	/// must never replace the last real reading with an empty one.
	func testBlockWritesNothingWithoutAnOfficialWindow() throws {
		for payload in [#"{"rate_limits":null}"#, "{}", #"{"rate_limits":{"spend_limit":{"used_percentage":5,"resets_at":1}}}"#] {
			let home = try runCaptureBlock(payload: payload)
			defer { try? FileManager.default.removeItem(at: home) }
			XCTAssertFalse(FileManager.default.fileExists(atPath: capturedFile(home: home).path), payload)
		}
	}

	private func capturedFile(home: URL) -> URL {
		home.appendingPathComponent("Library/Application Support/JPtheCat/claude-rate-limits.json")
	}

	/// Executes `input=$(cat)` plus the installed block with a throwaway `HOME`; never touches the real
	/// capture file. Fails closed when jq is missing, because the shipped block depends on it.
	private func runCaptureBlock(payload: String, home existing: URL? = nil) throws -> URL {
		let jq = URL(fileURLWithPath: "/usr/bin/jq")
		guard FileManager.default.isExecutableFile(atPath: jq.path) else {
			XCTFail("/usr/bin/jq is required to execute the capture block")
			throw CocoaError(.fileNoSuchFile)
		}
		let home: URL
		if let existing {
			home = existing
		} else {
			home = URL(fileURLWithPath: NSTemporaryDirectory())
				.appendingPathComponent("jpc-statusline-\(UUID().uuidString)", isDirectory: true)
			try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-c", "input=$(cat)\n" + StatuslineCapture.captureBlock(varName: "input")]
		process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
		let stdin = Pipe()
		process.standardInput = stdin
		try process.run()
		stdin.fileHandleForWriting.write(Data(payload.utf8))
		try stdin.fileHandleForWriting.close()
		process.waitUntilExit()
		XCTAssertEqual(process.terminationStatus, 0)
		return home
	}

	func testRemovingBlockFullyReverts() {
		let original = "#!/bin/bash\ninput=$(cat)\necho hi\n"
		let installed = original + "\n" + StatuslineCapture.captureBlock(varName: "input") + "\n"
		XCTAssertTrue(StatuslineCapture.isInstalled(inScript: installed))
		let reverted = StatuslineCapture.removingBlock(from: installed)
		XCTAssertFalse(StatuslineCapture.isInstalled(inScript: reverted))
		XCTAssertTrue(reverted.contains("echo hi"))
	}
}
