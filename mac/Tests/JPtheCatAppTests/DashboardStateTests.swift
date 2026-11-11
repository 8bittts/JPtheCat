import XCTest
import JPtheCatCore

@testable import JPtheCatApp

final class DashboardStateTests: XCTestCase {
	func testViewModelSelectionResolverAllowsStaleRows() {
		let stale = providerRow(
			id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true
		).markingStale()
		let unavailable = providerRow(
			id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18]
		).markingUnavailable(days: 14)

		XCTAssertEqual(DashboardViewModel.selectableProviderID("codex", rows: [stale, unavailable]), "codex")
		XCTAssertNil(DashboardViewModel.selectableProviderID("claude", rows: [stale, unavailable]))
	}

	func testBlankUnpricedModelHasUsefulDisplayName() {
		XCTAssertEqual(displayUnpricedModel(""), "unknown Codex model")
		XCTAssertEqual(displayUnpricedModel("future-model"), "future-model")
	}

	func testPricingDisclosureOmitsKnownFreeTierModels() {
		XCTAssertNil(pricingDisclosure(for: ["mimo-v2.5-free", "nemotron-3-ultra-free"]))
		XCTAssertEqual(
			pricingDisclosure(for: ["mimo-v2.5-free", "future-model"]),
			"Unpriced models omitted from cost: future-model")
		// The disclosure uses the same decorator-aware free-tier rule as `PricingTable`, so a free id
		// that pricing deliberately leaves unpriced is never reported as a pricing gap.
		XCTAssertNil(pricingDisclosure(for: [
			"muse-spark-1.3-contributor-free[1m]", "opencode/mimo-v2.6-pro-free-20260923",
		]))
	}

	func testSelectedAggregateCarriesOneCoherentWindowSnapshot() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)

		let state = DashboardState(
			rows: [claude, codex],
			aggregateSeries: [5, 45],
			aggregateToday: 10,
			aggregateWeek: 50,
			aggregateCostProvenance: .realAndNotionalListPrice,
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedId: nil,
			selectedDays: 30)

		XCTAssertTrue(state.hasData)
		XCTAssertEqual(state.selectedName, "All providers")
		XCTAssertEqual(state.selectedToday, 10)
		XCTAssertEqual(state.selectedWeek, 50)
		XCTAssertEqual(state.selectedSeries, [5, 45])
		XCTAssertEqual(state.selectedDays, 30)
		XCTAssertEqual(state.selectedCostProvenance, .realAndNotionalListPrice)
		XCTAssertEqual(state.selectedBasisLabel, "REAL + NOTIONAL LIST-PRICE · TODAY")
		XCTAssertEqual(state.weeklyShare(codex), 0.6)
	}

	func testSelectedProviderCarriesProviderProvenanceAndRefreshStatus() {
		let codex = providerRow(
			id: "codex",
			name: "Codex",
			today: 6,
			window: 30,
			series: [3, 27],
			notional: true,
			usedPct: 83,
			usageOfficial: true)

		let state = DashboardState(
			rows: [codex],
			aggregateSeries: [3, 27],
			aggregateToday: 6,
			aggregateWeek: 30,
			aggregateCostProvenance: .realAndNotionalListPrice,
			refreshStatus: .failed(message: "Codex refresh failed", lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedId: "codex",
			selectedDays: 14)

		XCTAssertEqual(state.selectedName, "Codex")
		XCTAssertEqual(state.selectedCostProvenance, .notionalListPrice)
		XCTAssertEqual(state.selectedBasisLabel, "NOTIONAL LIST-PRICE · TODAY")
		XCTAssertTrue(state.selectedRow?.usageOfficial ?? false)
		XCTAssertFalse(state.isRefreshing)
		XCTAssertEqual(state.refreshError, "Codex refresh failed")
		XCTAssertEqual(state.lastRefresh, Date(timeIntervalSince1970: 100))
	}

	func testSelectorRejectsExpiredAndUnofficialQuotas() {
		let row = providerRow(id: "codex", name: "Codex", today: 1, window: 2, series: [1, 1], usedPct: 0, usageOfficial: true)
		XCTAssertNil(row.selectorTrendSeries(now: Date(timeIntervalSince1970: 100)))
		XCTAssertEqual(row.selectorTrendSeries(now: .distantFuture), [1, 1])
		let unofficial = providerRow(id: "mimo", name: "MiMo", today: 1, window: 2, series: [1, 1], usedPct: 42)
		XCTAssertEqual(unofficial.selectorTrendSeries(), [1, 1])
	}

	func testSelectorMeterUsesRateLimitUsageWhenProviderExposesIt() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 90, window: 90, series: [45, 45])
		let codex = providerRow(
			id: "codex",
			name: "Codex",
			today: 10,
			window: 10,
			series: [5, 5],
			notional: true,
			usedPct: 76,
			usageOfficial: true)
		let state = DashboardState(
			rows: [claude, codex],
			aggregateSeries: [50, 50],
			aggregateToday: 100,
			aggregateWeek: 100,
			aggregateCostProvenance: .realAndNotionalListPrice,
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		XCTAssertEqual(state.weeklyShare(codex), 0.1)
		XCTAssertEqual(state.selectorMeterFraction(codex), 0.76, accuracy: 0.001)
		XCTAssertEqual(state.selectorMeterDescription(codex), "76% of 5-hour window used")
		XCTAssertEqual(state.selectorMeterDescription(claude), "Spend activity, last 14 days — quota unavailable")
	}

	func testSelectorMeterKeepsOfficialReadingWhenLimitIsOnlyInferred() {
		var claude = providerRow(
			id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18],
			usedPct: 86, usageOfficial: true)
		claude.limitLikelyHit = true
		let state = DashboardState(rows: [claude], selectedDays: 7)

		XCTAssertEqual(state.selectorMeterFraction(claude), 0.86, accuracy: 0.001)
		XCTAssertEqual(
			state.selectorMeterDescription(claude),
			"86% of 5-hour window used")
	}

	/// OpenCode Go: local cost against a PUBLISHED cap, with no provider-reported reset boundary. The
	/// window still owns a quota-shaped meter (this is the fix for the row falling back to a sparkline),
	/// but it is described as measured, never official.
	func testSelectorMeterUsesAMeasuredGatewayWindowWithNoResetBoundary() {
		let go = providerRow(
			id: "opencodego", name: "OpenCode Go", today: 0.38, window: 0.9,
			series: [0.1, 0.14, 0.12, 0.16, 0.13, 0.15, 0.1],
			notional: true, usedPct: 12, quotaIsMeasured: true, monthlyUsedPct: 2, isAggregable: false)
		let state = DashboardState(rows: [go], selectedDays: 14)

		let quota = go.selectorQuota()
		XCTAssertEqual(quota?.percent ?? 0, 12, accuracy: 0.001)
		XCTAssertEqual(quota?.measured, true)
		XCTAssertFalse(go.usageOfficial)
		// A quota-shaped meter means NO trend sparkline.
		XCTAssertNil(go.selectorTrendSeries())
		XCTAssertEqual(state.selectorMeterFraction(go), 0.12, accuracy: 0.001)
		XCTAssertEqual(
			state.selectorMeterDescription(go),
			"Measured 12% of the 5-hour cap used — local usage, no provider reset reported")
	}

	/// The measured branch is scoped to a gateway. A plain provider with a percentage but no official
	/// flag and no reset still charts activity — a self-relative reading never becomes quota-shaped.
	func testSelectorRejectsMeasuredFlagOnANonGateway() {
		let row = providerRow(
			id: "mimo", name: "MiMo", today: 0.2, window: 1.4, series: [0.1, 0.2],
			usedPct: 42, quotaIsMeasured: false, isAggregable: false)
		XCTAssertNil(row.selectorQuota())
		XCTAssertNotNil(row.selectorTrendSeries())
	}

	func testSelectorUsesCostTrendWhenNoOfficialQuota() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 90, window: 90, series: [45, 45])
		let museSpark = providerRow(
			id: "muse_spark", name: "Muse Spark", today: 0.02, window: 0.02, series: [0.02],
			notional: true, estimatedSharePct: 100)
		let state = DashboardState(
			rows: [claude, museSpark],
			aggregateSeries: [45.02, 45.02],
			aggregateToday: 90.02,
			aggregateWeek: 90.02,
			aggregateCostProvenance: .realAndNotionalListPrice,
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		XCTAssertEqual(state.weeklyShare(museSpark), 0.02 / 90.02, accuracy: 0.001)
		XCTAssertEqual(state.selectorMeterFraction(museSpark), 0, accuracy: 0.001)
		XCTAssertEqual(state.selectorMeterDescription(museSpark), "Notional cost activity, last 14 days — quota unavailable")
	}

	func testAggregateProvenanceDistinguishesRealNotionalAndMixed() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)

		XCTAssertEqual(DashboardCostProvenance.aggregate(for: []), .realSpend)
		XCTAssertEqual(DashboardCostProvenance.aggregate(for: [claude]), .realSpend)
		XCTAssertEqual(DashboardCostProvenance.aggregate(for: [codex]), .notionalListPrice)
		XCTAssertEqual(DashboardCostProvenance.aggregate(for: [claude, codex]), .realAndNotionalListPrice)
	}

	func testFreshnessCaptionTicksAndFlagsStaleData() {
		let lastRefresh = Date(timeIntervalSince1970: 100)

		let justNow = DashboardFreshness.evaluate(
			refreshStatus: .idle(lastRefresh: lastRefresh),
			now: Date(timeIntervalSince1970: 103))
		let secondsOld = DashboardFreshness.evaluate(
			refreshStatus: .idle(lastRefresh: lastRefresh),
			now: Date(timeIntervalSince1970: 112))
		let minutesOld = DashboardFreshness.evaluate(
			refreshStatus: .idle(lastRefresh: lastRefresh),
			now: Date(timeIntervalSince1970: 280))
		let stale = DashboardFreshness.evaluate(
			refreshStatus: .idle(lastRefresh: lastRefresh),
			now: Date(timeIntervalSince1970: 405))

		XCTAssertEqual(justNow.kind, .current)
		XCTAssertEqual(justNow.footerText, "Updated just now")
		XCTAssertEqual(secondsOld.kind, .current)
		XCTAssertEqual(secondsOld.footerText, "Updated 12s ago")
		XCTAssertEqual(minutesOld.kind, .current)
		XCTAssertEqual(minutesOld.footerText, "Updated 3m ago")
		XCTAssertEqual(stale.kind, .stale)
		XCTAssertEqual(stale.footerText, "Data may be stale · updated 5m ago")
	}

	func testFreshnessCaptionPreservesRefreshingState() {
		let lastRefresh = Date(timeIntervalSince1970: 100)
		let freshness = DashboardFreshness.evaluate(
			refreshStatus: .refreshing(lastRefresh: lastRefresh),
			now: Date(timeIntervalSince1970: 405))

		XCTAssertEqual(freshness.kind, .refreshing)
		XCTAssertEqual(freshness.footerText, "Refreshing…")
	}

	func testApplyingRefreshDropsVanishedProviderSelection() {
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
		let refreshedClaude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let previous = DashboardState(
			rows: [codex],
			aggregateSeries: [3, 27],
			aggregateToday: 6,
			aggregateWeek: 30,
			aggregateCostProvenance: .realAndNotionalListPrice,
			refreshStatus: .refreshing(lastRefresh: nil),
			selectedId: "codex",
			selectedDays: 14)

		let next = previous.applyingRefresh(
			rows: [refreshedClaude],
			aggregateSeries: [2, 18],
			aggregateToday: 4,
			aggregateWeek: 20,
			aggregateCostProvenance: .realSpend,
			errorMessage: nil,
			now: Date(timeIntervalSince1970: 200))

		XCTAssertNil(next.selectedId)
		XCTAssertEqual(next.selectedName, "All providers")
		XCTAssertEqual(next.selectedCostProvenance, .realSpend)
		XCTAssertEqual(next.lastRefresh, Date(timeIntervalSince1970: 200))
	}

	func testApplyingRefreshKeepsUnavailableProviderVisibleButNonContributing() {
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
		let refreshedClaude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let previous = DashboardState(
			rows: [codex],
			aggregateSeries: [3, 27],
			aggregateToday: 6,
			aggregateWeek: 30,
			aggregateCostProvenance: .notionalListPrice,
			refreshStatus: .refreshing(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedId: "codex",
			selectedDays: 14)

		let unavailableCodex = codex.markingUnavailable(days: 14)
		let next = previous.applyingRefresh(
			rows: [refreshedClaude, unavailableCodex],
			aggregateSeries: [2, 18],
			aggregateToday: 4,
			aggregateWeek: 20,
			aggregateCostProvenance: DashboardCostProvenance.aggregate(for: [refreshedClaude, unavailableCodex]),
			providerAvailabilityNotice: "Codex unavailable; aggregate excludes it until its log folder returns.",
			errorMessage: nil,
			now: Date(timeIntervalSince1970: 200))

		XCTAssertEqual(next.rows.map(\.id), ["claude", "codex"])
		XCTAssertEqual(next.rows.first { $0.id == "codex" }?.availability, .unavailable)
		XCTAssertNil(next.rows.first { $0.id == "codex" }?.today)
		XCTAssertEqual(next.rows.first { $0.id == "codex" }?.week, 0)
		XCTAssertEqual(next.rows.first { $0.id == "codex" }?.series, Array(repeating: 0, count: 14))
		XCTAssertEqual(next.aggregateCostProvenance, .realSpend)
		XCTAssertEqual(next.weeklyShare(unavailableCodex), 0)
		XCTAssertNil(next.selectedId)
		XCTAssertEqual(
			next.providerAvailabilityNotice,
			"Codex unavailable; aggregate excludes it until its log folder returns.")
	}

	func testAggregateProvenanceIgnoresUnavailableRows() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let unavailableCodex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
			.markingUnavailable(days: 14)

		XCTAssertEqual(DashboardCostProvenance.aggregate(for: [claude, unavailableCodex]), .realSpend)
		XCTAssertEqual(DashboardCostProvenance.aggregate(for: [unavailableCodex]), .realSpend)
	}

	func testDisabledProviderIsVisibleButNonContributingLikeUnavailable() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let disabledCodex = providerRow(
			id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true,
			usedPct: 95, usageOfficial: true
		).markingDisabled(days: 14)
		let state = DashboardState(
			rows: [claude, disabledCodex],
			aggregateSeries: [2, 18],
			aggregateToday: 4,
			aggregateWeek: 20,
			aggregateCostProvenance: DashboardCostProvenance.aggregate(for: [claude, disabledCodex]),
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		XCTAssertEqual(disabledCodex.availability, .disabled)
		XCTAssertFalse(disabledCodex.isContributing)
		XCTAssertFalse(disabledCodex.isSelectable)
		XCTAssertEqual(disabledCodex.today, nil)
		XCTAssertEqual(disabledCodex.series, Array(repeating: 0, count: 14))
		XCTAssertEqual(state.aggregateCostProvenance, .realSpend)
		XCTAssertEqual(state.weeklyShare(disabledCodex), 0)
		XCTAssertEqual(state.selectorMeterDescription(disabledCodex), "Unavailable")
	}

	func testAggregateCurrencyIgnoresUnavailableRows() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let unavailableForeignProvider = providerRow(
			id: "future", name: "Future Provider", today: 6, window: 30, series: [3, 27], currencyCode: "EUR"
		).markingUnavailable(days: 14)
		let state = DashboardState(
			rows: [claude, unavailableForeignProvider],
			aggregateSeries: [2, 18],
			aggregateToday: 4,
			aggregateWeek: 20,
			aggregateCostProvenance: DashboardCostProvenance.aggregate(for: [claude, unavailableForeignProvider]),
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		XCTAssertEqual(state.aggregateCurrencyCode, "USD")
	}

	/// A visible, available, non-aggregable row (e.g. Copilot's OTel estimate) must be excluded from
	/// the aggregate total, currency selection, and cost-provenance basis — but MUST still be
	/// selectable/contributing so it renders as a normal row with its own sparkline and totals.
	func testNonAggregableRowIsVisibleButExcludedFromEveryAggregatePath() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let copilot = providerRow(
			id: "copilot", name: "Copilot", today: 100, window: 700, series: [50, 650],
			notional: true, isAggregable: false)

		XCTAssertTrue(copilot.isContributing, "a non-aggregable row is still contributing/visible")
		XCTAssertTrue(copilot.isSelectable)
		XCTAssertEqual(
			DashboardCostProvenance.aggregate(for: [claude, copilot]), .realSpend,
			"Copilot's notional dollars must not flip the aggregate basis to mixed")

		let state = DashboardState(
			rows: [claude, copilot],
			aggregateSeries: [2, 18],
			aggregateToday: 4,
			aggregateWeek: 20,
			aggregateCostProvenance: .realSpend,
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		XCTAssertEqual(state.aggregateCurrencyCode, "USD")
		XCTAssertEqual(state.weeklyShare(copilot), 0, "excluded from the shared aggregate scale")
		// Self-relative fraction: today/week, not a share of an aggregate it was excluded from.
		XCTAssertEqual(state.selectorMeterFraction(copilot), 0, accuracy: 0.001)
		XCTAssertEqual(state.selectorMeterDescription(copilot), "Local token activity, last 14 days — quota unavailable")
	}

	/// Marking a non-aggregable provider (e.g. Copilot) unavailable or disabled must NOT flip it back to
	/// aggregable. `markingExcluded` rebuilds the row via the full initializer, so any classification flag
	/// not tied to the excluded window has to be carried over from `self` — regression guard for that.
	func testMarkingExcludedPreservesNonAggregableClassification() {
		let copilot = providerRow(
			id: "copilot", name: "Copilot", today: 100, window: 700, series: [50, 650],
			notional: true, isAggregable: false)
		XCTAssertFalse(copilot.isAggregable)

		XCTAssertFalse(
			copilot.markingUnavailable(days: 14).isAggregable,
			"an excluded non-aggregable row must stay non-aggregable, not silently reset to the default true")
		XCTAssertFalse(copilot.markingDisabled(days: 14).isAggregable)
	}

	/// `contributesToAggregate` is the single predicate every aggregate/widget site filters on. It must be
	/// false unless the row is BOTH contributing (not unavailable/disabled) AND aggregable — a row that is
	/// only aggregable (e.g. an unavailable row, `isAggregable` still true) must not slip into a total.
	func testContributesToAggregateRequiresBothContributingAndAggregable() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		XCTAssertTrue(claude.contributesToAggregate, "a fresh, aggregable row contributes")
		XCTAssertTrue(claude.markingStale().contributesToAggregate, "a stale row still contributes its last-good data")
		XCTAssertFalse(
			claude.markingUnavailable(days: 14).contributesToAggregate,
			"unavailable rows are aggregable-by-default but non-contributing — must be excluded from the total")
		XCTAssertFalse(claude.markingDisabled(days: 14).contributesToAggregate)

		let copilot = providerRow(
			id: "copilot", name: "Copilot", today: 100, window: 700, series: [50, 650],
			notional: true, isAggregable: false)
		XCTAssertFalse(copilot.contributesToAggregate, "a non-aggregable estimate never contributes to the total")
	}

	/// A row whose every model is unpriced (e.g. Copilot on `gpt-5-mini`) has a real, non-zero token
	/// count but a dead all-zero dollar total/series — `isFullyUnpriced` is the signal the UI uses to
	/// show tokens instead of a misleading `$0.00`. A row with a MIX of priced and unpriced models
	/// must NOT trip this (its dollar total is real, just an undercount).
	func testIsFullyUnpricedDetectsAnAllUnpricedRowButNotAMixedOne() {
		let allUnpriced = DashboardViewModel.ProviderRow(
			id: "copilot", name: "Copilot", tintHex: "#000000", today: 0, week: 0,
			todayUsage: TokenUsage(input: 100, output: 50), weekUsage: TokenUsage(input: 700, output: 350),
			todayEvents: 1, weekEvents: 5, series: [0, 0], notional: true, usedPct: nil, weeklyUsedPct: nil,
			usageOfficial: false, planLabel: nil, unpricedModels: ["gpt-5-mini"],
			byModel7d: [
				DashboardViewModel.ModelLine(model: "gpt-5-mini", cost: nil, usage: TokenUsage(input: 700, output: 350), eventCount: 5)
			],
			cacheSavings7d: nil, resetsAt5h: nil, resetsAtWeekly: nil, windowMinutes5h: nil, windowMinutesWeekly: nil)
		XCTAssertTrue(allUnpriced.isFullyUnpriced)
		let selectedState = DashboardState(
			rows: [allUnpriced],
			aggregateSeries: [],
			aggregateToday: 0,
			aggregateWeek: 0,
			aggregateCostProvenance: .realSpend,
			refreshStatus: .idle(lastRefresh: nil),
			selectedId: allUnpriced.id,
			selectedDays: 30)
		XCTAssertEqual(selectedState.selectedBasisLabel, "LOCAL TOKENS · TODAY")

		let mixed = DashboardViewModel.ProviderRow(
			id: "claude", name: "Claude Code", tintHex: "#000000", today: 4, week: 20,
			todayUsage: TokenUsage(input: 100, output: 50), weekUsage: TokenUsage(input: 700, output: 350),
			todayEvents: 1, weekEvents: 5, series: [2, 18], notional: false, usedPct: nil, weeklyUsedPct: nil,
			usageOfficial: false, planLabel: nil, unpricedModels: ["some-preview-model"],
			byModel7d: [
				DashboardViewModel.ModelLine(model: "claude-opus", cost: 20, usage: TokenUsage(input: 700, output: 350), eventCount: 4),
				DashboardViewModel.ModelLine(model: "some-preview-model", cost: nil, usage: TokenUsage(input: 10, output: 5), eventCount: 1),
			],
			cacheSavings7d: nil, resetsAt5h: nil, resetsAtWeekly: nil, windowMinutes5h: nil, windowMinutesWeekly: nil)
		XCTAssertFalse(mixed.isFullyUnpriced)

		let noActivity = DashboardViewModel.ProviderRow(
			id: "copilot", name: "Copilot", tintHex: "#000000", today: nil, week: 0,
			todayUsage: TokenUsage(), weekUsage: TokenUsage(), todayEvents: 0, weekEvents: 0, series: [0, 0],
			notional: true, usedPct: nil, weeklyUsedPct: nil, usageOfficial: false, planLabel: nil,
			unpricedModels: [], byModel7d: [], cacheSavings7d: nil, resetsAt5h: nil, resetsAtWeekly: nil,
			windowMinutes5h: nil, windowMinutesWeekly: nil)
		XCTAssertFalse(noActivity.isFullyUnpriced, "no events at all is not the same as a real all-unpriced row")
	}

	func testAvailabilityReconcilePlacesGrokBotImmediatelyAfterGrok() {
		let grok = providerRow(
			id: "grok", name: "Grok", today: 4, window: 20, series: [2, 18], notional: true)
		let grokBot = providerRow(
			id: "grok_bot", name: "Grok Bot", today: 0, window: 0, series: [0, 0],
			notional: false, usedPct: nil, weeklyUsedPct: 15, usageOfficial: true, isAggregable: false)
		let muse = providerRow(
			id: "muse_spark", name: "Muse Spark", today: 2, window: 10, series: [1, 9], notional: true)
		let copilot = providerRow(
			id: "copilot", name: "Copilot", today: 0, window: 0, series: [0, 0], notional: false,
			isAggregable: false)

		let result = DashboardViewModel.reconcileProviderAvailability(
			rows: [copilot, grokBot, muse, grok],
			previousRows: [],
			hadPreviousRefresh: false,
			unavailableProviderIDs: [],
			days: 14)

		XCTAssertEqual(result.rows.map(\.id), ["grok", "grok_bot", "muse_spark", "copilot"])
	}

	func testAvailabilityReconcileAnnouncesFirstSeenProviderWithoutClaimingItReturned() {
		// A provider never in previousRows is first-seen, not a return — the copy must not say "again".
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)

		let result = DashboardViewModel.reconcileProviderAvailability(
			rows: [codex],
			previousRows: [],
			hadPreviousRefresh: true,
			unavailableProviderIDs: [],
			days: 14)

		XCTAssertEqual(result.rows.map(\.id), ["codex"])
		XCTAssertEqual(result.notice, "Now tracking Codex in the aggregate.")
	}

	func testAvailabilityReconcileSaysAgainOnlyForAGenuineReturn() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
		let previouslyUnavailableCodex = codex.markingUnavailable(days: 14)

		let result = DashboardViewModel.reconcileProviderAvailability(
			rows: [claude, codex],
			previousRows: [claude, previouslyUnavailableCodex],
			hadPreviousRefresh: true,
			unavailableProviderIDs: [],
			days: 14)

		XCTAssertEqual(result.notice, "Codex available again; aggregate includes it again.")
	}

	func testReconcileKeepsFailedProviderAsStaleLastGoodRowWithoutANotice() {
		// Codex's directory is present but its refresh threw, so it is NOT in the freshly-built rows and NOT
		// in unavailableProviderIDs — only in failedProviderIDs. It must survive as a stale last-good row.
		let refreshedClaude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let lastGoodCodex = providerRow(
			id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true, usedPct: 82,
			usageOfficial: true)

		let result = DashboardViewModel.reconcileProviderAvailability(
			rows: [refreshedClaude],
			previousRows: [refreshedClaude, lastGoodCodex],
			hadPreviousRefresh: true,
			unavailableProviderIDs: [],
			failedProviderIDs: ["codex"],
			days: 14)

		let codexRow = result.rows.first { $0.id == "codex" }
		XCTAssertEqual(codexRow?.availability, .stale)
		XCTAssertEqual(codexRow?.today, 6, "stale keeps last-good data, not a zeroed row")
		XCTAssertEqual(codexRow?.week, 30)
		XCTAssertEqual(codexRow?.series, [3, 27])
		XCTAssertEqual(codexRow?.isContributing, true, "stale still contributes to the aggregate")
		XCTAssertNil(result.notice, "a transient failure discloses via the footer + stale badge, not a chart notice")
	}

	func testStaleProviderRecoveryEmitsNoNotice() {
		// stale → available never changed inclusion (stale kept contributing), so there is nothing to announce.
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
		let previousStaleCodex = codex.markingStale()

		let result = DashboardViewModel.reconcileProviderAvailability(
			rows: [claude, codex],
			previousRows: [claude, previousStaleCodex],
			hadPreviousRefresh: true,
			unavailableProviderIDs: [],
			days: 14)

		XCTAssertEqual(result.rows.first { $0.id == "codex" }?.availability, .available)
		XCTAssertNil(result.notice)
	}

	func testStaleRowContributesToProvenanceCurrencyAndShare() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let staleCodex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
			.markingStale()

		XCTAssertEqual(DashboardCostProvenance.aggregate(for: [claude, staleCodex]), .realAndNotionalListPrice)

		let state = DashboardState(
			rows: [claude, staleCodex],
			aggregateSeries: [5, 45],
			aggregateToday: 10,
			aggregateWeek: 50,
			aggregateCostProvenance: DashboardCostProvenance.aggregate(for: [claude, staleCodex]),
			refreshStatus: .failed(message: "Codex refresh failed", lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		XCTAssertTrue(state.hasContributingData)
		XCTAssertEqual(state.weeklyShare(staleCodex), 0.6, accuracy: 0.001)
		XCTAssertEqual(state.aggregateCurrencyCode, "USD")
	}

	func testApplyingRefreshKeepsAStaleSelectedProvider() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
		let previous = DashboardState(
			rows: [claude, codex],
			aggregateSeries: [5, 45], aggregateToday: 10, aggregateWeek: 50,
			aggregateCostProvenance: .realAndNotionalListPrice,
			refreshStatus: .refreshing(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedId: "codex", selectedDays: 14)

		let staleCodex = codex.markingStale()
		let next = previous.applyingRefresh(
			rows: [claude, staleCodex],
			aggregateSeries: [5, 45], aggregateToday: 10, aggregateWeek: 50,
			aggregateCostProvenance: .realAndNotionalListPrice,
			errorMessage: "Codex refresh failed",
			now: Date(timeIntervalSince1970: 200))

		XCTAssertEqual(next.selectedId, "codex", "a stale provider stays selectable and selected")
		XCTAssertEqual(next.selectedName, "Codex")
	}

	func testAllProvidersUnavailableLabelsBasisHonestlyInsteadOfRealSpend() {
		let unavailableClaude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
			.markingUnavailable(days: 14)
		let unavailableCodex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
			.markingUnavailable(days: 14)
		let state = DashboardState(
			rows: [unavailableClaude, unavailableCodex],
			aggregateSeries: [0, 0], aggregateToday: 0, aggregateWeek: 0,
			aggregateCostProvenance: DashboardCostProvenance.aggregate(for: [unavailableClaude, unavailableCodex]),
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		XCTAssertTrue(state.hasData)
		XCTAssertFalse(state.hasContributingData)
		XCTAssertEqual(state.selectedBasisLabel, "SOURCES UNAVAILABLE · TODAY")
	}

	func testFreshnessReportsFailedRefreshInsteadOfMasqueradingAsFresh() {
		let lastGood = Date(timeIntervalSince1970: 100)
		let failed = DashboardFreshness.evaluate(
			refreshStatus: .failed(message: "Claude refresh failed", lastRefresh: lastGood),
			now: Date(timeIntervalSince1970: 280))
		XCTAssertEqual(failed.kind, .failed)
		XCTAssertEqual(failed.footerText, "Refresh failed · updated 3m ago")

		let failedNoHistory = DashboardFreshness.evaluate(
			refreshStatus: .failed(message: "Claude refresh failed", lastRefresh: nil),
			now: Date(timeIntervalSince1970: 280))
		XCTAssertEqual(failedNoHistory.kind, .failed)
		XCTAssertEqual(failedNoHistory.footerText, "Refresh failed")
	}

	func testApplyingRefreshFailurePreservesLastGoodRefreshTime() {
		let previous = DashboardState(
			rows: [providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])],
			aggregateSeries: [2, 18], aggregateToday: 4, aggregateWeek: 20,
			aggregateCostProvenance: .realSpend,
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
			selectedDays: 14)

		let next = previous.applyingRefresh(
			rows: previous.rows,
			aggregateSeries: [2, 18], aggregateToday: 4, aggregateWeek: 20,
			aggregateCostProvenance: .realSpend,
			errorMessage: "Claude refresh failed: boom",
			now: Date(timeIntervalSince1970: 999))

		XCTAssertEqual(next.refreshError, "Claude refresh failed: boom")
		XCTAssertEqual(
			next.lastRefresh, Date(timeIntervalSince1970: 100),
			"a failed refresh must not advance the last-good timestamp")
	}

	func testSurfaceSizingSignatureTracksAvailabilityAndNotice() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)
		func state(rows: [DashboardViewModel.ProviderRow], notice: String?, selectedId: String? = nil) -> DashboardState {
			DashboardState(
				rows: rows, aggregateSeries: [5, 45], aggregateToday: 10, aggregateWeek: 50,
				aggregateCostProvenance: .realAndNotionalListPrice,
				refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 100)),
				selectedId: selectedId, selectedDays: 14, providerAvailabilityNotice: notice)
		}

		let allAvailable = state(rows: [claude, codex], notice: nil)
		let oneUnavailable = state(rows: [claude, codex.markingUnavailable(days: 14)], notice: "Codex unavailable; …")
		XCTAssertNotEqual(
			allAvailable.surfaceSizingSignature, oneUnavailable.surfaceSizingSignature,
			"availability + notice change the card height and must resize the AppKit window")

		// The notice only renders in the All-providers view, so folding it in while a provider is selected
		// must NOT change the signature (no spurious resize).
		let selectedNoNotice = state(rows: [claude, codex], notice: nil, selectedId: "claude")
		let selectedWithNotice = state(rows: [claude, codex], notice: "Codex unavailable; …", selectedId: "claude")
		XCTAssertEqual(selectedNoNotice.surfaceSizingSignature, selectedWithNotice.surfaceSizingSignature)
	}

	func testChartAccessibilityLabelSpeaksTheNoticeOnlyForTheAggregate() {
		let base = "All providers spend, last 14 days, $10.00"
		let notice = "Codex unavailable; aggregate excludes it until its log folder returns."

		XCTAssertEqual(
			DashboardState.chartAccessibilityLabel(base: base, notice: notice, isAllSelected: true),
			"\(base). \(notice)")
		XCTAssertEqual(
			DashboardState.chartAccessibilityLabel(base: base, notice: notice, isAllSelected: false), base)
		XCTAssertEqual(
			DashboardState.chartAccessibilityLabel(base: base, notice: nil, isAllSelected: true), base)
	}

	func testAvailabilityReconcileKeepsStillUnavailableProviderWithoutRepeatingTransitionNotice() {
		let unavailableCodex = providerRow(
			id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true
		).markingUnavailable(days: 14)

		let result = DashboardViewModel.reconcileProviderAvailability(
			rows: [],
			previousRows: [unavailableCodex],
			hadPreviousRefresh: true,
			unavailableProviderIDs: ["codex"],
			days: 14)

		XCTAssertEqual(result.rows.map(\.id), ["codex"])
		XCTAssertEqual(result.rows.first?.availability, .unavailable)
		XCTAssertNil(result.notice)
	}

	func testAvailabilityReconcileRemovesDisabledProviderEntirelyButStillAnnouncesIt() {
		let codex = providerRow(id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true)

		let result = DashboardViewModel.reconcileProviderAvailability(
			rows: [],
			previousRows: [codex],
			hadPreviousRefresh: true,
			unavailableProviderIDs: ["codex"],
			disabledProviderIDs: ["codex"],
			days: 14)

		// A user-disabled provider (Settings toggle off) is fully removed from the view — mirrors
		// Copilot's "off means gone" behavior — rather than kept as a zeroed/badged row.
		XCTAssertTrue(result.rows.isEmpty)
		XCTAssertEqual(result.notice, "Codex disabled in Settings; aggregate excludes it until re-enabled.")
	}

	@MainActor func testWidgetSnapshotKeepsCopilotAsTokenEstimateWithoutChangingDollarAggregate() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		var copilot = providerRow(
			id: "copilot", name: "GitHub Copilot", today: 0, window: 0, series: [], isAggregable: false)
		copilot.tokenSeries = [1200, 3400]
		let state = DashboardState(
			rows: [claude, copilot], aggregateSeries: [2, 18], aggregateToday: 4,
			aggregateWeek: 20, aggregateCostProvenance: .realSpend,
			refreshStatus: .idle(lastRefresh: Date()), selectedDays: 14)
		let snapshot = DashboardWidgetPublisher.makeSnapshot(
			from: state, index: nil, access: .premium, now: Date())

		XCTAssertEqual(snapshot.totalToday, 4)
		XCTAssertEqual(snapshot.metric, .dollars)
		XCTAssertEqual(snapshot.providers.map(\.id), ["claude", "copilot"])
		XCTAssertEqual(snapshot.providers.last?.metric, .tokens)
		XCTAssertEqual(snapshot.providers.last?.series, [1200, 3400])
		XCTAssertEqual(Set(snapshot.windows.keys), Set([7, 14, 30, 90]))
		XCTAssertNotNil(snapshot.windows[14]?.providerWindows["copilot"])
	}

	@MainActor func testLocalAutomationSnapshotFromDashboardStateExcludesUnavailableButKeepsStaleRows() {
		let claude = providerRow(id: "claude", name: "Claude Code", today: 4, window: 20, series: [2, 18])
		let staleCodex = providerRow(
			id: "codex", name: "Codex", today: 6, window: 30, series: [3, 27], notional: true, usedPct: 82,
			usageOfficial: true
		).markingStale()
		let unavailableGemini = providerRow(
			id: "gemini", name: "Gemini", today: 9, window: 90, series: [45, 45], notional: true
		).markingUnavailable(days: 14)
		let state = DashboardState(
			rows: [claude, staleCodex, unavailableGemini],
			aggregateSeries: [5, 45],
			aggregateToday: 10,
			aggregateWeek: 50,
			aggregateCostProvenance: .realAndNotionalListPrice,
			refreshStatus: .idle(lastRefresh: Date(timeIntervalSince1970: 1_783_425_600)),
			selectedDays: 14,
			providerAvailabilityNotice: "Gemini unavailable; aggregate excludes it until its log folder returns.")

		let snapshot = DashboardWidgetPublisher.makeAutomationSnapshot(from: state)

		XCTAssertEqual(snapshot.generatedAt, Date(timeIntervalSince1970: 1_783_425_600))
		XCTAssertEqual(snapshot.providers.map(\.id), ["claude", "codex"])
		XCTAssertEqual(snapshot.totalToday, 10, accuracy: 0.001)
		XCTAssertEqual(snapshot.totalWindow, 50, accuracy: 0.001)
		XCTAssertEqual(snapshot.costBasis, .realAndNotionalListPrice)
		XCTAssertEqual(snapshot.rateLimits["codex"]?.primary5h?.usedPercent, 82)
		XCTAssertEqual(snapshot.notice, "Gemini unavailable; aggregate excludes it until its log folder returns.")
	}

	/// A measured gateway window must never reach the widget as an OFFICIAL limit: the widget renders a
	/// limit capsule and speaks "N% used" only for `usageOfficial` rows, and a published-cap measurement
	/// is not a provider-reported percentage.
	@MainActor func testWidgetAndAutomationTreatAMeasuredGatewayWindowAsNotOfficial() {
		let go = providerRow(
			id: "opencodego", name: "OpenCode Go", today: 0.38, window: 0.9,
			series: [0.1, 0.14, 0.12], notional: true, usedPct: 12, quotaIsMeasured: true,
			monthlyUsedPct: 2, isAggregable: false)
		let state = DashboardState(
			rows: [go], aggregateSeries: [0.1, 0.14, 0.12], aggregateToday: 0.38, aggregateWeek: 0.9,
			aggregateCostProvenance: .realSpend,
			refreshStatus: .idle(lastRefresh: Date()), selectedDays: 14)

		let widget = DashboardWidgetPublisher.makeSnapshot(
			from: state, index: nil, access: .premium, now: Date())
		let row = widget.providers.first { $0.id == "opencodego" }
		XCTAssertNotNil(row?.usedPercent)
		XCTAssertEqual(row?.usageOfficial, false)

		let automation = DashboardWidgetPublisher.makeAutomationSnapshot(from: state)
		XCTAssertEqual(automation.rateLimits["opencodego"]?.primary5h?.official, false)
	}

	func testClaudeWeeklyGaugeReadsAllModelsOnlyBesideAModelWindow() {
		var claude = providerRow(
			id: "claude", name: "Claude Code", today: 1, window: 2, series: [1],
			weeklyUsedPct: 71, usageOfficial: true)
		XCTAssertEqual(claude.weeklyGaugeLabel(), "7-day window used")
		claude.modelWindows = [
			ModelScopedRateLimitWindow(
				key: "model_scoped:Fable",
				window: RateLimitWindow(usedPercent: 96, windowMinutes: 10080, resetsAt: .distantFuture),
				displayName: "Fable"),
		]
		XCTAssertEqual(claude.weeklyGaugeLabel(), "All models")
		XCTAssertEqual(claude.modelWindows[0].label, "Fable")

		var codex = providerRow(
			id: "codex", name: "Codex", today: 1, window: 2, series: [1],
			weeklyUsedPct: 40, usageOfficial: true)
		codex.modelWindows = claude.modelWindows
		XCTAssertEqual(codex.weeklyGaugeLabel(), "7-day window used")
	}

	private func providerRow(
		id: String,
		name: String,
		today: Double,
		window: Double,
		series: [Double],
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
		notional: Bool = false,
		usedPct: Double? = nil,
		weeklyUsedPct: Double? = nil,
		usageOfficial: Bool = false,
		quotaIsMeasured: Bool = false,
		monthlyUsedPct: Double? = nil,
		isAggregable: Bool = true,
		estimatedSharePct: Double? = nil
	) -> DashboardViewModel.ProviderRow {
		// A measured window publishes a cap but NO reset boundary, so it must resolve without one.
		let hasWindow = usedPct != nil || weeklyUsedPct != nil
		return DashboardViewModel.ProviderRow(
			id: id,
			name: name,
			tintHex: "#000000",
			currencyCode: currencyCode,
			today: today,
			week: window,
			todayUsage: TokenUsage(input: 1, output: 1),
			weekUsage: TokenUsage(input: 2, output: 2),
			todayEvents: 1,
			weekEvents: 2,
			series: series,
			notional: notional,
			usedPct: usedPct,
			weeklyUsedPct: weeklyUsedPct,
			estimatedSharePct: estimatedSharePct,
			usageOfficial: usageOfficial,
			quotaIsMeasured: quotaIsMeasured,
			planLabel: nil,
			unpricedModels: [],
			byModel7d: [],
			cacheSavings7d: nil,
			resetsAt5h: usageOfficial ? .distantFuture : nil,
			resetsAtWeekly: nil,
			windowMinutes5h: hasWindow ? 300 : nil,
			windowMinutesWeekly: weeklyUsedPct != nil ? 10080 : nil,
			monthlyUsedPct: monthlyUsedPct,
			monthlyWindowMinutes: monthlyUsedPct != nil ? 43200 : nil,
			isAggregable: isAggregable)
	}
}
