import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

/// Pins the pure Advanced Analytics readout logic extracted out of `AdvancedAnalyticsTrayView`, so the
/// money/token aggregations stay correct independently of the SwiftUI view. Copilot (`.estimate`) must
/// never contribute to a `$` aggregate but DOES contribute to token/event totals.
final class AnalyticsReadoutTests: XCTestCase {
	private let cal = Calendar.current

	private func row(
		_ provider: ProviderID, day: Date, events: Int,
		input: Int, output: Int, c5m: Int = 0, c1h: Int = 0, cread: Int = 0, cost: Double
	) -> ModelDaySummary {
		ModelDaySummary(
			provider: provider, model: "\(provider.rawValue)-m", day: day, eventCount: events,
			inputTokens: input, outputTokens: output, cache5mTokens: c5m, cache1hTokens: c1h,
			cacheReadTokens: cread, cost: cost)
	}

	/// r1 claude-today: tok 185, $5 · r2 claude-yesterday: tok 120, $3 · r3 codex-today: tok 100, $2 ·
	/// r4 copilot-today: tok 100, $0 (estimate — excluded from $).
	private func fixture(now: Date) -> [ModelDaySummary] {
		let today = cal.startOfDay(for: now)
		let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
		return [
			row(.claude, day: today, events: 10, input: 100, output: 50, c5m: 10, c1h: 5, cread: 20, cost: 5),
			row(.claude, day: yesterday, events: 8, input: 80, output: 40, cost: 3),
			row(.codex, day: today, events: 6, input: 60, output: 30, cread: 10, cost: 2),
			row(.copilot, day: today, events: 4, input: 100, output: 0, cost: 0),
		]
	}

	func testFreeBigPickleChartsTokensWithoutAddingDollars() {
		let now = Date()
		let rows = [row(.bigPickle, day: now, events: 1, input: 100, output: 20, cost: 0)]
		let readout = AnalyticsReadout(rows: rows, scopedProviders: [.bigPickle], days: 14, measure: .events, now: now)
		XCTAssertEqual(readout.heroPrimaryValue, "120")
		XCTAssertEqual(readout.providerFigure(.bigPickle), "120")
		XCTAssertEqual(readout.providerDailySeries(.bigPickle).reduce(0, +), 120)
		XCTAssertEqual(readout.windowDollars, 0)
	}

	func testFreeGatewayChartsTokensAndNeverAddsDollars() {
		// OpenCode Zen's window is all-free, so its `$` total is a dead $0.00 — it must chart tokens
		// instead, and (being `ProviderBasis.gateway`) must never enter the aggregate.
		let now = Date()
		let rows = [row(.opencode, day: now, events: 2, input: 200, output: 40, cost: 0)]
		let readout = AnalyticsReadout(
			rows: rows, scopedProviders: [.opencode], days: 14, measure: .events, now: now)
		XCTAssertEqual(readout.providerShowsTokens(.opencode), true)
		XCTAssertEqual(readout.heroPrimaryValue, "240")
		XCTAssertEqual(readout.providerFigure(.opencode), "240")
		XCTAssertEqual(readout.windowDollars, 0)
	}

	func testPricedGatewayStillChartsDollars() {
		// OpenCode Go carries real notional cost, so it reads dollars — but stays out of the total.
		let now = Date()
		let rows = [row(.opencodego, day: now, events: 2, input: 200, output: 40, cost: 1.5)]
		let readout = AnalyticsReadout(
			rows: rows, scopedProviders: [.opencodego], days: 14, measure: .events, now: now)
		XCTAssertEqual(readout.providerShowsTokens(.opencodego), false)
		XCTAssertTrue(readout.providerFigure(.opencodego).hasPrefix("$"))
		XCTAssertEqual(readout.windowDollars, 0, "gateway dollars never aggregate")
	}

	func testDollarAggregatesExcludeCopilotButTokensDoNot() {
		let now = Date()
		let r = AnalyticsReadout(
			rows: fixture(now: now),
			scopedProviders: [.claude, .codex, .copilot], days: 7, measure: .events, now: now)

		// $ aggregates: Claude + Codex only (Copilot excluded).
		XCTAssertEqual(r.aggregableRows.count, 3)
		XCTAssertEqual(r.windowDollars, 10, accuracy: 1e-9)      // 5 + 3 + 2
		XCTAssertEqual(r.todayDollars, 7, accuracy: 1e-9)        // today claude 5 + codex 2
		XCTAssertEqual(r.avgPerDay, 10.0 / 7.0, accuracy: 1e-9)
		XCTAssertEqual(r.peakDayDollars, 7, accuracy: 1e-9)      // today bucket, aggregable

		// Tokens/events: every scoped provider, Copilot included.
		XCTAssertEqual(r.scopedRows.count, 4)
		XCTAssertEqual(r.scopeTokens, 505)                       // 185 + 120 + 100 + 100
		XCTAssertEqual(r.todayTokens, 385)                       // 185 + 100 + 100 (today rows)
		XCTAssertEqual(r.avgTokensPerDay, 72)                    // 505 / 7 (integer)
		XCTAssertEqual(r.peakDayTokens, 385)                     // today token bucket
		XCTAssertEqual(r.totalEvents, 28)                        // 10 + 8 + 6 + 4
		XCTAssertEqual(r.copilotTokens, 100)
		XCTAssertTrue(r.showCopilotTokenLine)
		XCTAssertFalse(r.scopeIsFullyUnpriced)
	}

	func testCopilotOnlyScopeIsFullyUnpricedAndLeadsWithTokens() {
		let now = Date()
		let r = AnalyticsReadout(
			rows: fixture(now: now), scopedProviders: [.copilot], days: 7, measure: .events, now: now)

		XCTAssertTrue(r.scopeIsFullyUnpriced)
		XCTAssertEqual(r.aggregableRows.count, 0)               // Copilot never aggregable
		XCTAssertEqual(r.windowDollars, 0, accuracy: 1e-9)
		XCTAssertEqual(r.scopeTokens, 100)
		XCTAssertEqual(r.copilotTokens, 100)
		// A fully-unpriced scope hides the "+ Copilot tokens" side line (the hero already IS tokens).
		XCTAssertFalse(r.showCopilotTokenLine)
	}

	func testDisplayStringsAndPerProviderFigures() {
		let now = Date()
		let r = AnalyticsReadout(
			rows: fixture(now: now), scopedProviders: [.claude, .codex, .copilot], days: 7,
			measure: .events, focusedProvider: nil, now: now)

		// Not fully unpriced → hero leads with $.
		XCTAssertEqual(r.heroPrimaryValue, MoneyFormatter.dollars(10))
		XCTAssertEqual(r.heroSecondaryValue, MoneyFormatter.dollars(7))
		XCTAssertEqual(r.heroSecondaryCaption, "today")
		XCTAssertEqual(r.heroEyebrow, "ALL PROVIDERS")

		// Per-provider (over ALL that provider's rows): Claude/Codex = $, Copilot = tokens.
		XCTAssertEqual(r.providerFigure(.claude), MoneyFormatter.compactDollars(8))   // 5 + 3
		XCTAssertEqual(r.providerTrendFigure(.codex), MoneyFormatter.compactDollars(2))
		XCTAssertEqual(r.providerFigure(.copilot), TokenFormatter.compact(100))
		XCTAssertEqual(r.tokenMix.total, r.scopeTokens)                               // 505
	}

	func testFocusedEyebrowAndFullyUnpricedHeroLeadsWithTokens() {
		let now = Date()
		let r = AnalyticsReadout(
			rows: fixture(now: now), scopedProviders: [.copilot], days: 7, measure: .events,
			focusedProvider: .copilot, now: now)

		XCTAssertEqual(r.heroEyebrow, analyticsShortProviderName(.copilot).uppercased())
		XCTAssertEqual(r.heroPrimaryValue, TokenFormatter.compact(100))   // fully unpriced → tokens, not $0
		XCTAssertEqual(r.heroSecondaryCaption, "today · tokens")
	}

	func testEmptyScopeIsNotFullyUnpriced() {
		let r = AnalyticsReadout(rows: [], scopedProviders: [], days: 7, measure: .events)
		XCTAssertFalse(r.scopeIsFullyUnpriced)                  // guard: !scopedProviders.isEmpty
		XCTAssertEqual(r.windowDollars, 0, accuracy: 1e-9)
		XCTAssertEqual(r.scopeTokens, 0)
		XCTAssertEqual(r.totalEvents, 0)
	}
}
