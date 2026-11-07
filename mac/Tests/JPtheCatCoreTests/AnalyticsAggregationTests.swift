import XCTest

@testable import JPtheCatCore

/// Locks the pure client-side re-shaping the Advanced Analytics canvas depends on: day-bucketing into a
/// dense zero-filled window, the events/tokens/cost measure selection, and the per-(provider, model)
/// collapse for the model table.
final class AnalyticsAggregationTests: XCTestCase {

	private var calendar: Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}

	private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
		calendar.date(from: DateComponents(year: y, month: m, day: d))!
	}

	private func summary(
		_ provider: ProviderID, _ model: String, day: Date, events: Int, input: Int = 0, output: Int = 0,
		cache5m: Int = 0, cache1h: Int = 0, cacheRead: Int = 0, cost: Double = 0
	) -> ModelDaySummary {
		ModelDaySummary(
			provider: provider, model: model, day: day, eventCount: events, inputTokens: input,
			outputTokens: output, cache5mTokens: cache5m, cache1hTokens: cache1h, cacheReadTokens: cacheRead,
			cost: cost)
	}

	// MARK: heatmapDays

	func testHeatmapBucketsByLocalDayAndZeroFillsTheWindow() {
		let now = day(2026, 7, 9)  // "today"
		let rows = [
			summary(.claude, "opus", day: day(2026, 7, 9), events: 3, cost: 5),
			summary(.codex, "gpt", day: day(2026, 7, 7), events: 2, cost: 1),
			// Outside the 5-day window (2026-07-05 … 2026-07-09) — must be ignored.
			summary(.claude, "opus", day: day(2026, 7, 1), events: 9, cost: 99),
		]
		let out = AnalyticsAggregation.heatmapDays(
			rows: rows, measure: .cost, days: 5, now: now, calendar: calendar)

		XCTAssertEqual(out.count, 5, "dense: exactly one entry per day in the window")
		XCTAssertEqual(out.first?.day, day(2026, 7, 5), "oldest day first")
		XCTAssertEqual(out.last?.day, day(2026, 7, 9), "last entry is today")
		XCTAssertEqual(out.map(\.value), [0, 0, 1, 0, 5], "cost bucketed by day, out-of-window ignored")
	}

	func testMeasureSelectsEventsTokensOrCost() {
		let now = day(2026, 7, 9)
		let rows = [
			summary(
				.claude, "opus", day: day(2026, 7, 9), events: 2, input: 100, output: 50, cache5m: 10,
				cache1h: 5, cacheRead: 35, cost: 4.25)
		]

		XCTAssertEqual(
			AnalyticsAggregation.heatmapDays(rows: rows, measure: .events, days: 1, now: now, calendar: calendar)
				.map(\.value), [2])
		XCTAssertEqual(
			AnalyticsAggregation.heatmapDays(rows: rows, measure: .tokens, days: 1, now: now, calendar: calendar)
				.map(\.value), [200], "tokens = input+output+cache5m+cache1h+cacheRead")
		XCTAssertEqual(
			AnalyticsAggregation.heatmapDays(rows: rows, measure: .cost, days: 1, now: now, calendar: calendar)
				.map(\.value), [4.25])
	}

	// MARK: modelTotals

	func testModelTotalsCollapseAcrossDaysPerProviderModel() {
		let rows = [
			summary(.claude, "opus", day: day(2026, 7, 8), events: 1, input: 10, cost: 2),
			summary(.claude, "opus", day: day(2026, 7, 9), events: 2, input: 20, output: 5, cost: 3),
			summary(.codex, "gpt", day: day(2026, 7, 9), events: 4, cacheRead: 7, cost: 1),
		]
		let totals = AnalyticsAggregation.modelTotals(rows: rows)

		XCTAssertEqual(totals.count, 2, "two distinct (provider, model) pairs")
		let opus = try! XCTUnwrap(totals.first { $0.provider == .claude && $0.model == "opus" })
		XCTAssertEqual(opus.eventCount, 3)
		XCTAssertEqual(opus.inputTokens, 30)
		XCTAssertEqual(opus.outputTokens, 5)
		XCTAssertEqual(opus.cost, 5, accuracy: 0.0001)
		XCTAssertEqual(opus.totalTokens, 35)

		let codex = try! XCTUnwrap(totals.first { $0.provider == .codex })
		XCTAssertEqual(codex.eventCount, 4)
		XCTAssertEqual(codex.cacheReadTokens, 7)
		XCTAssertEqual(codex.totalTokens, 7)

		// Stable order: provider rawValue ("claude" < "codex"), then model.
		XCTAssertEqual(totals.map(\.provider), [.claude, .codex])
	}

	// MARK: tokenMix + cache efficiency

	func testTokenMixSumsTheFiveBucketsAndCacheHitRateIsReadOverTotal() {
		let rows = [
			summary(.claude, "opus", day: day(2026, 7, 9), events: 1, input: 100, output: 40, cache5m: 10, cache1h: 5, cacheRead: 45),
			summary(.codex, "gpt", day: day(2026, 7, 9), events: 1, input: 200, output: 60, cache5m: 0, cache1h: 0, cacheRead: 55),
		]
		let mix = AnalyticsAggregation.tokenMix(rows: rows)
		XCTAssertEqual(mix.input, 300)
		XCTAssertEqual(mix.output, 100)
		XCTAssertEqual(mix.cache5m, 10)
		XCTAssertEqual(mix.cache1h, 5)
		XCTAssertEqual(mix.cacheRead, 100)
		XCTAssertEqual(mix.total, 515, "sum of all five buckets")
		XCTAssertEqual(mix.cacheHitRate, 100.0 / 515.0, accuracy: 0.0001, "cacheRead ÷ total")
	}

	func testTokenMixCacheHitRateIsZeroWhenNoTokens() {
		let mix = AnalyticsAggregation.tokenMix(rows: [])
		XCTAssertEqual(mix.total, 0)
		XCTAssertEqual(mix.cacheHitRate, 0, "no divide-by-zero on an empty scope")
	}

	// MARK: modelDayGrid

	func testModelDayGridRanksModelsByMeasureTotalAndCapsRows() {
		let now = day(2026, 7, 9)
		let rows = [
			// opus: 2 events across two days (busiest by events)
			summary(.claude, "opus", day: day(2026, 7, 8), events: 1, cost: 1),
			summary(.claude, "opus", day: day(2026, 7, 9), events: 1, cost: 1),
			// sonnet: 1 event
			summary(.claude, "sonnet", day: day(2026, 7, 9), events: 1, cost: 9),
			// gpt: 1 event
			summary(.codex, "gpt", day: day(2026, 7, 7), events: 1, cost: 3),
		]
		let grid = AnalyticsAggregation.modelDayGrid(
			rows: rows, measure: .events, days: 3, topModels: 2, now: now, calendar: calendar)

		XCTAssertEqual(grid.days.count, 3, "dense window: one column per day")
		XCTAssertEqual(grid.days.first, day(2026, 7, 7))
		XCTAssertEqual(grid.days.last, day(2026, 7, 9))
		XCTAssertEqual(grid.rows.count, 2, "capped at topModels")
		XCTAssertEqual(grid.rows.first?.model, "opus", "opus has the most events → row 0")
		XCTAssertEqual(grid.rows.first?.total, 2)
		// opus values across [7,8,9]: 0, 1, 1.
		XCTAssertEqual(grid.values.first, [0, 1, 1])
	}

	func testModelDayGridRanksByCostWhenMeasureIsCost() {
		let now = day(2026, 7, 9)
		let rows = [
			summary(.claude, "opus", day: day(2026, 7, 9), events: 5, cost: 1),
			summary(.claude, "sonnet", day: day(2026, 7, 9), events: 1, cost: 50),
		]
		let grid = AnalyticsAggregation.modelDayGrid(
			rows: rows, measure: .cost, days: 1, topModels: 5, now: now, calendar: calendar)
		XCTAssertEqual(grid.rows.first?.model, "sonnet", "by cost, sonnet ($50) outranks opus ($1)")
		XCTAssertEqual(grid.values.first, [50])
	}

	// MARK: filteredRows (drill-down slice selection)

	func testFilteredRowsByDay() {
		let rows = [
			summary(.claude, "opus", day: day(2026, 7, 8), events: 1),
			summary(.claude, "opus", day: day(2026, 7, 9), events: 2),
			summary(.codex, "gpt", day: day(2026, 7, 9), events: 3),
		]
		let out = AnalyticsAggregation.filteredRows(rows, matching: .day(day(2026, 7, 9)), calendar: calendar)
		XCTAssertEqual(out.count, 2, "both 2026-07-09 rows, not the 07-08 one")
		XCTAssertTrue(out.allSatisfy { $0.day == day(2026, 7, 9) })
	}

	func testFilteredRowsByWeekday() {
		// 2026-07-09 is a Thursday (Calendar weekday 5); 2026-07-02 is also a Thursday; 2026-07-08 is Wed.
		let rows = [
			summary(.claude, "opus", day: day(2026, 7, 2), events: 1),  // Thu
			summary(.claude, "opus", day: day(2026, 7, 8), events: 2),  // Wed
			summary(.codex, "gpt", day: day(2026, 7, 9), events: 3),  // Thu
		]
		let out = AnalyticsAggregation.filteredRows(rows, matching: .weekday(5), calendar: calendar)
		XCTAssertEqual(out.count, 2, "both Thursdays, not the Wednesday")
		XCTAssertTrue(out.allSatisfy { calendar.component(.weekday, from: $0.day) == 5 })
	}

	func testFilteredRowsByModelDay() {
		let rows = [
			summary(.claude, "opus", day: day(2026, 7, 9), events: 1),
			summary(.claude, "sonnet", day: day(2026, 7, 9), events: 2),
			summary(.claude, "opus", day: day(2026, 7, 8), events: 3),
		]
		let out = AnalyticsAggregation.filteredRows(
			rows, matching: .modelDay(provider: .claude, model: "opus", day: day(2026, 7, 9)),
			calendar: calendar)
		XCTAssertEqual(out.count, 1, "only claude/opus on 2026-07-09")
		XCTAssertEqual(out.first?.model, "opus")
		XCTAssertEqual(out.first?.eventCount, 1)
	}
}
