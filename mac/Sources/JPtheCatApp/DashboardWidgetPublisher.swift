import Foundation
import JPtheCatCore
import WidgetKit

/// Thread-safe cache for `UsageIndex.multiWindowSummaries` results, keyed on the index's own
/// `generation` (bumped only when `ingest`/`deleteEvents` actually mutates the events table) plus the
/// requesting provider set and calendar day. `multiWindowSummaries` is an unbounded scan over up to 90
/// days of events — on a heavy history this repeats real, measurable work on EVERY publish even though
/// the underlying data usually hasn't changed since the last publish a few seconds ago. Reusing the
/// cached result when the generation/providers/day all still match turns most publishes into an O(1)
/// dictionary lookup instead of a full re-scan.
private final class MultiWindowSummaryCache: @unchecked Sendable {
	private struct Key: Equatable {
		let generation: Int
		let providers: [String]
		let day: String
	}
	private let lock = NSLock()
	private var lastKey: Key?
	private var lastResult: UsageMultiWindowSummaries?

  func cached(generation: Int, providers: [ProviderID], day: String)
    -> UsageMultiWindowSummaries?
  {
    let key = Key(
      generation: generation, providers: providers.map(\.rawValue).sorted(),
      day: day)
		lock.lock()
		defer { lock.unlock() }
		guard lastKey == key else { return nil }
		return lastResult
	}

  func store(
    generation: Int, providers: [ProviderID], day: String,
    result: UsageMultiWindowSummaries
  ) {
    let key = Key(
      generation: generation, providers: providers.map(\.rawValue).sorted(),
      day: day)
		lock.lock()
		defer { lock.unlock() }
		lastKey = key
		lastResult = result
	}
}

private let multiWindowSummaryCache = MultiWindowSummaryCache()

@MainActor
enum DashboardWidgetPublisher {
	/// Last snapshot actually written, kept to skip redundant App Group writes + WidgetCenter reloads.
	/// WidgetKit budgets reloads; the dashboard refreshes on a 60s/300s cadence plus FS-watch bursts, so
	/// rewriting a byte-identical file (and asking WidgetKit to reload) on every tick is wasted I/O and
	/// risks the system throttling genuine updates.
	private static var lastPublished: WidgetSnapshot?
	private static var lastAutomationPublished: LocalAutomationSnapshot?

	/// [Regression guard] `publish` must not assemble a full snapshot on every `onDidUpdate` (every
	/// refresh completion AND every provider-row click): the content-dedup in `finishPublishing` only
	/// skips the WRITE, after the expensive assembly already happened. WidgetKit budgets reloads at
	/// roughly 40-70/day and the snapshot's own `staleAfter` is +30 min. Postmortem:
	/// `_docs/00-foundation.md#sustained-cpu-postmortem-the-refresh-storm-2026-07-2627-shipped-v1083`.
	///
	/// `lastPublishAttempt == nil` (never `lastPublished == nil`) is what exempts the first publish after
	/// launch: `lastPublished` is only assigned after a SUCCESSFUL write, so keying the exemption on it
	/// would let the post-open burst stack concurrent detached 90-day scans, and would disable the
	/// throttle forever if the App Group write kept failing.
	private static var lastPublishAttempt: Date?
	private static var publishInFlight = false
	private static let minPublishSpacing: TimeInterval = 5 * 60

	/// Every day-count the widget's per-instance `Timeframe` picker can select. Mirrors the app dashboard's
	/// own `TimeframePicker` options so a widget can always match whatever the user could pick in-app.
	private nonisolated static let supportedWindowDays = [7, 14, 30, 90]

	/// [Regression guard] `makeSnapshot`'s DB scan (`UsageIndex.multiWindowSummaries`, unbounded over up
	/// to 90 days) must run off-main via `nonisolated`, hopping to `@MainActor` only for the final
	/// compare-and-write. `access` and `publishAutomationSnapshot` (cheap — no DB hit, just
	/// `state.rows`) stay on main.
	static func publish(from dashboard: DashboardViewModel, force: Bool = false, now: Date = Date()) {
		let state = dashboard.state
		let index = dashboard.usageIndex
		let access = WidgetPremiumAccess.current()
		// The local-automation snapshot stays UNTHROTTLED: it is a pure projection of `state.rows` with
		// no DB hit, and it is the surface local scripts poll.
		publishAutomationSnapshot(from: state)
		// Before the throttle, so a skipped publish never starts the spacing floor.
		guard hasPublishableData(state.refreshStatus) else { return }
		guard shouldAssembleSnapshot(force: force, now: now) else { return }
		Task.detached(priority: .utility) {
			let snapshot = makeSnapshot(from: state, index: index, access: access)
			await finishPublishing(snapshot)
		}
	}

	/// Whether the dashboard has figures a widget may show. Before the first refresh finishes, the state
	/// has no rows, and a snapshot of it reads "today $0.00, real spend", which is false. Measured on the
	/// 1.131 to 1.132 update: a forced publish wrote that empty snapshot one second after launch, and the
	/// spacing floor then skipped the first real refresh, so placed widgets showed $0.00 for up to five
	/// minutes.
	nonisolated static func hasPublishableData(
		_ status: DashboardRefreshStatus
	) -> Bool {
		switch status {
		case .idle(lastRefresh: .none), .refreshing(lastRefresh: .none): return false
		case .idle, .refreshing, .failed: return true
		}
	}

	/// Skips snapshot assembly when a publish is already running or the spacing floor hasn't elapsed.
	/// `force` is for entitlement changes, where a lock/unlock must reach the widget immediately.
	/// Internal (not private) so `DashboardWidgetPublisherThrottleTests` can pin the decision directly
	/// without standing up a real `DashboardViewModel` and its detached scan.
	static func shouldAssembleSnapshot(force: Bool, now: Date) -> Bool {
		if force {
			lastPublishAttempt = now
			publishInFlight = true
			return true
		}
		if publishInFlight { return false }
		if let last = lastPublishAttempt, now.timeIntervalSince(last) < minPublishSpacing {
			return false
		}
		lastPublishAttempt = now
		publishInFlight = true
		return true
	}

	/// Lets a just-placed widget (or a returning user) get fresh numbers without waiting out the floor.
	static func invalidatePublishThrottle() { lastPublishAttempt = nil }

	/// Resets BOTH throttle fields. Test-only: the throttle is process-wide static state, so a test must
	/// start from a known point rather than inherit whatever a previous test left behind.
	static func resetPublishThrottleForTesting() {
		lastPublishAttempt = nil
		publishInFlight = false
	}

	/// Test-only: clears the in-flight flag `finishPublishing` normally clears, so a throttle test can
	/// exercise the spacing floor without running a real detached snapshot assembly.
	static func clearPublishInFlightForTesting() { publishInFlight = false }

	@MainActor
	private static func finishPublishing(_ snapshot: WidgetSnapshot) {
		publishInFlight = false
		if let lastPublished, lastPublished.hasSameContent(as: snapshot) { return }
		do {
			try WidgetSnapshotStore().write(snapshot)
			lastPublished = snapshot
			WidgetCenter.shared.reloadTimelines(ofKind: JPWidgetContract.kind)
			warnIfAppGroupUnavailable()
		} catch {
			NSLog("JPtheCat widget snapshot write failed: \(String(describing: error))")
		}
	}

	/// The main app is not sandboxed, so a dropped app-groups entitlement makes `write` succeed to the
	/// App Support fallback that the sandboxed widget can't read — the widget would then render stale
	/// preview data forever. Surface it (only from a real .app bundle, to keep raw dev launches quiet)
	/// instead of failing silently.
	private static func warnIfAppGroupUnavailable() {
		guard Bundle.main.bundleIdentifier == "com.8bittts.jpthecat",
			!WidgetSnapshotStore.resolvedRootIsAppGroup()
		else { return }
    NSLog(
      "JPtheCat widget: App Group container unavailable — snapshot written to the Application "
        + "Support fallback the sandboxed widget cannot read. Check the app-groups entitlement."
    )
	}

  nonisolated private static func widgetProviderSnapshot(
    from row: DashboardViewModel.ProviderRow
  ) -> WidgetProviderSnapshot {
    if row.isOfficialPlanOnly {
      return WidgetProviderSnapshot(
        id: row.id, name: row.name, tintHex: row.tintHex,
        today: row.primaryPlanPercent ?? 0, window: row.primaryPlanPercent ?? 0,
        currencyCode: row.currencyCode, metric: .percent,
        basis: .notionalListPrice,
        usedPercent: nil, weeklyUsedPercent: row.weeklyUsedPct,
        usageOfficial: row.primaryPlanPercent != nil, series: [])
    }
    let tokenMetric = row.usesTokenDisplay
    return WidgetProviderSnapshot(
      id: row.id, name: row.name, tintHex: row.tintHex,
      today: tokenMetric ? Double(row.todayUsage.total) : (row.today ?? 0),
      window: tokenMetric ? Double(row.weekUsage.total) : row.week,
      currencyCode: row.currencyCode, metric: tokenMetric ? .tokens : .dollars,
      basis: row.notional ? .notionalListPrice : .realSpend,
      usedPercent: row.usedPct, weeklyUsedPercent: row.weeklyUsedPct,
      usageOfficial: row.usageOfficial,
      series: tokenMetric ? row.tokenSeries : row.series)
  }

  nonisolated static func makeSnapshot(
    from state: DashboardState, index: UsageIndex?, access: WidgetAccessState,
    now: Date = Date()
	) -> WidgetSnapshot {
		// Contributing = available + last-good stale; both belong in the widget's provider list and totals.
		// Only a truly-gone (unavailable) source is dropped.
    let displayRows = state.rows.filter { row in
      guard row.isContributing else { return false }
      if row.isOfficialPlanOnly { return row.primaryPlanPercent != nil }
      return true
    }
    let providers = displayRows.map { widgetProviderSnapshot(from: $0) }
		return WidgetSnapshot(
			generatedAt: state.lastRefresh ?? now,
			access: access,
			title: "All providers",
			totalToday: state.aggregateToday,
			totalWindow: state.aggregateWeek,
			currencyCode: state.aggregateCurrencyCode,
			windowDays: state.selectedDays,
			basis: state.aggregateCostProvenance.widgetCostBasis,
			series: state.aggregateSeries,
			providers: providers,
			staleAfter: now.addingTimeInterval(30 * 60),
			errorMessage: state.refreshError,
			availabilityNotice: widgetAvailabilityNotice(from: state),
      windows: makeWindows(from: displayRows, index: index, now: now))
	}

	/// Every supported timeframe's aggregate + per-provider figures, computed from ONE additional
	/// single-scan `UsageIndex.multiWindowSummaries` call (bounded by the largest supported window, not
	/// one scan per day-count) so each placed widget instance can independently select its own timeframe
	/// via `WidgetSnapshot.selectingWindow(days:)` instead of always mirroring `state.selectedDays`.
	// LOCAL-day cache discriminator, NOT UTC. `multiWindowSummaries` buckets today/window/series by the
	// LOCAL calendar day (calendar = .current); a UTC-day key let the cache serve a pre-local-midnight
	// result after local midnight when the generation was unchanged (idle overnight) — a stale window
	// total + sparkline for up to the UTC-offset. `.autoupdatingCurrent` tracks a live tz change too.
	/// Token-only rows are excluded from every dollar aggregate, so their bucketed `cost` is provably
	/// discarded — `heatmapDays(measure: .tokens)` never reads it. Building a real `CostCalculator` per
	/// row per publish paid a full `JPResourceBundle` walk plus a pricing-JSON decode for a value nobody
	/// reads; this is the same empty table `makeTokenEstimateRow` already uses.
	private nonisolated static let tokenOnlyCalculator = CostCalculator(
		pricing: PricingTable(models: [:]))

	private nonisolated static let dayFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "yyyy-MM-dd"
		f.timeZone = TimeZone.autoupdatingCurrent
		f.locale = Locale(identifier: "en_US_POSIX")
		return f
	}()

	private nonisolated static func makeWindows(
    from contributingRows: [DashboardViewModel.ProviderRow], index: UsageIndex?,
    now: Date
	) -> [Int: WidgetWindowSnapshot] {
    let providerIDs = contributingRows.filter(\.isAggregable).compactMap {
      ProviderID(rawValue: $0.id)
    } + (contributingRows.contains { $0.id == "grok" } && CursorHookSetup.state() == .active ? [.cursor] : [])
    let multi: UsageMultiWindowSummaries
    if let index, !providerIDs.isEmpty {
		let day = dayFormatter.string(from: now)
		// Snapshot the generation ONCE for both lookup and store. Reading it twice around the compute let
		// an ingest that landed mid-compute cache generation-G data under generation-G′ (served as current
		// until the next bump). Same snapshot for both closes that TOCTOU window.
		let gen = index.generation
      multi =
        multiWindowSummaryCache.cached(
          generation: gen, providers: providerIDs,
          day: day)
			?? {
				// A mid-scan SQLite error → empty (never a silently-truncated partial), and NOT cached, so the
				// next refresh re-attempts the scan rather than serving a stale error until the generation bumps.
          guard
            let computed = try? index.multiWindowSummaries(
              providers: providerIDs,
              windows: supportedWindowDays, now: now)
				else { return UsageMultiWindowSummaries(byDays: [:]) }
          multiWindowSummaryCache.store(
            generation: gen,
            providers: providerIDs, day: day, result: computed)
				return computed
			}()
    } else {
      multi = UsageMultiWindowSummaries(byDays: [:])
		}
    // Token-only providers share one window-building contract. They remain outside `providerIDs`
    // (and therefore every dollar aggregate), while each gets its own token series.
    let tokenRows: [String: [ModelDaySummary]] = Dictionary(
      uniqueKeysWithValues: contributingRows.filter { !$0.isAggregable }.compactMap { row in
        let events: [UsageEvent]
        switch row.id {
        case "copilot": events = CopilotProvider().loadEvents()
        case "cursor": events = CursorProvider().loadEvents()
        default: return nil
        }
        return (
          row.id,
          ModelDaySummary.bucketed(events: events, calculator: tokenOnlyCalculator)
        )
      })
    guard !multi.byDays.isEmpty || !tokenRows.isEmpty else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: supportedWindowDays.map { days in
        let summaries = multi.byDays[days]
        var providerWindows = Dictionary(
          uniqueKeysWithValues: (summaries?.providers ?? [:]).map {
            providerID, summary in
            (
              providerID.rawValue,
              WidgetProviderWindow(
                window: contributingRows.first { $0.id == providerID.rawValue }?.usesTokenDisplay == true ? Double(summary.rollup.last7d.usage.total) : summary.rollup.last7d.cost,
                series: contributingRows.first { $0.id == providerID.rawValue }?.usesTokenDisplay == true ? summary.dailyTokenSeries : summary.dailyCostSeries)
            )
          })
        for (providerID, rows) in tokenRows {
          let tokenDays = AnalyticsAggregation.heatmapDays(
            rows: rows, measure: .tokens, days: days,
            now: now
          )
          let tokenSeries = tokenDays.map(\.value)
          providerWindows[providerID] = WidgetProviderWindow(
            window: tokenSeries.reduce(0, +),
            series: tokenSeries)
        }
        return (
          days,
          WidgetWindowSnapshot(
            days: days,
            totalWindow: summaries?.aggregate.rollup.last7d.cost
              ?? 0,
            series: summaries?.aggregate.dailyCostSeries
              ?? Array(repeating: 0, count: days),
            providerWindows: providerWindows)
        )
      })
	}

  static func makeAutomationSnapshot(from state: DashboardState, now: Date = Date())
    -> LocalAutomationSnapshot
  {
		// Include every contributing row so token-only providers are available to local automation.
		// A non-aggregable row still does NOT feed the
		// aggregate totals (those come from `state.aggregate*`, which already exclude it) — it only adds
		// its own entry to the `providers` list, honestly carrying $0 dollars + its real aiu_window.
		let providers = state.rows
			.filter(\.isContributing)
			.map { row in
        let basis = ProviderBasis.of(rawID: row.id)
        let tokenMetric = row.usesTokenDisplay
				return LocalAutomationProvider(
					id: row.id,
					name: row.name,
					currencyCode: row.currencyCode,
					today: row.isOfficialPlanOnly ? (row.primaryPlanPercent ?? 0) : (tokenMetric ? Double(row.todayUsage.total) : (row.today ?? 0)),
					window: row.isOfficialPlanOnly ? (row.primaryPlanPercent ?? 0) : (tokenMetric ? Double(row.weekUsage.total) : row.week),
					costBasis: LocalAutomationCostBasis(basis),
					valueMetric: row.isOfficialPlanOnly ? .percent : (tokenMetric ? .tokens : .dollars),
					series: tokenMetric ? row.tokenSeries : row.series,
					eventsToday: row.todayEvents,
					eventsWindow: row.weekEvents,
					unpricedModels: row.unpricedModels,
					headroom: automationHeadroom(row, now: now),
					aiuWindow: row.aiuWindow)
			}
		let rateLimits = Dictionary(
      uniqueKeysWithValues: state.rows.compactMap {
        row -> (String, LocalAutomationRateLimits)? in
        guard row.isContributing,
          row.usedPct != nil || row.weeklyUsedPct != nil || row.codexCredits != nil
        else { return nil }
				return (
					row.id,
					LocalAutomationRateLimits(
						planType: row.planLabel,
						primary5h: row.usedPct.map {
							LocalAutomationRateLimitWindow(
								usedPercent: $0,
                windowMinutes: row.windowMinutes5h
                  ?? 300,
								resetsAt: row.resetsAt5h,
								official: row.usageOfficial)
						},
						secondaryWeekly: row.weeklyUsedPct.map {
							LocalAutomationRateLimitWindow(
								usedPercent: $0,
                windowMinutes: row
                  .windowMinutesWeekly
                  ?? 10080,
								resetsAt: row.resetsAtWeekly,
								official: row.usageOfficial)
						}, credits: row.codexCredits, capturedAt: row.creditsCapturedAt)
				)
			})
		return LocalAutomationSnapshot(
			generatedAt: state.lastRefresh ?? now,
			source: "JPtheCatApp",
			windowDays: state.selectedDays,
			currencyCode: state.aggregateCurrencyCode,
			totalToday: state.aggregateToday,
			totalWindow: state.aggregateWeek,
			costBasis: state.aggregateCostProvenance.localAutomationCostBasis,
			series: state.aggregateSeries,
			providers: providers,
			rateLimits: rateLimits,
			status: state.refreshError == nil ? "ok" : "refresh_failed",
			notice: widgetAvailabilityNotice(from: state))
	}

	private static func automationHeadroom(
		_ row: DashboardViewModel.ProviderRow, now: Date
	) -> LocalAutomationHeadroom {
		guard row.usageOfficial else { return LocalAutomationHeadroom(.unknown) }
		if row.limitLikelyHit { return LocalAutomationHeadroom(.likelyExhausted) }
		let snapshot = RateLimitSnapshot(
			primary: row.usedPct.map {
				RateLimitWindow(usedPercent: $0, windowMinutes: row.windowMinutes5h ?? 300,
					resetsAt: row.resetsAt5h)
			},
			secondary: row.weeklyUsedPct.map {
				RateLimitWindow(usedPercent: $0, windowMinutes: row.windowMinutesWeekly ?? 10080,
					resetsAt: row.resetsAtWeekly)
			}, planType: row.planLabel)
		return LocalAutomationHeadroom(ProviderHeadroom.resolve(from: snapshot, now: now))
	}

	private static func publishAutomationSnapshot(from state: DashboardState) {
		let snapshot = makeAutomationSnapshot(from: state)
    if let lastAutomationPublished, lastAutomationPublished.hasSameContent(as: snapshot) {
      return
    }
		do {
			try LocalAutomationSnapshotStore().write(snapshot)
			lastAutomationPublished = snapshot
		} catch {
      NSLog(
        "JPtheCat local automation snapshot write failed: \(String(describing: error))"
      )
		}
	}

	/// Prefer the dashboard's transition notice; but that clears on steady-state refreshes, so when rows
	/// exist yet none contribute, synthesize a disclosure so the widget never shows a bare "$0.00" for a
	/// wholly-unavailable state.
  private nonisolated static func widgetAvailabilityNotice(from state: DashboardState)
    -> String?
  {
		if let notice = state.providerAvailabilityNotice { return notice }
    if state.hasData, !state.hasContributingData {
      return "All sources unavailable — open JP the Cat."
    }
		return nil
	}
}

extension DashboardCostProvenance {
  fileprivate var widgetCostBasis: WidgetCostBasis {
		switch self {
		case .realSpend:
			.realSpend
		case .notionalListPrice:
			.notionalListPrice
		case .realAndNotionalListPrice:
			.realAndNotionalListPrice
		}
	}

  fileprivate var localAutomationCostBasis: LocalAutomationCostBasis {
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

enum WidgetPremiumAccess {
	/// JP is free: the app always publishes the full widget. The snapshot keeps its `access` field so
	/// widgets placed by older builds keep decoding.
	@MainActor static func current() -> WidgetAccessState {
		.premium
	}
}
