import Foundation
import XCTest

@testable import JPtheCatCore

/// Covers Claude's OFFICIAL rate-limit path: decoding the statusline-captured `rate_limits` JSON
/// into a `RateLimitSnapshot`. There is deliberately no plan-tier detection — reading Claude Code's
/// Keychain item to label the gauge made macOS prompt for the login password (see
/// `PlanTierKeychainReadTests`).
final class ClaudeRateLimitTests: XCTestCase {
	// MARK: Captured rate_limits decode

	func testDecodesOfficialWindowsWithResetTimes() {
		let capturedAt = 1_783_000_000.0
		let fiveReset = capturedAt + 4 * 3600
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":8,"resets_at":\(fiveReset)},
			 "seven_day":{"used_percentage":41,"resets_at":\(capturedAt + 86_400)}}
			""".data(using: .utf8)!
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertEqual(snap?.primary?.usedPercent ?? -1, 8, accuracy: 0.001)
		XCTAssertEqual(snap?.primary?.windowMinutes, 300)
		XCTAssertEqual(snap?.primary?.resetsAt?.timeIntervalSince1970 ?? 0, fiveReset, accuracy: 0.001)
		XCTAssertEqual(snap?.secondary?.usedPercent ?? -1, 41, accuracy: 0.001)
		XCTAssertEqual(snap?.secondary?.windowMinutes, 10080)
	}

	// MARK: Per-model weekly windows (Claude's "Fable" / "Sonnet" bars)

	/// Today's REAL statusline payload carries exactly `five_hour` + `seven_day` (verified against a
	/// live capture on Claude Code 2.1.228). No per-model window is reported, so JP must surface none —
	/// an absent window means "not reported", never a synthesized 0% or a token-derived estimate.
	func testTodaysRealPayloadReportsNoPerModelWindow() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":47,"resets_at":\(capturedAt + 4 * 3600)},
			 "seven_day":{"used_percentage":88,"resets_at":\(capturedAt + 86_400)}}
			""".data(using: .utf8)!
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertEqual(snap?.secondary?.usedPercent ?? -1, 88, accuracy: 0.001)
		XCTAssertEqual(snap?.modelWindows.count, 0)
	}

	/// Forward compatibility: if Claude Code starts putting its per-model weekly windows in the
	/// statusline feed, the already-installed capture block forwards them and this decoder must turn
	/// them into REAL official gauges with no further code change.
	func testDecodesPerModelWeeklyWindowsWhenTheFeedCarriesThem() {
		let capturedAt = 1_783_000_000.0
		let weekReset = capturedAt + 86_400
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":42,"resets_at":\(capturedAt + 4 * 3600)},
			 "seven_day":{"used_percentage":87,"resets_at":\(weekReset)},
			 "seven_day_opus":{"used_percentage":100,"resets_at":\(weekReset - 60)},
			 "seven_day_sonnet":{"used_percentage":12,"resets_at":\(weekReset)}}
			""".data(using: .utf8)!
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertEqual(snap?.modelWindows.map(\.key), ["seven_day_opus", "seven_day_sonnet"])
		XCTAssertEqual(snap?.modelWindows.map(\.label), ["Fable", "Sonnet"])
		XCTAssertEqual(snap?.modelWindows.first?.window.usedPercent ?? -1, 100, accuracy: 0.001)
		XCTAssertEqual(snap?.modelWindows.first?.window.windowMinutes, 10080)
		XCTAssertEqual(
			snap?.modelWindows.first?.window.resetsAt?.timeIntervalSince1970 ?? 0, weekReset - 60,
			accuracy: 0.001)
		// The plan-wide weekly window stays exactly what it was — a per-model bar never replaces it.
		XCTAssertEqual(snap?.secondary?.usedPercent ?? -1, 87, accuracy: 0.001)
	}

	/// An unrecognized future family must still render honestly from its own key rather than vanishing
	/// or borrowing another model's name.
	func testUnknownPerModelKeyHumanizesItsOwnSuffix() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":5,"resets_at":\(capturedAt + 4 * 3600)},
			 "seven_day_new_thing":{"used_percentage":9,"resets_at":\(capturedAt + 86_400)}}
			""".data(using: .utf8)!
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertEqual(snap?.modelWindows.map(\.label), ["New Thing"])
	}

	/// A per-model window past its reset is dropped like any other expired official window — never
	/// rolled forward, never shown stale.
	func testExpiredPerModelWindowIsDropped() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":5,"resets_at":\(capturedAt + 4 * 3600)},
			 "seven_day_opus":{"used_percentage":100,"resets_at":\(capturedAt + 30)}}
			""".data(using: .utf8)!
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertNotNil(snap?.primary)
		XCTAssertEqual(snap?.modelWindows.count, 0)
	}

	/// A model-scoped window is not a plan-wide usage signal: with every plan window expired the
	/// snapshot must still go nil rather than leaving one orphan per-model bar on screen.
	func testPerModelWindowAloneDoesNotKeepAnExpiredSnapshotAlive() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":5,"resets_at":\(capturedAt + 30)},
			 "seven_day_opus":{"used_percentage":100,"resets_at":\(capturedAt + 86_400)}}
			""".data(using: .utf8)!
		XCTAssertNil(ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60)))
	}

	/// The capture carries no tier, and Claude emits these windows for Pro as well as Max, so a
	/// decoded snapshot must not claim one. A hardcoded `"max"` here labelled every Pro subscriber
	/// "max" in `LocalAutomationSnapshot.plan_type` and the CLI's `plan_type` output.
	func testDecodedSnapshotClaimsNoPlanTier() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":8,"resets_at":\(capturedAt + 4 * 3600)}}
			""".data(using: .utf8)!
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertNotNil(snap)
		XCTAssertNil(snap?.planType)
	}

	/// [DURABLE] A stale CAPTURE must not hide a still-current window. This replaces
	/// `testStaleCaptureIsIgnored`, which encoded a 12h capture-age cutoff — the exact bug v1.113
	/// shipped for Codex (the row collapsed to an activity sparkline while its weekly boundary was
	/// still ahead) and v1.114 reverted. The Claude path still carried it, so an idle night hid a
	/// valid 100% weekly bar behind a sparkline. A window is dropped ONLY by its own `resets_at`.
	func testStaleCaptureStillYieldsACurrentWindow() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),
			 "five_hour":{"used_percentage":8,"resets_at":\(capturedAt + 3_600)},
			 "seven_day":{"used_percentage":100,"resets_at":\(capturedAt + 4 * 86_400)}}
			""".data(using: .utf8)!

		// Two days later: the 5h window has long expired, the weekly one is still current.
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 48 * 3600))
		XCTAssertNil(snap?.primary, "an expired 5h window is still dropped by its own resets_at")
		XCTAssertEqual(snap?.secondary?.usedPercent ?? -1, 100, accuracy: 0.001)
		XCTAssertNotNil(snap?.secondary?.resetsAt)
		XCTAssertEqual(snap?.capturedAt?.timeIntervalSince1970 ?? -1, capturedAt, accuracy: 0.5)
	}

	/// The Settings "live limits are flowing" indicator is the ONE place capture age still matters —
	/// a stopped statusline must not read as active forever.
	func testIsActiveRequiresAFreshCapture() throws {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-claude-limits-age-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: url) }
		let now = Date()

		func payload(capturedAt: TimeInterval) -> Data {
			"""
			{"capturedAt":\(capturedAt),
			 "seven_day":{"used_percentage":100,"resets_at":\(capturedAt + 4 * 86_400)}}
			""".data(using: .utf8)!
		}

		try payload(capturedAt: now.timeIntervalSince1970).write(to: url)
		XCTAssertTrue(ClaudeRateLimitStore.isActive(now: now, url: url))

		// 17h old, weekly window still current → NOT "flowing", but the window still decodes.
		try payload(capturedAt: now.timeIntervalSince1970 - 17 * 3600).write(to: url)
		XCTAssertFalse(ClaudeRateLimitStore.isActive(now: now, url: url))
		XCTAssertNotNil(
			ClaudeRateLimitStore.load(now: now, url: url),
			"a stale capture must still surface its still-current window")
	}

	func testExpiredCapturedWindowIsIgnoredEvenWhenCaptureIsFresh() throws {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),
			 "five_hour":{"used_percentage":91,"resets_at":\(capturedAt - 1)},
			 "seven_day":{"used_percentage":41,"resets_at":\(capturedAt + 86_400)}}
			""".data(using: .utf8)!

		let snap = try XCTUnwrap(ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt)))

		XCTAssertNil(snap.primary)
		XCTAssertEqual(snap.secondary?.usedPercent ?? -1, 41, accuracy: 0.001)
	}

	func testAllExpiredCapturedWindowsYieldNil() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),
			 "five_hour":{"used_percentage":91,"resets_at":\(capturedAt)},
			 "seven_day":{"used_percentage":41,"resets_at":\(capturedAt - 1)}}
			""".data(using: .utf8)!

		XCTAssertNil(ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt)))
	}

	func testEmptyOrMissingWindowsYieldNil() {
		XCTAssertNil(ClaudeRateLimitStore.decode(#"{"capturedAt":1783000000}"#.data(using: .utf8)!,
			now: Date(timeIntervalSince1970: 1_783_000_001)))
		XCTAssertNil(ClaudeRateLimitStore.decode(Data("not json".utf8)))
	}

	// MARK: likelyAtLimit — the "hit my limit but the reading is frozen" signal

	func testDecodeCarriesCaptureTimestamp() {
		let capturedAt = 1_783_000_000.0
		let json = """
			{"capturedAt":\(capturedAt),"five_hour":{"used_percentage":88,"resets_at":\(capturedAt + 3600)}}
			""".data(using: .utf8)!
		let snap = ClaudeRateLimitStore.decode(json, now: Date(timeIntervalSince1970: capturedAt + 60))
		XCTAssertEqual(snap?.capturedAt, Date(timeIntervalSince1970: capturedAt))
	}

	func testLikelyAtLimitOnlyWhenHighAndCaptureWentQuiet() {
		let captured = Date(timeIntervalSince1970: 1_783_000_000)
		let win = RateLimitWindow(usedPercent: 92, windowMinutes: 300, resetsAt: captured.addingTimeInterval(3600))
		let snap = RateLimitSnapshot(primary: win, secondary: nil, planType: "max", capturedAt: captured)
		// Fresh (1 min old) → trust the reading, no warning even at 92%.
		XCTAssertFalse(snap.likelyAtLimit(now: captured.addingTimeInterval(60)))
		// Quiet for 20 min at 92% → Claude is almost certainly refusing you; flag it.
		XCTAssertTrue(snap.likelyAtLimit(now: captured.addingTimeInterval(20 * 60)))
		// Quiet but LOW usage → not a limit, just idle. No warning.
		let low = RateLimitSnapshot(
			primary: RateLimitWindow(usedPercent: 30, windowMinutes: 300, resetsAt: captured.addingTimeInterval(3600)),
			secondary: nil, planType: "max", capturedAt: captured)
		XCTAssertFalse(low.likelyAtLimit(now: captured.addingTimeInterval(60 * 60)))
		// No capture timestamp (Codex-style always-current feed) → never a stale-limit warning.
		let codexLike = RateLimitSnapshot(primary: win, secondary: nil, planType: "pro", capturedAt: nil)
		XCTAssertFalse(codexLike.likelyAtLimit(now: captured.addingTimeInterval(60 * 60)))
	}

	// MARK: clear() — the "Settings toggle sprang back on after turning it off" regression

	/// `clear()` must delete the captured file so `isActive()` flips to false immediately. Before this
	/// fix, the Claude live-limits row's uninstall confirmation only removed the shell rc block
	/// (`state`) and left this file (`active`) fresh for up to 12h, so the toggle's
	/// `isInstalled = active || state == .active` stayed true and the switch visually reverted to "on"
	/// right after the user turned it off. That row is now one of the four `ProviderOptInDescriptor`s
	/// driving `ProviderOptInRow`, whose `isInstalled` reads the install marker ALONE and whose
	/// `reconcileStaleCapture` calls this method.
	func testClearDeletesTheCapturedFileSoIsActiveFlipsToFalse() throws {
		// A dedicated temp file — NEVER the real defaultURL() production path. An earlier version of
		// this test used the real path with no override and silently deleted a real developer machine's
		// genuine leftover capture file when the suite ran; always pass an explicit url: in tests.
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-claude-limits-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: url) }

		let fresh = """
			{"capturedAt":\(Date().timeIntervalSince1970),"five_hour":{"used_percentage":8,"resets_at":\(Date().timeIntervalSince1970 + 3600)}}
			""".data(using: .utf8)!
		try fresh.write(to: url)
		XCTAssertTrue(ClaudeRateLimitStore.isActive(url: url))

		XCTAssertTrue(ClaudeRateLimitStore.clear(url: url))

		XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
		XCTAssertFalse(ClaudeRateLimitStore.isActive(url: url))
	}

	func testClearOnAMissingFileIsHarmless() {
		// Best-effort: calling clear() when there's nothing to delete must not throw or crash. A
		// dedicated temp path that was never created — never the real defaultURL() production path.
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-claude-limits-missing-\(UUID().uuidString).json")
		XCTAssertFalse(ClaudeRateLimitStore.clear(url: url))
	}
}
