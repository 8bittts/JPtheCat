import Foundation
import JPtheCatCore

enum DashboardCostProvenance: Equatable, Sendable {
	case realSpend
	case notionalListPrice
	case realAndNotionalListPrice

	var includesNotional: Bool {
		switch self {
		case .realSpend:
			false
		case .notionalListPrice, .realAndNotionalListPrice:
			true
		}
	}

	var basisLabel: String {
		switch self {
		case .realSpend:
			"REAL SPEND · TODAY"
		case .notionalListPrice:
			"NOTIONAL LIST-PRICE · TODAY"
		case .realAndNotionalListPrice:
			"REAL + NOTIONAL LIST-PRICE · TODAY"
		}
	}

	static func aggregate(for rows: [DashboardViewModel.ProviderRow]) -> DashboardCostProvenance {
		let contributingRows = rows.filter(\.contributesToAggregate)
		guard contributingRows.contains(where: \.notional) else { return .realSpend }
		guard contributingRows.contains(where: { !$0.notional }) else { return .notionalListPrice }
		return .realAndNotionalListPrice
	}

	var menuBarTooltipCostBasis: MenuBarTooltipCostBasis {
		switch self {
		case .realSpend:
			.realSpend
		case .notionalListPrice:
			.notionalListPrice
		case .realAndNotionalListPrice:
			.realAndNotionalListPrice
		}
	}
}

enum DashboardRefreshStatus: Equatable, Sendable {
	case idle(lastRefresh: Date?)
	case refreshing(lastRefresh: Date?)
	case failed(message: String, lastRefresh: Date?)

	var isRefreshing: Bool {
		if case .refreshing = self { return true }
		return false
	}

	var lastRefresh: Date? {
		switch self {
		case let .idle(lastRefresh), let .refreshing(lastRefresh), let .failed(_, lastRefresh):
			lastRefresh
		}
	}

	var errorMessage: String? {
		if case let .failed(message, _) = self { return message }
		return nil
	}
}

struct DashboardFreshness: Equatable, Sendable {
	enum Kind: Equatable, Sendable {
		case refreshing
		case current
		case stale
		/// The last refresh threw. The footer must say so rather than reading "Updated just now" as if the
		/// refresh had succeeded — the age reflects the last GOOD refresh, not the failed attempt.
		case failed
	}

	static let staleAfter: TimeInterval = 5 * 60

	var kind: Kind
	var ageText: String

	var footerText: String {
		switch kind {
		case .refreshing:
			"Refreshing…"
		case .current:
			"Updated \(ageText)"
		case .stale:
			"Data may be stale · updated \(ageText)"
		case .failed:
			ageText.isEmpty ? "Refresh failed" : "Refresh failed · updated \(ageText)"
		}
	}

	static func evaluate(
		refreshStatus: DashboardRefreshStatus,
		now: Date,
		staleAfter: TimeInterval = DashboardFreshness.staleAfter
	) -> DashboardFreshness {
		if refreshStatus.isRefreshing {
			return DashboardFreshness(kind: .refreshing, ageText: "")
		}

		if case .failed = refreshStatus {
			guard let lastRefresh = refreshStatus.lastRefresh else {
				return DashboardFreshness(kind: .failed, ageText: "")
			}
			return DashboardFreshness(kind: .failed, ageText: formatElapsed(max(0, now.timeIntervalSince(lastRefresh))))
		}

		guard let lastRefresh = refreshStatus.lastRefresh else {
			return DashboardFreshness(kind: .current, ageText: "just now")
		}

		let elapsed = max(0, now.timeIntervalSince(lastRefresh))
		let kind: Kind = elapsed >= staleAfter ? .stale : .current
		return DashboardFreshness(kind: kind, ageText: formatElapsed(elapsed))
	}

	private static func formatElapsed(_ seconds: TimeInterval) -> String {
		let wholeSeconds = Int(seconds)
		if wholeSeconds < 5 { return "just now" }
		if wholeSeconds < 60 { return "\(wholeSeconds)s ago" }
		let minutes = wholeSeconds / 60
		if minutes < 60 { return "\(minutes)m ago" }
		let hours = minutes / 60
		if hours < 24 { return "\(hours)h ago" }
		return "\(hours / 24)d ago"
	}
}

struct DashboardState: Sendable {
	var rows: [DashboardViewModel.ProviderRow]
	var aggregateSeries: [Double]
	var aggregateToday: Double
	var aggregateWeek: Double
	var aggregateCostProvenance: DashboardCostProvenance
	var refreshStatus: DashboardRefreshStatus
	var selectedId: String?
	var selectedDays: Int
	var providerAvailabilityNotice: String?

	init(
		rows: [DashboardViewModel.ProviderRow] = [],
		aggregateSeries: [Double] = [],
		aggregateToday: Double = 0,
		aggregateWeek: Double = 0,
		aggregateCostProvenance: DashboardCostProvenance = .realSpend,
		refreshStatus: DashboardRefreshStatus = .idle(lastRefresh: nil),
		selectedId: String? = nil,
		selectedDays: Int,
		providerAvailabilityNotice: String? = nil
	) {
		self.rows = rows
		self.aggregateSeries = aggregateSeries
		self.aggregateToday = aggregateToday
		self.aggregateWeek = aggregateWeek
		self.aggregateCostProvenance = aggregateCostProvenance
		self.refreshStatus = refreshStatus
		self.selectedId = selectedId.map(ProviderID.consolidatedRawID)
		self.selectedDays = selectedDays
		self.providerAvailabilityNotice = providerAvailabilityNotice
	}

	var hasData: Bool { !rows.isEmpty }
	var isRefreshing: Bool { refreshStatus.isRefreshing }
	var lastRefresh: Date? { refreshStatus.lastRefresh }
	var refreshError: String? { refreshStatus.errorMessage }
	var aggregateIncludesNotional: Bool { aggregateCostProvenance.includesNotional }

	var selectedRow: DashboardViewModel.ProviderRow? {
		selectedId.flatMap { id in rows.first { $0.id == id && $0.isSelectable } }
	}

	var isAllSelected: Bool { selectedId == nil }
	var selectedName: String { selectedRow?.name ?? "All providers" }
	/// A selected provider never inherits the aggregate figures — `today: nil` (plan-only Grok Bot) is
	/// not "fall back to All providers' total".
	var selectedToday: Double {
		if let row = selectedRow { return row.today ?? 0 }
		return aggregateToday
	}
	var selectedWeek: Double {
		if let row = selectedRow { return row.week }
		return aggregateWeek
	}
	var selectedSeries: [Double] {
		if let row = selectedRow { return row.series }
		return aggregateSeries
	}
	var selectedCostProvenance: DashboardCostProvenance { selectedRow?.costProvenance ?? aggregateCostProvenance }
	var selectedNotional: Bool { selectedCostProvenance.includesNotional }

	/// At least one row is available or stale — i.e. the aggregate reflects a real source. When rows exist
	/// but none contribute (every provider's log source vanished), surfaces must NOT imply "$0 spend".
	var hasContributingData: Bool { rows.contains(where: \.isContributing) }

	var selectedBasisLabel: String {
		if let row = selectedRow, let planHero = row.heroBasisLabel() {
			return planHero
		}
		if selectedRow?.usesTokenDisplay == true {
			return "LOCAL TOKENS · TODAY"
		}
		// All-providers view where every source is unavailable: the aggregate is $0 only because there is no
		// source, so label it honestly instead of asserting "REAL SPEND · TODAY".
		if isAllSelected, hasData, !hasContributingData {
			return "SOURCES UNAVAILABLE · TODAY"
		}
		return selectedCostProvenance.basisLabel
	}

	var aggregateCurrencyCode: String {
		let codes = Set(rows.filter(\.contributesToAggregate).map(\.currencyCode))
		return codes.count == 1 ? (codes.first ?? MoneyFormatter.baseCurrencyCode) : MoneyFormatter.baseCurrencyCode
	}

	func weeklyShare(_ row: DashboardViewModel.ProviderRow) -> Double {
		row.contributesToAggregate && aggregateWeek > 0
			? min(1, max(0, row.week / aggregateWeek)) : 0
	}

	func selectorMeterFraction(_ row: DashboardViewModel.ProviderRow) -> Double {
		if let meter = row.selectorPlanMeter() { return meter.usedPercent / 100 }
		return (row.selectorQuota()?.percent ?? 0) / 100
	}

	func selectorMeterDescription(_ row: DashboardViewModel.ProviderRow) -> String {
		guard row.isContributing else { return "Unavailable" }
		if let meter = row.selectorPlanMeter() {
			return "\(roundedPct(meter.usedPercent)) of \(meter.label) used — official \(row.name) plan usage"
		}
		if let quota = row.selectorQuota() {
			let window = windowName(quota.minutes, fallback: quota.weekly ? "weekly" : "5-hour")
			if quota.measured {
				// A gateway's bar is local cost against the provider's PUBLISHED cap, not a
				// provider-reported percentage — and OpenCode publishes no reset boundary, so there is
				// no countdown to promise.
				return "Measured \(roundedPct(quota.percent)) of the \(window) cap used — local usage, no provider reset reported"
			}
			return "\(roundedPct(quota.percent)) of \(window) window used"
		}
		return row.usesTokenDisplay
			? "Local token activity, last \(selectedDays) days — quota unavailable"
			: "\(row.notional ? "Notional cost" : "Spend") activity, last \(selectedDays) days — quota unavailable"
	}

	private func roundedPct(_ value: Double) -> String {
		"\(Int(value.rounded()))%"
	}

	private func windowName(_ minutes: Int?, fallback: String) -> String {
		switch minutes {
		case 300: "5-hour"
		case 10080: "weekly"
		default: fallback
		}
	}

	func selecting(_ id: String?) -> DashboardState {
		var next = self
		next.selectedId = id.map(ProviderID.consolidatedRawID)
		return next
	}

	func selectingDays(_ days: Int) -> DashboardState {
		var next = self
		next.selectedDays = days
		return next
	}

	func refreshing() -> DashboardState {
		withRefreshStatus(.refreshing(lastRefresh: lastRefresh))
	}

	func idleIfRefreshing() -> DashboardState {
		isRefreshing ? withRefreshStatus(.idle(lastRefresh: lastRefresh)) : self
	}

	func applyingRefresh(
		rows: [DashboardViewModel.ProviderRow],
		aggregateSeries: [Double],
		aggregateToday: Double,
		aggregateWeek: Double,
		aggregateCostProvenance: DashboardCostProvenance,
		providerAvailabilityNotice: String? = nil,
		errorMessage: String?,
		now: Date
	) -> DashboardState {
		var next = self
		next.rows = rows
		next.aggregateSeries = aggregateSeries
		next.aggregateToday = aggregateToday
		next.aggregateWeek = aggregateWeek
		next.aggregateCostProvenance = aggregateCostProvenance
		next.providerAvailabilityNotice = providerAvailabilityNotice
		// On failure, keep the LAST GOOD refresh time (don't stamp `now`) so the footer reads
		// "Refresh failed · updated 2m ago" instead of masquerading as a fresh "Updated just now".
		next.refreshStatus =
			errorMessage.map { .failed(message: $0, lastRefresh: self.lastRefresh) } ?? .idle(lastRefresh: now)
		if let selectedId, !rows.contains(where: { $0.id == selectedId && $0.isSelectable }) {
			next.selectedId = nil
		}
		return next
	}

	private func withRefreshStatus(_ refreshStatus: DashboardRefreshStatus) -> DashboardState {
		var next = self
		next.refreshStatus = refreshStatus
		return next
	}

	/// The data half of `DashboardView.surfaceSizingKey` — everything that can change the card's intrinsic
	/// height. Kept here (not just inline in the view) so it is behaviorally testable and so provider
	/// availability, the exclusion notice, and the height-affecting detail toggles all resize the AppKit
	/// window. The notice only folds in for the All-providers view (it doesn't render on a provider face),
	/// so selecting a provider while a notice is set does not fire a spurious resize.
	var surfaceSizingSignature: String {
		let rowShape = rows.map { row in
			[
				row.id,
				String(describing: row.availability),
				String(row.byModel7d.count),
				String(row.unpricedModels.count),
				String(row.usedPct != nil),
				String(row.weeklyUsedPct != nil),
				String(row.resetsAt5h != nil),
				String(row.resetsAtWeekly != nil),
				String(row.monthlyUsedPct != nil),
				String(row.week > 0),
			].joined(separator: ":")
		}
		.joined(separator: "|")
		let notice = isAllSelected ? (providerAvailabilityNotice ?? "") : ""
		return "\(hasData)-\(selectedId ?? "all")-\(selectedDays)-\(notice)-\(rowShape)"
	}

	/// VoiceOver label for the trend chart. Pure + static so the "same words visible users see" contract is
	/// asserted behaviorally instead of by grepping the view source. The exclusion notice is spoken only in
	/// the All-providers view, mirroring where it renders.
	static func chartAccessibilityLabel(base: String, notice: String?, isAllSelected: Bool) -> String {
		guard isAllSelected, let notice else { return base }
		return "\(base). \(notice)"
	}
}

extension DashboardViewModel.ProviderRow {
	var isAvailable: Bool { availability == .available }

	/// Only a current window can own the selector's quota-shaped meter — either an OFFICIAL one (the
	/// provider reported the percentage and its reset is still ahead) or a MEASURED one (a gateway's
	/// local cost against the provider's published cap, which has no reset boundary to age out).
	/// `measured` is carried out so every consumer labels the bar honestly instead of calling it
	/// official; a self-relative activity share is still never quota-shaped.
	func selectorQuota(now: Date = Date())
		-> (percent: Double, minutes: Int?, weekly: Bool, measured: Bool)?
	{
		if usageOfficial {
			if let usedPct, let resetsAt5h, resetsAt5h > now, usedPct.isFinite {
				return (min(100, max(0, usedPct)), windowMinutes5h, false, false)
			}
			if let weeklyUsedPct, let resetsAtWeekly, resetsAtWeekly > now, weeklyUsedPct.isFinite {
				return (min(100, max(0, weeklyUsedPct)), windowMinutesWeekly, true, false)
			}
			return nil
		}
		guard isContributing, quotaIsMeasured else { return nil }
		if let usedPct, usedPct.isFinite {
			return (min(100, max(0, usedPct)), windowMinutes5h, false, true)
		}
		if let weeklyUsedPct, weeklyUsedPct.isFinite {
			return (min(100, max(0, weeklyUsedPct)), windowMinutesWeekly, true, true)
		}
		return nil
	}

	/// Official billing-cycle fallback only when no current weekly/5-hour window exists.
	/// Never let a fuller monthly pool displace the primary weekly quota.
	func selectorPlanMeter(now: Date = Date()) -> CursorPlanMeter? {
		guard isContributing, selectorQuota(now: now) == nil else { return nil }
		return cursorPlan?.current(at: now)?.primaryMeter
	}

	func selectorTrendSeries(now: Date = Date()) -> [Double]? {
		if isOfficialPlanOnly { return nil }
		guard selectorQuota(now: now) == nil, selectorPlanMeter(now: now) == nil else { return nil }
		return usesTokenDisplay ? tokenSeries : series
	}

	var isOfficialPlanOnly: Bool {
		ProviderBasis.of(rawID: id) == .officialPlan ||
			(todayEvents == 0 && weekEvents == 0 && todayUsage.total == 0 && weekUsage.total == 0
				&& (usageOfficial || cursorPlan != nil || officialPlanExpected))
	}

	/// Only secondary pools belong below a plan-only hero; weekly already occupies usageWindows
	/// for a mixed local-activity row. Stable keys, not equal percentages, identify duplicate pools.
	func detailPlanMeters(now: Date = Date()) -> [CursorPlanMeter] {
		let meters = cursorPlan?.current(at: now)?.meters ?? []
		return meters.filter { meter in
			if meter.key == CursorPlanMeter.grokBotKey && weeklyUsedPct != nil { return false }
			if heroShowsOfficialPlanUsage(), meter.key == selectorPlanMeter(now: now)?.key {
				return false
			}
			return true
		}
	}

	/// A shared-plan section already names the plan. Its individual pools name only the window.
	func detailWindowLabel(_ minutes: Int?, fallback: String) -> String {
		let base: String
		switch minutes {
		case 300: base = "5-hour"
		case 10080: base = "7-day"
		default: base = fallback
		}
		if id == "grok", cursorPlan != nil {
			return minutes == 10080 ? "Weekly included usage" : "\(base) window used"
		}
		let prefix = planLabel.map { "\($0.prefix(1).uppercased())\($0.dropFirst()) · " } ?? ""
		return "\(prefix)\(base) window used"
	}

	var detailShowsPrimaryWindow: Bool { !isOfficialPlanOnly }
	var detailShowsWeeklyWindow: Bool { !isOfficialPlanOnly || usedPct != nil }
	var primaryPlanPercent: Double? { selectorQuota()?.percent ?? selectorPlanMeter()?.usedPercent }
	var primaryPlanReset: Date? { selectorQuota()?.weekly == true ? resetsAtWeekly : (resetsAt5h ?? selectorPlanMeter()?.resetsAt) }
	var primaryPlanWindowLabel: String {
		if let quota = selectorQuota() { return quota.weekly ? "7-day window" : "5-hour window" }
		if let meter = selectorPlanMeter() { return meter.key == CursorPlanMeter.grokBotKey ? "7-day window" : "Billing-cycle window" }
		return "Awaiting official plan usage"
	}

	func heroFooterCaption(now: Date = Date()) -> String? {
		guard heroShowsOfficialPlanUsage() else { return nil }
		return ProviderRelativeReset.resetsInPhrase(until: primaryPlanReset, now: now) ?? primaryPlanWindowLabel
	}

	/// Right-column selector amount for plan-only Grok: official weekly included-usage % instead of
	/// a dead em dash (no local dollar or token ledger on the Mac).
	func selectorTrailingAmount(now: Date = Date()) -> String? {
		guard isOfficialPlanOnly, isContributing else { return nil }
		return (selectorQuota(now: now)?.percent ?? selectorPlanMeter(now: now)?.usedPercent).map { "\(Int($0.rounded()))%" } ?? "—"
	}

	/// Selector badge when official plan usage is the row's only signal.
	func selectorOfficialPlanBadge() -> String? {
		guard isOfficialPlanOnly, isAvailable else { return nil }
		return ProviderBasis.officialPlan.badge
	}

	/// With no local usage ledger, the hero surfaces official included usage instead of a
	/// fabricated zero-dollar chart, including while a newly reset window awaits refresh.
	func heroShowsOfficialPlanUsage() -> Bool { isOfficialPlanOnly }

	func heroPrimaryTextOverride(now: Date = Date()) -> String? {
		guard heroShowsOfficialPlanUsage() else { return nil }
		return (selectorQuota(now: now)?.percent ?? selectorPlanMeter(now: now)?.usedPercent).map { "\(Int($0.rounded()))%" } ?? "—"
	}

	func heroBasisLabel(now: Date = Date()) -> String? {
		guard heroShowsOfficialPlanUsage() else { return nil }
		return selectorQuota(now: now)?.weekly == true || selectorPlanMeter(now: now)?.key == CursorPlanMeter.grokBotKey
			? "OFFICIAL PLAN USAGE · WEEKLY" : "OFFICIAL PLAN USAGE"
	}

	func heroSecondaryCaption() -> String? {
		guard heroShowsOfficialPlanUsage() else { return nil }
		return planLabel ?? "Official included usage"
	}

	func heroChartQuotaFraction(now: Date = Date()) -> Double? {
		guard heroShowsOfficialPlanUsage() else { return nil }
		let pct = selectorQuota(now: now)?.percent ?? selectorPlanMeter(now: now)?.usedPercent ?? 0
		return min(1, max(0, pct / 100))
	}

	/// Free Big Pickle activity remains visible without changing its zero-dollar accounting.
	/// A GATEWAY (OpenCode Zen) whose window cost is $0 while it clearly saw activity is the same
	/// situation — its models are free, so the dollar figure is a dead `$0.00` and tokens are the
	/// honest readout. `isFullyUnpriced` misses this because `big-pickle` carries an explicit $0 price.
	var usesTokenDisplay: Bool {
		ProviderBasis.of(rawID: id).showsTokens || isFullyUnpriced || (id == "big_pickle" && week == 0)
			|| (ProviderBasis.of(rawID: id) == .gateway && week == 0 && weekEvents > 0)
	}

	/// True when EVERY model this row saw this window is unpriced — its dollar total is a dead `$0.00`
	/// and its cost sparkline is a flat line, both misleading. When true, the UI shows token counts
	/// (which ARE real data) instead of the dollar figures (which are not). A row with a MIX of priced
	/// and unpriced models stays dollar-based — its dollar total is real, just an undercount, which the
	/// existing "Unpriced models omitted from cost" note already discloses correctly.
	var isFullyUnpriced: Bool {
		weekEvents > 0 && !byModel7d.isEmpty && byModel7d.allSatisfy { $0.cost == nil }
	}

	/// Contributes its dollars/usage to the aggregate: fresh `available` rows and last-good `stale` rows do;
	/// `unavailable` (directory-gone) and `disabled` (user-disabled) rows do not.
	var isContributing: Bool { availability != .unavailable && availability != .disabled }

	/// THE single predicate for "belongs in the aggregate `$`/usage total": a row must both be
	/// contributing (fresh or stale, not unavailable/disabled) AND aggregable (not a non-aggregable
	/// estimate like Copilot). Every dollar-aggregate consumer must filter on this — never on
	/// `isAggregable` alone (which would fold an unavailable row into the fallback reduce) nor
	/// `isContributing` alone (which would fold a non-aggregable estimate into the real-dollar total).
	var contributesToAggregate: Bool { isContributing && isAggregable }

	/// Selectable in the row list (opens its detail). Non-contributing rows are inert; a stale row still
	/// shows its last-good detail.
	var isSelectable: Bool { isContributing }

	/// Keep the row's last-good data but flag it stale, for a provider whose directory is still present but
	/// whose index refresh threw this cycle.
	func markingStale() -> DashboardViewModel.ProviderRow {
		var copy = self
		copy.availability = .stale
		return copy
	}

	func markingUnavailable(days: Int) -> DashboardViewModel.ProviderRow {
		markingExcluded(days: days, availability: .unavailable)
	}

	func markingDisabled(days: Int) -> DashboardViewModel.ProviderRow {
		markingExcluded(days: days, availability: .disabled)
	}

	private func markingExcluded(
		days: Int,
		availability: DashboardProviderAvailability
	) -> DashboardViewModel.ProviderRow {
		// This rebuilds the row (its window-derived figures are `let`, so a copy-mutate like
		// `markingStale()` can't zero them). Any identity/classification flag NOT tied to the excluded
		// window MUST be carried over from `self` here — in particular `isAggregable`, or a
		// non-aggregable provider (e.g. Copilot) would silently flip back to aggregable when excluded.
		var row = DashboardViewModel.ProviderRow(
			id: id,
			name: name,
			tintHex: tintHex,
			availability: availability,
			currencyCode: currencyCode,
			today: nil,
			week: 0,
			todayUsage: TokenUsage(),
			weekUsage: TokenUsage(),
			todayEvents: 0,
			weekEvents: 0,
			series: Array(repeating: 0, count: max(days, 1)),
			notional: notional,
			usedPct: nil,
			weeklyUsedPct: nil,
			usageOfficial: false,
			planLabel: planLabel,
			unpricedModels: [],
			byModel7d: [],
			cacheSavings7d: nil,
			resetsAt5h: nil,
			resetsAtWeekly: nil,
			windowMinutes5h: nil,
			windowMinutesWeekly: nil)
		row.isAggregable = isAggregable
		// Same reason as `isAggregable`: the measured-vs-official provenance is a classification flag,
		// not a window figure. It carries no percentage here (the window fields above are cleared), so
		// `selectorQuota` still resolves to nil for an excluded row.
		row.quotaIsMeasured = quotaIsMeasured
		return row
	}

	var costProvenance: DashboardCostProvenance {
		notional ? .notionalListPrice : .realSpend
	}
}
