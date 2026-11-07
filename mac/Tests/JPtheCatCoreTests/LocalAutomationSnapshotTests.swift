import XCTest

@testable import JPtheCatCore

final class LocalAutomationSnapshotTests: XCTestCase {
	private let iso: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	func testSnapshotJSONUsesStableSnakeCaseContract() throws {
		let snapshot = LocalAutomationSnapshot.fixture()
		let data = try LocalAutomationSnapshotEncoder.encode(snapshot)
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

		XCTAssertEqual(json["schema_version"] as? Int, 4)
		XCTAssertEqual(json["value_metric"] as? String, "dollars")
		XCTAssertEqual(json["generated_at"] as? String, "2026-07-07T12:00:00Z")
		XCTAssertEqual(json["window_days"] as? Int, 14)
		XCTAssertEqual(json["cost_basis"] as? String, "real_and_notional_list_price")
		XCTAssertEqual(json["currency_code"] as? String, "USD")
		XCTAssertEqual(json["total_today"] as? Double, 10.24)
		XCTAssertEqual(json["total_window"] as? Double, 50.68)
		XCTAssertNotNil(json["providers"])
		XCTAssertNotNil(json["rate_limits"])

		let providers = try XCTUnwrap(json["providers"] as? [[String: Any]])
		let codex = try XCTUnwrap(providers.first { $0["id"] as? String == "codex" })
		XCTAssertEqual(codex["cost_basis"] as? String, "notional_list_price")
		XCTAssertEqual(codex["value_metric"] as? String, "dollars")
		XCTAssertEqual(codex["today"] as? Double, 6.0)
		// Copilot carries AIU consumption; a non-AIU provider omits the key entirely (no fake `0`).
		let copilot = try XCTUnwrap(providers.first { $0["id"] as? String == "copilot" })
		XCTAssertEqual(copilot["aiu_window"] as? Double, 1.43)
		XCTAssertNil(codex["aiu_window"], "providers without a local AIU signal must omit aiu_window, never emit 0")

		// Every provider carries a unified headroom. Codex's is an official 17% remaining...
		let codexHeadroom = try XCTUnwrap(codex["headroom"] as? [String: Any])
		XCTAssertEqual(codexHeadroom["state"] as? String, "official")
		XCTAssertEqual(codexHeadroom["remaining_percent"] as? Double, 17)
		XCTAssertEqual(codexHeadroom["window_minutes"] as? Int, 300)
		// ...while Claude (no signal in this fixture) is honestly `unknown` with NO number.
		let claude = try XCTUnwrap(providers.first { $0["id"] as? String == "claude" })
		let claudeHeadroom = try XCTUnwrap(claude["headroom"] as? [String: Any])
		XCTAssertEqual(claudeHeadroom["state"] as? String, "unknown")
		XCTAssertNil(claudeHeadroom["remaining_percent"], "unknown must never carry a fabricated number")

		let rateLimits = try XCTUnwrap(json["rate_limits"] as? [String: Any])
		let codexLimits = try XCTUnwrap(rateLimits["codex"] as? [String: Any])
		let primary = try XCTUnwrap(codexLimits["primary_5h"] as? [String: Any])
		XCTAssertEqual(primary["used_percent"] as? Double, 83)
	}

	func testMarkdownReportDisclosesNotionalAndOfficialUsage() {
		let report = LocalAutomationSnapshot.fixture().markdownReport()

		XCTAssertTrue(report.contains("# JP the Cat Local Snapshot"))
		XCTAssertTrue(report.contains("Total today: $10.24 USD (incl notional)"))
		XCTAssertTrue(report.contains("- Codex: today $6.00, 14d $30.00, notional list-price"))
		XCTAssertTrue(report.contains("5h used 83% official"))
		XCTAssertTrue(report.contains("headroom: 17% left (official)"))
		XCTAssertTrue(report.contains("headroom: unknown (no official limit signal)"))
	}

	func testBuilderCreatesAggregateSnapshotForLiveProviders() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		try index.ingest([
			event("claude-today", "2026-07-07T01:00:00.000Z", provider: .claude, model: "claude-opus-4-8"),
			event("codex-today", "2026-07-07T02:00:00.000Z", provider: .codex, model: "gpt-5-codex"),
			event("gemini-roadmap", "2026-07-07T03:00:00.000Z", provider: .gemini, model: "gemini-2.5-pro"),
		])
		let summaries = try index.windowSummaries(providers: [.claude, .codex], days: 14, now: now, calendar: utc())

		let snapshot = LocalAutomationSnapshotBuilder.build(
			summaries: summaries,
			providerIDs: [.claude, .codex],
			rateLimits: [
				.codex: RateLimitSnapshot(
					primary: RateLimitWindow(
						usedPercent: 44,
						windowMinutes: 300,
						resetsAt: iso.date(from: "2026-07-07T17:00:00.000Z")),
					secondary: nil,
					planType: "pro")
			],
			source: "test",
			generatedAt: now)

		XCTAssertEqual(snapshot.windowDays, 14)
		XCTAssertEqual(snapshot.series.count, 14)
		XCTAssertEqual(snapshot.providers.map(\.id), ["claude", "codex"])
		XCTAssertEqual(snapshot.totalToday, 35, accuracy: 0.001)
		XCTAssertEqual(snapshot.costBasis, .realAndNotionalListPrice)
		XCTAssertEqual(snapshot.providers.first { $0.id == "codex" }?.costBasis, .notionalListPrice)
		XCTAssertEqual(snapshot.rateLimits["codex"]?.primary5h?.usedPercent, 44)
		XCTAssertEqual(snapshot.rateLimits["codex"]?.primary5h?.official, true)
		// The builder resolves a per-provider headroom: Codex has a live window (44% used, resets in the
		// future) -> official 56% left; Claude has no signal -> honest unknown.
		let codexHeadroom = snapshot.providers.first { $0.id == "codex" }?.headroom
		XCTAssertEqual(codexHeadroom?.state, "official")
		XCTAssertEqual(codexHeadroom?.remainingPercent, 56)
		XCTAssertEqual(snapshot.providers.first { $0.id == "claude" }?.headroom.state, "unknown")
	}

	func testBuilderResolvesGrokNotionalWithSecondaryOnlyWeeklyHeadroom() throws {
		// Grok's automation shape is distinct from both tested providers: notional list-price cost basis
		// (like Codex) but its ONLY official window is weekly (primary nil, secondary weekly) — unlike
		// Codex's 5h-primary. Guards the builder's `.grok` cost-basis bucket + secondary-only headroom.
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		try index.ingest([
			event("grok-today", "2026-07-07T02:00:00.000Z", provider: .grok, model: "grok-4.5")
		])
		let summaries = try index.windowSummaries(providers: [.grok], days: 14, now: now, calendar: utc())

		let snapshot = LocalAutomationSnapshotBuilder.build(
			summaries: summaries,
			providerIDs: [.grok],
			rateLimits: [
				.grok: RateLimitSnapshot(
					primary: nil,
					secondary: RateLimitWindow(
						usedPercent: 30,
						windowMinutes: 10_080,
						resetsAt: iso.date(from: "2026-07-13T06:22:57.000Z")),
					planType: "SuperGrok")
			],
			source: "test",
			generatedAt: now)

		let grok = try XCTUnwrap(snapshot.providers.first { $0.id == "grok" })
		XCTAssertEqual(grok.costBasis, .notionalListPrice)
		// Weekly is the only official window -> official headroom of 70% left from a 10080-min window.
		XCTAssertEqual(grok.headroom.state, "official")
		XCTAssertEqual(grok.headroom.remainingPercent, 70)
		XCTAssertEqual(grok.headroom.windowMinutes, 10_080)
		XCTAssertEqual(snapshot.rateLimits["grok"]?.secondaryWeekly?.usedPercent, 30)
		XCTAssertEqual(snapshot.rateLimits["grok"]?.secondaryWeekly?.official, true)
		XCTAssertNil(snapshot.rateLimits["grok"]?.primary5h)
	}

	func testBuilderMarksMuseSparkNotionalWithUnknownHeadroom() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		try index.ingest([
			event("muse-today", "2026-07-07T02:00:00.000Z", provider: .museSpark, model: "muse-spark-1.1")
		])
		let summaries = try index.windowSummaries(providers: [.museSpark], days: 14, now: now, calendar: utc())

		let snapshot = LocalAutomationSnapshotBuilder.build(
			summaries: summaries,
			providerIDs: [.museSpark],
			rateLimits: [:],
			source: "test",
			generatedAt: now)

		let muse = try XCTUnwrap(snapshot.providers.first { $0.id == "muse_spark" })
		XCTAssertEqual(muse.costBasis, .notionalListPrice)
		XCTAssertEqual(muse.headroom.state, "unknown")
	}

	/// [Regression guard] The builder derives every provider's basis from `ProviderBasis`. A private
	/// per-provider switch once labelled the OpenCode model-brand rows as REAL spend because they were
	/// missing from it; Gemini keeps its audit-only notional carve-out.
	func testBuilderDerivesBrandRowsAsNotionalAndGatewaysAsGateway() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-07T12:00:00.000Z")!
		try index.ingest([
			event("mimo-today", "2026-07-07T02:00:00.000Z", provider: .mimo, model: "mimo-v2.5-free"),
			event("ds-today", "2026-07-07T02:00:00.000Z", provider: .deepseek, model: "deepseek-v4.1-flash"),
			event("go-today", "2026-07-07T02:00:00.000Z", provider: .opencodego, model: "deepseek-v4.1-flash"),
			event("gem-today", "2026-07-07T02:00:00.000Z", provider: .gemini, model: "gemini-3"),
		])
		let ids: [ProviderID] = [.mimo, .deepseek, .opencodego, .gemini]
		let summaries = try index.windowSummaries(providers: ids, days: 14, now: now, calendar: utc())
		let snapshot = LocalAutomationSnapshotBuilder.build(
			summaries: summaries, providerIDs: ids, rateLimits: [:], source: "test", generatedAt: now)
		func basis(_ id: String) throws -> LocalAutomationCostBasis {
			try XCTUnwrap(snapshot.providers.first { $0.id == id }).costBasis
		}
		XCTAssertEqual(try basis("mimo"), .notionalListPrice)
		XCTAssertEqual(try basis("deepseek"), .notionalListPrice)
		XCTAssertEqual(try basis("opencodego"), .gateway)
		XCTAssertEqual(try basis("gemini"), .notionalListPrice)
		XCTAssertNotEqual(snapshot.costBasis, .realSpend)
		// A free-tier brand row is unpriced and reports tokens, never a dead $0.
		let mimo = try XCTUnwrap(snapshot.providers.first { $0.id == "mimo" })
		XCTAssertEqual(mimo.unpricedModels, ["mimo-v2.5-free"])
	}

	func testBuilderKeepsWindowDaysAndSeriesLengthAligned() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-07-15T12:00:00.000Z")!
		try index.ingest([
			event("today", "2026-07-15T01:00:00.000Z", provider: .claude, model: "claude-opus-4-8"),
			event("day10", "2026-07-05T01:00:00.000Z", provider: .claude, model: "claude-opus-4-8"),
		])
		let summaries = try index.windowSummaries(providers: [.claude], days: 14, now: now, calendar: utc())

		let snapshot = LocalAutomationSnapshotBuilder.build(
			summaries: summaries,
			providerIDs: [.claude],
			rateLimits: [:],
			source: "test",
			generatedAt: now)

		XCTAssertEqual(snapshot.windowDays, 14)
		XCTAssertEqual(snapshot.series.count, 14)
		XCTAssertEqual(snapshot.totalWindow, 50, accuracy: 0.001)
		XCTAssertEqual(snapshot.series[3], 25, accuracy: 0.001)
		XCTAssertEqual(snapshot.series[13], 25, accuracy: 0.001)
	}

	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-local-automation-\(UUID().uuidString).sqlite").path
	}

	private func utc() -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		return calendar
	}

	private func event(_ id: String, _ timestamp: String, provider: ProviderID, model: String) -> UsageEvent {
		UsageEvent(
			messageId: "m-\(id)",
			requestId: "r-\(id)",
			provider: provider,
			model: model,
			timestamp: iso.date(from: timestamp)!,
			usage: TokenUsage(output: 1_000_000))
	}
}

private extension LocalAutomationSnapshot {
	static func fixture() -> LocalAutomationSnapshot {
		LocalAutomationSnapshot(
			generatedAt: Date(timeIntervalSince1970: 1_783_425_600),
			source: "test",
			windowDays: 14,
			currencyCode: "USD",
			totalToday: 10.235,
			totalWindow: 50.679,
			costBasis: .realAndNotionalListPrice,
			series: [5, 45.679],
			providers: [
				LocalAutomationProvider(
					id: "claude",
					name: "Claude Code",
					currencyCode: "USD",
					today: 4.235,
					window: 20.679,
					costBasis: .realSpend,
					series: [2, 18.679],
					eventsToday: 2,
					eventsWindow: 8,
					unpricedModels: []),
				LocalAutomationProvider(
					id: "codex",
					name: "Codex",
					currencyCode: "USD",
					today: 6,
					window: 30,
					costBasis: .notionalListPrice,
					series: [3, 27],
					eventsToday: 1,
					eventsWindow: 3,
					unpricedModels: [],
					headroom: LocalAutomationHeadroom(
						.official(remainingPercent: 17, windowMinutes: 300, resetsAt: nil))),
				LocalAutomationProvider(
					id: "copilot",
					name: "GitHub Copilot",
					currencyCode: "USD",
					today: 0,
					window: 0,
					costBasis: .realSpend,
					series: [0, 0],
					eventsToday: 3,
					eventsWindow: 12,
					unpricedModels: ["auto"],
					aiuWindow: 1.43),
			],
			rateLimits: [
				"codex": LocalAutomationRateLimits(
					planType: "pro",
					primary5h: LocalAutomationRateLimitWindow(
						usedPercent: 83,
						windowMinutes: 300,
						resetsAt: Date(timeIntervalSince1970: 1_783_443_600),
						official: true),
					secondaryWeekly: nil)
			],
			status: "ok",
			notice: nil)
	}
}
