import Foundation

public enum LocalAutomationSnapshotBuilder {
	public static let supportedTimeframes = [7, 14, 30, 90]

	public static func normalizedDays(_ days: Int) -> Int {
		if supportedTimeframes.contains(days) { return days }
		return supportedTimeframes.min(by: { abs($0 - days) < abs($1 - days) }) ?? 14
	}

	public static func build(
		summaries: UsageWindowSummaries,
		providerIDs: [ProviderID],
		rateLimits: [ProviderID: RateLimitSnapshot],
		source: String,
		grokPlan: CursorPlanUsage? = nil,
		generatedAt: Date = Date()
	) -> LocalAutomationSnapshot {
		let canonicalIDs = Set(providerIDs.map(\.consolidated))
		var canonicalRateLimits: [ProviderID: RateLimitSnapshot] = [:]
		for id in rateLimits.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
			let canonical = id.consolidated
			if canonicalRateLimits[canonical] == nil || id == canonical {
				canonicalRateLimits[canonical] = rateLimits[id]
			}
		}
		let providers = Array(canonicalIDs).sorted { $0.rawValue < $1.rawValue }.compactMap { id -> LocalAutomationProvider? in
			guard let summary = summaries.providers[id] else { return nil }
			// Every provider carries a headroom — resolved from its own live signal, or `.unknown` when
			// it has none (Copilot/Gemini/OpenCode). Never fabricated. Uses `generatedAt` as "now" so a
			// window's expiry is judged against the same clock the snapshot is stamped with.
			return provider(
				id: id,
				summary: summary,
				name: ProviderCatalog.descriptor(for: id)?.name ?? id.rawValue.capitalized,
				headroom: LocalAutomationHeadroom(
					ProviderHeadroom.resolve(from: canonicalRateLimits[id], now: generatedAt)),
				planMeter: id == .grok ? GrokPlanUsageStore.primaryMeter(plan: grokPlan, fallback: canonicalRateLimits[id], now: generatedAt) : nil)
		}
		// GATEWAY rollups (OpenCode Zen/Go) are listed but excluded from the total: their usage is
		// already counted under the model-brand rows, so summing them again would double-count.
		let aggregable = providers.filter { $0.costBasis != .tokenEstimate && $0.costBasis != .gateway && $0.valueMetric != .percent }
		let aggregateBasis = aggregateCostBasis(for: aggregable)
		let tokenOnly = !aggregable.isEmpty && aggregable.allSatisfy { $0.valueMetric == .tokens }
		let seriesDays = summaries.aggregate.dailyCostSeries.count
		let aggregateSeries = tokenOnly
			? []
			: (0..<seriesDays).map { index in
				aggregable.reduce(0.0) { total, provider in
					index < provider.series.count ? total + provider.series[index] : total
				}
			}
		let rateLimitRows = Dictionary(
			uniqueKeysWithValues: canonicalRateLimits.compactMap { id, snapshot -> (String, LocalAutomationRateLimits)? in
				guard canonicalIDs.contains(id) else { return nil }
				return (id.rawValue, localRateLimits(from: snapshot))
			})

		return LocalAutomationSnapshot(
			generatedAt: generatedAt,
			source: source,
			windowDays: summaries.aggregate.rollup.windowDays,
			totalToday: aggregable.reduce(0) { $0 + $1.today },
			totalWindow: aggregable.reduce(0) { $0 + $1.window },
			costBasis: aggregateBasis,
			valueMetric: tokenOnly ? .tokens : .dollars,
			series: aggregateSeries,
			providers: providers,
			rateLimits: rateLimitRows,
			status: providers.isEmpty ? "no_sources" : "ok",
			notice: providers.isEmpty ? "No live provider sources are available on this Mac." : nil)
	}

	private static func provider(
		id: ProviderID, summary: UsageWindowSummary, name: String, headroom: LocalAutomationHeadroom,
		planMeter: CursorPlanMeter? = nil
	) -> LocalAutomationProvider {
		// Copilot is a token feed by construction; unified Grok prices known local models. An OpenCode gateway (Zen/Go) is dollar-based,
		// but a window whose models are ALL unpriced (Zen's free tier) would print a dead `$0.00` — the
		// same trap `ProviderRow.isFullyUnpriced` avoids on the dashboard — so it falls back to tokens.
		let gatewayFullyUnpriced =
			costBasis(for: id) == .gateway
			&& summary.rollup.last7d.cost == 0
			&& summary.rollup.last7d.eventCount > 0
			&& !summary.rollup.last7d.unpricedModels.isEmpty
		let tokenOnly = id == .copilot || gatewayFullyUnpriced || (id == .grok && summary.rollup.last7d.cost == 0 && summary.rollup.last7d.eventCount > 0 && !summary.rollup.last7d.unpricedModels.isEmpty)
		let planOnly = summary.rollup.last7d.eventCount == 0 && planMeter != nil
		return LocalAutomationProvider(
			id: id.rawValue,
			name: name,
			today: planOnly ? planMeter!.usedPercent : (tokenOnly ? Double(summary.rollup.today.usage.total) : summary.rollup.today.cost),
			window: planOnly ? planMeter!.usedPercent : (tokenOnly ? Double(summary.rollup.last7d.usage.total) : summary.rollup.last7d.cost),
			costBasis: costBasis(for: id),
			valueMetric: planOnly ? .percent : (tokenOnly ? .tokens : .dollars),
			series: tokenOnly || planOnly ? [] : summary.dailyCostSeries,
			eventsToday: summary.rollup.today.eventCount,
			eventsWindow: summary.rollup.last7d.eventCount,
			unpricedModels: Array(summary.rollup.last7d.unpricedModels),
			headroom: headroom)
	}

	/// Derived from `ProviderBasis` — the single source of truth — with one automation-only carve-out:
	/// Gemini is audit-only and has no `ProviderBasis` row of its own, but its figures are a
	/// subscription's notional list price, never real spend.
	private static func costBasis(for id: ProviderID) -> LocalAutomationCostBasis {
		if id == .gemini { return .notionalListPrice }
		return LocalAutomationCostBasis(ProviderBasis.of(id))
	}

	private static func aggregateCostBasis(for providers: [LocalAutomationProvider]) -> LocalAutomationCostBasis {
		let hasNotional = providers.contains { $0.costBasis == .notionalListPrice }
		let hasReal = providers.contains { $0.costBasis == .realSpend }
		let hasTokenEstimate = providers.contains { $0.costBasis == .tokenEstimate }
		if hasNotional && hasReal { return .realAndNotionalListPrice }
		if hasNotional { return .notionalListPrice }
		if hasTokenEstimate && !hasReal { return .tokenEstimate }
		return .realSpend
	}

	private static func localRateLimits(from snapshot: RateLimitSnapshot) -> LocalAutomationRateLimits {
		LocalAutomationRateLimits(
			planType: snapshot.planType,
			primary5h: snapshot.primary.map(localRateLimitWindow),
			secondaryWeekly: snapshot.secondary.map(localRateLimitWindow),
			credits: snapshot.credits, capturedAt: snapshot.capturedAt)
	}

	private static func localRateLimitWindow(from window: RateLimitWindow) -> LocalAutomationRateLimitWindow {
		LocalAutomationRateLimitWindow(
			usedPercent: window.usedPercent,
			windowMinutes: window.windowMinutes,
			resetsAt: window.resetsAt,
			official: true)
	}
}
