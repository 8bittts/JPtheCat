import Foundation
import JPtheCatCore

/// Pure derived-readout state for the Advanced Analytics tray — a value function of
/// (rows × scope × timeframe × measure × now). Extracted from `AdvancedAnalyticsTrayView`'s inline
/// computed properties so the money/token aggregations are unit-testable in isolation; the View keeps
/// thin delegates and stays layout-only. Copilot's basis (`.estimate`) is excluded from every `$`
/// aggregate — same honesty rule the dashboard enforces via `isAggregable`. Guard: `AnalyticsReadoutTests`.
struct AnalyticsReadout {
	let rows: [ModelDaySummary]
	let scopedProviders: Set<ProviderID>
	let days: Int
	let measure: AnalyticsMeasure
	let focusedProvider: ProviderID?
	let now: Date
	/// Primary official Grok plan %; weekly first, otherwise explicitly billing-cycle.
	let grokPlanUsedPercent: Double?
	let grokPlanWindowLabel: String
	let grokPlanEnabled: Bool

	/// Scoped rows whose basis may be summed into `$` (Claude + Codex — Copilot excluded).
	///
	/// [Perf] Both scope slices are resolved ONCE here rather than as computed properties: every derived
	/// figure below (hero, tiles, provenance, token mix, heatmap source, table source) re-scanned the full
	/// `rows` array on each access, and the view multiplies that by every section it feeds. Build ONE
	/// readout per render pass and reuse it — never a fresh one per figure.
	let aggregableRows: [ModelDaySummary]
	let scopedRows: [ModelDaySummary]

	init(
		rows: [ModelDaySummary],
		scopedProviders: Set<ProviderID>,
		days: Int,
		measure: AnalyticsMeasure,
		focusedProvider: ProviderID? = nil,
		now: Date = Date(),
		grokPlanUsedPercent: Double? = nil,
		grokPlanWindowLabel: String = "weekly",
		grokPlanEnabled: Bool = false
	) {
		self.rows = rows
		self.scopedProviders = scopedProviders
		self.days = days
		self.measure = measure
		self.focusedProvider = focusedProvider
		self.now = now
		self.grokPlanUsedPercent = grokPlanUsedPercent
		self.grokPlanWindowLabel = grokPlanWindowLabel
		self.grokPlanEnabled = grokPlanEnabled
		self.scopedRows = rows.filter { scopedProviders.contains($0.provider) }
		self.aggregableRows = self.scopedRows.filter { ProviderBasis.of($0.provider).isAggregable }
	}

	private func tokenTotal(_ row: ModelDaySummary) -> Int {
		row.inputTokens + row.outputTokens + row.cache5mTokens + row.cache1hTokens + row.cacheReadTokens
	}

	/// The rows the heatmaps color by: the `$` measure counts only aggregable rows (Copilot has no
	/// dollars); events/tokens count every scoped provider's activity.
	var heatmapSourceRows: [ModelDaySummary] {
		measure == .cost ? aggregableRows : scopedRows
	}

	var windowDollars: Double { aggregableRows.reduce(0) { $0 + $1.cost } }

	var todayDollars: Double {
		let today = Calendar.current.startOfDay(for: now)
		return aggregableRows.filter { Calendar.current.startOfDay(for: $0.day) == today }.reduce(0) { $0 + $1.cost }
	}

	var avgPerDay: Double { windowDollars / Double(max(days, 1)) }

	var dailyCostSeries: [Double] {
		AnalyticsAggregation.heatmapDays(rows: aggregableRows, measure: .cost, days: days).map(\.value)
	}

	var peakDayDollars: Double { dailyCostSeries.max() ?? 0 }

	var scopeTokens: Int { scopedRows.reduce(0) { $0 + tokenTotal($1) } }

	var todayTokens: Int {
		let today = Calendar.current.startOfDay(for: now)
		return scopedRows.filter { Calendar.current.startOfDay(for: $0.day) == today }.reduce(0) { $0 + tokenTotal($1) }
	}

	var avgTokensPerDay: Int { scopeTokens / max(days, 1) }

	var peakDayTokens: Int {
		Int(AnalyticsAggregation.heatmapDays(rows: scopedRows, measure: .tokens, days: days).map(\.value).max() ?? 0)
	}

	var totalEvents: Int { scopedRows.reduce(0) { $0 + $1.eventCount } }

	/// True when every scoped provider is fully unpriced (a Copilot-only focus): the hero + money tiles
	/// then lead with TOKENS instead of a dead `$0.00` (mirroring the dashboard's `isFullyUnpriced` path).
	var scopeIsFullyUnpriced: Bool {
		!scopedProviders.isEmpty && scopedProviders.allSatisfy { providerShowsTokens($0) }
	}

	var copilotTokens: Int {
		guard scopedProviders.contains(.copilot) else { return 0 }
		return rows.filter { $0.provider == .copilot }.reduce(0) { $0 + tokenTotal($1) }
	}

	var showCopilotTokenLine: Bool {
		!scopeIsFullyUnpriced && scopedProviders.contains(.copilot) && copilotTokens > 0
	}

	// MARK: - Display strings (hero + per-provider) — pure formatters, no theme

	func providerIsPlanOnly(_ id: ProviderID) -> Bool {
		id.consolidated == .grok && (grokPlanUsedPercent != nil || grokPlanEnabled) &&
			!rows.contains { $0.provider.consolidated == .grok && $0.eventCount > 0 }
	}

	var heroPrimaryValue: String {
		if focusedProvider.map(providerIsPlanOnly) == true {
			return grokPlanUsedPercent.map { "\(Int($0.rounded()))%" } ?? "—"
		}
		return scopeIsFullyUnpriced ? TokenFormatter.compact(scopeTokens) : MoneyFormatter.dollars(windowDollars)
	}

	var heroSecondaryValue: String {
		if focusedProvider.map(providerIsPlanOnly) == true { return grokPlanWindowLabel }
		return scopeIsFullyUnpriced ? TokenFormatter.compact(todayTokens) : MoneyFormatter.dollars(todayDollars)
	}

	var heroSecondaryCaption: String {
		if focusedProvider.map(providerIsPlanOnly) == true { return "included usage" }
		return scopeIsFullyUnpriced ? "today · tokens" : "today"
	}

	var heroEyebrow: String {
		focusedProvider.map { analyticsShortProviderName($0).uppercased() } ?? "ALL PROVIDERS"
	}

	func providerShowsTokens(_ id: ProviderID) -> Bool {
		if ProviderBasis.of(id).showsTokens { return true }
		let scoped = rows.filter { $0.provider == id }
		if id == .bigPickle, scoped.allSatisfy({ $0.cost == 0 }) { return true }
		// A GATEWAY whose every model is free (OpenCode Zen) has a dead `$0.00` — the same rule the
		// dashboard applies via `ProviderRow.usesTokenDisplay`.
		if ProviderBasis.of(id) == .gateway {
			return !scoped.isEmpty && scoped.allSatisfy({ $0.cost == 0 })
				&& scoped.contains(where: { tokenTotal($0) > 0 })
		}
		return false
	}

	func providerFigure(_ id: ProviderID) -> String {
		if providerIsPlanOnly(id) {
			return grokPlanUsedPercent.map { "\(Int($0.rounded()))%" } ?? "—"
		}
		let provRows = rows.filter { $0.provider == id }
		if providerShowsTokens(id) {
			return TokenFormatter.compact(provRows.reduce(0) { $0 + tokenTotal($1) })
		}
		return MoneyFormatter.compactDollars(provRows.reduce(0) { $0 + $1.cost })
	}

	/// A provider's own-basis daily series: real/notional providers use their cost series; a fully
	/// unpriced provider (Copilot) uses its token series (never a dead all-zero cost line).
	func providerDailySeries(_ id: ProviderID) -> [Double] {
		let provRows = rows.filter { $0.provider == id }
		let m: AnalyticsMeasure = providerShowsTokens(id) ? .tokens : .cost
		return AnalyticsAggregation.heatmapDays(rows: provRows, measure: m, days: days).map(\.value)
	}

	/// The trend small-multiple's headline figure is the SAME own-basis total the sidebar row shows — one
	/// implementation so the two can never disagree.
	func providerTrendFigure(_ id: ProviderID) -> String { providerFigure(id) }

	var tokenMix: TokenMix { AnalyticsAggregation.tokenMix(rows: scopedRows) }
}
