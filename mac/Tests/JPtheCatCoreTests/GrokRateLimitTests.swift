import Foundation
import XCTest

@testable import JPtheCatCore

/// Covers Grok's OFFICIAL SuperGrok weekly capture path: log-line parse → capture file →
/// `RateLimitSnapshot`, plus opt-in install/uninstall of the Grok hook.
final class GrokRateLimitTests: XCTestCase {

	// MARK: - Log line parse

	func testParseBillingLogLineExtractsWeeklyPercentAndReset() throws {
		let line = """
			{"ts":"2026-07-13T21:09:29.960Z","src":"shell","pid":1,"lvl":"info","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":23.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-13T06:22:57.070170+00:00","end":"2026-07-20T06:22:57.070170+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0},"isUnifiedBillingUser":true},"onDemandEnabled":null,"subscriptionTier":"X Premium+"}}
			"""
		let payload = try XCTUnwrap(GrokRateLimitCapture.parseBillingLogLine(line))
		XCTAssertEqual((payload["plan_type"] as? String), "X Premium+")
		XCTAssertEqual(payload["source"] as? String, "unified.jsonl")
		let weekly = try XCTUnwrap(payload["weekly"] as? [String: Any])
		XCTAssertEqual((weekly["used_percentage"] as? NSNumber)?.doubleValue ?? -1, 23, accuracy: 0.001)
		XCTAssertNotNil(weekly["resets_at"] as? NSNumber)
		XCTAssertEqual(payload["period_type"] as? String, "USAGE_PERIOD_TYPE_WEEKLY")
	}

	func testParseBillingLogLineIgnoresMissingPercent() {
		// Early Grok log lines sometimes omit creditUsagePercent — never invent 0.
		let line = """
			{"ts":"2026-07-13T20:23:38.913Z","msg":"billing: fetched credits config","ctx":{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-20T06:22:57.070170+00:00"}},"subscriptionTier":"X Premium+"}}
			"""
		XCTAssertNil(GrokRateLimitCapture.parseBillingLogLine(line))
	}

	func testParseBillingLogLineIgnoresUnrelatedLines() {
		XCTAssertNil(GrokRateLimitCapture.parseBillingLogLine(#"{"msg":"shell.tool.exec_done"}"#))
		XCTAssertNil(GrokRateLimitCapture.parseBillingLogLine("not json"))
	}

	func testScrapeLatestBillingPrefersNewestLine() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-grok-scrape-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let log = dir.appendingPathComponent("unified.jsonl")
		let older = """
			{"ts":"2026-07-13T20:00:00.000Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":5.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-20T06:22:57.070170+00:00"}},"subscriptionTier":"X Premium+"}}
			"""
		let newer = """
			{"ts":"2026-07-13T21:00:00.000Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":23.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-20T06:22:57.070170+00:00"}},"subscriptionTier":"X Premium+"}}
			"""
		try "\(older)\n\(newer)\n".write(to: log, atomically: true, encoding: .utf8)

		let payload = try XCTUnwrap(GrokRateLimitCapture.scrapeLatestBilling(fromLog: log))
		let weekly = try XCTUnwrap(payload["weekly"] as? [String: Any])
		XCTAssertEqual((weekly["used_percentage"] as? NSNumber)?.doubleValue ?? -1, 23, accuracy: 0.001)
	}

	// MARK: - Store decode

	func testDecodesWeeklyWindowWithReset() {
		let capturedAt = 1_783_000_000.0
		let reset = capturedAt + 7 * 86_400
		let json = """
			{"capturedAt":\(capturedAt),"weekly":{"used_percentage":23,"resets_at":\(reset)},"plan_type":"X Premium+"}
			""".data(using: .utf8)!
		let snap = GrokRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertNil(snap?.primary)
		XCTAssertEqual(snap?.secondary?.usedPercent ?? -1, 23, accuracy: 0.001)
		XCTAssertEqual(snap?.secondary?.windowMinutes, 10_080)
		XCTAssertEqual(snap?.secondary?.resetsAt?.timeIntervalSince1970 ?? 0, reset, accuracy: 0.001)
		XCTAssertEqual(snap?.planType, "X Premium+")
		XCTAssertEqual(snap?.capturedAt, Date(timeIntervalSince1970: capturedAt))
	}

	func testStaleCaptureIsIgnored() {
		let capturedAt = 1_783_000_000.0
		let json = #"{"capturedAt":\#(capturedAt),"weekly":{"used_percentage":23,"resets_at":\#(capturedAt + 86_400)}}"#
			.data(using: .utf8)!
		XCTAssertNil(
			GrokRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 13 * 3600)))
	}

	func testExpiredWeeklyWindowYieldsNil() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"weekly":{"used_percentage":23,"resets_at":\(capturedAt - 1)}}
			""".data(using: .utf8)!
		XCTAssertNil(GrokRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt)))
	}

	/// The refactor guard: a fresh capture whose weekly window JUST rolled past reset must still strip the
	/// stale % from `decode` (no fabricated number) while `decodeRaw` keeps the expired window so the
	/// "awaiting fresh data after reset" hint can fire. This is the "bars reset randomly" case for Grok.
	func testJustRolledOverWeeklyStripsPercentButFlagsAwaitingHint() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"weekly":{"used_percentage":23,"resets_at":\(capturedAt + 60)}}
			""".data(using: .utf8)!
		let justAfterReset = Date(timeIntervalSince1970: capturedAt + 120)
		XCTAssertNil(
			GrokRateLimitStore.decode(json, now: justAfterReset),
			"decode must drop the expired window — never a stale/fabricated %")
		XCTAssertTrue(
			GrokRateLimitStore.decodeRaw(json, now: justAfterReset)?
				.awaitingFreshDataAfterReset(at: justAfterReset) ?? false,
			"decodeRaw must keep the just-rolled-over window so the awaiting-reset hint can fire")
	}

	func testEmptyOrMissingWindowsYieldNil() {
		XCTAssertNil(
			GrokRateLimitStore.decode(
				#"{"capturedAt":1783000000}"#.data(using: .utf8)!,
				now: Date(timeIntervalSince1970: 1_783_000_001)))
		XCTAssertNil(GrokRateLimitStore.decode(Data("not json".utf8)))
	}

	func testClearDeletesTheCapturedFileSoIsActiveFlipsToFalse() throws {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-grok-clear-\(UUID().uuidString).json")
		let capturedAt = Date().timeIntervalSince1970
		let json = """
			{"capturedAt":\(capturedAt),"weekly":{"used_percentage":10,"resets_at":\(capturedAt + 86_400)}}
			"""
		try json.write(to: url, atomically: true, encoding: .utf8)
		XCTAssertTrue(GrokRateLimitStore.isActive(url: url))
		XCTAssertTrue(GrokRateLimitStore.clear(url: url))
		XCTAssertFalse(GrokRateLimitStore.isActive(url: url))
		XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
	}

	// MARK: - Capture install payloads

	func testCaptureScriptContainsMarkersAndNoAuthOrNetwork() {
		let script = GrokRateLimitCapture.captureScript()
		XCTAssertTrue(script.contains(GrokRateLimitCapture.beginMarker))
		XCTAssertTrue(script.contains(GrokRateLimitCapture.endMarker))
		XCTAssertTrue(script.contains("unified.jsonl"))
		XCTAssertTrue(script.contains("grok-rate-limits.json"))
		// Privacy contract: capture never touches auth or hits the network.
		// (Comment text may mention auth.json as a negative — assert the runnable body does not.)
		let body = script
			.split(separator: "\n")
			.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
			.joined(separator: "\n")
			.lowercased()
		XCTAssertFalse(body.contains("auth.json"))
		XCTAssertFalse(body.contains("curl "))
		XCTAssertFalse(body.contains("cli-chat-proxy"))
		XCTAssertFalse(body.contains("https://"))
	}

	func testHookJSONPointsAtCaptureScript() {
		let json = GrokRateLimitCapture.hookJSON(scriptPath: "/tmp/jpc-capture.sh")
		XCTAssertTrue(json.contains("SessionStart"))
		XCTAssertTrue(json.contains("UserPromptSubmit"))
		XCTAssertTrue(json.contains("Stop"))
		XCTAssertTrue(json.contains("/tmp/jpc-capture.sh"))
		// Valid enough JSON for Grok's hooks loader.
		let data = Data(json.utf8)
		XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
	}

	func testIsInstalledInScriptRequiresBeginMarker() {
		XCTAssertFalse(GrokRateLimitCapture.isInstalled(inScript: "echo hi"))
		XCTAssertTrue(
			GrokRateLimitCapture.isInstalled(
				inScript: "\(GrokRateLimitCapture.beginMarker)\necho hi\n\(GrokRateLimitCapture.endMarker)"))
	}

	func testToggleDerivesFromInstallMarkerNotLeftoverCaptureFile() {
		// The "fixed twice" regression: the switch must key ONLY on the install marker (state == .active),
		// never on a leftover fresh capture file. `.installable` = detected but hook gone (an orphaned
		// grok-rate-limits.json can put us here) → OFF. `.unavailable` = not detected → OFF.
		XCTAssertTrue(GrokRateLimitCapture.toggleIsOn(state: .active))
		XCTAssertFalse(GrokRateLimitCapture.toggleIsOn(state: .installable))
		XCTAssertFalse(GrokRateLimitCapture.toggleIsOn(state: .unavailable))
	}

	func testStateUnavailableWhenGrokNotDetected() {
		// Explicit empty fixture home → not detected → unavailable (never installs against the
		// real machine from tests).
		let empty = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-grok-empty-\(UUID().uuidString)", isDirectory: true)
		try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: empty) }
		XCTAssertEqual(
			GrokRateLimitCapture.state(grokHome: empty, detected: false),
			.unavailable)
	}

	func testRefreshFromLogsWritesCaptureFile() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-grok-refresh-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let log = dir.appendingPathComponent("unified.jsonl")
		let out = dir.appendingPathComponent("grok-rate-limits.json")
		// Derive `ts` (capture instant) and the weekly `end` from the current clock so the fixture never
		// rots: `capturedAt` prefers the log's `ts`, and `GrokRateLimitStore.load` drops any reading older
		// than its 12h staleness window — a hardcoded past timestamp made this test fail 12h after it was
		// written. A recent `ts` + a future `end` keep both the freshness and current-window checks true.
		let iso = ISO8601DateFormatter()
		iso.formatOptions = [.withInternetDateTime]
		let ts = iso.string(from: Date())
		let end = iso.string(from: Date().addingTimeInterval(7 * 24 * 3600))
		let line = """
			{"ts":"\(ts)","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":23.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"\(end)"}},"subscriptionTier":"X Premium+"}}
			"""
		try line.write(to: log, atomically: true, encoding: .utf8)

		XCTAssertTrue(GrokRateLimitCapture.refreshFromLogs(logURL: log, outputURL: out))
		let snap = try XCTUnwrap(GrokRateLimitStore.load(url: out))
		XCTAssertEqual(snap.secondary?.usedPercent ?? -1, 23, accuracy: 0.001)
		XCTAssertEqual(snap.planType, "X Premium+")
	}

	func testStringTypedCreditPercentIsAcceptedMatchingPython() throws {
		// A string-typed percentage ("23") must parse identically to a numeric one — the hook python
		// does `float(used)`, so the Swift path must accept it too or the two scrapers disagree.
		let line = """
			{"ts":"2026-07-13T21:09:29.960Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":"23","currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-20T06:22:57.070170+00:00"}},"subscriptionTier":"X Premium+"}}
			"""
		let payload = try XCTUnwrap(GrokRateLimitCapture.parseBillingLogLine(line))
		let weekly = try XCTUnwrap(payload["weekly"] as? [String: Any])
		XCTAssertEqual((weekly["used_percentage"] as? NSNumber)?.doubleValue ?? -1, 23, accuracy: 0.001)
	}

	// MARK: - Swift ↔ embedded-python scrape parity

	func testEmbeddedPythonScrapeMatchesSwiftParser() throws {
		// The PRODUCTION capture path is the embedded python (run by the Grok hook); the Swift
		// `parseBillingLogLine` is a second in-process scraper of the same log, documented "keep in
		// sync." Run the REAL python on a fixture and assert it agrees with the Swift path on every
		// field both write, so a future edit to one that diverges from the other fails here.
		guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
			throw XCTSkip("python3 unavailable in this environment")
		}
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-grok-parity-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }

		let line = """
			{"ts":"2026-07-13T21:09:29.960Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":23.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-20T06:22:57.070170+00:00"}},"subscriptionTier":"X Premium+"}}
			"""
		let log = dir.appendingPathComponent("unified.jsonl")
		try "some unrelated line\n\(line)\n".write(to: log, atomically: true, encoding: .utf8)

		// Pull the embedded python out of the capture script and run it directly with OUR own out path
		// (never the real Application Support store).
		let script = GrokRateLimitCapture.captureScript()
		let py = try XCTUnwrap(Self.pythonBody(from: script), "could not extract embedded python body")
		let pyFile = dir.appendingPathComponent("scrape.py")
		try py.write(to: pyFile, atomically: true, encoding: .utf8)
		let pyOut = dir.appendingPathComponent("py-out.json")

		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
		proc.arguments = [pyFile.path, log.path, pyOut.path]
		try proc.run()
		proc.waitUntilExit()
		XCTAssertEqual(proc.terminationStatus, 0, "embedded python exited non-zero")

		let pyJSON = try XCTUnwrap(
			try JSONSerialization.jsonObject(with: Data(contentsOf: pyOut)) as? [String: Any])
		let swift = try XCTUnwrap(GrokRateLimitCapture.parseBillingLogLine(line))

		XCTAssertEqual(pyJSON["plan_type"] as? String, swift["plan_type"] as? String)
		XCTAssertEqual(pyJSON["period_type"] as? String, swift["period_type"] as? String)
		XCTAssertEqual(
			(pyJSON["capturedAt"] as? NSNumber)?.doubleValue ?? -1,
			(swift["capturedAt"] as? NSNumber)?.doubleValue ?? -2, accuracy: 0.001)
		let pyWeekly = try XCTUnwrap(pyJSON["weekly"] as? [String: Any])
		let swWeekly = try XCTUnwrap(swift["weekly"] as? [String: Any])
		XCTAssertEqual(
			(pyWeekly["used_percentage"] as? NSNumber)?.doubleValue ?? -1,
			(swWeekly["used_percentage"] as? NSNumber)?.doubleValue ?? -2, accuracy: 0.001)
		XCTAssertEqual(
			(pyWeekly["resets_at"] as? NSNumber)?.doubleValue ?? -1,
			(swWeekly["resets_at"] as? NSNumber)?.doubleValue ?? -2, accuracy: 0.001)
	}

	/// Extract the python heredoc body (`<<'PY' … PY`) from the capture shell script.
	private static func pythonBody(from script: String) -> String? {
		guard let start = script.range(of: "<<'PY'\n") else { return nil }
		let afterStart = script[start.upperBound...]
		guard let end = afterStart.range(of: "\nPY") else { return nil }
		return String(afterStart[..<end.lowerBound])
	}

	// MARK: - Provider entry point (GrokProvider.latestRateLimits)

	func testLatestRateLimitsNilWithoutCapture() {
		// No installed hook + a nonexistent store → no gauge (never a fabricated %). Scoped to a fixture
		// home + injected store so it can never read or write the real Application Support state.
		let home = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-grok-nolimit-\(UUID().uuidString)", isDirectory: true)
		let store = home.appendingPathComponent("absent-grok-rate-limits.json")
		XCTAssertNil(
			GrokProvider(root: home).latestRateLimits(now: Date(), storeURL: store, logURL: nil))
	}

	func testLatestRateLimitsReturnsWeeklyFromInjectedStore() throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-grok-limit-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let store = dir.appendingPathComponent("grok-rate-limits.json")
		let capturedAt = Date().timeIntervalSince1970
		let json = """
			{"capturedAt":\(capturedAt),"weekly":{"used_percentage":42,"resets_at":\(capturedAt + 86_400)},"plan_type":"SuperGrok"}
			"""
		try json.write(to: store, atomically: true, encoding: .utf8)
		// Fixture home has no installed hook → no scrape/write; just decodes the injected store.
		let snap = try XCTUnwrap(
			GrokProvider(root: dir).latestRateLimits(
				now: Date(timeIntervalSince1970: capturedAt + 60), storeURL: store, logURL: nil))
		XCTAssertNil(snap.primary)
		XCTAssertEqual(snap.secondary?.usedPercent ?? -1, 42, accuracy: 0.001)
		XCTAssertEqual(snap.secondary?.windowMinutes, 10_080)
		XCTAssertEqual(snap.planType, "SuperGrok")
	}
}
