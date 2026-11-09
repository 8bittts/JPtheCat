import Foundation
import XCTest

@testable import JPtheCatCore

/// Proves the grouped-scan window summaries (`multiWindowSummariesGrouped` / `windowSummariesGrouped`)
/// are numerically identical to the per-event reference implementations (`multiWindowSummaries` /
/// `windowSummaries`) they replace. The grouped path buckets days in SQLite via
/// `date(ts,'unixepoch','localtime')`, so parity only holds when the passed `Calendar`'s timezone
/// matches the process/OS timezone SQLite reads — every test here uses a calendar in `TimeZone.current`
/// (production always passes `.current`), and the DST test pins the process tz explicitly.
final class MultiWindowSummariesParityTests: XCTestCase {
	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-parity-\(UUID().uuidString).sqlite").path
	}

	/// A calendar whose timezone matches what SQLite's `localtime` will use for this process.
	private func systemCalendar() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone.current
		return c
	}

	private func ev(
		_ provider: ProviderID, _ model: String, _ ts: Date,
		input: Int = 0, output: Int = 0, c5: Int = 0, c1: Int = 0, cr: Int = 0, tag: String = "e"
	) -> UsageEvent {
		UsageEvent(
			messageId: "\(tag)-\(UUID().uuidString)", requestId: "r", provider: provider, model: model,
			timestamp: ts,
			usage: TokenUsage(input: input, output: output, cacheCreate5m: c5, cacheCreate1h: c1, cacheRead: cr))
	}

	// MARK: - Field-level comparison

	private func assertEqual(
		_ a: CostBucket, _ b: CostBucket, _ ctx: String, file: StaticString = #filePath,
		line: UInt = #line
	) {
		XCTAssertEqual(a.cost, b.cost, accuracy: 1e-9, "\(ctx) cost", file: file, line: line)
		XCTAssertEqual(a.usage.input, b.usage.input, "\(ctx) input", file: file, line: line)
		XCTAssertEqual(a.usage.output, b.usage.output, "\(ctx) output", file: file, line: line)
		XCTAssertEqual(a.usage.cacheCreate5m, b.usage.cacheCreate5m, "\(ctx) c5", file: file, line: line)
		XCTAssertEqual(a.usage.cacheCreate1h, b.usage.cacheCreate1h, "\(ctx) c1", file: file, line: line)
		XCTAssertEqual(a.usage.cacheRead, b.usage.cacheRead, "\(ctx) cr", file: file, line: line)
		XCTAssertEqual(a.eventCount, b.eventCount, "\(ctx) eventCount", file: file, line: line)
		XCTAssertEqual(a.unpricedModels, b.unpricedModels, "\(ctx) unpriced", file: file, line: line)
	}

	private func assertEqual(
		_ a: UsageWindowSummary, _ b: UsageWindowSummary, _ ctx: String, file: StaticString = #filePath,
		line: UInt = #line
	) {
		assertEqual(a.rollup.today, b.rollup.today, "\(ctx).today", file: file, line: line)
		assertEqual(a.rollup.last7d, b.rollup.last7d, "\(ctx).window", file: file, line: line)
		XCTAssertEqual(a.rollup.windowDays, b.rollup.windowDays, "\(ctx) windowDays", file: file, line: line)
		XCTAssertEqual(
			Set(a.rollup.byModel7d.keys), Set(b.rollup.byModel7d.keys), "\(ctx) byModel keys", file: file,
			line: line)
		for model in a.rollup.byModel7d.keys {
			assertEqual(
				a.rollup.byModel7d[model]!, b.rollup.byModel7d[model]!, "\(ctx).byModel[\(model)]", file: file,
				line: line)
		}
		XCTAssertEqual(
			a.dailyCostSeries.count, b.dailyCostSeries.count, "\(ctx) series count", file: file, line: line)
		for i in 0..<min(a.dailyCostSeries.count, b.dailyCostSeries.count) {
			XCTAssertEqual(
				a.dailyCostSeries[i], b.dailyCostSeries[i], accuracy: 1e-9, "\(ctx) series[\(i)]", file: file,
				line: line)
		}
	}

	private func assertParity(
		_ index: UsageIndex, providers: [ProviderID], windows: [Int], now: Date, calendar: Calendar,
		_ ctx: String, file: StaticString = #filePath, line: UInt = #line
	) throws {
		let expected = try index.multiWindowSummariesPerEvent(
			providers: providers, windows: windows, now: now, calendar: calendar)
		let actual = try index.multiWindowSummariesGrouped(
			providers: providers, windows: windows, now: now, calendar: calendar)
		XCTAssertEqual(
			Set(expected.byDays.keys), Set(actual.byDays.keys), "\(ctx) window keys", file: file, line: line)
		for days in expected.byDays.keys {
			let e = expected.byDays[days]!
			let a = actual.byDays[days]!
			assertEqual(e.aggregate, a.aggregate, "\(ctx)[\(days)d].aggregate", file: file, line: line)
			XCTAssertEqual(
				Set(e.providers.keys), Set(a.providers.keys), "\(ctx)[\(days)d] provider keys", file: file,
				line: line)
			for p in e.providers.keys {
				assertEqual(
					e.providers[p]!, a.providers[p]!, "\(ctx)[\(days)d].providers[\(p.rawValue)]", file: file,
					line: line)
			}
		}
	}

	// MARK: - Tests

	func testHaiku55GroupedScanSplits100kBoundaryIncludingCachedInput() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = Date(timeIntervalSince1970: 1_784_000_000)
		try index.ingest([
			ev(.claude, "claude-haiku-5-5", now, input: 25_000, output: 1_000, c5: 25_000, c1: 25_000, cr: 25_000),
			ev(.claude, "claude-haiku-5-5", now, input: 25_001, output: 1_000, c5: 25_000, c1: 25_000, cr: 25_000),
		])
		try assertParity(index, providers: [.claude], windows: [7, 14, 30, 90], now: now, calendar: systemCalendar(), "haiku100k")
		let result = try index.multiWindowSummariesGrouped(providers: [.claude], windows: [14], now: now, calendar: systemCalendar())
		let bucket = try XCTUnwrap(result.byDays[14]?.providers[.claude]).rollup.last7d
		XCTAssertEqual(bucket.cost, 0.0682505, accuracy: 1e-12)
		XCTAssertEqual(bucket.eventCount, 2)
		XCTAssertEqual(bucket.unpricedModels, [])
	}

	func testGroupedPricingUsesEachModelsExactContextBoundary() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = Date(timeIntervalSince1970: 1_784_000_000)
		try index.ingest([
			ev(.codex, "gpt-6-luna", now, input: 272_000),
			ev(.codex, "gpt-6-luna", now, input: 272_001),
			ev(.opencodego, "qwen3.6-plus", now, input: 256_000),
			ev(.opencodego, "qwen3.6-plus", now, input: 256_001),
			ev(.grok, "grok-4.7", now, input: 200_000),
			ev(.opencode, "grok-4.7-opencode", now, input: 200_000),
			ev(.opencode, "grok-4.7-opencode", now, input: 200_001),
		])
		let result = try index.multiWindowSummariesGrouped(providers: [.codex, .opencodego, .grok, .opencode], windows: [7], now: now, calendar: systemCalendar())
		let window = try XCTUnwrap(result.byDays[7])
		XCTAssertEqual(try XCTUnwrap(window.providers[.codex]).rollup.last7d.cost, 0.0816002, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(window.providers[.opencodego]).rollup.last7d.cost, 0.640002, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(window.providers[.grok]).rollup.last7d.cost, 0.8, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(window.providers[.opencode]).rollup.last7d.cost, 1.200004, accuracy: 1e-12)
	}


	func testGroupedMatchesPerEventAcrossRandomCorpus() throws {
		let index = try UsageIndex(path: tempDBPath())
		let cal = systemCalendar()
		let now = Date(timeIntervalSince1970: 1_784_000_000)  // fixed instant, mid-2026
		let providers: [ProviderID] = [.claude, .codex, .grok, .museSpark]
		let models = ["qwen3.6-plus", "qwen3.7-plus", "gpt-6-luna", "gpt-6-sol", "gpt-6.1-sol", "claude-sonnet-5-5", "claude-sonnet-5-5-zen", "claude-haiku-5-5", "claude-haiku-5-5-us-inference", "claude-opus-5-5-fast-mode", "space-bunny", "gpt-reserve",
			"claude-sonnet-4-5",  // has a real >200K tier — exercises the cliff
			"grok-4.7",  // current Grok Build emit + xAI >200K cliff, no cache-creation fields
			"grok-4.7-fast",  // exclusive 200K cliff (prompt must exceed 200K) at the Fast rates
			"grok-4.6",  // prior Grok Build emit; same cliff shape
			"grok-4.5",  // older Grok Build emit; same cliff shape, cheaper cached-input rate
			"claude-opus-4-8",  // priced, no tier
			"gpt-5-codex",  // priced
			"gpt-9-imaginary",  // UNPRICED → must land in unpricedModels, never $0
		]
		// Deterministic LCG so failures reproduce without Math.random flakiness.
		var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
		func rnd(_ n: Int) -> Int {
			seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
			return Int((seed >> 33) % UInt64(n))
		}
		var batch: [UsageEvent] = []
		for i in 0..<1500 {
			let provider = providers[rnd(providers.count)]
			let model = models[rnd(models.count)]
			// Spread across ~100 local days, all hours (exercises cross-local-midnight attribution).
			let secondsBack = Double(rnd(100 * 86_400))
			let ts = now.addingTimeInterval(-secondsBack)
			// ~20% of events push context past 200K to exercise the tier split within a (model, day).
			let big = rnd(5) == 0
			batch.append(
				ev(
					provider, model, ts,
					input: big ? 210_000 + rnd(90_000) : rnd(40_000),
					output: rnd(8_000),
					c5: rnd(2_000), c1: rnd(1_000), cr: big ? rnd(60_000) : rnd(5_000),
					tag: "r\(i)"))
			if batch.count == 200 { try index.ingest(batch); batch.removeAll(keepingCapacity: true) }
		}
		if !batch.isEmpty { try index.ingest(batch) }

		try assertParity(
			index, providers: providers, windows: [7, 14, 30, 90], now: now, calendar: cal, "random")
		// Single-window sibling must match its own per-event reference too.
		for days in [7, 14, 30, 90] {
			let e = try index.windowSummariesPerEvent(providers: providers, days: days, now: now, calendar: cal)
			let a = try index.windowSummariesGrouped(providers: providers, days: days, now: now, calendar: cal)
			assertEqual(e.aggregate, a.aggregate, "windowSummaries[\(days)d].aggregate")
			for p in e.providers.keys {
				assertEqual(e.providers[p]!, a.providers[p]!, "windowSummaries[\(days)d][\(p.rawValue)]")
			}
		}
	}

	func testNonGregorianCalendarParity() throws {
		// SQLite's date(ts,'unixepoch','localtime') is proleptic-Gregorian, but localDayFormatter renders
		// the calendar's own era (Buddhist -> "2569-..", Islamic -> "1448-.."). A user whose macOS region
		// uses a non-Gregorian calendar makes Calendar.current non-Gregorian; the grouped path must NOT
		// day-bucket with an era-mismatched string (which drops every row -> $0). It must fall back to the
		// era-agnostic per-event path. Regression guard for the v1.059 non-Gregorian data-loss bug.
		for id in [Calendar.Identifier.buddhist, .japanese, .islamic, .hebrew] {
			let index = try UsageIndex(path: tempDBPath())
			var cal = Calendar(identifier: id)
			cal.timeZone = TimeZone.current  // region calendar keeps the system timezone
			let now = Date(timeIntervalSince1970: 1_784_000_000)
			try index.ingest([
				ev(.claude, "claude-opus-4-8", now.addingTimeInterval(-3_600), input: 1_000_000, tag: "today"),
				ev(.claude, "claude-opus-4-8", now.addingTimeInterval(-3 * 86_400), input: 1_000_000, tag: "d3"),
			])
			try assertParity(index, providers: [.claude], windows: [7, 30], now: now, calendar: cal, "cal=\(id)")
			// Belt-and-suspenders: the grouped result must be NON-empty (the bug produced all-zeros).
			let g = try index.multiWindowSummariesGrouped(providers: [.claude], windows: [7], now: now, calendar: cal)
			XCTAssertEqual(g.byDays[7]!.aggregate.rollup.last7d.cost, 10.0, accuracy: 1e-9, "cal=\(id) window cost")
		}
	}

	func testZeroDayWindowAndFallbackRouteParity() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = Date(timeIntervalSince1970: 1_784_000_000)
		try index.ingest([
			ev(.claude, "claude-opus-4-8", now.addingTimeInterval(-1_800), input: 1_000_000, tag: "today"),
			ev(.codex, "gpt-5-codex", now.addingTimeInterval(-2 * 86_400), input: 500_000, tag: "d2"),
		])

		// (a) The 0-day today-only branch (`days > 0 ? dayIndex : (isToday ? 0 : nil)`), never otherwise hit.
		try assertParity(index, providers: [.claude, .codex], windows: [0], now: now, calendar: systemCalendar(), "days0")

		// (b) A fixed non-current, DST-bearing tz SQLite can't reproduce → the grouped scan MUST route to the
		// per-event fallback (sqlLocalDayExpression == nil) AND still match. Pick a zone that isn't the host.
		let foreign = TimeZone.current.identifier == "Europe/Paris" ? "America/New_York" : "Europe/Paris"
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = TimeZone(identifier: foreign)!
		XCTAssertNil(
			UsageIndex.sqlLocalDayExpression(cal),
			"a non-current DST tz must route to the per-event fallback, not the grouped SQL path")
		try assertParity(index, providers: [.claude, .codex], windows: [7, 30], now: now, calendar: cal, "fallback")
	}

	func testTierCliffMixedDayParity() throws {
		// Same (provider, model, local day) with events on BOTH sides of the 200K cliff — the exact case
		// a naive "sum tokens then re-derive tier" over-bills. Grouped must equal per-event.
		let index = try UsageIndex(path: tempDBPath())
		let cal = systemCalendar()
		let now = Date(timeIntervalSince1970: 1_784_000_000)
		let noon = cal.startOfDay(for: now).addingTimeInterval(12 * 3_600)
		var batch: [UsageEvent] = []
		for k in 0..<6 { batch.append(ev(.claude, "claude-sonnet-4-5", noon, input: 40_000, output: 500, tag: "sub\(k)")) }
		for k in 0..<3 { batch.append(ev(.claude, "claude-sonnet-4-5", noon, input: 260_000, output: 3_000, cr: 20_000, tag: "over\(k)")) }
		try index.ingest(batch)
		try assertParity(index, providers: [.claude], windows: [7, 30], now: now, calendar: cal, "tierCliff")
	}

	func testEdgeCasesParity() throws {
		let cal = systemCalendar()
		let now = Date(timeIntervalSince1970: 1_784_000_000)

		// Empty providers list.
		let empty = try UsageIndex(path: tempDBPath())
		try assertParity(empty, providers: [], windows: [7, 90], now: now, calendar: cal, "emptyProviders")

		// Providers requested but no events at all.
		let noEvents = try UsageIndex(path: tempDBPath())
		try assertParity(
			noEvents, providers: [.claude, .codex], windows: [7, 14], now: now, calendar: cal, "noEvents")

		// Unpriced-only + single event.
		let one = try UsageIndex(path: tempDBPath())
		try one.ingest([ev(.codex, "gpt-9-imaginary", now.addingTimeInterval(-3_600), input: 500, output: 20)])
		try assertParity(one, providers: [.codex], windows: [7], now: now, calendar: cal, "unpricedSingle")
	}

	func testCrossLocalMidnightAttribution() throws {
		// Two events straddling local midnight must land in different local-day slots identically in both
		// paths (the whole reason day bucketing is local, not UTC).
		let index = try UsageIndex(path: tempDBPath())
		let cal = systemCalendar()
		let now = Date(timeIntervalSince1970: 1_784_000_000)
		let midnight = cal.startOfDay(for: now)
		try index.ingest([
			ev(.claude, "claude-opus-4-8", midnight.addingTimeInterval(-1_800), output: 1_000_000, tag: "prev"),
			ev(.claude, "claude-opus-4-8", midnight.addingTimeInterval(1_800), output: 1_000_000, tag: "today"),
		])
		try assertParity(index, providers: [.claude], windows: [7, 14], now: now, calendar: cal, "crossMidnight")
	}

	func testDSTBoundaryParity() throws {
		// Pin the process tz to one with a known DST transition, then verify SQLite's localtime actually
		// honors it before asserting — skip cleanly if the platform caches tz (never a false failure).
		setenv("TZ", "America/Los_Angeles", 1)
		tzset()
		defer { unsetenv("TZ"); tzset() }
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!

		let index = try UsageIndex(path: tempDBPath())
		let now = Date(timeIntervalSince1970: 1_773_856_800)  // 2026-03-09T18:00Z
		// This test only MEANS anything when the grouped SQLite `localtime` path is actually exercised —
		// i.e. `TimeZone.current` matches the pinned LA calendar (a Pacific host). Elsewhere
		// `sqlLocalDayExpression` returns nil (setenv+tzset moves SQLite's C tz but NOT Foundation's cached
		// `TimeZone.current`), so `multiWindowSummariesGrouped` would just re-run the per-event oracle and
		// `assertParity` would be a per-event-vs-per-event tautology reporting a false pass. Skip HONESTLY
		// (reported as skipped, not passed) rather than pretend the DST bucketing was verified.
		try XCTSkipUnless(
			UsageIndex.sqlLocalDayExpression(cal) != nil,
			"grouped localtime path not exercised on this host (need TimeZone.current == America/Los_Angeles); DST parity is verified only on Pacific hosts.")

		// Events spanning the spring-forward transition (23-hour local day).
		var batch: [UsageEvent] = []
		for hourUTC in stride(from: 0, through: 47, by: 3) {
			let ts = Date(timeIntervalSince1970: 1_773_705_600 + Double(hourUTC) * 3_600)  // from 2026-03-08T00:00Z
			batch.append(ev(.claude, "claude-opus-4-8", ts, output: 500_000, tag: "dst\(hourUTC)"))
		}
		try index.ingest(batch)
		try assertParity(index, providers: [.claude], windows: [7, 14], now: now, calendar: cal, "dst")
	}
}
