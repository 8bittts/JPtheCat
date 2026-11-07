import Foundation
import XCTest

@testable import JPtheCatCore

final class CursorProviderTests: XCTestCase {
	private func tempDirectory(_ name: String) throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-cursor-\(name)-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private let validLine = """
		{"captured_at":1785029000,"conversation_id":"conversation-1","generation_id":"generation-1","model":"claude-4.5-sonnet","input_tokens":120,"output_tokens":30,"cache_read_tokens":40,"cache_write_tokens":10}
		"""

	func testDecodesUsageOnlyCaptureAndNormalizesCachedInputOnce() throws {
		let event = try XCTUnwrap(CursorProvider.decode(line: Data(validLine.utf8)))
		XCTAssertEqual(event.provider, .cursor)
		XCTAssertEqual(event.messageId, "generation-1")
		XCTAssertEqual(event.requestId, "conversation-1")
		XCTAssertEqual(event.model, "claude-4.5-sonnet")
		XCTAssertEqual(event.usage, TokenUsage(input: 70, output: 30, cacheCreate5m: 10, cacheRead: 40))
		XCTAssertNil(event.project)
	}

	func testMalformedMissingNegativeAndEmptyRecordsFailClosed() {
		for line in [
			"not json",
			#"{"captured_at":1,"conversation_id":"c","model":"m","input_tokens":1}"#,
			#"{"captured_at":1,"generation_id":"g","model":"m","input_tokens":-1}"#,
			#"{"captured_at":1,"generation_id":"g","model":"m","input_tokens":0}"#,
		] {
			XCTAssertNil(CursorProvider.decode(line: Data(line.utf8)), line)
		}
	}

	func testProviderAvailabilityLoadAndDedupReuseSharedPrimitives() throws {
		let root = try tempDirectory("load")
		defer { try? FileManager.default.removeItem(at: root) }
		let capture = root.appendingPathComponent("cursor-usage.jsonl")
		try "\(validLine)\n\(validLine)\ntruncated".write(
			to: capture, atomically: true, encoding: .utf8)
		let provider = CursorProvider(root: capture)
		XCTAssertTrue(provider.isAvailable())
		XCTAssertEqual(provider.loadEvents().count, 1)
		XCTAssertFalse(
			CursorProvider(root: root.appendingPathComponent("missing.jsonl")).isAvailable())
	}

	func testUsageIndexerTailsAppendOnlyCaptureIdempotently() throws {
		let root = try tempDirectory("index")
		defer { try? FileManager.default.removeItem(at: root) }
		let capture = root.appendingPathComponent("cursor-usage.jsonl")
		try (validLine + "\n").write(to: capture, atomically: true, encoding: .utf8)
		let provider = CursorProvider(root: capture)
		let index = try UsageIndex(path: root.appendingPathComponent("usage.sqlite").path)
		let indexer = UsageIndexer(index: index)

		let first = try indexer.refresh(provider)
		XCTAssertEqual(first.eventsIngested, 1)
		XCTAssertEqual(index.eventCount(provider: .cursor), 1)
		let second = try indexer.refresh(provider)
		XCTAssertEqual(second.filesSkipped, 1)

		let appended = validLine
			.replacingOccurrences(of: "generation-1", with: "generation-2")
			.replacingOccurrences(of: "output_tokens\":30", with: "output_tokens\":31")
		let handle = try FileHandle(forWritingTo: capture)
		try handle.seekToEnd()
		try handle.write(contentsOf: Data((appended + "\n").utf8))
		try handle.close()
		let third = try indexer.refresh(provider)
		XCTAssertEqual(third.eventsIngested, 1)
		XCTAssertEqual(index.eventCount(provider: .cursor), 2)
	}

	func testSetupMergesAndRemovesOnlyItsExistingStopHook() throws {
		let home = try tempDirectory("setup")
		defer { try? FileManager.default.removeItem(at: home) }
		let cursorHome = home.appendingPathComponent(".cursor", isDirectory: true)
		let support = home.appendingPathComponent("support", isDirectory: true)
		try FileManager.default.createDirectory(at: cursorHome, withIntermediateDirectories: true)
		let original = """
			{"version":1,"hooks":{"stop":[{"command":"./hooks/existing.sh","timeout":9}],"beforeReadFile":[{"command":"./hooks/read.sh"}]},"other":"kept"}
			"""
		try original.write(
			to: CursorHookSetup.hooksURL(cursorHome: cursorHome), atomically: true, encoding: .utf8)

		try CursorHookSetup.install(cursorHome: cursorHome, appSupport: support, detected: true)
		try CursorHookSetup.install(cursorHome: cursorHome, appSupport: support, detected: true)
		XCTAssertEqual(
			CursorHookSetup.state(cursorHome: cursorHome, appSupport: support, detected: true), .active)
		let installedData = try Data(contentsOf: CursorHookSetup.hooksURL(cursorHome: cursorHome))
		let installed = try XCTUnwrap(
			JSONSerialization.jsonObject(with: installedData) as? [String: Any])
		let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
		let stop = try XCTUnwrap(hooks["stop"] as? [[String: Any]])
		XCTAssertEqual(stop.count, 2, "idempotent install adds one JP command")
		XCTAssertEqual(stop[0]["command"] as? String, "./hooks/existing.sh")
		XCTAssertNotNil(hooks["beforeReadFile"])
		XCTAssertEqual(installed["other"] as? String, "kept")

		try CursorHookSetup.uninstall(cursorHome: cursorHome, appSupport: support)
		let revertedData = try Data(contentsOf: CursorHookSetup.hooksURL(cursorHome: cursorHome))
		let reverted = try XCTUnwrap(
			JSONSerialization.jsonObject(with: revertedData) as? [String: Any])
		let revertedHooks = try XCTUnwrap(reverted["hooks"] as? [String: Any])
		let revertedStop = try XCTUnwrap(revertedHooks["stop"] as? [[String: Any]])
		XCTAssertEqual(revertedStop.count, 1)
		XCTAssertEqual(revertedStop[0]["command"] as? String, "./hooks/existing.sh")
		XCTAssertNotNil(revertedHooks["beforeReadFile"])
		XCTAssertFalse(FileManager.default.fileExists(atPath: CursorHookSetup.scriptURL(appSupport: support).path))
	}

	func testSetupRejectsMalformedConfigWithoutMutation() throws {
		let home = try tempDirectory("malformed")
		defer { try? FileManager.default.removeItem(at: home) }
		let cursorHome = home.appendingPathComponent(".cursor", isDirectory: true)
		let support = home.appendingPathComponent("support", isDirectory: true)
		try FileManager.default.createDirectory(at: cursorHome, withIntermediateDirectories: true)
		let url = CursorHookSetup.hooksURL(cursorHome: cursorHome)
		let malformed = Data("{not-json".utf8)
		try malformed.write(to: url)
		XCTAssertThrowsError(
			try CursorHookSetup.install(cursorHome: cursorHome, appSupport: support, detected: true))
		XCTAssertEqual(try Data(contentsOf: url), malformed)
	}

	func testRecorderScriptWritesOnlyAllowlistedUsageAndFailsOpen() throws {
		let root = try tempDirectory("script")
		defer { try? FileManager.default.removeItem(at: root) }
		let output = root.appendingPathComponent("cursor-usage.jsonl")
		let script = root.appendingPathComponent("capture.sh")
		try CursorHookSetup.captureScript(outputURL: output)
			.write(to: script, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

		let payload = """
			{"conversation_id":"c","generation_id":"g","model":"m","status":"completed","input_tokens":20,"output_tokens":4,"cache_read_tokens":3,"cache_write_tokens":2,"prompt":"SECRET PROMPT","text":"SECRET RESPONSE","cwd":"/secret/path"}
			"""
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = [script.path]
		let input = Pipe()
		process.standardInput = input
		try process.run()
		input.fileHandleForWriting.write(Data(payload.utf8))
		try input.fileHandleForWriting.close()
		process.waitUntilExit()
		XCTAssertEqual(process.terminationStatus, 0)

		let captured = try String(contentsOf: output, encoding: .utf8)
		XCTAssertFalse(captured.contains("SECRET"))
		XCTAssertFalse(captured.contains("/secret/path"))
		XCTAssertEqual(captured.split(separator: "\n").count, 1)
		let event = try XCTUnwrap(CursorProvider.decode(line: Data(captured.utf8)))
		XCTAssertEqual(event.messageId, "g")
		XCTAssertEqual(event.requestId, "c")
		XCTAssertEqual(event.model, "m")
		XCTAssertEqual(event.usage, TokenUsage(input: 15, output: 4, cacheCreate5m: 2, cacheRead: 3))
	}

	// MARK: - Decode cache

	/// `loadEvents()` re-read the capture file from offset 0 on EVERY call — and `DashboardViewModel`
	/// calls it on every refresh build (60 s poll plus every FSEvents burst, 2 s floor) with
	/// `DashboardWidgetPublisher` calling it again per publish. An unchanged refresh must now cost one
	/// `stat(2)`. A cache hit is not otherwise observable, so this reads the traversal counter.
	func testUnchangedRefreshDoesNotReDecodeTheCaptureFile() throws {
		let root = try tempDirectory("cache")
		defer { try? FileManager.default.removeItem(at: root) }
		let capture = root.appendingPathComponent("cursor-usage.jsonl")
		try (validLine + "\n").write(to: capture, atomically: true, encoding: .utf8)
		let provider = CursorProvider(root: capture)

		let before = CursorProvider.decodeTraversalCount
		XCTAssertEqual(provider.loadEvents().count, 1)
		XCTAssertEqual(CursorProvider.decodeTraversalCount - before, 1)
		for _ in 0..<5 { XCTAssertEqual(provider.loadEvents().count, 1) }
		XCTAssertEqual(
			CursorProvider.decodeTraversalCount - before, 1, "unchanged file must not be re-decoded")

		let appended = validLine.replacingOccurrences(of: "generation-1", with: "generation-2")
		let handle = try FileHandle(forWritingTo: capture)
		try handle.seekToEnd()
		try handle.write(contentsOf: Data((appended + "\n").utf8))
		try handle.close()
		XCTAssertEqual(provider.loadEvents().count, 2)
		XCTAssertEqual(CursorProvider.decodeTraversalCount - before, 2)
	}

	/// [Regression guard] `(size, mtime)` alone is the v1.013-v1.015 correctness hole — a
	/// mtime-preserving rewrite leaves both identical while the bytes change. The key includes `ctime`.
	func testCacheInvalidatesOnSameSizeSameMtimeRewrite() throws {
		let root = try tempDirectory("rewrite")
		defer { try? FileManager.default.removeItem(at: root) }
		let capture = root.appendingPathComponent("cursor-usage.jsonl")
		try (validLine + "\n").write(to: capture, atomically: true, encoding: .utf8)
		let provider = CursorProvider(root: capture)
		XCTAssertEqual(provider.loadEvents().first?.messageId, "generation-1")

		let mtime = try XCTUnwrap(
			FileManager.default.attributesOfItem(atPath: capture.path)[.modificationDate] as? Date)
		// Same byte length ("generation-1" -> "generation-9"), mtime deliberately restored.
		let rewritten = validLine.replacingOccurrences(of: "generation-1", with: "generation-9")
		try (rewritten + "\n").write(to: capture, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.modificationDate: mtime], ofItemAtPath: capture.path)

		XCTAssertEqual(provider.loadEvents().first?.messageId, "generation-9")
	}

	// MARK: - Bounded capture file

	/// The recorder appends with `>> $output` and nothing else in the app ever trimmed it, so the file
	/// grew for as long as the hook stayed installed. The cap lives at the WRITE side and is
	/// line-granular, so a trimmed file never starts mid-record.
	func testRecorderScriptTrimsItsOwnCaptureFileOncePastTheCap() throws {
		let root = try tempDirectory("rotate")
		defer { try? FileManager.default.removeItem(at: root) }
		let output = root.appendingPathComponent("cursor-usage.jsonl")
		let script = root.appendingPathComponent("capture.sh")
		try CursorHookSetup.captureScript(outputURL: output)
			.write(to: script, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

		// Pre-fill past the cap with real, decodable records — enough lines that the byte size trips
		// `captureMaxBytes` AND enough that `captureKeepLines` genuinely drops some of them.
		let lineBytes = validLine.utf8.count + 1
		let fillerCount = max(
			CursorHookSetup.captureKeepLines + 100, CursorHookSetup.captureMaxBytes / lineBytes + 500)
		let filler = (0..<fillerCount).map {
			validLine.replacingOccurrences(of: "generation-1", with: "generation-old-\($0)")
		}
		try (filler.joined(separator: "\n") + "\n").write(to: output, atomically: true, encoding: .utf8)
		let sizeBefore = try XCTUnwrap(
			FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber).intValue
		XCTAssertGreaterThan(sizeBefore, CursorHookSetup.captureMaxBytes)

		let payload = """
			{"conversation_id":"c","generation_id":"g-new","model":"m","input_tokens":20,"output_tokens":4,"cache_read_tokens":3,"cache_write_tokens":2}
			"""
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = [script.path]
		let input = Pipe()
		process.standardInput = input
		try process.run()
		input.fileHandleForWriting.write(Data(payload.utf8))
		try input.fileHandleForWriting.close()
		process.waitUntilExit()
		XCTAssertEqual(process.terminationStatus, 0)

		let captured = try String(contentsOf: output, encoding: .utf8)
		let lines = captured.split(separator: "\n")
		XCTAssertEqual(lines.count, CursorHookSetup.captureKeepLines)
		XCTAssertLessThan(
			try XCTUnwrap(
				FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber).intValue,
			sizeBefore)
		// Newest record survives, oldest is gone, and every retained line is still a whole record.
		XCTAssertTrue(captured.contains("Zy1uZXc="), "the just-written record must be retained")
		XCTAssertFalse(captured.contains("generation-old-0\""))
		for line in lines {
			XCTAssertNotNil(
				CursorProvider.decode(line: Data(line.utf8)), "a trimmed line must stay a whole record")
		}
	}

	func testRecorderScriptLeavesAnUnderCapFileAlone() throws {
		let root = try tempDirectory("nocap")
		defer { try? FileManager.default.removeItem(at: root) }
		let output = root.appendingPathComponent("cursor-usage.jsonl")
		let script = root.appendingPathComponent("capture.sh")
		try CursorHookSetup.captureScript(outputURL: output)
			.write(to: script, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

		for index in 0..<3 {
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/bin/sh")
			process.arguments = [script.path]
			let input = Pipe()
			process.standardInput = input
			try process.run()
			input.fileHandleForWriting.write(
				Data(
					"""
					{"conversation_id":"c","generation_id":"g\(index)","model":"m","input_tokens":20,"output_tokens":4,"cache_read_tokens":3,"cache_write_tokens":2}
					""".utf8))
			try input.fileHandleForWriting.close()
			process.waitUntilExit()
			XCTAssertEqual(process.terminationStatus, 0)
		}
		let captured = try String(contentsOf: output, encoding: .utf8)
		XCTAssertEqual(captured.split(separator: "\n").count, 3)
	}

	/// A trim shrinks the file, which `FileCursor.classify` reports as `.reset`. Under the default
	/// whole-file replace that would DELETE every Cursor event the warehouse already indexed from the
	/// trimmed-away lines — the opposite of durable retention.
	func testTrimmingTheCaptureFileDoesNotDeleteAlreadyIndexedEvents() throws {
		let root = try tempDirectory("retain")
		defer { try? FileManager.default.removeItem(at: root) }
		let capture = root.appendingPathComponent("cursor-usage.jsonl")
		let lines = (0..<6).map {
			validLine.replacingOccurrences(of: "generation-1", with: "generation-\($0)")
		}
		try (lines.joined(separator: "\n") + "\n").write(to: capture, atomically: true, encoding: .utf8)

		let provider = CursorProvider(root: capture)
		let index = try UsageIndex(path: root.appendingPathComponent("usage.sqlite").path)
		let indexer = UsageIndexer(index: index)
		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .cursor), 6)

		// Simulate the hook's trim: keep only the newest two records.
		try (lines.suffix(2).joined(separator: "\n") + "\n")
			.write(to: capture, atomically: true, encoding: .utf8)
		_ = try indexer.refresh(provider)
		XCTAssertEqual(
			index.eventCount(provider: .cursor), 6,
			"trimmed-away history must survive in the warehouse")
		XCTAssertEqual(CursorProvider(root: capture).resetPolicy, .rereadWholeRetainingIndexedEvents)
	}

	/// `install()` only ever runs on an explicit opt-in, so an existing install would otherwise keep the
	/// recorder revision it was first written with forever — and that population is exactly the one the
	/// capture-file cap has to reach.
	func testStateUpgradesAnActiveInstallRunningAnOlderRecorder() throws {
		let home = try tempDirectory("upgrade")
		defer { try? FileManager.default.removeItem(at: home) }
		let cursorHome = home.appendingPathComponent(".cursor", isDirectory: true)
		let support = home.appendingPathComponent("support", isDirectory: true)
		try FileManager.default.createDirectory(at: cursorHome, withIntermediateDirectories: true)
		try CursorHookSetup.install(cursorHome: cursorHome, appSupport: support, detected: true)

		// Simulate the shipped pre-cap recorder: JP's marker, no revision marker, no trim.
		let script = CursorHookSetup.scriptURL(appSupport: support)
		let legacy = "#!/bin/sh\n\(CursorHookSetup.scriptMarker)\nexit 0\n"
		try legacy.write(to: script, atomically: true, encoding: .utf8)
		let hooksBefore = try Data(contentsOf: CursorHookSetup.hooksURL(cursorHome: cursorHome))

		XCTAssertEqual(
			CursorHookSetup.state(cursorHome: cursorHome, appSupport: support, detected: true), .active,
			"an outdated recorder is still an ACTIVE install — the toggle must not flicker to off")
		let repaired = try String(contentsOf: script, encoding: .utf8)
		XCTAssertTrue(repaired.contains(CursorHookSetup.scriptRevisionMarker))
		XCTAssertTrue(repaired.contains("/usr/bin/tail -n \(CursorHookSetup.captureKeepLines)"))
		XCTAssertEqual(
			try Data(contentsOf: CursorHookSetup.hooksURL(cursorHome: cursorHome)), hooksBefore,
			"[CRITICAL] the self-heal may only touch JP's own script, never the user's Cursor config")

		// Idempotent: a second query rewrites nothing.
		let mtime = try XCTUnwrap(
			FileManager.default.attributesOfItem(atPath: script.path)[.modificationDate] as? Date)
		XCTAssertEqual(
			CursorHookSetup.state(cursorHome: cursorHome, appSupport: support, detected: true), .active)
		XCTAssertEqual(
			try XCTUnwrap(
				FileManager.default.attributesOfItem(atPath: script.path)[.modificationDate] as? Date),
			mtime)
	}

	/// `DashboardViewModel` calls `state()` TWICE on every refresh and `SettingsBackView` calls it on
	/// every appearance, so the steady state — an install already on the current recorder revision —
	/// must be a pure read. A refresh that writes to disk is exactly what the revision self-heal must
	/// not turn `state()` into.
	func testSteadyStateQueryPerformsNoDiskWrite() throws {
		let home = try tempDirectory("steady")
		defer { try? FileManager.default.removeItem(at: home) }
		let cursorHome = home.appendingPathComponent(".cursor", isDirectory: true)
		let support = home.appendingPathComponent("support", isDirectory: true)
		try FileManager.default.createDirectory(at: cursorHome, withIntermediateDirectories: true)
		try CursorHookSetup.install(cursorHome: cursorHome, appSupport: support, detected: true)

		// Backdate everything the setup owns; any write would move one of these forward.
		let script = CursorHookSetup.scriptURL(appSupport: support)
		let hooks = CursorHookSetup.hooksURL(cursorHome: cursorHome)
		let backdated = Date(timeIntervalSince1970: 1_000_000)
		for path in [script.path, hooks.path, support.path] {
			try FileManager.default.setAttributes([.modificationDate: backdated], ofItemAtPath: path)
		}
		let scriptBefore = try Data(contentsOf: script)
		let hooksBefore = try Data(contentsOf: hooks)

		for _ in 0..<5 {
			XCTAssertEqual(
				CursorHookSetup.state(cursorHome: cursorHome, appSupport: support, detected: true), .active)
		}

		for path in [script.path, hooks.path, support.path] {
			XCTAssertEqual(
				try XCTUnwrap(
					FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date),
				backdated,
				"`state()` wrote to \(path) in the steady state — it must be a pure read there")
		}
		XCTAssertEqual(try Data(contentsOf: script), scriptBefore)
		XCTAssertEqual(try Data(contentsOf: hooks), hooksBefore)
	}

	/// The revision repair is a one-time MIGRATION, so it is capped at one attempt per process per
	/// install path. Without the cap a write that cannot land (read-only volume, revoked permission)
	/// would be retried on every single refresh for the life of the process.
	func testRecorderRepairIsBoundedToOneAttemptPerProcess() throws {
		let home = try tempDirectory("bounded")
		defer { try? FileManager.default.removeItem(at: home) }
		let cursorHome = home.appendingPathComponent(".cursor", isDirectory: true)
		let support = home.appendingPathComponent("support", isDirectory: true)
		try FileManager.default.createDirectory(at: cursorHome, withIntermediateDirectories: true)
		try CursorHookSetup.install(cursorHome: cursorHome, appSupport: support, detected: true)

		let script = CursorHookSetup.scriptURL(appSupport: support)
		let legacy = "#!/bin/sh\n\(CursorHookSetup.scriptMarker)\nexit 0\n"
		try legacy.write(to: script, atomically: true, encoding: .utf8)
		XCTAssertEqual(
			CursorHookSetup.state(cursorHome: cursorHome, appSupport: support, detected: true), .active)
		XCTAssertTrue(
			try String(contentsOf: script, encoding: .utf8).contains(
				CursorHookSetup.scriptRevisionMarker),
			"the first query must repair the outdated recorder")

		// Re-introduce the outdated recorder: this process already spent its one attempt on this path.
		try legacy.write(to: script, atomically: true, encoding: .utf8)
		XCTAssertEqual(
			CursorHookSetup.state(cursorHome: cursorHome, appSupport: support, detected: true), .active)
		XCTAssertEqual(
			try String(contentsOf: script, encoding: .utf8), legacy,
			"the repair must not retry per call — it is capped at one attempt per process")
	}

	func testUninstallRemovesJPsOwnCaptureFile() throws {
		let home = try tempDirectory("uninstall")
		defer { try? FileManager.default.removeItem(at: home) }
		let cursorHome = home.appendingPathComponent(".cursor", isDirectory: true)
		let support = home.appendingPathComponent("support", isDirectory: true)
		try FileManager.default.createDirectory(at: cursorHome, withIntermediateDirectories: true)

		try CursorHookSetup.install(cursorHome: cursorHome, appSupport: support, detected: true)
		let capture = CursorHookSetup.captureURL(appSupport: support)
		try (validLine + "\n").write(to: capture, atomically: true, encoding: .utf8)
		XCTAssertTrue(FileManager.default.fileExists(atPath: capture.path))

		try CursorHookSetup.uninstall(cursorHome: cursorHome, appSupport: support)
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: capture.path),
			"nothing else ever deleted the capture file, so uninstall must")
		XCTAssertFalse(
			FileManager.default.fileExists(
				atPath: CursorHookSetup.scriptURL(appSupport: support).path))
		// Idempotent: a second uninstall with nothing left to remove still succeeds.
		XCTAssertNoThrow(try CursorHookSetup.uninstall(cursorHome: cursorHome, appSupport: support))
	}

	func testDetectionReusesSharedExecutablePrimitive() throws {
		let directory = try tempDirectory("bin")
		defer { try? FileManager.default.removeItem(at: directory) }
		XCTAssertFalse(CursorHookSetup.isCursorCLIDetected(searchDirectories: [directory]))
		let binary = directory.appendingPathComponent("cursor-agent")
		FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8))
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
		XCTAssertTrue(CursorHookSetup.isCursorCLIDetected(searchDirectories: [directory]))
	}
}
