import Foundation
import JPtheCatCore
import Observation

/// Thread-safe cache for the dashboard's own `UsageIndex.windowSummaries` scan — the single largest
/// item inside `buildRefreshResult`, which otherwise runs unconditionally on BOTH the reindex path and
/// the "just re-query the DB window" fast path. Postmortem:
/// `_docs/00-foundation.md#sustained-cpu-postmortem-the-refresh-storm-2026-07-2627-shipped-v1083`.
///
/// Safe on a money surface for the same reason `MultiWindowSummaryCache` is: every event that could
/// change the answer arrives through `UsageIndex.ingest`, which bumps `generation`. The extra key
/// components close the gaps a generation alone would miss — `day` for the local-midnight rollover on an
/// idle Mac, and `pricingGeneration` for a `RemotePricingStore` hot-swap, which changes the DOLLARS
/// without touching a single event.
private final class WindowSummaryCache: @unchecked Sendable {
	struct Key: Equatable {
		let generation: Int
		let providers: [String]
		let days: Int
		let day: String
		let pricingGeneration: Int
	}
	private let lock = NSLock()
	private var lastKey: Key?
	private var lastResult: UsageWindowSummaries?

	func cached(_ key: Key) -> UsageWindowSummaries? {
		lock.lock()
		defer { lock.unlock() }
		guard lastKey == key else { return nil }
		return lastResult
	}

	func store(_ key: Key, _ result: UsageWindowSummaries) {
		lock.lock()
		defer { lock.unlock() }
		lastKey = key
		lastResult = result
	}
}

private let windowSummaryCache = WindowSummaryCache()

/// LOCAL-day cache discriminator, NOT UTC — `windowSummaries` buckets today/window/series by the LOCAL
/// calendar day, so a UTC key would serve a pre-midnight result after local midnight while the
/// generation sat unchanged overnight. `.autoupdatingCurrent` tracks a live timezone change too.
private let localDayFormatter: DateFormatter = {
	let f = DateFormatter()
	f.dateFormat = "yyyy-MM-dd"
	f.timeZone = TimeZone.autoupdatingCurrent
	f.locale = Locale(identifier: "en_US_POSIX")
	return f
}()

private func localDayKey(for date: Date) -> String { localDayFormatter.string(from: date) }

enum DashboardProviderAvailability: Equatable, Sendable {
	/// Fresh data from a successful refresh.
	case available
	/// The provider's log directory disappeared after being visible — non-contributing, shown as "—"
	/// (never "$0 today") and excluded from the aggregate.
	case unavailable
	/// The live provider is intentionally disabled in Settings. It follows the same non-contributing
	/// aggregate/widget/alert path as `unavailable`, but the user-facing copy names the setting.
	case disabled
	/// The log directory is still present but this refresh's index/parse update threw. We keep the last
	/// good row (data + contribution intact) and badge it "stale" rather than silently dropping the
	/// provider; the footer additionally reads "Refresh failed" until the next clean refresh.
	case stale
}

/// Data source for the status item and compact `DashboardView` — the native surface that mirrors the
/// marketing site's `menubar-demo.tsx`, including its interactive view-state machine: selecting
/// "All providers" (nil) vs a provider row swaps the header, the trend chart, and the detail section.
///
/// Single app-level refresh owner: Claude real dollars and Codex notional list-price dollars refresh
/// through the shared `UsageIndex`; Codex's honest headline is its file-based `rate_limits` usage.
/// Heavy work runs off the main thread; observable state mutates back on the main actor only.
@MainActor
@Observable
final class DashboardViewModel {
	/// One provider's line + its selected-window cost series. `today`/`week` are dollars (nil = no priced data).
	/// `usedPct`/`weeklyUsedPct` are rate-limit "how close to running out" percentages and are ALWAYS
	/// official when present: Codex's 5h/weekly from its rollout JSONL, or Claude's 5h/weekly from the
	/// opt-in statusline capture — both set `usageOfficial=true`. Claude is never estimated (rule (d):
	/// no capture → no gauge), so a non-official percentage is not produced; `usageOfficial` stays as a
	/// guard so any future non-official source is surfaced as absent rather than shown.
	struct ProviderRow: Identifiable, Sendable {
		var id: String
		var name: String
		var tintHex: String
		var availability: DashboardProviderAvailability = .available
		/// ISO 4217 currency the row's dollar figures are denominated in. Always "USD" today — our
		/// pricing tables are USD/token and Codex list price is USD, and the provider logs carry no
		/// native-currency field. Kept per-row so a future provider that reports a native currency only
		/// has to set a different code; all money display routes through `MoneyFormatter(code:)`.
		var currencyCode: String = MoneyFormatter.baseCurrencyCode
		let today: Double?
		let week: Double
		let todayUsage: TokenUsage
		let weekUsage: TokenUsage
		let todayEvents: Int
		let weekEvents: Int
		let series: [Double]  // selected-window daily cost, oldest → newest
		/// Selected-window daily TOTAL token count, oldest → newest — parallel to `series` but tokens
		/// instead of dollars, including free Big Pickle activity. Kept separate from `series`
		/// rather than repurposing it so cost-based aggregate math (`weeklyShare`, provenance) never
		/// accidentally reads token counts.
		var tokenSeries: [Double] = []
		let notional: Bool
		let usedPct: Double?
		let weeklyUsedPct: Double?
		/// Self-relative estimate (today's share of this row's own selected-window total, 0-100),
		/// populated for providers with no official quota % (Copilot, Muse Spark) so menu-bar rotation
		/// and the selector meter can show honest activity without fabricating a rate limit. Deliberately
		/// kept separate from `usedPct`/`weeklyUsedPct`, which are contractually "always official when
		/// present" — every consumer must label this visibly as an estimate.
		var estimatedSharePct: Double? = nil
		let usageOfficial: Bool
		/// True when `usedPct`/`weeklyUsedPct` are MEASURED local cost against the provider's published
		/// caps rather than a provider-reported percentage — today only OpenCode Go. Such a window still
		/// draws a quota-shaped meter (dashboard selector + provider detail, badged `measured`), but it is
		/// never treated as official and never carries a reset countdown, so it must stay out of the
		/// widget's official-limit capsule and the spoken "N% used" value. Always false when
		/// `usageOfficial` is true; the two are mutually exclusive.
		var quotaIsMeasured: Bool = false
		let planLabel: String?
		let unpricedModels: [String]
		/// Per-model selected-window breakdown (newest model version first). Powers the model
		/// mini-list and the "one model eats the bill" concentration insight.
		let byModel7d: [ModelLine]
		/// Real (Claude) / notional (Codex) dollars the week's cache reads saved vs full input price.
		let cacheSavings7d: Double?
		/// Codex rate-limit window metadata (nil for Claude): when each window rolls over and its
		/// nominal length, so the drawer can show a live "resets in …" countdown + burn pace.
		let resetsAt5h: Date?
		let resetsAtWeekly: Date?
		let windowMinutes5h: Int?
		let windowMinutesWeekly: Int?
		/// OpenCode Go's monthly window — the third measured usage-vs-published-cap bar, matching the
		/// provider's own console. `nil` for every other provider (and for a Go row with no capped model
		/// in the trailing month). Carries no reset: OpenCode publishes the cap, not a window boundary.
		/// Rendered in provider detail only, deliberately NOT in the menu bar or widget, which stay on
		/// the 5-hour/weekly windows a user actually budgets by.
		var monthlyUsedPct: Double? = nil
		var monthlyWindowMinutes: Int? = nil
		/// Extra OFFICIAL per-model weekly windows the provider reported alongside the plan-wide one
		/// (Claude's `seven_day_opus` = the "Fable" bar, `seven_day_sonnet`). Empty for every provider
		/// today because Claude's statusline feed does not carry them yet — empty means "not reported",
		/// never 0%. Shown in provider detail only; deliberately kept OUT of the menu bar, widget, and
		/// the 80/95% attention border, which stay on the plan-wide window a user actually budgets by.
		var modelWindows: [ModelScopedRateLimitWindow] = []
		var codexCredits: CodexCreditBalance? = nil
		var creditsCapturedAt: Date? = nil
		/// True when the official 5-hour reading is high but its capture has gone quiet — i.e. Claude is
		/// probably refusing you (rate-limited) and the frozen percentage understates reality. Only set
		/// for Claude (statusline feed); false for Codex, which reads its own always-current log.
		var limitLikelyHit: Bool = false
		/// True when this provider's official window just rolled past its reset boundary and no fresher
		/// reading has arrived — the gauge is blank because the window RESET, not because there's no data.
		/// Drives a "window reset — awaiting fresh data" hint in place of the vanished %, so an idle-past-
		/// reset gauge reads as intentional rather than randomly broken. Never carries a fabricated number.
		var awaitingResetRefresh: Bool = false
		/// False for a provider that is visible/selectable with its own real sparkline + totals but
		/// deliberately excluded from aggregate "All providers" dollar totals and alerts — e.g.
		/// Copilot's OTel-derived token estimate, which is far less precise than Claude/Codex's official
		/// accounting. Every dollar-aggregate/alert consumer must filter on this in addition
		/// to `isContributing`; `weeklyShare`/`selectorMeterFraction` fall back to a self-relative measure
		/// for non-aggregable rows since they have no shared aggregate scale to compare against.
		var isAggregable: Bool = true
		/// Optional scope disclosure for providers whose local signal is narrower than account billing
		/// (today: Muse Spark = OpenCode on this Mac only). Shown in provider detail, never in the pill.
		var sourceScopeNote: String? = nil
		/// Zen and Go inside the one OpenCode row. Empty for every other provider, and for an
		/// OpenCode row that only has one gateway. Each section keeps its own honest figures.
		var sourceSections: [ProviderRow] = []
		/// Trailing-window AIU consumption for a provider that bills in AIU (today: Copilot, from
		/// `github.copilot.nano_aiu`). A raw consumption count — NEVER dollars, NEVER a quota %. `nil`
		/// for every provider without a local AIU signal; shown in provider detail only.
		var aiuWindow: Double? = nil
		/// Unified opt-in official plan pools. Weekly quota is also projected into `weeklyUsedPct`;
		/// distinct monthly pools stay separately labeled and percentages never enter dollar totals.
		var cursorPlan: CursorPlanUsage? = nil
		var officialPlanExpected: Bool = false
	}

	/// One model's slice of the selected window. `cost` is nil when the model is unpriced (badge it,
	/// never rank at $0). Basis follows the parent row (real for Claude, notional for Codex).
	struct ModelLine: Identifiable, Sendable {
		let model: String
		let cost: Double?
		let usage: TokenUsage
		let eventCount: Int
		var id: String { model }
	}

	/// Newest model families belong at the top of the compact list, independent of how much they cost;
	/// variants within one version then follow Core's strongest-to-lightest capability order.
	nonisolated static func orderedModelLines(_ lines: [ModelLine]) -> [ModelLine] {
		lines.sorted { ModelName.sortsBeforeForCompactDisplay($0.model, $1.model) }
	}

	/// Projects a rollup's `byModel7d` into sorted `ModelLine`s and sums the week's conservative cache
	/// savings across every priced model (nil when nothing priced read from cache). `nonisolated` so the
	/// off-main-thread refresh closure can call it.
	/// Builds the selectable row for an OFFICIAL provider (Claude / Codex). Both share the identical
	/// clamp, per-model breakdown, `usageOfficial` derivation, and 23-field init; only the leading
	/// scalars differ (`id`/`name`/`tintHex`/`notional`/`planLabel`/`limitLikelyHit`). Copilot is
	/// deliberately NOT built through here — it uses a different series/`isAggregable: false` path.
	/// Self-relative activity share for menu-bar rotation when a provider has no official quota %.
	/// Dollar-based by default; token-based when every model in the window is unpriced (dead $0.00).
	nonisolated private static func estimatedSharePct(
		rollup: UsageRollup, breakdown: (lines: [ModelLine], cacheSavings: Double?)
	) -> Double? {
		let fullyUnpriced =
			rollup.last7d.eventCount > 0 && !breakdown.lines.isEmpty
			&& breakdown.lines.allSatisfy { $0.cost == nil }
		if fullyUnpriced {
			let weekTokens = rollup.last7d.usage.total
			return weekTokens > 0
				? min(100, max(0, Double(rollup.today.usage.total) / Double(weekTokens) * 100)) : nil
		}
		return rollup.last7d.cost > 0
			? min(100, max(0, rollup.today.cost / rollup.last7d.cost * 100)) : nil
	}

	/// OpenCode Go's usage windows, measured from LOCAL cost against Go's PUBLISHED per-model monthly
	/// caps (5-hour = 20% of a model's monthly limit, weekly = 50%, monthly = 100%). Each window's
	/// reported percentage is the model nearest its cap in that window — the binding constraint.
	/// OpenCode writes no local reset boundary, so `resetsAt` is nil (the window is always current):
	/// this is a documented-cap / measured-usage gauge, never a provider-reported percentage and never
	/// a synthesized countdown. Approved deliberately for the menu-bar rotation despite the app's usual
	/// "official = provider-reported" rule — see `_docs/00-foundation.md`.
	///
	/// The Core helper owns the window math; this only splits the result into the snapshot's two slots
	/// (5-hour/weekly, which the menu bar, widget, and alerts read) plus the monthly window the detail
	/// view draws as a third bar.
	nonisolated static func openCodeGoWindows(
		events: [UsageEvent], calculator: CostCalculator, now: Date = Date()
	) -> (fiveHour: RateLimitWindow?, weekly: RateLimitWindow?, monthly: RateLimitWindow?) {
		let windows = OpenCodeGoLimits.measuredWindows(
			events: events, calculator: calculator, now: now)
		func find(_ minutes: Int) -> RateLimitWindow? {
			windows.first { $0.windowMinutes == minutes }
		}
		return (
			find(OpenCodeGoLimits.fiveHourMinutes), find(OpenCodeGoLimits.weeklyMinutes),
			find(OpenCodeGoLimits.monthlyMinutes)
		)
	}

	/// One selector row. Go's measured windows own the selector when Go is present, because Zen
	/// publishes no quota. Both gateways still render in the detail when both are present.
	nonisolated static func unifiedOpenCodeRow(zen: ProviderRow?, go: ProviderRow?) -> ProviderRow? {
		guard var face = go ?? zen else { return nil }
		let sections = [zen, go].compactMap { $0 }
		face.id = "opencode"
		face.name = "OpenCode"
		face.tintHex = JPAppColor.openCodeZenTintHex
		if sections.count > 1 {
			face.sourceSections = sections.map { section in
				var copy = section
				copy.sourceScopeNote = nil
				copy.sourceSections = []
				return copy
			}
			face.sourceScopeNote = "OpenCode gateway on this Mac · Zen · Go · excluded from combined totals"
		}
		return face
	}

	nonisolated static func openCodeGoSnapshot(
		events: [UsageEvent], calculator: CostCalculator, now: Date = Date()
	) -> RateLimitSnapshot? {
		guard !events.isEmpty else { return nil }
		let windows = openCodeGoWindows(events: events, calculator: calculator, now: now)
		guard windows.fiveHour != nil || windows.weekly != nil else { return nil }
		return RateLimitSnapshot(
			primary: windows.fiveHour, secondary: windows.weekly, planType: "go", capturedAt: nil)
	}

	nonisolated private static func makeOfficialProviderRow(
		id: String,
		name: String,
		tintHex: String,
		planLabel: String?,
		limitLikelyHit: Bool,
		rollup: UsageRollup,
		indexSeries: [Double],
		events: [UsageEvent],
		days: Int,
		snapshot: RateLimitSnapshot?,
		calculator: CostCalculator,
		estimatedSharePct: Double? = nil,
		sourceScopeNote: String? = nil,
		awaitingResetRefresh: Bool = false,
		monthlyWindow: RateLimitWindow? = nil,
		indexTokenSeries: [Double]
	) -> ProviderRow {
		let breakdown = modelBreakdown(rollup, calculator: calculator)
		// Cost basis is DERIVED from Core's one `ProviderBasis` table, never a per-call-site literal —
		// a `notional:`/`isAggregable:` argument here is exactly how a new provider silently defaults
		// into being dollar-aggregable (guard: `ProviderBasisTests`).
		let basis = ProviderBasis.of(rawID: id)
		let pct = (snapshot?.primary?.usedPercent).map { min(100, max(0, $0)) }
		let weekly = (snapshot?.secondary?.usedPercent).map { min(100, max(0, $0)) }
		// A provider-reported percentage is "official"; a gateway's published-cap percentage is
		// "measured". The two are exclusive, and only `usageOfficial` may drive the widget's
		// official-limit capsule (mac/AGENTS.md: "only an official limit renders there").
		let hasWindow = pct != nil || weekly != nil
		let measured = basis == .gateway && hasWindow
		let series = resolvedDailyCostSeries(
			indexSeries: indexSeries, events: events, days: days,
			calculator: calculator, windowCost: rollup.last7d.cost)
		return ProviderRow(
			id: id, name: name, tintHex: tintHex,
			today: rollup.today.cost, week: rollup.last7d.cost,
			todayUsage: rollup.today.usage, weekUsage: rollup.last7d.usage,
			todayEvents: rollup.today.eventCount, weekEvents: rollup.last7d.eventCount,
			series: series,
			tokenSeries: resolvedDailyTokenSeries(
				indexSeries: indexTokenSeries, events: events, days: days,
				windowTokens: rollup.last7d.usage.total),
			notional: basis.isNotional, usedPct: pct, weeklyUsedPct: weekly,
			estimatedSharePct: estimatedSharePct,
			usageOfficial: hasWindow && !measured, quotaIsMeasured: measured, planLabel: planLabel,
			unpricedModels: rollup.last7d.unpricedModels.sorted(),
			byModel7d: breakdown.lines, cacheSavings7d: breakdown.cacheSavings,
			resetsAt5h: snapshot?.primary?.resetsAt,
			resetsAtWeekly: snapshot?.secondary?.resetsAt,
			windowMinutes5h: snapshot?.primary?.windowMinutes,
			windowMinutesWeekly: snapshot?.secondary?.windowMinutes,
			monthlyUsedPct: monthlyWindow?.usedPercent,
			monthlyWindowMinutes: monthlyWindow?.windowMinutes,
			modelWindows: snapshot?.modelWindows ?? [],
			codexCredits: snapshot?.credits,
			creditsCapturedAt: snapshot?.credits == nil ? nil : snapshot?.capturedAt,
			limitLikelyHit: limitLikelyHit,
			awaitingResetRefresh: awaitingResetRefresh && pct == nil && weekly == nil,
			isAggregable: basis.isAggregable,
			sourceScopeNote: sourceScopeNote)
	}

	/// Result of the off-main refresh build: the rows, aggregate figures, provenance, availability
	/// notice, error, and resolved Claude plan the main-actor completion applies to `state`.
	nonisolated struct RefreshBuild: Sendable {
		let rows: [ProviderRow]
		let aggregateSeries: [Double]
		let aggregateToday: Double
		let aggregateWeek: Double
		let aggregateCostProvenance: DashboardCostProvenance
		let availabilityNotice: String?
		let errorMessage: String?
	}

	/// Pure, off-main refresh build extracted from `refresh(reindex:)` so the row-build + aggregate
	/// math is unit-testable in isolation. Takes only value/provider inputs (no `self`), returns a
	/// `RefreshBuild`; the caller owns threading, the refresh gate, and applying the result to `state`.
	///
	/// `pricingGeneration` participates ONLY in the `windowSummaries` cache key (see
	/// `WindowSummaryCache`); it never affects the computed figures.
	///
	/// `onPartial`, when set, receives one `RefreshBuild` AFTER indexed dollars (and every
	/// non-Codex row) are ready but BEFORE `CodexProvider.latestRateLimitState` walks rollout
	/// files — and only when the previous Codex row has no official %. A warm 60s poll that
	/// already shows a Codex gauge must not publish a snapshot-nil row first. A cold process
	/// with an empty rate-limit tail cache spent minutes on that walk (debug CLI, ~2,200
	/// rollout files) while Claude skip-path reindex was 392 ms. Tests omit the callback and
	/// still get one final build that includes the walk.
	nonisolated static func buildRefreshResult(
		reindex: Bool,
		days: Int,
		calculator: CostCalculator,
		pricingGeneration: Int = 0,
		claude: ClaudeProvider,
		codex: CodexProvider,
		grok: GrokProvider,
		copilot: CopilotProvider,
		cursor: CursorProvider = CursorProvider(),
		museSpark: MuseSparkProvider,
		brands: [OpenCodeBrandProvider] = OpenCodeBrand.allCases.map { OpenCodeBrandProvider(brand: $0) },
		openCodeZen: OpenCodeProvider = OpenCodeProvider(),
		openCodeGo: OpenCodeGoProvider = OpenCodeGoProvider(),
		index: UsageIndex?,
		claudeEnabled: Bool,
		codexEnabled: Bool,
		grokEnabled: Bool,
		copilotEnabled: Bool,
		cursorEnabled: Bool = false,
		cursorPlan: CursorPlanUsage? = nil,
		grokPlanEnabled: Bool = false,
		museSparkEnabled: Bool,
		enabledBrands: Set<OpenCodeBrand> = Set(OpenCodeBrand.allCases),
		openCodeZenEnabled: Bool = true,
		openCodeGoEnabled: Bool = true,
		previousRows: [ProviderRow],
		hadPreviousRefresh: Bool,
		onPartial: (@Sendable (RefreshBuild) -> Void)? = nil
	) -> RefreshBuild {
		// NOTE: this closure runs OFF the main thread. Any `JPAppColor`/`JP.*` token read here must stay
		// theme-INDEPENDENT — the per-provider `tintHex` values below are fixed brand-color string
		// constants, safe to read off-main. `JPTheme.current` is main-thread-only; when the deferred
		// dark-tuned provider tints land, resolve them on the main actor (in the view/presentation
		// layer), never in this background build.
		var rows: [ProviderRow] = []
		var errors: [String] = []
		var liveProviderIDs: [ProviderID] = []
		var summaries: UsageWindowSummaries?
		var gatewaySummaries: UsageWindowSummaries?

		let claudeAvailable = claudeEnabled && claude.isAvailable()
		let codexAvailable = codexEnabled && codex.isAvailable()
		let grokAvailable = grokEnabled && grok.isAvailable()
		let museSparkAvailable = museSparkEnabled && museSpark.isAvailable()
		// The OpenCode model-brand rows are one table (`OpenCodeBrand`), driven identically from here
		// on: availability, disabled/unavailable bookkeeping, index refresh, and the row itself.
		let availableBrands = brands.filter { enabledBrands.contains($0.brand) && $0.isAvailable() }
		let openCodeZenAvailable = openCodeZenEnabled && openCodeZen.isAvailable()
		let openCodeGoAvailable = openCodeGoEnabled && openCodeGo.isAvailable()
		let cursorAvailable = grokEnabled && cursorEnabled && cursor.isAvailable()
		// The store owns legacy fallback; never reload old Bot data after an authoritative empty cache.
		let unifiedPlan = grokEnabled ? cursorPlan?.current() : nil
		let grokVisible = grokEnabled && (grokAvailable || cursorAvailable || unifiedPlan != nil || grokPlanEnabled)
		var unavailableProviderIDs = Set<String>()
		if !claudeAvailable { unavailableProviderIDs.insert("claude") }
		if !codexAvailable { unavailableProviderIDs.insert("codex") }
		if !grokVisible { unavailableProviderIDs.insert("grok") }
		if !museSparkAvailable { unavailableProviderIDs.insert("muse_spark") }
		for provider in brands where !availableBrands.contains(where: { $0.brand == provider.brand }) {
			unavailableProviderIDs.insert(provider.id.rawValue)
		}
		// One dashboard row. A missing gateway omits its section; it does not come back as its own row.
		if !openCodeZenAvailable && !openCodeGoAvailable { unavailableProviderIDs.insert("opencode") }
		var disabledProviderIDs = Set<String>()
		if !claudeEnabled { disabledProviderIDs.insert("claude") }
		if !codexEnabled { disabledProviderIDs.insert("codex") }
		if !grokEnabled { disabledProviderIDs.insert("grok") }
		if !museSparkEnabled { disabledProviderIDs.insert("muse_spark") }
		for provider in brands where !enabledBrands.contains(provider.brand) {
			disabledProviderIDs.insert(provider.id.rawValue)
		}
		if !openCodeZenEnabled && !openCodeGoEnabled { disabledProviderIDs.insert("opencode") }
		disabledProviderIDs.formUnion(["cursor", "grok_bot"])
		// Providers whose directory is present but whose index/parse refresh threw this cycle. Distinct
		// from `unavailableProviderIDs` (directory gone) — a transient sqlite/IO hiccup must keep the
		// last good row (marked stale), not vanish the provider + its dollars from the aggregate.
		var failedProviderIDs = Set<String>()

		if let index {
			if reindex {
				if claudeAvailable {
					liveProviderIDs.append(.claude)
					do {
						_ = try UsageIndexer(index: index).refresh(claude)
					} catch {
						errors.append("Claude refresh failed: \(error)")
						failedProviderIDs.insert("claude")
					}
				}
				if codexAvailable {
					liveProviderIDs.append(.codex)
					do {
						_ = try UsageIndexer(index: index).refresh(codex)
					} catch {
						errors.append("Codex refresh failed: \(error)")
						failedProviderIDs.insert("codex")
					}
				}
				if grokAvailable {
					liveProviderIDs.append(.grok)
					do {
						_ = try UsageIndexer(index: index).refresh(grok)
					} catch {
						errors.append("Grok refresh failed: \(error)")
						failedProviderIDs.insert("grok")
					}
				}
			if museSparkAvailable {
				liveProviderIDs.append(.museSpark)
				do {
					_ = try UsageIndexer(index: index).refresh(museSpark)
				} catch {
					errors.append("Muse Spark refresh failed: \(error)")
					failedProviderIDs.insert("muse_spark")
				}
			}
			for provider in availableBrands {
				liveProviderIDs.append(provider.id)
				do {
					_ = try UsageIndexer(index: index).refresh(provider)
				} catch {
					errors.append("\(provider.brand.displayName) refresh failed: \(error)")
					failedProviderIDs.insert(provider.id.rawValue)
				}
			}
			// OpenCode Zen / Go are indexed for Advanced Analytics + exports but deliberately NOT
			// appended to `liveProviderIDs`: that array feeds the dollar-aggregate query, and both are
			// `ProviderBasis.gateway` rollups whose usage is already summed under the model-brand rows.
			if openCodeZenAvailable {
				do { _ = try UsageIndexer(index: index).refresh(openCodeZen) } catch {
					errors.append("OpenCode Zen refresh failed: \(error)")
					failedProviderIDs.insert("opencode")
				}
			}
			if openCodeGoAvailable {
				do { _ = try UsageIndexer(index: index).refresh(openCodeGo) } catch {
					errors.append("OpenCode Go refresh failed: \(error)")
					failedProviderIDs.insert("opencodego")
				}
			}
				// Index Cursor independently; reporting projects its opted-in events into Grok once.
				if cursorAvailable {
					do {
						_ = try UsageIndexer(index: index).refresh(cursor)
					} catch {
						errors.append("Cursor refresh failed: \(error)")
						failedProviderIDs.insert("grok")
					}
				}
			} else {
				// Fast path: prior refreshes already indexed the logs; just re-query the DB window.
				if claudeAvailable { liveProviderIDs.append(.claude) }
				if codexAvailable { liveProviderIDs.append(.codex) }
				if grokAvailable { liveProviderIDs.append(.grok) }
				if museSparkAvailable { liveProviderIDs.append(.museSpark) }
				liveProviderIDs.append(contentsOf: availableBrands.map(\.id))
			}
			if cursorAvailable { liveProviderIDs.append(.cursor) }
			// Grok mid-turn overlay is not in `updates.jsonl`, so the fast path must still sync it
			// (the reindex path already ran `postRefresh` inside `UsageIndexer.refresh`). Cheap
			// when `unified.jsonl` and the involved session files have not moved.
			if grokAvailable {
				do {
					try grok.syncInProgressUsage(into: index)
				} catch {
					errors.append("Grok live usage refresh failed: \(error)")
				}
			}
			// `try?` → nil on a mid-scan SQLite error, so BOTH the per-provider (`summary?.rollup ?? …`)
			// and the aggregate (`summaries?.aggregate ?? reduce`) paths fall back to the fresh log rollup
			// consistently, instead of presenting a silently-truncated DB total as authoritative.
			// Snapshot the generation ONCE for both lookup and store, so an ingest landing mid-scan can't
			// cache generation-G data under generation-G′ (the same TOCTOU rule `MultiWindowSummaryCache`
			// documents). A `nil` (mid-scan SQLite error) is deliberately NOT cached — the next refresh
			// must re-attempt the scan rather than serve a cached failure until the generation moves.
			let summaryGeneration = index.generation
			let cacheKey = WindowSummaryCache.Key(
				generation: summaryGeneration, providers: liveProviderIDs.map(\.rawValue).sorted(),
				days: days, day: localDayKey(for: Date()), pricingGeneration: pricingGeneration)
			if let hit = windowSummaryCache.cached(cacheKey) {
				summaries = hit
			} else {
				summaries = try? index.windowSummaries(
					providers: liveProviderIDs, days: days, calculator: calculator)
				if let summaries { windowSummaryCache.store(cacheKey, summaries) }
			}
			// The gateway rows (Zen / Go) read the SAME index in a second, separately-keyed scan so
			// they never enter `summaries.aggregate` — that aggregate is the dollar total, and both are
			// `ProviderBasis.gateway` rollups already counted under the brand rows. Reading the index
			// here (instead of `loadEvents()` per refresh) is what keeps a gateway row O(window), not
			// O(lifetime message history).
			let gatewayIDs: [ProviderID] =
				(openCodeZenAvailable ? [.opencode] : []) + (openCodeGoAvailable ? [.opencodego] : [])
			if !gatewayIDs.isEmpty {
				let gatewayKey = WindowSummaryCache.Key(
					generation: summaryGeneration, providers: gatewayIDs.map(\.rawValue).sorted(),
					days: days, day: localDayKey(for: Date()), pricingGeneration: pricingGeneration)
				if let hit = windowSummaryCache.cached(gatewayKey) {
					gatewaySummaries = hit
				} else {
					gatewaySummaries = try? index.windowSummaries(
						providers: gatewayIDs, days: days, calculator: calculator)
					if let gatewaySummaries { windowSummaryCache.store(gatewayKey, gatewaySummaries) }
				}
			}
		}

		// Claude — real dollars + OFFICIAL 5h/weekly windows when the statusline capture is present
		// (`ClaudeRateLimitStore`). No capture → no gauge (never a token-based estimate: token counts
		// can't reproduce Claude's real limit %). There is deliberately NO plan-tier label: the only
		// local source was Claude Code's own OAuth Keychain item, and reading another app's Keychain
		// item makes macOS prompt for the login password on every token refresh and every JP the Cat
		// update (guard: `PlanTierKeychainReadTests`). `planLabel` stays for providers that publish a plan in their own
		// snapshot (Muse Spark).
		if claudeAvailable {
			let summary = summaries?.providers[.claude]
			let inputs = Self.resolveOfficialProviderInputs(
				summary: summary, days: days, calculator: calculator, loadEvents: claude.loadEvents)
			let snapshot = claude.latestRateLimits()
			rows.append(
				Self.makeOfficialProviderRow(
					id: "claude", name: "Claude Code", tintHex: JPAppColor.claudeTintHex,
					planLabel: nil,
					limitLikelyHit: snapshot?.likelyAtLimit() ?? false,
					rollup: inputs.rollup, indexSeries: summary?.dailyCostSeries ?? [],
					events: inputs.events, days: days,
					snapshot: snapshot, calculator: calculator,
					awaitingResetRefresh: claude.latestRateLimitAwaitingReset(now: Date()),
					indexTokenSeries: summary?.dailyTokenSeries ?? []))
		}

		// Codex — notional dollars + honest 5-hour / weekly used percentage.
		//
		// The rollout-file walk (`latestRateLimitState`) is the cold-launch bottleneck: it is
		// independent of the indexed dollar figures. When `onPartial` is set, publish a Codex row
		// with dollars and no gauge first, then replace it after the walk. ONE walk still resolves
		// both the snapshot and the awaiting-reset hint — do not split that back into two walks.
		var cachedCodexInputs: (summary: UsageWindowSummary?, rollup: UsageRollup, events: [UsageEvent])?
		func appendCodexRow(snapshot: RateLimitSnapshot?, awaitingReset: Bool) {
			if cachedCodexInputs == nil {
				let summary = summaries?.providers[.codex]
				let inputs = Self.resolveOfficialProviderInputs(
					summary: summary, days: days, calculator: calculator, loadEvents: codex.loadEvents)
				cachedCodexInputs = (summary, inputs.rollup, inputs.events)
			}
			let cached = cachedCodexInputs!
			rows.append(
				Self.makeOfficialProviderRow(
					id: "codex", name: "Codex", tintHex: JPAppColor.codexTintHex,
					planLabel: snapshot?.planType,
					limitLikelyHit: false,
					rollup: cached.rollup, indexSeries: cached.summary?.dailyCostSeries ?? [],
					events: cached.events, days: days,
					snapshot: snapshot, calculator: calculator,
					awaitingResetRefresh: awaitingReset,
					indexTokenSeries: cached.summary?.dailyTokenSeries ?? []))
		}
		var deferCodexRateLimits = false
		if codexAvailable {
			// Defer only while no official Codex windows or credits are visible. A warm poll must
			// not publish a snapshot-nil row that briefly clears either kind of account data.
			let previousCodexHasOfficialData = previousRows.contains {
				$0.id == "codex" && ($0.usedPct != nil || $0.weeklyUsedPct != nil || $0.codexCredits != nil)
			}
			if onPartial != nil && !previousCodexHasOfficialData {
				appendCodexRow(snapshot: nil, awaitingReset: false)
				deferCodexRateLimits = true
			} else {
				let codexLimits = codex.latestRateLimitState(
					now: Date(), persistedStates: try? index?.parserStates(provider: .codex))
				appendCodexRow(snapshot: codexLimits.current, awaitingReset: codexLimits.awaitingReset)
			}
		}

		// One Grok row: raw source IDs remain separate in the warehouse, summary projection merges
		// them without rewriting history or confusing independent Cursor and Claude Code turns.
		if grokVisible {
			let summary = summaries?.providers[.grok]
			let inputs = Self.resolveOfficialProviderInputs(
				summary: summary, days: days, calculator: calculator,
				loadEvents: { (grokAvailable ? grok.loadEvents() : []) + (cursorAvailable ? cursor.loadEvents() : []) })
			let hook = grok.latestRateLimits()
			let snapshot = GrokPlanUsageStore.officialSnapshot(plan: unifiedPlan, hook: hook)
			let hookWeekly = hook?.secondary?.windowMinutes == 10080
			var row = Self.makeOfficialProviderRow(
				id: "grok", name: "Grok", tintHex: JPAppColor.grokTintHex,
				planLabel: hookWeekly ? hook?.planType : (unifiedPlan?.planLabel ?? snapshot?.planType),
				limitLikelyHit: false,
				rollup: inputs.rollup, indexSeries: summary?.dailyCostSeries ?? [],
				events: inputs.events, days: days, snapshot: snapshot, calculator: calculator,
				awaitingResetRefresh: snapshot == nil && grok.latestRateLimitAwaitingReset(now: Date()),
				indexTokenSeries: summary?.dailyTokenSeries ?? [])
			row.cursorPlan = unifiedPlan
			row.officialPlanExpected = grokPlanEnabled || unifiedPlan != nil
			rows.append(row)
		}

		// Muse Spark — notional list-price $, indexed like Grok (same opencode.db source, but
		// filtered to muse-spark model rows). Aggregable (same honesty as Grok/Codex) with its own
		// brand tint. Without an official quota, selectors show activity and the menu bar shows tokens.
		if museSparkAvailable {
			let summary = summaries?.providers[.museSpark]
			let inputs = Self.resolveOfficialProviderInputs(
				summary: summary, days: days, calculator: calculator, loadEvents: museSpark.loadEvents)
			let breakdown = Self.modelBreakdown(inputs.rollup, calculator: calculator)
			rows.append(
				Self.makeOfficialProviderRow(
					id: "muse_spark", name: "Muse Spark", tintHex: JPAppColor.museSparkTintHex,
					planLabel: nil, limitLikelyHit: false,
					rollup: inputs.rollup, indexSeries: summary?.dailyCostSeries ?? [],
					events: inputs.events, days: days,
					snapshot: nil, calculator: calculator,
					estimatedSharePct: Self.estimatedSharePct(rollup: inputs.rollup, breakdown: breakdown),
					sourceScopeNote: MuseSparkScope.detailNote(
						weekEvents: inputs.rollup.last7d.eventCount, opencodeRoot: museSpark.root),
					indexTokenSeries: summary?.dailyTokenSeries ?? []))
		}

		// OpenCode model-brand rows (Nemotron / MiMo / Big Pickle / DeepSeek) — notional list-price $
		// from the same opencode.db source as Muse Spark, filtered to each brand's model rows.
		// Aggregable, no rate-limit gauge; a brand whose local usage is all free tier is fully unpriced
		// and shows tokens (`ProviderRow.isFullyUnpriced`), never a dead `$0.00`.
		for provider in availableBrands {
			let summary = summaries?.providers[provider.id]
			let inputs = Self.resolveOfficialProviderInputs(
				summary: summary, days: days, calculator: calculator, loadEvents: provider.loadEvents)
			let breakdown = Self.modelBreakdown(inputs.rollup, calculator: calculator)
			rows.append(
				Self.makeOfficialProviderRow(
					id: provider.id.rawValue, name: provider.brand.displayName,
					tintHex: JPAppColor.tintHex(for: provider.id),
					planLabel: nil, limitLikelyHit: false,
					rollup: inputs.rollup, indexSeries: summary?.dailyCostSeries ?? [],
					events: inputs.events, days: days,
					snapshot: nil, calculator: calculator,
					estimatedSharePct: Self.estimatedSharePct(rollup: inputs.rollup, breakdown: breakdown),
					sourceScopeNote: Self.brandSourceScopeNote(rollup: inputs.rollup),
					indexTokenSeries: summary?.dailyTokenSeries ?? []))
		}

		// OpenCode is one dashboard row. Zen and Go stay separate warehouse ids and break out in
		// the detail, the same way Grok keeps Build, Cursor, and Grok Bot under one row.
		// Neither gateway is summed: their usage already appears on the model-brand rows.
		var openCodeZenRow: ProviderRow?
		var openCodeGoRow: ProviderRow?
		if openCodeZenAvailable {
			let summary = gatewaySummaries?.providers[.opencode]
			let inputs = Self.resolveOfficialProviderInputs(
				summary: summary, days: days, calculator: calculator, loadEvents: openCodeZen.loadEvents)
			let breakdown = Self.modelBreakdown(inputs.rollup, calculator: calculator)
			openCodeZenRow = Self.makeOfficialProviderRow(
				id: "opencode", name: "Zen", tintHex: JPAppColor.openCodeZenTintHex,
				planLabel: nil, limitLikelyHit: false,
				rollup: inputs.rollup, indexSeries: summary?.dailyCostSeries ?? [],
				events: inputs.events, days: days,
				snapshot: nil, calculator: calculator,
				estimatedSharePct: Self.estimatedSharePct(rollup: inputs.rollup, breakdown: breakdown),
				sourceScopeNote: "OpenCode Zen gateway on this Mac · excluded from combined totals",
				indexTokenSeries: summary?.dailyTokenSeries ?? [])
		}
		if openCodeGoAvailable {
			let now = Date()
			let summary = gatewaySummaries?.providers[.opencodego]
			let inputs = Self.resolveOfficialProviderInputs(
				summary: summary, days: days, calculator: calculator, loadEvents: openCodeGo.loadEvents)
			let breakdown = Self.modelBreakdown(inputs.rollup, calculator: calculator)
			// The measured usage-vs-cap windows need per-turn events for the trailing 30 days only
			// (the longest published window) — a bounded read, never the lifetime message set.
			let windowEvents = openCodeGo.recentEvents(since: now.addingTimeInterval(-30 * 24 * 3600))
			let goWindows = Self.openCodeGoWindows(
				events: windowEvents, calculator: calculator, now: now)
			openCodeGoRow = Self.makeOfficialProviderRow(
				id: "opencodego", name: "Go", tintHex: JPAppColor.openCodeGoTintHex,
				planLabel: "go", limitLikelyHit: false,
				rollup: inputs.rollup, indexSeries: summary?.dailyCostSeries ?? [],
				events: inputs.events, days: days,
				snapshot: Self.openCodeGoSnapshot(
					events: windowEvents, calculator: calculator, now: now),
				calculator: calculator,
				estimatedSharePct: Self.estimatedSharePct(rollup: inputs.rollup, breakdown: breakdown),
				sourceScopeNote: "OpenCode Go gateway on this Mac · excluded from combined totals",
				monthlyWindow: goWindows.monthly,
				indexTokenSeries: summary?.dailyTokenSeries ?? [])
		}
		if let openCode = Self.unifiedOpenCodeRow(zen: openCodeZenRow, go: openCodeGoRow) {
			rows.append(openCode)
		}
		// A failed gateway must stale the one public row, never resurrect a second Go or Zen row.
		if failedProviderIDs.contains("opencode") || failedProviderIDs.contains("opencodego") {
			failedProviderIDs.insert("opencode")
			failedProviderIDs.remove("opencodego")
		}

		// Copilot — visible with its own sparkline/totals, but NEVER goes through `UsageIndexer`/
		// `liveProviderIDs`/`index`, so it can never leak into the primary `summaries?.aggregate` path.
		// `isAggregable: false` additionally excludes it from the fallback dollar aggregate and alerts.
		// Its widget view is token-estimate only: Copilot's OTel-derived accounting is far less
		// precise than Claude/Codex's official sources, so this stays out of every real total.
		// Gated on the live Settings toggle (`copilotEnabled`), not just raw file presence — turning
		// the toggle off must hide the row even though old otel files remain on disk (see above).
		if copilotEnabled && copilot.isAvailable() {
			let events = copilot.loadEvents()
			if let row = Self.makeTokenEstimateRow(
				id: "copilot", name: "Copilot", tintHex: JPAppColor.copilotTintHex,
				events: events, days: days,
				// AIU consumption over the selected window (github.copilot.nano_aiu), nil when the
				// OTel export carries no AIU signal. Consumption count only — never $, never %.
				aiuWindow: copilot.windowAIU(days: days))
			{
				rows.append(row)
			}
		}


		func assemble() -> RefreshBuild {
			let availability = Self.reconcileProviderAvailability(
				rows: rows,
				previousRows: previousRows,
				hadPreviousRefresh: hadPreviousRefresh,
				unavailableProviderIDs: unavailableProviderIDs,
				failedProviderIDs: failedProviderIDs,
				disabledProviderIDs: disabledProviderIDs,
				days: days)
			rows = availability.rows
			// A kept-stale row's last-good figures come from `previousRows`, not the DB summaries built this
			// cycle (which excludes the failed provider). Sum the visible rows directly whenever a stale row
			// is present so the headline aggregate stays consistent with what the selector shows.
			let hasStaleRow = rows.contains { $0.availability == .stale }
			// Aggregate fallback must exclude BOTH non-aggregable estimates AND non-contributing
			// (unavailable/disabled) rows — the same predicate every other aggregate site uses.
			let aggregableRows = rows.filter(\.contributesToAggregate)
			let aggToday =
				(hasStaleRow ? nil : summaries?.aggregate.rollup.today.cost)
				?? aggregableRows.reduce(0.0) { $0 + ($1.today ?? 0) }
			let aggWeek =
				(hasStaleRow ? nil : summaries?.aggregate.rollup.last7d.cost)
				?? aggregableRows.reduce(0.0) { $0 + $1.week }
			let aggSeries =
				(hasStaleRow ? nil : summaries?.aggregate.dailyCostSeries)
				?? aggregableRows.reduce([Double](repeating: 0, count: days)) { partial, row in
					guard row.series.count == partial.count else { return partial }
					return zip(partial, row.series).map(+)
				}
			let aggregateProvenance = DashboardCostProvenance.aggregate(for: rows)
			return RefreshBuild(
				rows: rows,
				aggregateSeries: aggSeries,
				aggregateToday: aggToday,
				aggregateWeek: aggWeek,
				aggregateCostProvenance: aggregateProvenance,
				availabilityNotice: availability.notice,
				errorMessage: errors.first)
		}

		if let onPartial, deferCodexRateLimits {
			onPartial(assemble())
			rows.removeAll { $0.id == "codex" }
			let codexLimits = codex.latestRateLimitState(
				now: Date(), persistedStates: try? index?.parserStates(provider: .codex))
			appendCodexRow(snapshot: codexLimits.current, awaitingReset: codexLimits.awaitingReset)
		}
		return assemble()
	}

	nonisolated private static func modelBreakdown(
		_ rollup: UsageRollup, calculator: CostCalculator
	) -> (lines: [ModelLine], cacheSavings: Double?) {
		let lines = orderedModelLines(rollup.byPresentedModel7d.map { model, bucket in
			ModelLine(
				model: model,
				cost: bucket.unpricedModels.isEmpty ? bucket.cost : nil,
				usage: bucket.usage,
				eventCount: bucket.eventCount)
		})
		let savings = rollup.byModel7d.reduce(into: 0.0) { total, entry in
			total += calculator.cacheReadSavings(model: entry.key, usage: entry.value.usage) ?? 0
		}
		return (lines, savings > 0 ? savings : nil)
	}

	/// True when `resolvedDailyCostSeries` must read raw provider logs because the indexed series is empty
	/// but the window already carries priced/token signal.
	nonisolated private static func needsEventSeriesFallback(
		indexSeries: [Double], days: Int, windowCost: Double
	) -> Bool {
		let windowDays = max(days, 1)
		let sized = indexSeries.count == windowDays ? indexSeries : []
		if sized.contains(where: { $0 > 0 }) { return false }
		return windowCost > 0
	}

	nonisolated private static func needsEventTokenSeriesFallback(
		indexSeries: [Double], days: Int, windowTokens: Int
	) -> Bool {
		let windowDays = max(days, 1)
		let sized = indexSeries.count == windowDays ? indexSeries : []
		if sized.contains(where: { $0 > 0 }) { return false }
		return windowTokens > 0
	}

	/// Prefer indexed rollups/series; touch provider logs only when the index is missing a rollup or the
	/// indexed daily series is empty while the window still carries priced activity (the Muse Spark chart
	/// fallback path). Eager `loadEvents()` on every refresh re-read a heavy Claude/Codex corpus and left
	/// the dashboard stuck on the first-run "Refreshing…" face even when `UsageIndex` already had data.
	/// Provider-detail disclosure for an OpenCode model-brand row. A brand whose window is entirely
	/// unpriced (free tier, or a model with no published rate) is showing tokens, and the note must say
	/// so instead of promising a list price the row is not applying.
	nonisolated static func brandSourceScopeNote(rollup: UsageRollup) -> String {
		let window = rollup.last7d
		if window.eventCount > 0, window.cost == 0, !window.unpricedModels.isEmpty {
			return "OpenCode on this Mac · free tier · local tokens"
		}
		return "OpenCode on this Mac · notional list price"
	}

	nonisolated static func resolveOfficialProviderInputs(
		summary: UsageWindowSummary?,
		days: Int,
		calculator: CostCalculator,
		loadEvents: () -> [UsageEvent]
	) -> (rollup: UsageRollup, events: [UsageEvent]) {
		if let rollup = summary?.rollup {
			let needsEvents = needsEventSeriesFallback(
				indexSeries: summary?.dailyCostSeries ?? [], days: days, windowCost: rollup.last7d.cost)
				|| needsEventTokenSeriesFallback(
					indexSeries: summary?.dailyTokenSeries ?? [], days: days,
					windowTokens: rollup.last7d.usage.total)
			return (rollup, needsEvents ? loadEvents() : [])
		}
		let events = loadEvents()
		return (UsageStore(calculator: calculator).rollup(events, days: days), events)
	}

	/// Picks the indexed per-day cost series when it carries real signal; otherwise falls back to an
	/// in-memory bucket from `events` so a row whose rollup came from logs still charts (Muse Spark
	/// before first index, a failed `windowSummaries`, or a zeroed index series with priced activity).
	nonisolated private static func resolvedDailyCostSeries(
		indexSeries: [Double],
		events: [UsageEvent],
		days: Int,
		calculator: CostCalculator,
		windowCost: Double
	) -> [Double] {
		let windowDays = max(days, 1)
		let sizedIndex = indexSeries.count == windowDays ? indexSeries : []
		if sizedIndex.contains(where: { $0 > 0 }) { return sizedIndex }
		let fromEvents = dailyCostSeries(events, days: days, calculator: calculator)
		if fromEvents.contains(where: { $0 > 0 }) || windowCost > 0 { return fromEvents }
		return sizedIndex.isEmpty ? fromEvents : sizedIndex
	}

	nonisolated private static func resolvedDailyTokenSeries(
		indexSeries: [Double],
		events: [UsageEvent],
		days: Int,
		windowTokens: Int
	) -> [Double] {
		let windowDays = max(days, 1)
		let sizedIndex = indexSeries.count == windowDays ? indexSeries : []
		if sizedIndex.contains(where: { $0 > 0 }) { return sizedIndex }
		let fromEvents = dailyTokenSeries(events, days: days)
		if fromEvents.contains(where: { $0 > 0 }) || windowTokens > 0 { return fromEvents }
		return sizedIndex.isEmpty ? fromEvents : sizedIndex
	}

	/// Oldest→newest per-day cost for `days` local days ending today, for providers computed directly
	/// from `UsageStore` rather than the indexed `UsageIndex` (which derives its own series via SQL).
	/// Copilot is small enough in volume that an in-memory day bucket is cheap and avoids adding it to
	/// the SQLite index at all.
	nonisolated private static func dailyCostSeries(
		_ events: [UsageEvent], days: Int, calculator: CostCalculator,
		now: Date = Date(), calendar: Calendar = .current
	) -> [Double] {
		let windowDays = max(days, 1)
		let startOfToday = calendar.startOfDay(for: now)
		guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: startOfToday)
		else { return Array(repeating: 0, count: windowDays) }
		var series = Array(repeating: 0.0, count: windowDays)
		for event in events {
			guard event.timestamp <= now, event.timestamp >= windowStart else { continue }
			let dayIndex = calendar.dateComponents([.day], from: windowStart, to: event.timestamp).day ?? 0
			guard series.indices.contains(dayIndex) else { continue }
			series[dayIndex] += calculator.cost(model: event.model, usage: event.usage) ?? 0
		}
		return series
	}

	/// Oldest→newest per-day TOTAL token count for `days` local days ending today — the token twin of
	/// `dailyCostSeries`, for a row whose dollar series would be a dead flat `0` line (see
	/// `ProviderRow.isFullyUnpriced`).
	nonisolated private static func dailyTokenSeries(
		_ events: [UsageEvent], days: Int, now: Date = Date(), calendar: Calendar = .current
	) -> [Double] {
		let windowDays = max(days, 1)
		let startOfToday = calendar.startOfDay(for: now)
		guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: startOfToday)
		else { return Array(repeating: 0, count: windowDays) }
		var series = Array(repeating: 0.0, count: windowDays)
		for event in events {
			guard event.timestamp <= now, event.timestamp >= windowStart else { continue }
			let dayIndex = calendar.dateComponents([.day], from: windowStart, to: event.timestamp).day ?? 0
			guard series.indices.contains(dayIndex) else { continue }
			series[dayIndex] += Double(event.usage.total)
		}
		return series
	}

	/// Shared presentation contract for providers with trustworthy local token counts but no
	/// trustworthy local dollars or quota percentage. Copilot is the one such row today; the estimate
	/// badge, token charting, self-relative meter, and aggregate exclusion all derive from here.
	nonisolated private static func makeTokenEstimateRow(
		id: String,
		name: String,
		tintHex: String,
		events: [UsageEvent],
		days: Int,
		aiuWindow: Double? = nil
	) -> ProviderRow? {
		// These providers are contractually token-only even when their emitted model id happens to
		// match the global list-price table. An empty table prevents an accidental model match from
		// turning the estimate row back into dollars on some surfaces.
		let tokenOnlyCalculator = CostCalculator(pricing: PricingTable(models: [:]))
		let rollup = UsageStore(calculator: tokenOnlyCalculator).rollup(events, days: days)
		guard rollup.today.eventCount > 0 || rollup.last7d.eventCount > 0 else { return nil }
		let breakdown = Self.modelBreakdown(rollup, calculator: tokenOnlyCalculator)
		// Same derivation as the official-row builder: `.estimate` is what makes these rows
		// non-aggregable, and it comes from Core's table rather than a literal here.
		let basis = ProviderBasis.of(rawID: id)
		return ProviderRow(
			id: id, name: name, tintHex: tintHex,
			today: rollup.today.cost, week: rollup.last7d.cost,
			todayUsage: rollup.today.usage, weekUsage: rollup.last7d.usage,
			todayEvents: rollup.today.eventCount, weekEvents: rollup.last7d.eventCount,
			series: Self.dailyCostSeries(events, days: days, calculator: tokenOnlyCalculator),
			tokenSeries: Self.dailyTokenSeries(events, days: days),
			notional: basis.isNotional, usedPct: nil, weeklyUsedPct: nil,
			estimatedSharePct: Self.estimatedSharePct(rollup: rollup, breakdown: breakdown),
			usageOfficial: false, planLabel: nil,
			unpricedModels: rollup.last7d.unpricedModels.sorted(),
			byModel7d: breakdown.lines, cacheSavings7d: breakdown.cacheSavings,
			resetsAt5h: nil, resetsAtWeekly: nil,
			windowMinutes5h: nil, windowMinutesWeekly: nil,
			isAggregable: basis.isAggregable, aiuWindow: aiuWindow)
	}


	/// Timeframe (in local days) for the chart and every window-derived figure. Default 14; the
	/// dropdown widens it and one refresh re-derives all visualizations from the new window.
	static let timeframeOptions = [7, 14, 30, 90]
	static let defaultDays = 14
	/// Persisted via `SettingsStore` (`JPtheCat.dashboard.timeframeDays`). Read here through the raw
	/// accessor and clamped to `timeframeOptions` — the store keeps the raw int; the option set is a
	/// dashboard concern, so an out-of-range stored value falls back to the default without rewriting it.
	private static func normalizedTimeframeDays(_ stored: Int) -> Int {
		DashboardViewModel.timeframeOptions.contains(stored) ? stored : DashboardViewModel.defaultDays
	}

	private(set) var state: DashboardState

	private let claude = ClaudeProvider()
	private let codex = CodexProvider()
	private let grok = GrokProvider()
	private let museSpark = MuseSparkProvider()
	private let brands = OpenCodeBrand.allCases.map { OpenCodeBrandProvider(brand: $0) }
	private let openCodeZen = OpenCodeProvider()
	private let openCodeGo = OpenCodeGoProvider()
	private let copilot = CopilotProvider()
	private let cursor = CursorProvider()
	private let index: UsageIndex?
	private let settingsStore: SettingsStore

	/// Exposed (same module only) so `DashboardWidgetPublisher` can compute the widget's per-timeframe
	/// `WidgetSnapshot.windows` payload directly from the index, since `DashboardState` only ever carries
	/// the single currently-selected window's data.
	var usageIndex: UsageIndex? { index }
	/// The single current pricing → cost engine. Cost is READ-TIME: the SQLite index caches token
	/// counts only, and every dollar figure (headline, daily series, per-model breakdown, aggregate) is
	/// recomputed from those cached tokens through THIS one calculator on each refresh. Threading one
	/// instance everywhere guarantees a single refresh can never mix old- and new-priced figures. Swap
	/// it via `updatePricing(_:)` (the hook the remote pricing layer calls), which recomputes from
	/// the already-indexed DB without a disk re-scan. Seeded at construction from `RemotePricingStore`'s
	/// resolved table (bundled defaults + any cached remote override) so launch pricing is correct before
	/// the first network byte.
	private var costCalculator: CostCalculator
	/// Monotonic counter bumped by `updatePricing`; keys the window-summary cache so a remote pricing
	/// hot-swap invalidates cached dollar figures.
	private var pricingGeneration = 0
	private var busy = false  // main-actor only
	private var pendingRefresh = DashboardRefreshQueue()  // main-actor only
	private var refreshGate = DashboardRefreshGate()  // rejects old-window results after timeframe changes

	/// [Regression guard — sustained near-100% CPU during active Claude Code use] `finishRefreshAndRunPending`
	/// used to immediately re-run a queued `.reindex` refresh the instant the prior one finished, with no
	/// floor. A provider log that writes faster than one reindex pass takes (routine for an active Claude
	/// Code session, which is exactly this app's core use case) queues a fresh `.reindex` on every
	/// `FileSystemWatcher` fire, so refreshes chained back-to-back with zero idle time for as long as writes
	/// kept coming — a real, profiler-confirmed spin (`sample` showed 100% of thread time in
	/// `UsageIndexer.refresh` / `FileCursor.fingerprint` sustained over 60+s of otherwise-idle UI). This
	/// floor limits queue-driven passes to once per `minQueuedRefreshSpacing`; a write burst still
	/// collapses to one request (unchanged), it just can't fire again before the floor elapses.
	/// Manual refresh (`refreshNow`), the periodic timer, and the post-open burst are untouched — they call
	/// `refresh(reindex:)` directly, not through this path.
	///
	/// Both the `.reindex` and `.windowOnly` queue-driven passes share one completion stamp and one
	/// floor (`minQueuedRefreshSpacing`) — splitting them lets a window-only pass re-arm with zero delay
	/// and defeats the floor.
	private var lastRefreshCompletedAt: Date?
	private let minQueuedRefreshSpacing: TimeInterval = 2.0
	@ObservationIgnored private var settingsObserver: Any?
	var onDidUpdate: (@MainActor () -> Void)?

	// Computed (not a stored `let`), so the aggregate chart tint tracks the active theme's ginger on a
	// runtime light↔dark toggle instead of freezing the launch-time value. Read only via
	// `selectedTintHex` on the main actor, so resolving `JPTheme.current` here stays main-thread-safe.
	static var allTintHex: String { JPAppColor.aggregateTintHex }  // ginger — the aggregate accent

	init(
		index: UsageIndex?, pricing: PricingTable = .bundledDefault(),
		settingsStore: SettingsStore? = nil, initialState: DashboardState? = nil
	) {
		let settingsStore = settingsStore ?? SettingsStore.shared
		self.index = index
		self.settingsStore = settingsStore
		self.costCalculator = CostCalculator(pricing: pricing)
		state = initialState ?? DashboardState(selectedDays: Self.normalizedTimeframeDays(settingsStore.timeframeDays))
		settingsObserver = NotificationCenter.default.addObserver(
			forName: SettingsStore.didChangeNotification, object: settingsStore, queue: .main
		) { [weak self] notification in
			// Extract the Sendable change in this nonisolated observer block so only it (not the
			// non-Sendable Notification) crosses into the main-actor closure.
			let change = SettingsStore.change(from: notification)
			MainActor.assumeIsolated {
				self?.handleSettingsChange(change)
			}
		}
	}

	// `isolated deinit` runs on the main actor (this is a @MainActor class) so it can touch the
	// main-actor-isolated, non-Sendable `settingsObserver`; removing an observer is a main-thread API.
	isolated deinit {
		if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
	}

	/// Provider log directories for FSEvents-based instant refresh — the single source of truth is
	/// the providers' own `watchPaths()` (respects any custom root override). Every OpenCode-derived
	/// row shares one store root, so the list is deduplicated before it reaches the watcher.
	func watchPaths() -> [URL] {
		var paths: [URL] = []
		if settingsStore.claudeProviderEnabled { paths += claude.watchPaths() }
		if settingsStore.codexProviderEnabled { paths += codex.watchPaths() }
		if settingsStore.grokProviderEnabled { paths += grok.watchPaths() }
		if settingsStore.museSparkProviderEnabled { paths += museSpark.watchPaths() }
		if settingsStore.openCodeZenProviderEnabled { paths += openCodeZen.watchPaths() }
		if settingsStore.openCodeGoProviderEnabled { paths += openCodeGo.watchPaths() }
		for provider in brands where settingsStore.isBrandEnabled(provider.brand) {
			paths += provider.watchPaths()
		}
		if CursorHookSetup.state() == .active { paths += cursor.watchPaths() }
		var seen = Set<String>()
		return paths.filter { seen.insert($0.standardizedFileURL.path).inserted }
	}

	// MARK: - Selected-view accessors (drive the header + chart + detail)

	var rows: [ProviderRow] { state.rows }
	var aggregateToday: Double { state.aggregateToday }
	var aggregateWeek: Double { state.aggregateWeek }
	var hasData: Bool { state.hasData }
	var isRefreshing: Bool { state.isRefreshing }
	var selectedId: String? { state.selectedId }
	var selectedDays: Int { state.selectedDays }
	var providerAvailabilityNotice: String? { state.providerAvailabilityNotice }

	var isAllSelected: Bool { state.isAllSelected }
	var selectedRow: ProviderRow? { state.selectedRow }
	var selectedName: String { state.selectedName }
	var selectedTintHex: String { selectedRow?.tintHex ?? Self.allTintHex }
	var selectedToday: Double { state.selectedToday }
	var selectedWeek: Double { state.selectedWeek }
	var selectedSeries: [Double] { state.selectedSeries }
	var selectedNotional: Bool { state.selectedNotional }
	var selectedBasisLabel: String { state.selectedBasisLabel }

	/// Currency for the cross-provider aggregate. All providers are USD today; if they ever diverge,
	/// summing is only meaningful when they share a code, so fall back to the base currency otherwise.
	var aggregateCurrencyCode: String { state.aggregateCurrencyCode }

	/// Weekly share (0…1) of the aggregate — feeds the composition bar.
	func weeklyShare(_ row: ProviderRow) -> Double {
		state.weeklyShare(row)
	}

	/// Selector-row meter: prefer a provider's own official/estimated usage window when present; otherwise
	/// fall back to aggregate dollar share. This keeps Codex's row from looking like a conflicting quota bar.
	func selectorMeterFraction(_ row: ProviderRow) -> Double {
		state.selectorMeterFraction(row)
	}

	func selectorMeterDescription(_ row: ProviderRow) -> String {
		state.selectorMeterDescription(row)
	}

	/// Select the aggregate (nil) or a provider row. Data is already loaded, so this only swaps the view.
	func select(_ id: String?) {
		let selectableID = Self.selectableProviderID(id, rows: state.rows)
		state = state.selecting(selectableID)
		onDidUpdate?()
	}

	nonisolated static func selectableProviderID(_ id: String?, rows: [ProviderRow]) -> String? {
		id.map(ProviderID.consolidatedRawID).flatMap { id in rows.first { $0.id == id && $0.isSelectable }?.id }
	}

	/// Change the chart/window timeframe and re-derive every visualization from the new window.
	func setTimeframe(_ days: Int) {
		let clamped = Self.normalizedTimeframeDays(days)
		guard clamped != selectedDays else { return }
		state = state.selectingDays(clamped)
		refreshGate.invalidate()
		settingsStore.timeframeDays = clamped
		// Re-derive from the already-indexed DB immediately (no disk re-scan) so the chart, rollups, and
		// per-model breakdown repaint the new window on click — not after the next 60s poll.
		refresh(reindex: false)
	}

	private func handleSettingsChange(_ change: SettingsStore.Change?) {
		guard let change else { return }
		switch change.key {
		case SettingsStore.Key.timeframeDays:
			guard case let .int(days) = change.newValue else { return }
			let clamped = Self.normalizedTimeframeDays(days)
			guard clamped != selectedDays else { return }
			state = state.selectingDays(clamped)
			refreshGate.invalidate()
			refresh(reindex: false)
		case SettingsStore.Key.providerClaudeEnabled, SettingsStore.Key.providerCodexEnabled,
			SettingsStore.Key.providerGrokEnabled, SettingsStore.Key.providerUnifiedGrokEnabled, SettingsStore.Key.providerMuseSparkEnabled,
			SettingsStore.Key.providerNemotronEnabled, SettingsStore.Key.providerMiMoEnabled,
			SettingsStore.Key.providerBigPickleEnabled, SettingsStore.Key.providerDeepSeekEnabled:
			state = state.selecting(nil)
			refreshGate.invalidate()
			refresh(reindex: true)
		default:
			return
		}
	}

	/// Swap the pricing table mid-session (the hook the remote pricing layer will call) and re-derive
	/// every displayed dollar figure from the already-indexed tokens — no disk re-scan. Because cost is
	/// read-time, one `reindex: false` refresh recomputes the headline, daily series, per-model
	/// breakdown, and aggregate together at the new prices, so the surface is never a mix of old and new.
	/// Coalesces + goes through the refresh gate like any other refresh.
	func updatePricing(_ pricing: PricingTable) {
		costCalculator = CostCalculator(pricing: pricing)
		// Bumped so the window-summary cache can't serve dollars computed under the OLD table. A pricing
		// hot-swap changes money without touching any event, so `UsageIndex.generation` alone would not
		// notice it.
		pricingGeneration += 1
		refresh(reindex: false)
	}

	// MARK: - Refresh

	/// `reindex: true` (launch / manual / the 60s poll) walks the provider logs on disk to pick up new
	/// events; `reindex: false` (timeframe change) skips that walk and just re-queries the indexed DB for
	/// the newly selected window, so widening/narrowing the timeframe updates every figure immediately.
	func refresh(reindex: Bool = true) {
		if reindex, !state.hasData, index != nil {
			// Cold launch on a heavy machine can spend minutes walking large Claude/Codex histories before
			// the first full reindex completes. The index already carries the last-good snapshot, so publish
			// that cheap DB read first and queue the real reindex behind it; otherwise the app looks hung on
			// the first-run/loading face despite having current indexed data on disk.
			pendingRefresh.request(reindex: true)
			refresh(reindex: false)
			return
		}
		if busy {
			pendingRefresh.request(reindex: reindex)
			return
		}
		busy = true
		PerformanceInstrumentation.shared.markRefreshStarted(reindex: reindex)
		let previousRows = state.rows
		let hadPreviousRefresh = state.lastRefresh != nil
		state = state.refreshing()
		let claude = self.claude
		let codex = self.codex
		let grok = self.grok
		let museSpark = self.museSpark
		let brands = self.brands
		let openCodeZen = self.openCodeZen
		let openCodeGo = self.openCodeGo
		let copilot = self.copilot
		let cursor = self.cursor
		let index = self.index
		let refreshToken = self.refreshGate.token(days: self.selectedDays)
		let days = refreshToken.days
		// The one current pricing engine, captured for the whole off-main build so the headline,
		// per-model breakdown, daily series, and aggregate are all priced identically (no old/new mix).
		let calculator = self.costCalculator
		let pricingGeneration = self.pricingGeneration
		let claudeEnabled = settingsStore.claudeProviderEnabled
		let codexEnabled = settingsStore.codexProviderEnabled
		let grokEnabled = settingsStore.grokProviderEnabled
		let museSparkEnabled = settingsStore.museSparkProviderEnabled
		let enabledBrands = settingsStore.enabledOpenCodeBrands
		let openCodeZenEnabled = settingsStore.openCodeZenProviderEnabled
		let openCodeGoEnabled = settingsStore.openCodeGoProviderEnabled
		// Copilot's OTel export is opt-in (the `copilotLiveData` `ProviderOptInDescriptor` /
		// `CopilotOtelSetup`) and `uninstall()` only
		// stops FUTURE writes — existing `~/.copilot/otel/*.jsonl` files stay on disk, so
		// `copilot.isAvailable()` (raw file presence) alone would keep showing the row forever after the
		// user turns the Settings toggle off. Gate on the live toggle state too so "off" actually hides it.
		let copilotEnabled = CopilotOtelSetup.state() == .active
		let cursorEnabled = CursorHookSetup.state() == .active
		refreshCursorPlanIfDue()

		// The FIRST data-producing reindex (nothing published yet) is exactly what the first-run loading
		// face is blocked on, so run it at `.userInitiated`. A busy machine at launch heavily deprioritizes
		// `.utility`, which is precisely when "it takes forever to load the first time" bites — the walk is
		// already off-main and coalesced, so raising only this one pass can't starve anything user-visible.
		// Every steady-state poll (data already on screen) stays `.utility` so background refreshes never
		// compete with the UI. `state.hasData` is read here on the main actor, before the hop off-main.
		let refreshQoS: DispatchQoS.QoSClass = (reindex && !state.hasData) ? .userInitiated : .utility
		DispatchQueue.global(qos: refreshQoS).async { [weak self] in
			let build = Self.buildRefreshResult(
				reindex: reindex, days: days,
				calculator: calculator, pricingGeneration: pricingGeneration,
				claude: claude, codex: codex, grok: grok, copilot: copilot,
				cursor: cursor,
				museSpark: museSpark, brands: brands,
				openCodeZen: openCodeZen, openCodeGo: openCodeGo,
				index: index, claudeEnabled: claudeEnabled,
				codexEnabled: codexEnabled, grokEnabled: grokEnabled, copilotEnabled: copilotEnabled,
				cursorEnabled: cursorEnabled, cursorPlan: GrokPlanUsageStore.load(),
				grokPlanEnabled: GrokPlanUsageStore.isEnabled(),
				museSparkEnabled: museSparkEnabled, enabledBrands: enabledBrands,
				openCodeZenEnabled: openCodeZenEnabled,
				openCodeGoEnabled: openCodeGoEnabled, previousRows: previousRows,
				hadPreviousRefresh: hadPreviousRefresh,
				onPartial: { partial in
					Task { @MainActor in
						guard let self else { return }
						guard self.refreshGate.shouldApply(refreshToken, currentDays: self.selectedDays)
						else { return }
						self.applyRefreshBuild(partial, now: Date())
						if self.state.hasContributingData {
							PerformanceInstrumentation.shared.markFirstNumberAvailable()
						}
						self.onDidUpdate?()
					}
				})
			Task { @MainActor in
				guard let self else { return }
				// Stamped on EVERY completed pass, not just reindexes — a window-only pass is expensive
				// enough on a heavy corpus to need the same queue floor.
				self.lastRefreshCompletedAt = Date()
				guard self.refreshGate.shouldApply(refreshToken, currentDays: self.selectedDays) else {
					self.markPerformanceRefreshFinished()
					self.finishRefreshAndRunPending()
					return
				}
				self.applyRefreshBuild(build, now: Date())
				self.markPerformanceRefreshFinished()
				self.onDidUpdate?()
				self.finishRefreshAndRunPending()
			}
		}
	}

	// MARK: - Unified Grok plan usage (opt-in network fetch)

	/// Minimum spacing between unified Grok plan-usage fetch ATTEMPTS, successful or not. Cursor's meters
	/// move slowly, and a failing fetch must never become a request per refresh.
	private static let cursorPlanFetchInterval: TimeInterval = 5 * 60
	@ObservationIgnored private var cursorPlanFetch: Task<Void, Never>?
	@ObservationIgnored private var lastCursorPlanAttempt: Date?

	/// Starts one background fetch of Grok's official plan usage when the user opted in and the
	/// last attempt is older than `cursorPlanFetchInterval`. The result lands on disk, then a
	/// window-only refresh re-derives the rows. Never runs without the opt-in marker.
	private func refreshCursorPlanIfDue(now: Date = Date()) {
		guard settingsStore.grokProviderEnabled, GrokPlanUsageStore.isEnabled() else {
			lastCursorPlanAttempt = nil
			return
		}
		guard cursorPlanFetch == nil else { return }
		if let last = lastCursorPlanAttempt ?? GrokPlanUsageStore.lastAttemptAt(), now.timeIntervalSince(last) < Self.cursorPlanFetchInterval {
			return
		}
		do { try GrokPlanUsageStore.recordAttempt(at: now) } catch { return }
		lastCursorPlanAttempt = now
		cursorPlanFetch = Task.detached(priority: .utility) { [weak self] in
			let changed = await Self.fetchCursorPlanUsage()
			await MainActor.run {
				guard let self else { return }
				self.cursorPlanFetch = nil
				if changed { self.refresh(reindex: false) }
			}
		}
	}

	/// One fetch. Missing/rejected sign-ins preserve only still-current cached pools; expired
	/// readings never become fabricated zero usage. No second Grok Bot fetch owner exists.
	nonisolated private static func fetchCursorPlanUsage() async -> Bool {
		guard GrokPlanUsageStore.isEnabled() else { return false }
		do {
			let usage = try await GrokPlanUsageClient().fetch(
				tokenLoaders: [{ CursorAuthToken.load() }, { GrokBotAuthToken.load() }],
				previous: GrokPlanUsageStore.load())
			guard GrokPlanUsageStore.isEnabled() else { return false }
			try GrokPlanUsageStore.save(usage)
			return true
		} catch {
			// Preserve the last current snapshot; expiry is per pool, not per network attempt.
			return false
		}
	}

	private func applyRefreshBuild(_ build: RefreshBuild, now: Date) {
		state = state.applyingRefresh(
			rows: build.rows,
			aggregateSeries: build.aggregateSeries,
			aggregateToday: build.aggregateToday,
			aggregateWeek: build.aggregateWeek,
			aggregateCostProvenance: build.aggregateCostProvenance,
			providerAvailabilityNotice: build.availabilityNotice,
			errorMessage: build.errorMessage,
			now: now)
	}

	private func markPerformanceRefreshFinished() {
		PerformanceInstrumentation.shared.markRefreshFinished(hasDisplayableNumber: state.hasContributingData)
	}

	nonisolated static func reconcileProviderAvailability(
		rows: [ProviderRow],
		previousRows: [ProviderRow],
		hadPreviousRefresh: Bool,
		unavailableProviderIDs: Set<String>,
		failedProviderIDs: Set<String> = [],
		disabledProviderIDs: Set<String> = [],
		days: Int
	) -> (rows: [ProviderRow], notice: String?) {
		let previousByID = Dictionary(uniqueKeysWithValues: previousRows.map { ($0.id, $0) })
		// A merged row can still be assembled from accepted index data after one source fails.
		// Retain the complete prior reading rather than publishing a half-updated source mix.
		var nextRows = rows.map { row in
			failedProviderIDs.contains(row.id) ? (previousByID[row.id] ?? row).markingStale() : row
		}
		let nextIDs = Set(nextRows.map(\.id))

		// Directory disappeared → keep a zeroed, non-contributing "unavailable" row.
		for row in previousRows where !disabledProviderIDs.contains(row.id) && unavailableProviderIDs.contains(row.id)
			&& !nextIDs.contains(row.id)
		{
			nextRows.append(row.markingUnavailable(days: days))
		}
		// A user-disabled provider (Settings → Live data toggle off) is fully REMOVED from the view,
		// not kept as a zeroed/badged row — mirrors Copilot's "off means gone" behavior, so every
		// provider's toggle reads consistently: on = visible with real data, off = not on the
		// dashboard at all. Deliberately no `nextRows.append(...)` here.
		// Directory present but the refresh threw → keep the last good row (data + contribution) as stale,
		// so a transient hiccup doesn't drop the provider or shrink the aggregate.
		for row in previousRows where failedProviderIDs.contains(row.id) && !nextIDs.contains(row.id) {
			nextRows.append(row.markingStale())
		}

		let rowIDs = nextRows.map(\.id)
		let rowNames = Dictionary(nextRows.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
		nextRows.sort { lhs, rhs in
			ProviderDashboardOrder.sortsBefore(lhs.id, rhs.id, rowIDs: rowIDs) { rowNames[$0] ?? $0 }
		}

		guard hadPreviousRefresh else { return (nextRows, nil) }

		// Was contributing (available or stale) last cycle, now its directory is gone.
		let disappeared = previousRows
			.filter { $0.availability != .unavailable && !disabledProviderIDs.contains($0.id) && unavailableProviderIDs.contains($0.id) }
			.map(\.name)
		let disabled = previousRows
			.filter { $0.availability != .disabled && disabledProviderIDs.contains($0.id) }
			.map(\.name)
		// Came back from an "unavailable" (directory-gone) state. A stale→available recovery is deliberately
		// NOT announced: a stale row kept contributing to the aggregate, so nothing about inclusion changed.
		let returned = rows
			.filter { $0.isAvailable && [.unavailable, .disabled].contains(previousByID[$0.id]?.availability) }
			.map(\.name)
		// Genuinely first seen after a prior refresh (never in `previousRows`) — a real inclusion change,
		// but it never "returned", so it must not claim "again".
		let firstSeen = rows
			.filter { $0.isAvailable && previousByID[$0.id] == nil }
			.map(\.name)

		var parts: [String] = []
		if !disappeared.isEmpty {
			parts.append(
				"\(list(disappeared)) unavailable; aggregate excludes \(disappeared.count == 1 ? "it" : "them") until \(disappeared.count == 1 ? "its log folder returns" : "their log folders return").")
		}
		if !disabled.isEmpty {
			parts.append(
				"\(list(disabled)) disabled in Settings; aggregate excludes \(disabled.count == 1 ? "it" : "them") until re-enabled.")
		}
		if !returned.isEmpty {
			parts.append(
				"\(list(returned)) available again; aggregate includes \(returned.count == 1 ? "it" : "them") again.")
		}
		if !firstSeen.isEmpty {
			parts.append(
				"Now tracking \(list(firstSeen)) in the aggregate.")
		}
		return (nextRows, parts.isEmpty ? nil : parts.joined(separator: " "))
	}

	nonisolated private static func list(_ names: [String]) -> String {
		switch names.count {
		case 0: return ""
		case 1: return names[0]
		case 2: return names.joined(separator: " and ")
		default: return names.dropLast().joined(separator: ", ") + ", and \(names.last ?? "")"
		}
	}

	private func finishRefreshAndRunPending() {
		let next = pendingRefresh.popNext()
		guard next != .none else {
			busy = false
			state = state.idleIfRefreshing()
			return
		}
		if let last = lastRefreshCompletedAt {
			let elapsed = Date().timeIntervalSince(last)
			if elapsed < minQueuedRefreshSpacing {
				// Deliberately leave `busy` true for the wait: any writes that land during it collapse into
				// `pendingRefresh` (as usual) instead of starting a second concurrent/immediate pass.
				let delay = minQueuedRefreshSpacing - elapsed
				if state.hasData {
					state = state.idleIfRefreshing()
				}
				DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
					guard let self else { return }
					self.busy = false
					// Re-pop rather than replaying `next`: a reindex requested during the wait must not be
					// downgraded to the window-only pass we popped before it arrived.
					self.pendingRefresh.request(reindex: next == .reindex)
					self.finishRefreshAndRunPending()
				}
				return
			}
		}
		busy = false
		refresh(reindex: next == .reindex)
	}
}
