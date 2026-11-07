import Foundation
import XCTest

@testable import JPtheCatCore

final class CodexProviderTests: XCTestCase {
	private let basicUUID = "feedface-0000-0000-0000-000000000001"
	private let compactUUID = "feedface-0000-0000-0000-000000000002"

	/// Stages a fixture inside a `~/.codex/sessions`-shaped temp dir under a real `rollout-…-<uuid>`
	/// filename, so we exercise the full public path (allowlist -> stream -> reset-aware diff).
	private func stage(_ fixtures: [(name: String, uuid: String)]) throws -> URL {
		let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-codex-\(UUID().uuidString)", isDirectory: true)
		let day = tmp.appendingPathComponent("2026/07/01", isDirectory: true)
		try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
		for fixture in fixtures {
			let src = try XCTUnwrap(
				Bundle.module.url(forResource: fixture.name, withExtension: "jsonl"),
				"fixture \(fixture.name) missing")
			try FileManager.default.copyItem(
				at: src, to: day.appendingPathComponent("rollout-2026-07-01T00-00-00-\(fixture.uuid).jsonl"))
		}
		return tmp
	}

	// MARK: - Costing correctness

	func testTelescopingDiffSumsToCumulativeAndDedupes() throws {
		let root = try stage([("codex-basic", basicUUID)])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = CodexProvider(root: root).loadEvents()

		// 4 token_count lines: one is a byte-for-byte duplicate (zero delta -> skipped), plus one
		// agent_message noise line -> 3 usage events.
		XCTAssertEqual(events.count, 3)
		XCTAssertTrue(events.allSatisfy { $0.provider == .codex })
		// Model comes from turn_context because session_meta.model is null.
		XCTAssertTrue(events.allSatisfy { $0.model == "gpt-5-codex" })
		XCTAssertTrue(events.allSatisfy { $0.project == "proj" })

		// The reconstructed per-turn deltas telescope to the FINAL cumulative total_token_usage:
		// uncached input 1000, cache-read 4000, output 400 (final total was input 5000, cached 4000).
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.input }, 1000)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.cacheRead }, 4000)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.output }, 400)
		// input + cacheRead == final total.input (5000), proving no double-count of the re-sent
		// context. (Naively summing last_token_usage.input would give 7000 here.)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.input + $1.usage.cacheRead }, 5000)
	}

	func testSyntheticIdsAreStableUniqueAndFileScoped() throws {
		let root = try stage([("codex-basic", basicUUID)])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = CodexProvider(root: root).loadEvents()
		// Codex has no message/request ids: identity is <fileUUID>#<turnOrdinal> mapped onto the
		// event's (messageId, requestId). Keyed on the FILENAME uuid, not session_meta.session_id.
		XCTAssertEqual(events.map(\.id), ["\(basicUUID):0", "\(basicUUID):1", "\(basicUUID):2"])
		XCTAssertEqual(Set(events.map(\.id)).count, events.count)
	}

	func testCompactionResetNeverProducesNegativeUsage() throws {
		let root = try stage([("codex-compaction", compactUUID)])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = CodexProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 3)
		XCTAssertTrue(events.allSatisfy { $0.model == "gpt-5.5" })
		// A cumulative DROP (10000 -> 4000) is treated as a fresh segment, not negative usage.
		XCTAssertTrue(
			events.allSatisfy { $0.usage.input >= 0 && $0.usage.cacheRead >= 0 && $0.usage.output >= 0 })
		XCTAssertEqual(events[1].usage.input, 500)  // 4000 - 3500 uncached, recounted fresh
		XCTAssertEqual(events[1].usage.cacheRead, 3500)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.output }, 800)  // 500 + 200 + 100
	}

	func testSmallCumulativeWobbleReconcilesWithoutDoubleCount() throws {
		// A tiny output decrease (250 -> 245) is a counter wobble, NOT a session reset: it must
		// reconcile against the cumulative, not start a fresh segment (which would ~2x double-count
		// input+cache). Guards the large-drop reset threshold.
		let root = try stage([("codex-wobble", "feedface-0000-0000-0000-000000000003")])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = CodexProvider(root: root).loadEvents()
		// Reconstructed totals equal the FINAL cumulative (input 5000, cached 4000, output 400):
		// uncached 1000, cache_read 4000, output 400. A double-count would inflate input/cache ~2x.
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.input }, 1000)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.cacheRead }, 4000)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.output }, 400)
		XCTAssertTrue(events.allSatisfy { $0.usage.input >= 0 && $0.usage.output >= 0 })
	}

	func testSmallSingleComponentWobbleDoesNotResetWholeCumulative() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		try write(
			"""
			{"type":"turn_context","timestamp":"2026-07-01T00:00:00.000Z","payload":{"model":"gpt-5.5","cwd":"/Users/x/proj"}}
			{"type":"event_msg","timestamp":"2026-07-01T00:00:01.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":100}}}}
			{"type":"event_msg","timestamp":"2026-07-01T00:00:02.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1100,"cached_input_tokens":850,"output_tokens":99}}}}
			""",
			to: root, filename: "rollout-2026-07-01T00-00-00-\(basicUUID).jsonl")

		let events = CodexProvider(root: root).loadEvents()

		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.input }, 250)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.cacheRead }, 850)
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.output }, 99)
	}

	// MARK: - Rate-limit usage (the honest subscription headline)

	func testLatestRateLimitsTakesTheFreshestPopulatedEvent() throws {
		let root = try stage([("codex-basic", basicUUID)])
		defer { try? FileManager.default.removeItem(at: root) }

		let snapshot = try XCTUnwrap(
			CodexProvider(root: root).latestRateLimits(
				now: Date(timeIntervalSince1970: 1_782_000_000 - 60)))
		XCTAssertEqual(snapshot.planType, "pro")
		// The last token_count (30% / 12%) wins, not an earlier one.
		XCTAssertEqual(snapshot.primary?.usedPercent, 30.0)
		XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 12.0)
		XCTAssertEqual(snapshot.secondary?.windowMinutes, 10080)
		XCTAssertEqual(snapshot.primary?.resetsAt, Date(timeIntervalSince1970: 1_782_000_000))
	}

	func testLatestRateLimitsUsesNewestTokenCountTimestampAcrossFiles() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let staleFile = "rollout-2026-07-01T09-00-00-feedface-1111-1111-1111-111111111111.jsonl"
		let freshFile = "rollout-2026-07-01T10-00-00-feedface-2222-2222-2222-222222222222.jsonl"
		try writeRateLimit(
			timestamp: "2026-07-01T09:01:00.000Z", primary: 10, secondary: 20, to: root,
			filename: staleFile)
		try writeRateLimit(
			timestamp: "2026-07-01T10:01:00.000Z", primary: 90, secondary: 80, to: root,
			filename: freshFile)
		let day = root.appendingPathComponent("2026/07/01", isDirectory: true)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
			ofItemAtPath: day.appendingPathComponent(staleFile).path)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
			ofItemAtPath: day.appendingPathComponent(freshFile).path)

		let snapshot = CodexProvider(root: root).latestRateLimits(
			now: Date(timeIntervalSince1970: 1_782_928_214 - 60))
		XCTAssertEqual(snapshot?.primary?.usedPercent, 90.0)
		XCTAssertEqual(snapshot?.secondary?.usedPercent, 80.0)
	}

	func testLatestRateLimitsDoesNotMixOlderFiveHourIntoNewerWeeklyOnlySnapshot() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let oldFile = "rollout-2026-07-01T09-00-00-feedface-6111-1111-1111-111111111111.jsonl"
		let newFile = "rollout-2026-07-01T10-00-00-feedface-6222-2222-2222-222222222222.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try writeRateLimit(
			timestamp: "2026-07-01T09:01:00.000Z", primary: 17, secondary: 2, to: root,
			filename: oldFile,
			primaryReset: now.addingTimeInterval(300).timeIntervalSince1970,
			secondaryReset: now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":3,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: newFile)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertNil(snapshot.primary)
		XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 3)
	}

	func testLatestRateLimitsRejectsRollingZeroPlaceholderAndKeepsFixedBoundaryWindow() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let realFile = "rollout-2026-07-01T09-00-00-feedface-8111-1111-1111-111111111111.jsonl"
		let placeholderFile = "rollout-2026-07-01T10-00-00-feedface-8222-2222-2222-222222222222.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		let fixedReset = now.addingTimeInterval(5 * 86_400).timeIntervalSince1970
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":54,"window_minutes":10080,"resets_at":\(fixedReset)},"secondary":null}}}
			""",
			to: root, filename: realFile)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":0,"window_minutes":10080,"resets_at":\(Date(timeIntervalSince1970: 1_783_000_000).addingTimeInterval(7 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			{"type":"event_msg","timestamp":"2026-07-01T10:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":20}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":0,"window_minutes":10080,"resets_at":\(Date(timeIntervalSince1970: 1_783_000_060).addingTimeInterval(7 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: placeholderFile)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertEqual(snapshot.secondary?.usedPercent, 54)
		XCTAssertEqual(snapshot.secondary?.resetsAt, Date(timeIntervalSince1970: fixedReset))
	}

	func testLatestRateLimitsIgnoresNewerModelSpecificLimitAndKeepsAccountLimit() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let accountFile = "rollout-2026-07-01T09-00-00-feedface-8444-4444-4444-444444444444.jsonl"
		let modelFile = "rollout-2026-07-01T10-00-00-feedface-8555-5555-5555-555555555555.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		let accountReset = now.addingTimeInterval(5 * 86_400).timeIntervalSince1970
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"limit_id":"codex","limit_name":null,"plan_type":"pro","primary":{"used_percent":77,"window_minutes":10080,"resets_at":\(accountReset)},"secondary":null}}}
			""",
			to: root, filename: accountFile)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","plan_type":"pro","primary":{"used_percent":0,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(7 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: modelFile)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertEqual(snapshot.secondary?.usedPercent, 77)
		XCTAssertEqual(snapshot.secondary?.resetsAt, Date(timeIntervalSince1970: accountReset))
	}

	func testLatestRateLimitsDoesNotPromoteModelSpecificLimitWithoutAnAccountReading() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-8666-6666-6666-666666666666.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","plan_type":"pro","primary":{"used_percent":35,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(7 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: file)

		XCTAssertNil(CodexProvider(root: root).latestRateLimits(now: now))
	}

	func testLatestRateLimitsKeepsGenuineZeroWithFixedResetBoundary() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-8333-3333-3333-333333333333.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		let fixedReset = now.addingTimeInterval(6 * 86_400).timeIntervalSince1970
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":0,"window_minutes":10080,"resets_at":\(fixedReset)},"secondary":null}}}
			{"type":"event_msg","timestamp":"2026-07-01T10:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":20}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":0,"window_minutes":10080,"resets_at":\(fixedReset)},"secondary":null}}}
			""",
			to: root, filename: file)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertEqual(snapshot.secondary?.usedPercent, 0)
		XCTAssertEqual(snapshot.secondary?.resetsAt, Date(timeIntervalSince1970: fixedReset))
	}

	func testLatestRateLimitsDoesNotReviveExpiredOlderFiveHourWhenNewestSnapshotIsWeeklyOnly() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let oldFile = "rollout-2026-07-01T09-00-00-feedface-6111-1111-1111-111111111111.jsonl"
		let newFile = "rollout-2026-07-01T10-00-00-feedface-6222-2222-2222-222222222222.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try writeRateLimit(
			timestamp: "2026-07-01T09:01:00.000Z", primary: 17, secondary: 2, to: root,
			filename: oldFile,
			primaryReset: now.addingTimeInterval(-30).timeIntervalSince1970,
			secondaryReset: now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":3,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: newFile)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertNil(snapshot.primary)
		XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 3)
	}

	/// The "bars reset randomly" case for Codex: the newest snapshot's 5-hour window has just rolled past
	/// its reset boundary and no fresher reading exists. `latestRateLimits` is correctly nil (no fabricated
	/// %), but `latestRateLimitAwaitingReset` flags it so the dashboard shows a hint instead of a silently
	/// blank gauge.
	func testAwaitingResetFlagsAJustRolledOverWindowWhileLatestRateLimitsStaysNil() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-7111-1111-1111-111111111111.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":62,"window_minutes":300,"resets_at":\(now.addingTimeInterval(-120).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: file)
		let provider = CodexProvider(root: root)

		XCTAssertNil(
			provider.latestRateLimits(now: now), "just-rolled-over window must not show a stale %")
		XCTAssertTrue(
			provider.latestRateLimitAwaitingReset(now: now),
			"a window that reset ~2 min ago must flag the awaiting-reset hint")
	}

	/// [Regression guard — duplicated O(rollout files) sweep] `latestRateLimitAwaitingReset` used to open
	/// by calling `latestRateLimits`, re-walking every rollout file a second (and on the miss path, a
	/// third) time — and `buildRefreshResult` calls both accessors on every refresh. One walk now
	/// resolves both, and the two selection rules must stay independent: `current` skips a degenerate
	/// `window_minutes:0` snapshot BEFORE its freshest-wins comparison, while the awaiting-reset
	/// accumulator keeps expired-but-recognized windows.
	func testResolvedStateMatchesTheIndividualAccessorsOnARolledOverWindow() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-7333-3333-3333-333333333333.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":62,"window_minutes":300,"resets_at":\(now.addingTimeInterval(-120).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: file)
		let provider = CodexProvider(root: root)

		let state = provider.latestRateLimitState(now: now)
		XCTAssertNil(state.current)
		XCTAssertTrue(state.awaitingReset)
		XCTAssertEqual(state.current?.primary?.usedPercent, provider.latestRateLimits(now: now)?.primary?.usedPercent)
		XCTAssertEqual(state.awaitingReset, provider.latestRateLimitAwaitingReset(now: now))
	}

	/// The invariant the old early return (`if latestRateLimits(now:) != nil { return false }`) provided
	/// implicitly, now that both accumulators run in one pass: a live window must never ALSO report the
	/// awaiting-reset hint, or provider detail would show a % and "waiting for the new percentage".
	func testResolvedStateNeverReportsAwaitingResetWhileAWindowIsCurrent() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		// An OLD rolled-over weekly alongside a CURRENT 5-hour: the awaiting accumulator sees a
		// recognized expired window, but `current` wins and must suppress the hint outright.
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-06-28T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":null,"secondary":{"used_percent":44,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(-600).timeIntervalSince1970)}}}}
			""",
			to: root, filename: "rollout-2026-06-28T10-00-00-feedface-7444-4444-4444-444444444444.jsonl")
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":62,"window_minutes":300,"resets_at":\(now.addingTimeInterval(1800).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: "rollout-2026-07-01T10-00-00-feedface-7555-5555-5555-555555555555.jsonl")

		let state = CodexProvider(root: root).latestRateLimitState(now: now)
		XCTAssertEqual(state.current?.primary?.usedPercent, 62)
		XCTAssertFalse(
			state.awaitingReset,
			"a current window must suppress the awaiting-reset hint, exactly as the old early return did")
	}

	/// [Regression guard] Capture age must NEVER hide an unexpired official window. Codex only records a
	/// window while a CLI turn runs against that quota pool, so a weekly reading is routinely hours or
	/// days old while its 7-day boundary is still ahead. v1.113 aged those readings out and the Codex row
	/// collapsed to an activity sparkline, losing the reset countdown — real, still-valid information.
	/// The window now survives on its own `resets_at` alone; `capturedAt` is diagnostic, not a gate.
	func testOldCaptureStillReportsWhileItsWeeklyResetIsAhead() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let captured = Date(timeIntervalSince1970: 1_782_900_000)
		let now = captured.addingTimeInterval(23 * 3600)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"limit_id":"codex","plan_type":"pro","primary":null,"secondary":{"used_percent":26,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(5 * 86_400).timeIntervalSince1970)}}}}
			""",
			to: root, filename: "rollout-2026-07-01T10-00-00-feedface-9111-1111-1111-111111111111.jsonl")

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertEqual(snapshot.secondary?.usedPercent, 26, "the weekly bar must survive a 23-hour-old capture")
		XCTAssertEqual(
			snapshot.secondary?.resetsAt, now.addingTimeInterval(5 * 86_400),
			"the 7-day reset countdown is the point of keeping the bar")
		XCTAssertEqual(snapshot.capturedAt, captured, "capture time is still recorded, just not a display gate")
	}

	/// Negative: while a window is still current, the hint stays off (the real % shows).
	func testAwaitingResetIsFalseWhileAWindowIsStillCurrent() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-7222-2222-2222-222222222222.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":62,"window_minutes":300,"resets_at":\(now.addingTimeInterval(1800).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: file)
		XCTAssertFalse(CodexProvider(root: root).latestRateLimitAwaitingReset(now: now))
	}

	func testLatestRateLimitsDoesNotMixEarlierFiveHourFromSameFileIntoLaterWeeklyOnlySnapshot() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-6333-3333-3333-333333333333.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":21,"window_minutes":300,"resets_at":\(now.addingTimeInterval(300).timeIntervalSince1970)},"secondary":{"used_percent":2,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)}}}}
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":20}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":3,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: file)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertNil(snapshot.primary)
		XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 3)
	}

	func testLatestRateLimitsRestoresFiveHourWhenNewestSnapshotIncludesItAgain() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-6444-4444-4444-444444444444.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":3,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)},"secondary":null}}}
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":20}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":8,"window_minutes":300,"resets_at":\(now.addingTimeInterval(300).timeIntervalSince1970)},"secondary":{"used_percent":4,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)}}}}
			""",
			to: root, filename: file)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
		XCTAssertEqual(snapshot.primary?.usedPercent, 8)
		XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 4)
	}

	/// Codex has been observed to emit a degenerate `window_minutes:0` rate-limit line (used_percent 0,
	/// `secondary` null) for an entire session. When such a session is the NEWEST rollout, its snapshot
	/// carries no recognized 300/10080 window, so selecting it and normalizing would blank the gauge. It
	/// must instead be skipped in favour of an older rollout that still holds a current window — the gauge
	/// shows that older-but-current 5-hour/weekly, never a blank. Regression guard for atomic-snapshot
	/// selection masking an older still-current window.
	func testLatestRateLimitsSkipsDegenerateNewestSnapshotAndKeepsOlderCurrentWindow() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let oldFile = "rollout-2026-07-01T09-00-00-feedface-6555-5555-5555-555555555555.jsonl"
		let newFile = "rollout-2026-07-01T10-00-00-feedface-6666-6666-6666-666666666666.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T09:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":40,"window_minutes":300,"resets_at":\(now.addingTimeInterval(300).timeIntervalSince1970)},"secondary":{"used_percent":20,"window_minutes":10080,"resets_at":\(now.addingTimeInterval(6 * 86_400).timeIntervalSince1970)}}}}
			""",
			to: root, filename: oldFile)
		// Newest activity is a whole-session degenerate window_minutes:0 line — no recognized window.
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":20}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":0,"window_minutes":0,"resets_at":\(now.addingTimeInterval(3600).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: newFile)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
		XCTAssertEqual(snapshot.primary?.usedPercent, 40)
		XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 20)
	}

	/// A newest snapshot that carries ONLY an unrecognized-duration window and nothing older still-current
	/// resolves to nil (blank gauge) rather than fabricating a reading — fail-safe, never a wrong number.
	func testLatestRateLimitsReturnsNilWhenNewestDegenerateSnapshotHasNoOlderCurrentWindow() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-6777-7777-7777-777777777777.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":0,"window_minutes":0,"resets_at":\(now.addingTimeInterval(3600).timeIntervalSince1970)},"secondary":null}}}
			""",
			to: root, filename: file)

		XCTAssertNil(CodexProvider(root: root).latestRateLimits(now: now))
	}

	func testLatestRateLimitsSuppressesElapsedPrimaryWhileWeeklyIsCurrent() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-3333-3333-3333-333333333333.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try writeRateLimit(
			timestamp: "2026-07-01T10:01:00.000Z", primary: 91, secondary: 44, to: root,
			filename: file,
			primaryReset: now.addingTimeInterval(-1).timeIntervalSince1970,
			secondaryReset: now.addingTimeInterval(3600).timeIntervalSince1970)

		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))

		XCTAssertNil(snapshot.primary)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 44)
		XCTAssertEqual(snapshot.planType, "pro")
	}

	func testLatestRateLimitsReturnsNilWhenAllWindowsExpired() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-4444-4444-4444-444444444444.jsonl"
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		try writeRateLimit(
			timestamp: "2026-07-01T10:01:00.000Z", primary: 91, secondary: 44, to: root,
			filename: file,
			primaryReset: now.addingTimeInterval(-1).timeIntervalSince1970,
			secondaryReset: now.timeIntervalSince1970)

		XCTAssertNil(CodexProvider(root: root).latestRateLimits(now: now))
	}

	/// Regression guard for the per-file tail-read cache: repeat calls against an UNCHANGED file must
	/// keep returning the same result (proving the cache hit doesn't silently drop or corrupt data),
	/// and a REAL change to the file (new content + a bumped mtime) must still be picked up on the next
	/// call (proving the cache invalidates rather than sticking forever).
	func testLatestRateLimitsCachePicksUpARealFileChange() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = "rollout-2026-07-01T10-00-00-feedface-5555-5555-5555-555555555555.jsonl"
		let now = Date(timeIntervalSince1970: 1_782_000_000 - 60)
		try writeRateLimit(timestamp: "2026-07-01T10:01:00.000Z", primary: 10, secondary: 5, to: root, filename: file)

		let provider = CodexProvider(root: root)
		let first = try XCTUnwrap(provider.latestRateLimits(now: now))
		XCTAssertEqual(first.primary?.usedPercent, 10.0)

		// Same content, same size+mtime: a second call must return the identical (cached) result.
		let second = try XCTUnwrap(provider.latestRateLimits(now: now))
		XCTAssertEqual(second.primary?.usedPercent, 10.0)

		// A real change (new content, forced-newer mtime) must be observed, not served stale from cache.
		try writeRateLimit(timestamp: "2026-07-01T10:05:00.000Z", primary: 77, secondary: 33, to: root, filename: file)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
			ofItemAtPath: root.appendingPathComponent("2026/07/01/\(file)").path)
		let third = try XCTUnwrap(provider.latestRateLimits(now: now))
		XCTAssertEqual(third.primary?.usedPercent, 77.0)
	}

	func testLatestRateLimitsRechecksSameSizeSameMtimeRewriteViaCtime() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let filename = "rollout-2026-07-20T10-00-00-feedface-5656-5656-5656-565656565656.jsonl"
		let now = Date()
		let reset = now.addingTimeInterval(6 * 86_400).timeIntervalSince1970
		func line(used: Int) -> String {
			"""
			{"type":"event_msg","timestamp":"2026-07-20T10:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":\(used),"window_minutes":10080,"resets_at":\(reset)},"secondary":null}}}
			"""
		}
		try write(line(used: 0), to: root, filename: filename)
		let file = root.appendingPathComponent("2026/07/01/\(filename)")
		let fixedMtime = now.addingTimeInterval(-60)
		try FileManager.default.setAttributes([.modificationDate: fixedMtime], ofItemAtPath: file.path)

		let provider = CodexProvider(root: root)
		XCTAssertEqual(provider.latestRateLimits(now: now)?.secondary?.usedPercent, 0)

		// Preserve size and mtime deliberately. The kernel still changes ctime, so a rewrite cannot reuse
		// the cached rate limit even when a writer restores the two ordinary cache-key fields.
		try line(used: 9).write(to: file, atomically: false, encoding: .utf8)
		try FileManager.default.setAttributes([.modificationDate: fixedMtime], ofItemAtPath: file.path)

		XCTAssertEqual(provider.latestRateLimits(now: now)?.secondary?.usedPercent, 9)
	}

	func testLatestRateLimitsDoesNotReparseUnchangedLargeFileWithoutASnapshot() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let filename = "rollout-2026-07-20T10-00-00-feedface-5757-5757-5757-575757575757.jsonl"
		let body = #"{"type":"ignored","pad":"\#(String(repeating: "x", count: 2 * 1_024 * 1_024))"}"# + "\n"
		try write(body, to: root, filename: filename)

		let scannedBytes = CodexScannedByteCounter()
		let provider = CodexProvider(
			root: root,
			reader: JSONLStreamReader(chunkSize: 1_024) { scannedBytes.add($0) })
		XCTAssertNil(provider.latestRateLimits())
		let firstScan = scannedBytes.value
		XCTAssertEqual(firstScan, body.utf8.count)

		XCTAssertNil(provider.latestRateLimits())
		XCTAssertEqual(scannedBytes.value, firstScan)
	}

	// MARK: - Allowlist, availability, and degenerate sessions

	func testStrictAllowlistIgnoresSecretsAndDatabases() throws {
		let root = try stage([("codex-basic", basicUUID)])
		defer { try? FileManager.default.removeItem(at: root) }
		let day = root.appendingPathComponent("2026/07/01", isDirectory: true)
		// Drop the exact siblings that live next to real rollouts. None match rollout-*.jsonl.
		for decoy in ["auth.json", "logs_2.sqlite", "state_5.sqlite-wal", "session.jsonl", "rollout-x.txt"] {
			try "SECRET-OR-GARBAGE".write(
				to: day.appendingPathComponent(decoy), atomically: true, encoding: .utf8)
		}

		let provider = CodexProvider(root: root)
		XCTAssertEqual(provider.rolloutFiles().count, 1, "only the rollout-*.jsonl is read")
		XCTAssertEqual(provider.loadEvents().count, 3)
	}

	func testIsAvailableReflectsSessionsDir() throws {
		let root = try stage([("codex-basic", basicUUID)])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(CodexProvider(root: root).isAvailable())
		XCTAssertFalse(
			CodexProvider(root: root.appendingPathComponent("nope", isDirectory: true)).isAvailable())
	}

	func testSessionWithoutTokenCountYieldsNothing() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		try write(
			"""
			{"type":"session_meta","timestamp":"2026-07-01T00:00:00.000Z","payload":{"cwd":"/Users/x/proj","model":null}}
			{"type":"turn_context","timestamp":"2026-07-01T00:00:01.000Z","payload":{"model":"gpt-5-codex"}}
			{"type":"event_msg","timestamp":"2026-07-01T00:00:02.000Z","payload":{"type":"agent_message","message":"hi"}}
			""",
			to: root, filename: "rollout-2026-07-01T00-00-00-\(basicUUID).jsonl")
		XCTAssertEqual(CodexProvider(root: root).loadEvents().count, 0)
	}

	func testTokenCountBeforeAnyTurnContextIsUnpricedModel() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T00:00:02.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10}}}}
			""",
			to: root, filename: "rollout-2026-07-01T00-00-00-\(basicUUID).jsonl")
		let events = CodexProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events[0].model, "")  // no turn_context yet -> empty model (unpriced, honest)
		XCTAssertEqual(events[0].usage.input, 50)  // 100 - 50 cached
		XCTAssertEqual(events[0].usage.cacheRead, 50)
	}

	func testEarlyTokenCountUsesFirstModelLaterDeclaredBySameRollout() throws {
		let root = try makeEmptyRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		try write(
			"""
			{"type":"event_msg","timestamp":"2026-07-01T00:00:01.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":10}}}}
			{"type":"turn_context","timestamp":"2026-07-01T00:00:02.000Z","payload":{"model":"gpt-5.6-sol","cwd":"/Users/x/proj"}}
			{"type":"event_msg","timestamp":"2026-07-01T00:00:03.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":60,"output_tokens":20}}}}
			""",
			to: root, filename: "rollout-2026-07-01T00-00-00-\(basicUUID).jsonl")
		let events = CodexProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 2)
		XCTAssertEqual(events.map(\.model), ["gpt-5.6-sol", "gpt-5.6-sol"])
		XCTAssertEqual(events[0].usage.input, 50)
		XCTAssertEqual(events[1].usage.input, 40)
	}

	// MARK: - helpers for inline degenerate sessions

	private func makeEmptyRoot() throws -> URL {
		let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-codex-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(
			at: tmp.appendingPathComponent("2026/07/01", isDirectory: true),
			withIntermediateDirectories: true)
		return tmp
	}

	private func write(_ contents: String, to root: URL, filename: String) throws {
		try contents.write(
			to: root.appendingPathComponent("2026/07/01/\(filename)"), atomically: true, encoding: .utf8)
	}

	private func writeRateLimit(
		timestamp: String,
		primary: Int,
		secondary: Int,
		to root: URL,
		filename: String,
		primaryReset: TimeInterval = 1_782_928_214,
		secondaryReset: TimeInterval = 1_783_391_186
	) throws
	{
		try write(
			"""
			{"type":"turn_context","timestamp":"2026-07-01T09:00:00.000Z","payload":{"model":"gpt-5.5","cwd":"/Users/x/proj"}}
			{"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":\(primary),"window_minutes":300,"resets_at":\(primaryReset)},"secondary":{"used_percent":\(secondary),"window_minutes":10080,"resets_at":\(secondaryReset)}}}}
			""",
			to: root, filename: filename)
	}
}

private final class CodexScannedByteCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var storedValue = 0

	var value: Int {
		lock.lock()
		defer { lock.unlock() }
		return storedValue
	}

	func add(_ count: Int) {
		lock.lock()
		storedValue += count
		lock.unlock()
	}
}
