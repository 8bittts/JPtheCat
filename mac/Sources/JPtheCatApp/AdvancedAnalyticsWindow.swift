import AppKit
import SwiftUI
import UniformTypeIdentifiers
import JPtheCatCore

/// Advanced Analytics — a large TWO-COLUMN deep-dive window (fixed right "inputs" sidebar + flexible
/// left "readout" canvas). Core rule: the SIDEBAR is the only place UI state lives; the left canvas is a
/// pure rendering of (scope × timeframe × measure × grain). Uses its OWN `@State` days selector
/// rather than sharing `SettingsStore`'s persisted dashboard timeframe — exploring analytics must never
/// disturb whatever the compact dashboard chart is currently showing.
///
/// Holds a weak reference to the window (set by the controller right after creation) so the SwiftUI
/// content can attach `NSSavePanel` as a proper sheet on the ACTUAL window rather than guessing at
/// `NSApp.keyWindow`.
@MainActor
final class TrayWindowRef: ObservableObject {
  weak var window: NSWindow?
}

/// One provider entry in the sidebar's checkbox list — display name kept alongside the raw `ProviderID`
/// since `DashboardViewModel`'s own `ProviderRow` construction is the naming source of truth ("Claude
/// Code", "Codex", "Copilot" — never the raw lowercase enum rawValue).
struct AnalyticsProviderOption: Sendable {
  let id: ProviderID
  let name: String
}

// The cost basis of an analytics provider is Core's `ProviderBasis` — the SAME table the dashboard
// rows and the selector badges derive from, so no surface can silently fold a notional/estimate
// figure into a real total. This window used to own a private `AnalyticsProviderBasis` copy with
// nothing tying it to `DashboardViewModel`'s hand-written `notional:`/`isAggregable:` literals.

/// Raw brand tint hex for a provider (mirrors `JPAppColor`'s per-provider strings; aggregate falls back
/// to the active ginger). Data-viz call sites lift it for legibility via `JPAppColor.providerTint`.
private func analyticsTintHex(_ id: ProviderID) -> String {
  JPAppColor.tintHex(for: id)
}

/// The composited heatmap cell color, built straight from `HeatmapRamp`'s sRGB components.
///
/// Pixel-identical to the old `Color(hex: HeatmapRamp.cellHex(...))` — the components are quantized to the
/// same 8-bit grid the hex form rounds to — but without three `String(format: "%02X")` calls and a third
/// hex parse per cell. A 90-day Model × Day grid is 630 cells inside a `GeometryReader`, so that round trip
/// repeated on every resize frame. Guard: `HeatmapRampTests.testCellComponentsAreTheExactColorCellHexSerializes`.
private func heatmapCellColor(t: Double, accentHex: String, trackHex: String) -> Color {
  let c = HeatmapRamp.cellComponents(
    t: t, accentHex: accentHex, trackHex: trackHex, maxAlpha: JPAppColor.barFillOpacity)
  return Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: 1)
}

/// The table's model label. Recipe lives in Core `ModelName.analyticsShort`.
private func analyticsShortModel(_ model: String) -> String { ModelName.analyticsShort(model) }

/// The SHORT provider name for trend labels / focus eyebrows ("Claude" not "Claude Code").
func analyticsShortProviderName(_ id: ProviderID) -> String {
  ProviderCatalog.descriptor(for: id)?.shortName ?? id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
}

/// A sortable column of the model table. `tokens` is a sort-only target (the "Tokens" measure) — it has
/// no dedicated header column; the five token buckets are shown individually.
private enum AnalyticsTableColumn: Hashable {
  case model, events, tokens, input, output, cache5m, cache1h, cacheRead, cost
}

private struct AnalyticsTableSort: Equatable {
  var column: AnalyticsTableColumn
  var ascending: Bool
}

/// Which heatmap grain the switcher shows — a single grid at a time so the heatmap area stays bounded
/// for the no-scroll budget. Calendar = weeks × weekday; Rhythm = 7 weekday rows × 24 hour columns;
/// Model × Day = models × days-in-window.
private enum AnalyticsGrain: String, CaseIterable {
  case calendar, rhythm, modelDay
}

/// The exact heatmap cell the user pinned the model table to (drill-down). Precise to the click (so a
/// second click on the SAME cell clears the filter, and the pill labels exactly what was clicked); the
/// Core `AnalyticsDrillFilter` it maps to resolves Rhythm to a WEEKDAY, since the by-model table is
/// day-grained (a `ModelDaySummary` has no hour-of-day).
private enum DrillSelection: Equatable {
  case day(Date)
  case rhythm(weekday: Int, hour: Int)
  case modelDay(provider: ProviderID, model: String, day: Date)

  var coreFilter: AnalyticsDrillFilter {
    switch self {
    case .day(let day): .day(day)
    case .rhythm(let weekday, _): .weekday(weekday)
    case .modelDay(let provider, let model, let day): .modelDay(provider: provider, model: model, day: day)
    }
  }
}

struct AdvancedAnalyticsTrayView: View {
  let index: UsageIndex?
  let pricing: PricingTable
  @ObservedObject var windowRef: TrayWindowRef

  // The whole two-column surface re-colors on a theme change (each `JP.*` token re-reads the active
  // theme); the heatmap cells additionally observe `ThemeManager` since a static leaf reading `JP.*`
  // would otherwise freeze at first-render theme (see AGENTS.md "Theming System").
  @ObservedObject private var themeManager = ThemeManager.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var days: Int = 14
  @State private var rows: [ModelDaySummary] = []
  // Per-provider rhythm punchcards, published from the same off-main load as `rows` (Claude/Codex from
  // `UsageIndex.hourWeekdayBins`, Copilot from `HourWeekdayMatrix.bucketed`). Held per-provider so the
  // Rhythm heatmap can scope to a focused provider and re-fold the checked subset on a checkbox toggle
  // WITHOUT a second scan — exactly how `rows` holds every provider and the canvas derives scoped views.
  @State private var rhythmByProvider: [ProviderID: HourWeekdayMatrix] = [:]
  @State private var checkedProviders = Set(Self.providerOptions.map(\.id))
  // Focus mode: when set, the ENTIRE left canvas scopes to this one provider and the heatmap ramp
  // reheats to its tint. Orthogonal to `checkedProviders` (which still controls include-in-export).
  @State private var focusedProvider: ProviderID?
  @State private var measure: AnalyticsMeasure = .events
  @State private var grain: AnalyticsGrain = .calendar
  @State private var drill: DrillSelection?
  @State private var sort = AnalyticsTableSort(column: .cost, ascending: false)
  @State private var loadTask: Task<Void, Never>?
  @State private var isExporting = false

  /// The Model × Day heatmap caps its rows so the grid never grows unbounded past the no-scroll budget.
  private static let modelDayGridMaxRows = 7

  /// The per-model table caps its rows for the SAME reason: the window is fixed-height with no internal
  /// scroll, so an uncapped table (a heavy user really does hit 14+ models in 14 days) grows the left
  /// canvas past the window and pushes the sidebar's bottom-pinned Export button off the bottom edge —
  /// a real shipped bug. Anything past the cap is disclosed inline and still included in Export.
  /// Guard: `AnalyticsProviderCoverageTests`.
  static let modelTableMaxRows = 7
  static let trendMaxColumns = 4

  static func visibleModelRowLimit(providerCount: Int) -> Int {
    let trendRows = max(1, (providerCount + trendMaxColumns - 1) / trendMaxColumns)
    return max(3, modelTableMaxRows - 2 * (trendRows - 1))
  }

  // Claude/Codex are indexed (UsageIndex); Copilot bypasses the index entirely (see AGENTS.md "Provider
  // Catalog & Live Data" — `CopilotProvider.loadEvents()` reads its OTel export directly), which is why
  // it needs a SEPARATE fetch in `reload()` merged into the same `rows`/`rhythmByProvider`.
  nonisolated static let providerOptions = [
    AnalyticsProviderOption(id: .claude, name: "Claude Code"),
    AnalyticsProviderOption(id: .codex, name: "Codex"),
    AnalyticsProviderOption(id: .grok, name: "Grok"),
    AnalyticsProviderOption(id: .museSpark, name: "Muse Spark"),
    AnalyticsProviderOption(id: .nemotron, name: "Nemotron"),
    AnalyticsProviderOption(id: .mimo, name: "MiMo"),
    AnalyticsProviderOption(id: .bigPickle, name: "Big Pickle"),
    AnalyticsProviderOption(id: .deepseek, name: "DeepSeek"),
    AnalyticsProviderOption(id: .opencode, name: "OpenCode Zen"),
    AnalyticsProviderOption(id: .opencodego, name: "OpenCode Go"),
    AnalyticsProviderOption(id: .copilot, name: "Copilot"),
  ]

  private var calculator: CostCalculator { CostCalculator(pricing: pricing) }
  private var canExport: Bool {
    !isExporting && !checkedProviders.isEmpty
  }

  var body: some View {
    // [Regression guard — chrome row drifting UP off the traffic lights] The window height is FIXED while
    // the canvas below is data-sized, so the body's minimum height can exceed it (measured 1011pt in a
    // 1000pt window on a real 14-day corpus). A plain `VStack` OVERFLOWS THAT SYMMETRICALLY — it centers,
    // pushing the chrome row 5.5pt above the window's own traffic lights and dropping the same 5.5pt off
    // the bottom, which read as "the title bar and dropdown aren't aligned like the main app's". Handing
    // the body exactly the height left over after the chrome row keeps the chrome pinned to the top (the
    // dashboard/Live data model), stretches the bottom-pinned footnote/Export when content is short, and
    // clips only downward when the fixed-height budget is genuinely blown.
    GeometryReader { geo in
      VStack(spacing: 0) {
        chromeBar
        Rectangle().fill(JP.line).frame(height: 1)
        columns(height: max(0, geo.size.height - JPAppSpacing.chromeHeight - 1))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .clipped()
    .background(JP.card)
    .onAppear { reload() }
    .onChange(of: days) { _, _ in reload() }
    // Toggling a provider, the measure, the grain, or the focus NEVER reloads — `rows`/`rhythmByProvider`
    // already hold all three providers; the canvas is a pure re-render over (scope × measure × grain).
    // Only widening/narrowing the timeframe re-scans.
    .onChange(of: measure) { _, newValue in syncSortToMeasure(newValue) }
    // A drill selection is tied to a specific grid/scope — clear it when the grid or the scope changes
    // so a stale "Filtered: Thu" pill never lingers over a grain that can't produce it.
    .onChange(of: grain) { _, _ in drill = nil }
    .onChange(of: focusedProvider) { _, _ in drill = nil }
    // [Regression guard — freeze/no-data on rapid close+reopen] cancel any in-flight scan so at most one
    // is ever running per window lifetime (an orphaned scan holding `UsageIndex.withConnectionLock`
    // blocks the next one and reads as "freezes and shows no data").
    .onDisappear { loadTask?.cancel() }
  }

  // MARK: - Left readout canvas

  private var leftCanvas: some View {
    // [Perf] ONE readout (and one provenance read of it) per body pass, threaded into every section as a
    // parameter. These used to be reached through ~15 pass-through computed properties, each of which
    // rebuilt the readout and re-scanned `rows` — roughly 30 constructions per render, ~10 of them
    // re-running `AnalyticsAggregation.heatmapDays`'s per-row `startOfDay` + `dateComponents` bucketing.
    let readout = self.readout
    let provenance = Self.provenance(of: readout.aggregableRows)
    // No `ScrollView` — the window default height (`analyticsWindowH`) is sized so the whole vertical
    // stack fits at the 14-day default. The section eyebrow now lives in the chrome bar (`JP the Cat 🐾 —
    // Advanced Analytics`), freeing the height the full-width trend and token-mix rows spend so each
    // visualization gets the whole canvas width; the Rhythm grid's 7-row orientation and the
    // single-grain-at-a-time switcher keep the rest within the no-scroll budget.
    return VStack(alignment: .leading, spacing: JPAppSpacing.analyticsSectionGap) {
      heroBand(readout, provenance: provenance)
      statTiles(readout, provenance: provenance)
      trendSection(readout).frame(maxWidth: .infinity, alignment: .leading)
      tokenMixSection(readout).frame(maxWidth: .infinity, alignment: .leading)
      heatmapSection(readout, provenance: provenance)
      modelTableSection(readout)
      // Absorb any slack in the fixed-height window so the footnote pins to the bottom, lining its
      // baseline up with the sidebar's bottom-pinned Export button (collapses to zero when the
      // content already fills the window at wider timeframes).
      Spacer(minLength: 0)
      tableFootnote
    }
    .padding(.horizontal, JPAppSpacing.analyticsCanvasX)
    .padding(.vertical, JPAppSpacing.analyticsCanvasY)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// The two-column body, given EXACTLY the height left over below the chrome row (see `body`).
  private func columns(height: CGFloat) -> some View {
    HStack(spacing: 0) {
      leftCanvas
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Rectangle().fill(JP.line).frame(width: 1)
      sidebar
    }
    .frame(height: height, alignment: .top)
    .frame(maxWidth: .infinity)
  }

  /// The full-window chrome row: `JP the Cat 🐾` drawn inline with the traffic lights (the window sets
  /// `safeAreaRegions = []` so it isn't pushed below them) on the LEFT, with the timeframe dropdown on the
  /// RIGHT — mirroring the main dashboard, whose timeframe picker lives in its header. Spans the full
  /// window width above BOTH the left canvas and the sidebar.
  private var chromeBar: some View {
    ChromeTitleRow(subtitle: "— Advanced Analytics") {
      TimeframePicker(
        days: days, options: DashboardViewModel.timeframeOptions, onSelect: { days = $0 })
    }
  }

  // MARK: Hero band (ALWAYS the scope's headline figure — money, or tokens for a fully-unpriced scope)

  private func heroBand(
    _ readout: AnalyticsReadout, provenance: DashboardCostProvenance
  ) -> some View {
    let basisLabel = heroBasisLabel(readout, provenance: provenance)
    return VStack(alignment: .leading, spacing: 8) {
      BasisLabelChip(text: basisLabel, reduceMotion: reduceMotion)
        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
        .id(basisLabel)
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          Text(readout.heroPrimaryValue)
            .font(JPAppFont.analyticsHero)
            .foregroundStyle(JP.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
          Text("last \(days) days")
            .font(JPAppFont.caption)
            .foregroundStyle(JP.inkFaint)
        }
        Spacer(minLength: 12)
        VStack(alignment: .trailing, spacing: 3) {
          Text(readout.heroEyebrow)
            .font(JPAppFont.eyebrow)
            .foregroundStyle(JP.gingerDeep)
          Text(readout.heroSecondaryValue)
            .font(JPAppFont.metric)
            .foregroundStyle(JP.ink)
            .lineLimit(1)
          Text(readout.heroSecondaryCaption)
            .font(JPAppFont.caption)
            .foregroundStyle(JP.inkFaint)
        }
      }
      // Copilot's token total is a QUIET secondary line — never folded into the `$` story above (only
      // shown when the scope has priced providers too; a Copilot-only focus already leads with tokens).
      if readout.showCopilotTokenLine {
        Text("+ \(TokenFormatter.compact(readout.copilotTokens)) Copilot tokens · estimate, excluded from $")
          .font(JPAppFont.caption)
          .foregroundStyle(JP.inkFaint)
      }
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: Mini stat row

  private func statTiles(
    _ readout: AnalyticsReadout, provenance: DashboardCostProvenance
  ) -> some View {
    HStack(spacing: JPAppSpacing.analyticsTileGap) {
      if readout.scopeIsFullyUnpriced {
        StatTile(
          label: "Avg tok/day", value: TokenFormatter.compact(readout.avgTokensPerDay), caption: "per day")
        StatTile(
          label: "Peak day", value: TokenFormatter.compact(readout.peakDayTokens), caption: "busiest day")
      } else {
        StatTile(
          label: "Avg $/day", value: MoneyFormatter.dollars(readout.avgPerDay),
          caption: costCaption(provenance, default: "per day"))
        StatTile(
          label: "Peak day", value: MoneyFormatter.dollars(readout.peakDayDollars),
          caption: costCaption(provenance, default: "busiest day"))
      }
      StatTile(label: "Events", value: readout.totalEvents.formatted(), caption: "across scope")
    }
  }

  private func costCaption(
    _ provenance: DashboardCostProvenance, default fallback: String
  ) -> String {
    provenance.includesNotional ? "incl notional" : fallback
  }

  // MARK: Daily trend — per-provider small multiples (one sparkline in focus mode)

  private func trendSection(_ readout: AnalyticsReadout) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Daily trend · last \(days) days")
        .font(JPAppFont.caption)
        .foregroundStyle(JP.inkSoft)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
          count: max(1, min(Self.trendMaxColumns, orderedScopedProviders.count))),
        alignment: .leading, spacing: 12
      ) {
        if orderedScopedProviders.isEmpty {
          Text("No providers selected")
            .font(JPAppFont.caption)
            .foregroundStyle(JP.inkFaint)
            .frame(height: 32)
        } else {
          ForEach(orderedScopedProviders, id: \.self) { providerTrend($0, readout: readout) }
        }
      }
    }
  }

  @ViewBuilder
  private func providerTrend(_ id: ProviderID, readout: AnalyticsReadout) -> some View {
    let tint = JP.providerTint(analyticsTintHex(id))
    let name = analyticsShortProviderName(id)
    if id == .grok, readout.providerIsPlanOnly(id) {
      let figure = readout.providerTrendFigure(id)
      let weekly = readout.grokPlanUsedPercent ?? 0
      let fraction = min(1, max(0, weekly / 100))
      let meter = GrokPlanUsageStore.primaryMeter(plan: GrokPlanUsageStore.load(), fallback: GrokProvider().latestRateLimits())
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Circle().fill(tint).frame(width: 7, height: 7)
          Text(name)
            .font(JPAppFont.caption)
            .foregroundStyle(JP.inkSoft)
            .lineLimit(1)
          Spacer(minLength: 6)
          Text(figure)
            .font(JPAppFont.metricSmall)
            .foregroundStyle(JP.ink)
            .lineLimit(1)
        }
        HeroOfficialQuotaMeter(
          fraction: fraction, tint: tint, showHeader: false,
          footerCaption: ProviderRelativeReset.resetsInPhrase(until: meter?.resetsAt))
          .frame(height: 32)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(name) official \(readout.grokPlanWindowLabel) included usage, \(figure)")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      let figure = readout.providerTrendFigure(id)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Circle().fill(tint).frame(width: 7, height: 7)
          Text(name)
            .font(JPAppFont.caption)
            .foregroundStyle(JP.inkSoft)
            .lineLimit(1)
          Spacer(minLength: 6)
          Text(figure)
            .font(JPAppFont.metricSmall)
            .foregroundStyle(JP.ink)
            .lineLimit(1)
        }
        SparkChart(values: readout.providerDailySeries(id), tint: tint, reduceMotion: reduceMotion)
          .frame(height: 32)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(name) daily trend, \(figure)")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Token-mix composition + cache efficiency

  private func tokenMixSection(_ readout: AnalyticsReadout) -> some View {
    let mix = readout.tokenMix
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Token mix · last \(days) days")
          .font(JPAppFont.caption)
          .foregroundStyle(JP.inkSoft)
        Spacer()
        Text(TokenFormatter.compact(mix.total))
          .font(JPAppFont.metricSmall)
          .foregroundStyle(JP.ink)
          .lineLimit(1)
      }
      TokenMixBar(mix: mix)
      TokenMixLegend()
      Text("Cache hit rate \(percentInt(mix.cacheHitRate))")
        .font(JPAppFont.micro)
        .foregroundStyle(JP.inkFaint)
    }
  }

  // MARK: Heatmap — grain switcher + one grid + peak callout

  /// The heatmap data for the ACTIVE grain only, resolved ONCE per render pass and shared by the grid,
  /// its per-cell tooltips, and the peak callout. Each of those used to rebuild the aggregation itself —
  /// the Rhythm tooltip re-summed the whole per-provider matrix once per CELL (168 cells).
  private enum GrainData {
    case calendar([HeatmapDay])
    case rhythm(HourWeekdayMatrix, [[Double]])
    case modelDay(ModelDayGrid)
  }

  private func grainData(_ readout: AnalyticsReadout) -> GrainData {
    switch grain {
    case .calendar:
      return .calendar(
        AnalyticsAggregation.heatmapDays(
          rows: readout.heatmapSourceRows, measure: measure, days: days))
    case .rhythm:
      let matrix = rhythmMatrix
      return .rhythm(matrix, rhythmValues(matrix))
    case .modelDay:
      return .modelDay(
        AnalyticsAggregation.modelDayGrid(
          rows: readout.heatmapSourceRows, measure: measure, days: days,
          topModels: Self.modelDayGridMaxRows))
    }
  }

  private func heatmapSection(
    _ readout: AnalyticsReadout, provenance: DashboardCostProvenance
  ) -> some View {
    // The accent resolves the focused provider's legible tint — once for the whole section (legend + grid)
    // rather than once per cell.
    let accentHex = heatmapAccentHex
    let data = grainData(readout)
    let callout = peakCallout(data)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Activity · \(measureTitle)")
          .font(JPAppFont.caption)
          .foregroundStyle(JP.inkSoft)
        Spacer()
        heatmapLegend(accentHex: accentHex)
      }
      AnalyticsGrainControl(grain: $grain)
      grainGrid(data, accentHex: accentHex)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if !callout.isEmpty {
          Text(callout)
            .font(JPAppFont.caption)
            .foregroundStyle(JP.inkSoft)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        // $-mode honesty: dollar cells count only aggregable providers; disclose the mixed basis and
        // that Copilot (unpriced) is excluded. Events/Tokens have no basis issue, so no disclosure.
        if measure == .cost, provenance.includesNotional {
          Text("incl notional · Copilot excluded from $")
            .font(JPAppFont.micro)
            .foregroundStyle(JP.inkFaint)
        }
      }
    }
  }

  @ViewBuilder private func grainGrid(_ data: GrainData, accentHex: String) -> some View {
    switch data {
    case .calendar(let heatmapDays):
      HeatmapGrid(
        days: heatmapDays, measure: measure, accentHex: accentHex,
        selectedDay: selectedCalendarDay, onTapDay: { toggleDrillDay($0) })
    case .rhythm(let matrix, let values):
      rhythmGrid(matrix: matrix, values: values, accentHex: accentHex)
    case .modelDay(let grid):
      modelDayGridView(grid, accentHex: accentHex)
    }
  }

  private func rhythmGrid(
    matrix: HourWeekdayMatrix, values: [[Double]], accentHex: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      LabeledHeatmapGrid(
        rowLabels: Self.rhythmRowLabels, rowLabelWidth: 30, values: values,
        accentHex: accentHex,
        cellTooltip: { row, col in rhythmTooltip(matrix, row: row, col: col) },
        selected: selectedRhythmCell,
        onTap: { toggleDrillRhythm(row: $0, col: $1) })
      hourAxis
    }
  }

  private var hourAxis: some View {
    HStack(spacing: 0) {
      Color.clear.frame(width: 30 + JPAppSpacing.analyticsHeatmapGap)
      Text("12a").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
      Spacer(minLength: 0)
      Text("6a").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
      Spacer(minLength: 0)
      Text("12p").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
      Spacer(minLength: 0)
      Text("6p").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
      Spacer(minLength: 0)
      Text("11p").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
    }
    // The grid above now FILLS the canvas width, so the axis spans the same width rather than a
    // hardcoded 24-square measurement (which would leave the hour labels bunched on the left).
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
  }

  @ViewBuilder private func modelDayGridView(_ grid: ModelDayGrid, accentHex: String) -> some View {
    if grid.rows.isEmpty {
      Text("No model activity in this window.")
        .font(JPAppFont.caption)
        .foregroundStyle(JP.inkFaint)
        .frame(height: JPAppSpacing.analyticsHeatmapCell)
    } else {
      VStack(alignment: .leading, spacing: 4) {
        LabeledHeatmapGrid(
          rowLabels: grid.rows.map { analyticsShortModel($0.model) }, rowLabelWidth: 120,
          values: grid.values, accentHex: accentHex,
          cellTooltip: { row, col in modelDayTooltip(grid, row: row, col: col) },
          selected: selectedModelDayCell(grid),
          onTap: { row, col in toggleDrillModelDay(grid, row: row, col: col) })
        Text("columns = days (oldest → newest, local)")
          .font(JPAppFont.micro)
          .foregroundStyle(JP.inkFaint)
      }
    }
  }

  private func heatmapLegend(accentHex: String) -> some View {
    let trackHex = themeManager.theme.track
    return HStack(spacing: 5) {
      Text("Less").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
      ForEach([0.0, 0.35, 0.6, 0.85, 1.0], id: \.self) { t in
        RoundedRectangle(cornerRadius: JPAppRadius.tile, style: .continuous)
          .fill(heatmapCellColor(t: t, accentHex: accentHex, trackHex: trackHex))
          .frame(width: 11, height: 11)
          .overlay(
            RoundedRectangle(cornerRadius: JPAppRadius.tile, style: .continuous)
              .strokeBorder(JP.line.opacity(0.5), lineWidth: 0.5))
      }
      Text("More").font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
    }
    .accessibilityHidden(true)
  }

  // MARK: Sortable per-model table (with optional drill-down pill)

  private func modelTableSection(_ readout: AnalyticsReadout) -> some View {
    // ONE aggregation + sort per render: the visible slice and the hidden-count both derive from it. Read
    // as two computed properties, the full group-by + sort ran twice on every render.
    let sorted = sortedModelTotals(readout)
    let rowLimit = Self.visibleModelRowLimit(providerCount: orderedScopedProviders.count)
    let hiddenModelCount = max(sorted.count - rowLimit, 0)
    return VStack(alignment: .leading, spacing: 8) {
      Text("By model · last \(days) days")
        .font(JPAppFont.caption)
        .foregroundStyle(JP.inkSoft)
      if let drill { drillPill(drill) }
      // The capped slice actually rendered (see `modelTableMaxRows`); the sort runs over the FULL set
      // first, so re-sorting always re-picks which models are shown.
      AnalyticsModelTable(totals: Array(sorted.prefix(rowLimit)), sort: $sort)
      if hiddenModelCount > 0 {
        Text("+ \(hiddenModelCount) more model\(hiddenModelCount == 1 ? "" : "s") — included in Export")
          .font(JPAppFont.micro)
          .foregroundStyle(JP.inkFaint)
      }
    }
  }

  /// The basis disclaimer footnote — pulled OUT of `modelTableSection` and pinned to the BOTTOM of the
  /// left canvas (via a `Spacer` before it in `readoutCanvas`) so its baseline lines up with the
  /// bottom-pinned Export button in the sidebar. The window is a fixed height, so a top-anchored
  /// footnote would otherwise float above the Export button whenever the left content is shorter than
  /// the window.
  private var tableFootnote: some View {
    Text("Codex, Grok & Muse Spark $ = notional list price · Copilot shows tokens (estimate, excluded from $ totals).")
      .font(JPAppFont.micro)
      .foregroundStyle(JP.inkFaint)
      .lineLimit(2)
  }

  private func drillPill(_ selection: DrillSelection) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "line.3.horizontal.decrease.circle")
        .font(JPAppFont.caption)
        .foregroundStyle(JP.gingerDeep)
      Text("Filtered: \(drillLabel(selection))")
        .font(JPAppFont.caption)
        .foregroundStyle(JP.gingerDeep)
        .lineLimit(1)
      Button(action: { drill = nil }) {
        Image(systemName: "xmark.circle.fill").font(JPAppFont.caption)
      }
      .buttonStyle(.plain)
      .foregroundStyle(JP.gingerDeep)
      .help("Clear filter")
      .accessibilityLabel("Clear filter")
      Spacer(minLength: 0)
    }
    .padding(.horizontal, LabelBadgeMetrics.horizontalInset)
    .frame(height: LabelBadgeMetrics.height)
    .background(
      JP.gingerDeep.opacity(0.1),
      in: RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
  }

  // MARK: - Right sidebar (the only place UI state lives)

  private var sidebar: some View {
    // The timeframe dropdown lives in the full-width chrome bar now (see `chromeBar`), not here — the
    // sidebar sits BELOW that shared chrome row, so it only needs the canvas top inset.
    VStack(alignment: .leading, spacing: JPAppSpacing.analyticsSidebarGap) {
      providersSection
      measureSection
      basisKeySection
      Spacer(minLength: 0)
      exportButton
    }
    .padding(.horizontal, JPAppSpacing.analyticsSidebarX)
    .padding(.top, JPAppSpacing.analyticsCanvasY)
    .padding(.bottom, JPAppSpacing.analyticsCanvasY)
    .frame(width: JPAppSpacing.analyticsSidebarW)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(JP.paper2)
  }

  private func sidebarHeader(_ text: String) -> some View {
    Text(text)
      .font(JPAppFont.eyebrowStrong)
      .foregroundStyle(JP.inkSoft)
  }

  private var providersSection: some View {
    // ONE readout for all six rows' figures (each `providerFigure` read used to rebuild it).
    let readout = self.readout
    return VStack(alignment: .leading, spacing: 8) {
      sidebarHeader("PROVIDERS")
      // "All providers" clears focus (returns the canvas to the checked aggregate). Highlighted when
      // nothing is focused, so it reads as the current scope.
      Button(action: { focusedProvider = nil }) {
        HStack(spacing: 8) {
          // Same bare JP mark as the dashboard All-providers row (no brand-tint chip).
          AnalyticsProviderMark(resourceName: "jp-menubar", tintHex: nil)
          Text("All providers")
            .font(JPAppFont.bodyStrong)
            .foregroundStyle(focusedProvider == nil ? JP.gingerDeep : JP.ink)
          Spacer(minLength: 4)
          if focusedProvider == nil {
            Image(systemName: "checkmark").font(JPAppFont.menuChevron).foregroundStyle(JP.gingerDeep)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Show all checked providers together")
      .accessibilityLabel("All providers\(focusedProvider == nil ? ", selected" : "")")
      ForEach(Self.providerOptions, id: \.id) { option in
        SidebarProviderRow(
          option: option,
          basis: ProviderBasis.of(option.id),
          figure: readout.providerFigure(option.id),
          tintHex: analyticsTintHex(option.id),
          isFocused: focusedProvider == option.id,
          onFocus: { focusedProvider = (focusedProvider == option.id) ? nil : option.id },
          isOn: checkedBinding(for: option.id))
      }
    }
  }

  private var measureSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sidebarHeader("MEASURE")
      AnalyticsMeasureControl(measure: $measure)
    }
  }

  /// One line per tray provider, meaning derived from Core's `ProviderBasis` — a provider added to
  /// `providerOptions` appears here automatically, so the key can never omit a row (it once omitted
  /// both OpenCode gateways).
  private var basisKeySection: some View {
    VStack(alignment: .leading, spacing: 4) {
      sidebarHeader("BASIS")
      ForEach(Self.providerOptions, id: \.id) { option in
        basisLine(option.name, ProviderBasis.of(option.id).keyMeaning)
      }
    }
  }

  private func basisLine(_ name: String, _ meaning: String) -> some View {
    HStack(spacing: 4) {
      Text(name).font(JPAppFont.captionStrong).foregroundStyle(JP.ink)
      Text("= \(meaning)").font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
      Spacer(minLength: 0)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.8)
  }

  private var exportButton: some View {
    Button(action: export) {
      HStack(spacing: 6) {
        Image(systemName: "square.and.arrow.up").font(JPAppFont.caption)
        Text("Export").font(JPAppFont.caption)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, JPAppSpacing.ctaPillY)
      .background(
        RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
          .fill(canExport ? JP.gingerDeep.opacity(0.12) : JP.paper.opacity(0.5)))
    }
    .buttonStyle(.plain)
    .foregroundStyle(canExport ? JP.gingerDeep : JP.inkFaint)
    .disabled(!canExport)
    .help(canExportHelp)
    .accessibilityLabel("Export analytics (CSV, JSON, or Markdown)")
  }

  private var canExportHelp: String {
    guard !checkedProviders.isEmpty else { return "Check at least one provider to export" }
    return "Export the checked providers' rows for the selected timeframe"
  }

  private func checkedBinding(for provider: ProviderID) -> Binding<Bool> {
    Binding(
      get: { checkedProviders.contains(provider) },
      set: { isOn in
        if isOn { checkedProviders.insert(provider) } else { checkedProviders.remove(provider) }
      })
  }

  // MARK: - Scope (pure functions of focus × checked)

  /// The providers the LEFT canvas renders: the single focused provider, or every checked provider.
  /// Export is unaffected (it always uses `checkedProviders`).
  private var scopedProviders: Set<ProviderID> {
    if let focusedProvider { return [focusedProvider] }
    return checkedProviders
  }

  /// `scopedProviders` in stable display order (Claude → Codex → Grok → Grok Bot → …) for
  /// the trend small multiples. Must list EVERY provider in `providerOptions` — a provider missing here is
  /// checkable in the sidebar but silently absent from the daily trend (a real shipped bug for Cursor).
  /// Guard: `AnalyticsProviderCoverageTests`.
	static let trendProviderOrder: [ProviderID] = [
		.claude, .codex, .grok, .museSpark, .nemotron, .mimo, .bigPickle, .deepseek,
		.opencode, .opencodego, .copilot,
	]
  private var orderedScopedProviders: [ProviderID] {
    Self.trendProviderOrder.filter { scopedProviders.contains($0) }
  }

  // MARK: - Derived readout state (pure functions of rows × scope × timeframe × measure)
  // The logic lives in the testable `AnalyticsReadout` value type. Guard: AnalyticsReadoutTests.
  //
  // [Perf] Every consumer takes the readout as a PARAMETER — there are deliberately no pass-through
  // computed properties (`avgPerDay`, `heroPrimaryValue`, …) delegating to a fresh `self.readout`. Each
  // such delegate rebuilt the readout and re-scanned `rows`, and one body pass touched ~15 of them.
  // Build it ONCE at the top of `leftCanvas` (and once for the sidebar) and thread it down.
  private var readout: AnalyticsReadout {
    let meter = GrokPlanUsageStore.primaryMeter(plan: GrokPlanUsageStore.load(), fallback: GrokProvider().latestRateLimits())
    return AnalyticsReadout(
      rows: rows, scopedProviders: scopedProviders, days: days, measure: measure,
      focusedProvider: focusedProvider,
      grokPlanUsedPercent: meter?.usedPercent,
      grokPlanWindowLabel: meter?.key == CursorPlanMeter.grokBotKey ? "weekly" : "billing-cycle",
      grokPlanEnabled: GrokPlanUsageStore.isEnabled())
  }

  // MARK: Heatmap grains

  private var heatmapAccentHex: String {
    guard let focusedProvider else { return themeManager.theme.ginger }
    // Reheat to the focused provider's LEGIBLE tint (the same value `JPAppColor.providerTint` renders),
    // so the ramp stays luminance-monotonic on every theme (guarded by `HeatmapRampTests`).
    return ProviderTintLegibility.legibleHex(
      tintHex: analyticsTintHex(focusedProvider), backgroundHex: themeManager.theme.card,
      inkHex: themeManager.theme.ink, isDark: themeManager.theme.isDark)
  }

  /// The scoped rhythm punchcard for the current measure — cost sums only aggregable providers (Copilot
  /// excluded from `$`); events/tokens sum every scoped provider.
  private var rhythmMatrix: HourWeekdayMatrix {
    let ids =
      measure == .cost
      ? scopedProviders.filter { ProviderBasis.of($0).isAggregable } : scopedProviders
    return HourWeekdayMatrix.summed(ids.compactMap { rhythmByProvider[$0] })
  }

  /// Mon-first weekday rows (the Rhythm grid orientation): Calendar weekdays 2…7 then 1 (Sunday).
  private static let rhythmWeekdayOrder = [2, 3, 4, 5, 6, 7, 1]
  private static let rhythmRowLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

  private func rhythmValues(_ matrix: HourWeekdayMatrix) -> [[Double]] {
    Self.rhythmWeekdayOrder.map { weekday in
      (0..<HourWeekdayMatrix.hourCount).map { hour in
        matrix.value(weekday: weekday, hour: hour, measure: measure)
      }
    }
  }

  // MARK: Peak callout

  /// Derived from the SAME `GrainData` the grid renders, so the callout can never disagree with the grid
  /// and the aggregation runs once.
  private func peakCallout(_ data: GrainData) -> String {
    switch data {
    case .calendar(let heatmapDays):
      guard let peak = heatmapDays.max(by: { $0.value < $1.value }), peak.value > 0 else { return "" }
      return "Busiest day: \(Self.shortWeekdayFormatter.string(from: peak.day))"
    case .rhythm(let matrix, _):
      guard let peak = matrix.peak(measure: measure) else { return "" }
      return "Busiest: \(Self.calendarWeekdayShort(peak.weekday)) \(Self.hourRangeLabel(peak.hour))"
    case .modelDay(let grid):
      guard let top = grid.rows.first, top.total > 0 else { return "" }
      return "Busiest model: \(analyticsShortModel(top.model))"
    }
  }

  // MARK: Drill-down (heatmap cell → model table filter)

  /// The table's source rows, narrowed by any active drill selection.
  private func tableRows(_ readout: AnalyticsReadout) -> [ModelDaySummary] {
    guard let drill else { return readout.scopedRows }
    return AnalyticsAggregation.filteredRows(readout.scopedRows, matching: drill.coreFilter)
  }

  private var selectedCalendarDay: Date? {
    if case .day(let day) = drill { return day }
    return nil
  }

  private var selectedRhythmCell: (Int, Int)? {
    if case .rhythm(let weekday, let hour) = drill,
      let row = Self.rhythmWeekdayOrder.firstIndex(of: weekday)
    {
      return (row, hour)
    }
    return nil
  }

  private func selectedModelDayCell(_ grid: ModelDayGrid) -> (Int, Int)? {
    guard case .modelDay(let provider, let model, let day) = drill,
      let rowIndex = grid.rows.firstIndex(where: { $0.provider == provider && $0.model == model }),
      let colIndex = grid.days.firstIndex(where: {
        Calendar.current.startOfDay(for: $0) == Calendar.current.startOfDay(for: day)
      })
    else { return nil }
    return (rowIndex, colIndex)
  }

  private func toggleDrillDay(_ day: Date) {
    let selection = DrillSelection.day(Calendar.current.startOfDay(for: day))
    drill = (drill == selection) ? nil : selection
  }

  private func toggleDrillRhythm(row: Int, col: Int) {
    guard row < Self.rhythmWeekdayOrder.count else { return }
    let selection = DrillSelection.rhythm(weekday: Self.rhythmWeekdayOrder[row], hour: col)
    drill = (drill == selection) ? nil : selection
  }

  private func toggleDrillModelDay(_ grid: ModelDayGrid, row: Int, col: Int) {
    guard row < grid.rows.count, col < grid.days.count else { return }
    let entry = grid.rows[row]
    let selection = DrillSelection.modelDay(provider: entry.provider, model: entry.model, day: grid.days[col])
    drill = (drill == selection) ? nil : selection
  }

  private func drillLabel(_ selection: DrillSelection) -> String {
    switch selection {
    case .day(let day):
      return Self.drillDayFormatter.string(from: day)
    case .rhythm(let weekday, let hour):
      return "\(Self.calendarWeekdayShort(weekday)) \(Self.hourRangeLabel(hour))"
    case .modelDay(_, let model, let day):
      return "\(analyticsShortModel(model)) · \(Self.drillDayFormatter.string(from: day))"
    }
  }

  /// Takes the ALREADY-SUMMED matrix: this is a per-cell closure (168 cells on the Rhythm grid), and
  /// reaching for `rhythmMatrix` here re-summed every provider's punchcard once per cell.
  private func rhythmTooltip(_ matrix: HourWeekdayMatrix, row: Int, col: Int) -> String {
    guard row < Self.rhythmWeekdayOrder.count else { return "" }
    let weekday = Self.rhythmWeekdayOrder[row]
    let value = matrix.value(weekday: weekday, hour: col, measure: measure)
    return "\(Self.rhythmRowLabels[row]) \(Self.hourRangeLabel(col)) · \(measureValueLabel(value))"
  }

  private func modelDayTooltip(_ grid: ModelDayGrid, row: Int, col: Int) -> String {
    guard row < grid.rows.count, col < grid.days.count else { return "" }
    let value = grid.values[row][col]
    return "\(analyticsShortModel(grid.rows[row].model)) · \(Self.drillDayFormatter.string(from: grid.days[col])) · \(measureValueLabel(value))"
  }

  private func measureValueLabel(_ value: Double) -> String {
    switch measure {
    case .events: return "\(Int(value)) events"
    case .tokens: return "\(TokenFormatter.compact(Int(value))) tokens"
    case .cost: return MoneyFormatter.dollars(value)
    }
  }

  // MARK: Provenance + labels

  /// Binds the aggregable rows ONCE — the two basis probes used to be two separate reads of a computed
  /// property that re-filtered the whole row set each time.
  private static func provenance(of aggregableRows: [ModelDaySummary]) -> DashboardCostProvenance {
    let realPresent = aggregableRows.contains { ProviderBasis.of($0.provider) == .real }
    let notionalPresent = aggregableRows.contains { ProviderBasis.of($0.provider) == .notional }
    if notionalPresent { return realPresent ? .realAndNotionalListPrice : .notionalListPrice }
    return .realSpend
  }

  /// The hero ticker's basis label — the provenance prefix with a window suffix (the shared
  /// `DashboardCostProvenance.basisLabel` is hardcoded to "· TODAY"; this window shows a range). A
  /// fully-unpriced scope (Copilot-only) leads with tokens, so its label says so.
  private func heroBasisLabel(
    _ readout: AnalyticsReadout, provenance: DashboardCostProvenance
  ) -> String {
    if readout.scopeIsFullyUnpriced { return "TOKEN ESTIMATE · LAST \(days) DAYS" }
    let prefix: String
    switch provenance {
    case .realSpend: prefix = "REAL SPEND"
    case .notionalListPrice: prefix = "NOTIONAL LIST-PRICE"
    case .realAndNotionalListPrice: prefix = "REAL + NOTIONAL LIST-PRICE"
    }
    return "\(prefix) · LAST \(days) DAYS"
  }

  private var measureTitle: String { measureName(measure) }

  private func syncSortToMeasure(_ measure: AnalyticsMeasure) {
    switch measure {
    case .events: sort = AnalyticsTableSort(column: .events, ascending: false)
    case .tokens: sort = AnalyticsTableSort(column: .tokens, ascending: false)
    case .cost: sort = AnalyticsTableSort(column: .cost, ascending: false)
    }
  }

  private func sortedModelTotals(_ readout: AnalyticsReadout) -> [AnalyticsModelTotal] {
    let totals = AnalyticsAggregation.modelTotals(rows: tableRows(readout))
    // The MODEL column sorts on the model string (A→Z ascending, case-insensitive); every other column
    // is a numeric `sortValue` sort.
    if sort.column == .model {
      return totals.sorted { lhs, rhs in
        let cmp = analyticsShortModel(lhs.model).localizedCaseInsensitiveCompare(analyticsShortModel(rhs.model))
        return sort.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
      }
    }
    return totals.sorted { lhs, rhs in
      let l = sortValue(lhs), r = sortValue(rhs)
      return sort.ascending ? l < r : l > r
    }
  }

  private func sortValue(_ t: AnalyticsModelTotal) -> Double {
    switch sort.column {
    case .model: 0  // handled by the string-sort branch in `sortedModelTotals`; never reached here
    case .events: Double(t.eventCount)
    case .tokens: Double(t.totalTokens)
    case .input: Double(t.inputTokens)
    case .output: Double(t.outputTokens)
    case .cache5m: Double(t.cache5mTokens)
    case .cache1h: Double(t.cache1hTokens)
    case .cacheRead: Double(t.cacheReadTokens)
    case .cost: t.cost
    }
  }

  // MARK: Formatting helpers

  private static let shortWeekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    return f
  }()

  private static let drillDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d"
    return f
  }()

  /// Short weekday name for a Calendar weekday (1 = Sun … 7 = Sat).
  private static func calendarWeekdayShort(_ weekday: Int) -> String {
    ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][max(0, min(7, weekday))]
  }

  /// A one-hour range label, 12-hour clock: 15 → "3–4 PM", 23 → "11 PM–12 AM".
  private static func hourRangeLabel(_ hour: Int) -> String {
    let end = (hour + 1) % 24
    func h12(_ x: Int) -> Int { x % 12 == 0 ? 12 : x % 12 }
    func meridiem(_ x: Int) -> String { x < 12 ? "AM" : "PM" }
    if meridiem(hour) == meridiem(end), hour != 11 {
      return "\(h12(hour))–\(h12(end)) \(meridiem(end))"
    }
    return "\(h12(hour)) \(meridiem(hour))–\(h12(end)) \(meridiem(end))"
  }

  private func percentInt(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }

  // MARK: - Load + export (off-main cancellable path)

  /// [Regression guard — main-thread stall on open] `modelDaySummaries` / `hourWeekdayBins` are UNBOUNDED
  /// SQL scans under `UsageIndex.withConnectionLock`; on a real large corpus they must never run on the
  /// main thread. A detached load computes BOTH the model rows AND the per-provider rhythm punchcards
  /// (loading Copilot's events ONCE and feeding both bucketings), cancels any prior task, and publishes
  /// only if the timeframe still matches. Two SQL scans per timeframe change — both off-main.
  ///
  /// [CRITICAL] It must be `Task.detached`, never a bare `Task {}`, and `loadData` must stay `nonisolated`.
  /// A `View` conformance infers `@MainActor` onto this WHOLE type (its static members included), and an
  /// unstructured `Task {}` INHERITS the enclosing actor — so the bare form ran both SQL scans plus
  /// `CopilotProvider().loadEvents()` synchronously on the main thread, exactly what this guard forbids.
  /// It also made the cancellation above and `.onDisappear { loadTask?.cancel() }` dead code: with no
  /// suspension point before the scan finished, nothing could observe the cancel. Same shape as
  /// `DashboardWidgetPublisher.publish` and `DashboardViewModel.refresh`.
  private func reload() {
    loadTask?.cancel()
    drill = nil
    let days = days
    let calculator = calculator
    let capturedIndex = index
    loadTask = Task.detached(priority: .utility) {
      let result = Self.loadData(index: capturedIndex, days: days, calculator: calculator)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard self.days == days else { return }
        self.rows = result.rows
        self.rhythmByProvider = result.rhythm
      }
    }
  }

  nonisolated static func loadData(
    index: UsageIndex?, days: Int, calculator: CostCalculator,
    copilot: CopilotProvider = CopilotProvider()
  ) -> (rows: [ModelDaySummary], rhythm: [ProviderID: HourWeekdayMatrix]) {
    let calendar = Calendar.current
    let now = Date()
    let windowStart =
      calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: calendar.startOfDay(for: now))
      ?? now
    let indexedProviders = providerOptions.map(\.id).filter { $0 != .copilot }
      + (CursorHookSetup.state() == .active ? [.cursor] : [])
    // `try?` → empty on a mid-scan SQLite error (never a silently-truncated partial breakdown).
    var rows = (try? index?.modelDaySummaries(
      providers: indexedProviders, days: days,
      calculator: calculator)) ?? []
    var rhythm = (try? index?.hourWeekdayBins(
      providers: indexedProviders, days: days,
      calculator: calculator)) ?? [:]
    // Copilot bypasses the index — load its events ONCE and feed BOTH bucketings.
    // Clamp BOTH bounds to match the SQL path's `ts >= windowStart AND ts <= now` — a lower-bound-only
    // filter would count a future-dated Copilot event (clock skew) where the equivalent Claude/Codex
    // event is excluded.
    let copilotEvents = copilot.loadEvents().filter {
      $0.timestamp >= windowStart && $0.timestamp <= now
    }
    rows.append(contentsOf: ModelDaySummary.bucketed(events: copilotEvents, calculator: calculator))
    rhythm[.copilot] = HourWeekdayMatrix.bucketed(events: copilotEvents, calculator: calculator)
    return (rows, rhythm)
  }

  /// The CSV export needs the same `rows` the dashboard builds — same window clamp, same Copilot
  /// event bucketing — so it delegates to `loadData` rather than re-deriving them (the two copies had
  /// drifted risk). The extra rhythm bucketing `loadData` also computes is discarded; export is a rare,
  /// user-initiated action, so the cost is irrelevant next to guaranteeing export == dashboard.
  private nonisolated static func loadRows(
    index: UsageIndex?, days: Int, calculator: CostCalculator
  ) -> [ModelDaySummary] {
    loadData(index: index, days: days, calculator: calculator).rows
  }

  /// [Regression guard — see the original tray] `isExporting` disables the button so a rapid second click
  /// is a no-op instead of a second concurrent scan / a second `beginSheetModal(for:)` on a window that
  /// already has an attached sheet (undefined AppKit behavior that reads as "randomly closes the window").
  /// `Task.detached` for the same reason `reload()` needs it: a bare `Task {}` inherits this View's
  /// inferred `@MainActor` and would run the export scan on the main thread.
  private func export() {
    guard canExport else { return }
    isExporting = true
    let days = days
    let calculator = calculator
    let capturedIndex = index
    let checked = checkedProviders
    Task.detached(priority: .utility) {
      let allRows = Self.loadRows(index: capturedIndex, days: days, calculator: calculator)
        .filter { checked.contains($0.provider) }
      await MainActor.run {
        defer { self.isExporting = false }
        guard let window = self.windowRef.window, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = AnalyticsCSVExporter.defaultFilename()
        // Offer CSV (spreadsheets), JSON (scripting/warehouse), and Markdown (pasteable). The chosen
        // file type drives which pure Core exporter serializes the SAME rows — `.md` has no standard
        // UTType, so it's registered by filename extension.
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [.commaSeparatedText, .json, markdownType]
        panel.beginSheetModal(for: window) { response in
          guard response == .OK, let url = panel.url else { return }
          let contents: String
          switch url.pathExtension.lowercased() {
          case "json": contents = AnalyticsJSONExporter.json(rows: allRows)
          case "md", "markdown": contents = AnalyticsMarkdownExporter.markdown(rows: allRows)
          default: contents = AnalyticsCSVExporter.csv(rows: allRows)
          }
          try? contents.write(to: url, atomically: true, encoding: .utf8)
        }
      }
    }
  }
}

// MARK: - Measure naming (shared)

private func measureName(_ measure: AnalyticsMeasure) -> String {
  switch measure {
  case .events: "Events"
  case .tokens: "Tokens"
  case .cost: "Spend"
  }
}

// MARK: - Mini stat tile

private struct StatTile: View {
  let label: String
  let value: String
  let caption: String
  // A pure-value leaf (only String inputs) reading `JP.*` freezes at first-render theme, since SwiftUI
  // skips its body when the parent re-colors but the strings are unchanged — see AGENTS.md "Theming
  // System" and the sibling `HeatmapCell`. Observing `ThemeManager` forces the re-render.
  // periphery:ignore - intentional theme dependency.
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(JPAppFont.eyebrow)
        .foregroundStyle(JP.gingerDeep)
      Text(value)
        .font(JPAppFont.metricValue)
        .foregroundStyle(JP.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(caption)
        .font(JPAppFont.micro)
        .foregroundStyle(JP.inkFaint)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, JPAppSpacing.metricCardX)
    .padding(.vertical, JPAppSpacing.metricCardY)
    .background(JP.paper.opacity(0.82), in: RoundedRectangle(cornerRadius: JPAppRadius.metricCard, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: JPAppRadius.metricCard, style: .continuous)
        .strokeBorder(JP.line.opacity(0.85), lineWidth: 0.5))
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Sidebar provider row

/// Brand-mark chip matching the dashboard selector (`SelectorRow` metrics): 18pt box, 16pt white
/// glyph on the provider tint (or bare JP mark when `tintHex` is nil for All providers).
/// A brand-mark chip: the white `provider-*.svg` glyph on the provider's brand tint (or the bare JP
/// mark when `tintHex` is nil). Shared by the Advanced Analytics sidebar and the Live Data window rows
/// so both match the dashboard selector's provider chips exactly. Internal (not `private`) for that reuse.
struct AnalyticsProviderMark: View {
  /// Resource stem under AppResources: `provider-claude` / `jp-menubar`.
  let resourceName: String
  /// Brand tint hex for the chip fill. `nil` = bare mark (All providers / JP).
  let tintHex: String?

  private var metrics: SelectorRowIconMetrics {
    tintHex == nil ? .allProviders : .provider
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
        .fill(tintHex.map { JP.providerTint($0) } ?? Color.clear)
      if metrics.drawsOutline {
        RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
          .strokeBorder(.white.opacity(0.22), lineWidth: 1)
      }
      if let img = AppResources.icon(named: resourceName) {
        Image(nsImage: img)
          .resizable()
          .interpolation(.high)
          .renderingMode(tintHex == nil ? .original : .template)
          .scaledToFit()
          .foregroundStyle(.white)
          .frame(width: metrics.imageSize, height: metrics.imageSize)
      }
    }
    .frame(width: metrics.containerSize, height: metrics.containerSize)
    .accessibilityHidden(true)
  }
}

private struct SidebarProviderRow: View {
  let option: AnalyticsProviderOption
  let basis: ProviderBasis
  let figure: String
  let tintHex: String
  let isFocused: Bool
  let onFocus: () -> Void
  @Binding var isOn: Bool

  var body: some View {
    // [Layout note] The NAME (focus action) and the CHECKBOX (include/exclude) are TRUE SIBLINGS — a
    // focus Button next to a Toggle, never one nested in the other. Per AGENTS.md's `SelectorRow`
    // tap-target lesson, a Button nested inside another Button's label silently swallows the inner tap
    // on macOS. The focus button owns chip+name+badge+figure (a generous target); the Toggle sits apart.
    HStack(spacing: 8) {
      Button(action: onFocus) {
        HStack(spacing: 8) {
          AnalyticsProviderMark(
            resourceName: "provider-\(option.id.rawValue)", tintHex: tintHex)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
              Text(option.name)
                .font(JPAppFont.bodyStrong)
                .foregroundStyle(isFocused ? JP.gingerDeep : JP.ink)
                .lineLimit(1)
              if isFocused {
                Image(systemName: "scope").font(JPAppFont.menuChevron).foregroundStyle(JP.gingerDeep)
              }
            }
            HStack(spacing: 5) {
              badge
              Text(figure)
                .font(JPAppFont.metricSmall)
                .foregroundStyle(JP.inkSoft)
                .lineLimit(1)
            }
          }
          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(isFocused ? "Showing only \(option.name) — click to show all" : "Focus the canvas on \(option.name)")
      Toggle("", isOn: $isOn)
        .toggleStyle(.checkbox)
        .labelsHidden()
        .help("Include \(option.name) in the view and export")
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(option.name), \(basis.badge), \(figure)\(isFocused ? ", focused" : ""), \(isOn ? "included" : "excluded")")
  }

  /// `estimate` (Copilot) borrows the provider's own tint at a light wash — a whole ROW excluded from
  /// every `$` total is a different KIND of thing than a `notional`/`real` caveat on a real figure (the
  /// shipped `SelectorRow` precedent). `real`/`notional` use the sage/honey pill vocabulary.
  private var badge: some View {
    let (fill, text): (Color, Color)
    switch basis {
    case .real, .officialPlan: (fill, text) = (JP.sage.opacity(0.2), JP.sageDeep)
    case .notional: (fill, text) = (JP.honey.opacity(0.25), JP.gingerDeep)
    case .estimate, .gateway:
      (fill, text) = (JP.providerTint(tintHex).opacity(0.18), JP.providerTint(tintHex))
    }
    return Text(basis.badge)
      .font(JPAppFont.microMedium)
      .lineLimit(1)
      .fixedSize()
      .labelBadgeLayout()
      .background(fill, in: RoundedRectangle(cornerRadius: JPAppRadius.chip, style: .continuous))
      .foregroundStyle(text)
  }
}

// MARK: - Measure segmented control

private struct AnalyticsMeasureControl: View {
  @Binding var measure: AnalyticsMeasure

  var body: some View {
    AnalyticsSegmentedControl(
      selection: $measure, options: AnalyticsMeasure.allCases,
      displayLabel: segmentLabel, accessibilityLabel: measureName)
  }

  private func segmentLabel(_ measure: AnalyticsMeasure) -> String {
    switch measure {
    case .events: "Events"
    case .tokens: "Tokens"
    case .cost: "$"
    }
  }
}

// MARK: - Grain segmented control (same proven pattern as AnalyticsMeasureControl)

private struct AnalyticsGrainControl: View {
  @Binding var grain: AnalyticsGrain

  var body: some View {
    AnalyticsSegmentedControl(
      selection: $grain, options: AnalyticsGrain.allCases,
      displayLabel: label, accessibilityLabel: label)
  }

  private func label(_ grain: AnalyticsGrain) -> String {
    switch grain {
    case .calendar: "Calendar"
    case .rhythm: "Rhythm"
    case .modelDay: "Model × Day"
    }
  }
}

private struct AnalyticsSegmentedControl<Option: Hashable>: View {
  @Binding var selection: Option
  let options: [Option]
  let displayLabel: (Option) -> String
  let accessibilityLabel: (Option) -> String

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(options.enumerated()), id: \.element) { index, option in
        if index != 0 {
          Rectangle().fill(JP.line).frame(width: 1)
        }
        Button(action: { selection = option }) {
          Text(displayLabel(option))
            .font(JPAppFont.captionStrong)
            .foregroundStyle(selection == option ? JP.gingerDeep : JP.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(selection == option ? JP.gingerDeep.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(option))
        .accessibilityAddTraits(selection == option ? [.isSelected] : [])
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .background(JP.paper)
    .clipShape(RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
        .strokeBorder(JP.line, lineWidth: 1))
  }

}

// MARK: - Shared heatmap cell

/// ONE heatmap cell — a `RoundedRectangle` filled from the luminance-monotonic `HeatmapRamp` over the
/// theme track, with a hover/help tooltip + accessibility label. Observes `ThemeManager` directly (the
/// documented static-leaf theme-freeze lesson). When `onTap` is set the cell is a `Button` (drill-down)
/// and a selected cell shows a strong ring. Every grain grid (Calendar / Rhythm / Model × Day) renders
/// with this cell so they share one look and one theme-safe path.
private struct HeatmapCell: View {
  let intensity: Double  // 0…1, already min-anchored / floored by the grid
  let isEmpty: Bool
  let accentHex: String
  let tooltip: String
  var isSelected: Bool = false
  var size: CGFloat = JPAppSpacing.analyticsHeatmapCell
  /// Cells are square by default; the calendar grain widens them (height stays `size`) so a one-month
  /// window fills the canvas width instead of hugging the left edge.
  var width: CGFloat? = nil
  var onTap: (() -> Void)? = nil
  @ObservedObject private var themeManager = ThemeManager.shared

  /// A nonzero cell's minimum visible intensity, so the lowest-activity cell is still distinguishable
  /// from an empty one (min-anchored `SparklineScale.fractions` maps the least value to 0).
  static let minVisibleIntensity = 0.18

  private var fill: Color {
    heatmapCellColor(
      t: isEmpty ? 0 : intensity, accentHex: accentHex, trackHex: themeManager.theme.track)
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: JPAppRadius.tile, style: .continuous)
    let tile =
      shape
      .fill(fill)
      .overlay(
        shape.strokeBorder(
          isSelected ? JP.ink : JP.line.opacity(0.5), lineWidth: isSelected ? 1.4 : 0.5))
      .frame(width: width ?? size, height: size)
      .help(tooltip)
      .accessibilityLabel(tooltip)
    if let onTap {
      Button(action: onTap) { tile.contentShape(Rectangle()) }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    } else {
      tile
    }
  }
}

// MARK: - Calendar heatmap grid (GitHub-contributions style)

/// A month-blocked calendar heatmap: one block per calendar month the window spans, X = week columns,
/// Y = 7 weekday rows, one cell per local calendar day, colored by the sidebar Measure through the
/// luminance-monotonic `HeatmapRamp`.
/// Empty (no-activity) days render the bare `track` groove so "no data" never reads as "low data".
private struct HeatmapGrid: View {
  let days: [HeatmapDay]
  let measure: AnalyticsMeasure
  let accentHex: String
  var selectedDay: Date? = nil
  var onTapDay: ((Date) -> Void)? = nil

  private var gap: CGFloat { JPAppSpacing.analyticsHeatmapGap }

  /// Whole calendar months (week columns × 7 weekday rows) instead of the ragged 2–3 columns a 14-day
  /// window used to occupy, and each day cell WIDENS to fill the canvas width (row height stays fixed, so
  /// the no-scroll budget is unaffected) instead of leaving the right two-thirds of the canvas empty.
  /// Days inside the month but outside the selected timeframe render recessive — never "no activity".
  var body: some View {
    let blocks = CalendarMonthLayout.months(days: days)
    let totalColumns = blocks.reduce(0) { $0 + $1.columns.count }
    // [Perf] One start-of-day-keyed lookup built for the whole grid. `slotView` used to resolve each
    // cell with `days.firstIndex { startOfDay($0.day) == startOfDay(day.day) }` — O(n²) over the window
    // with two `startOfDay` calls per comparison, re-run for every cell on every resize frame (this is
    // all inside the `GeometryReader`).
    let lookup = Self.dayLookup(days: days, selectedDay: selectedDay)
    GeometryReader { proxy in
      let cellWidth = Self.fittedCellWidth(
        width: proxy.size.width, columns: totalColumns, blocks: blocks.count)
      HStack(alignment: .top, spacing: Self.blockGap) {
        weekdayLabels
        ForEach(blocks) { block in monthBlock(block, lookup: lookup, cellWidth: cellWidth) }
        Spacer(minLength: 0)
      }
    }
    .frame(height: Self.gridHeight)
  }

  /// Per-cell inputs resolved once for the whole grid: every in-window day's min-anchored intensity
  /// fraction keyed by start-of-day, plus the selected day already normalized the same way so a cell's
  /// selection test is one `Date` compare.
  private struct DayLookup {
    let fractionByDay: [Date: Double]
    let selectedStart: Date?
  }

  private static func dayLookup(days: [HeatmapDay], selectedDay: Date?) -> DayLookup {
    let calendar = Calendar.current
    let fractions = SparklineScale.fractions(days.map(\.value))
    var fractionByDay: [Date: Double] = [:]
    fractionByDay.reserveCapacity(days.count)
    for (index, day) in days.enumerated() where index < fractions.count {
      // First entry wins, exactly like the `firstIndex` scan this replaced.
      let key = calendar.startOfDay(for: day.day)
      if fractionByDay[key] == nil { fractionByDay[key] = fractions[index] }
    }
    return DayLookup(
      fractionByDay: fractionByDay,
      selectedStart: selectedDay.map { calendar.startOfDay(for: $0) })
  }

  /// Day cells grow horizontally to consume the whole canvas width, clamped so a one-month window can't
  /// balloon into slabs and a four-month (90-day) window can't shrink below the legible floor.
  static func fittedCellWidth(width: CGFloat, columns: Int, blocks: Int) -> CGFloat {
    guard columns > 0, width > 0 else { return JPAppSpacing.analyticsHeatmapCell }
    let gap = JPAppSpacing.analyticsHeatmapGap
    let chrome = labelColumnWidth + blockGap * CGFloat(blocks + 1)
    let available = width - chrome - gap * CGFloat(max(columns - 1, 0))
    let fitted = available / CGFloat(columns)
    return min(max(fitted, JPAppSpacing.analyticsHeatmapCell), maxCellWidth)
  }

  private static let labelColumnWidth: CGFloat = 26
  private static let blockGap: CGFloat = 12
  /// Row height is FIXED (only the width flexes), so switching grains or widening the timeframe can never
  /// grow the no-scroll canvas past the window.
  private static let rowHeight: CGFloat = 18
  private static let maxCellWidth: CGFloat = 120
  private static let gridHeight: CGFloat =
    7 * rowHeight + 6 * JPAppSpacing.analyticsHeatmapGap + 18

  private func monthBlock(
    _ block: CalendarMonthBlock, lookup: DayLookup, cellWidth: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(block.label)
        .font(JPAppFont.micro)
        .foregroundStyle(JP.inkFaint)
        .accessibilityHidden(true)
      HStack(alignment: .top, spacing: gap) {
        ForEach(Array(block.columns.enumerated()), id: \.offset) { _, column in
          VStack(spacing: gap) {
            ForEach(Array(column.enumerated()), id: \.offset) { _, slot in
              slotView(slot, lookup: lookup, cellWidth: cellWidth)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func slotView(_ slot: CalendarSlot, lookup: DayLookup, cellWidth: CGFloat) -> some View {
    switch slot {
    case .blank:
      Color.clear.frame(width: cellWidth, height: Self.rowHeight)
    case .outOfWindow:
      RoundedRectangle(cornerRadius: JPAppRadius.tile, style: .continuous)
        .fill(JP.line.opacity(0.25))
        .frame(width: cellWidth, height: Self.rowHeight)
        .accessibilityHidden(true)
    case .day(let day):
      let start = Calendar.current.startOfDay(for: day.day)
      HeatmapCell(
        intensity: max(lookup.fractionByDay[start] ?? 0, HeatmapCell.minVisibleIntensity),
        isEmpty: day.value <= 0, accentHex: accentHex, tooltip: tooltip(day),
        isSelected: lookup.selectedStart == start, size: Self.rowHeight, width: cellWidth,
        onTap: (day.value > 0 && onTapDay != nil) ? { onTapDay?(day.day) } : nil)
    }
  }

  private var weekdayLabels: some View {
    VStack(alignment: .trailing, spacing: gap) {
      // Offset by the month-label row so the labels line up with their weekday rows.
      Color.clear.frame(width: Self.labelColumnWidth, height: 14)
      ForEach(0..<7, id: \.self) { row in
        Text(weekdayLabel(row))
          .font(JPAppFont.micro)
          .foregroundStyle(JP.inkFaint)
          .frame(width: Self.labelColumnWidth, height: Self.rowHeight, alignment: .trailing)
      }
    }
    .accessibilityHidden(true)
  }

  /// Row 0 is the calendar's first weekday (Sunday in the US locale) — label the 2nd, 4th and 6th rows.
  private func weekdayLabel(_ row: Int) -> String {
    let symbols = Calendar.current.shortWeekdaySymbols
    let index = (Calendar.current.firstWeekday - 1 + row) % 7
    return row % 2 == 1 ? symbols[index] : ""
  }

  /// Cached like the tray's own `shortWeekdayFormatter` / `drillDayFormatter`: this is called once per DAY
  /// CELL (up to ~120 in a 90-day window) and constructing a `DateFormatter` spins up an ICU formatter
  /// every time — on every resize frame, since the grid lives in a `GeometryReader`.
  private static let tooltipDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE MMM d"
    return f
  }()

  private func tooltip(_ day: HeatmapDay) -> String {
    let valueLabel: String
    switch measure {
    case .events: valueLabel = "\(Int(day.value)) events"
    case .tokens: valueLabel = "\(TokenFormatter.compact(Int(day.value))) tokens"
    case .cost: valueLabel = MoneyFormatter.dollars(day.value)
    }
    return "\(Self.tooltipDayFormatter.string(from: day.day)) · \(valueLabel)"
  }
}

// MARK: - Labeled row×column heatmap grid (Rhythm + Model × Day)

/// A generic labeled heatmap: left row labels + a rectangular grid of `HeatmapCell`s. Intensities are
/// min-anchored across the WHOLE grid (`SparklineScale.fractions` over the flattened values) so one
/// scale spans every cell. Used by the Rhythm (7 weekday rows × 24 hour columns) and Model × Day grains.
struct LabeledHeatmapGrid: View {
  let rowLabels: [String]
  let rowLabelWidth: CGFloat
  let values: [[Double]]
  let accentHex: String
  let cellTooltip: (Int, Int) -> String
  var selected: (Int, Int)? = nil
  var onTap: ((Int, Int) -> Void)? = nil

  private var cell: CGFloat { JPAppSpacing.analyticsHeatmapCell }
  private var gap: CGFloat { JPAppSpacing.analyticsHeatmapGap }

  /// Cells WIDEN to fill the canvas (row height stays `analyticsHeatmapCell`, so the fixed-height
  /// no-scroll budget is untouched) — the same treatment the Calendar grain gets, so neither Rhythm nor
  /// Model × Day leaves the right third of the canvas empty. Guard: `HeatmapFillWidthTests`.
  var body: some View {
    let flat = values.flatMap { $0 }
    let fractions = SparklineScale.fractions(flat)
    let cols = values.first?.count ?? 0
    GeometryReader { proxy in
      let layout = Self.fittedLayout(
        width: proxy.size.width, columns: cols, rowLabelWidth: rowLabelWidth)
      let cellWidth = layout.cell
      VStack(alignment: .leading, spacing: gap) {
        ForEach(Array(values.enumerated()), id: \.offset) { rowIndex, rowValues in
          HStack(spacing: layout.gap) {
            Text(rowIndex < rowLabels.count ? rowLabels[rowIndex] : "")
              .font(JPAppFont.micro)
              .foregroundStyle(JP.inkFaint)
              .lineLimit(1)
              .frame(width: rowLabelWidth, alignment: .trailing)
            ForEach(0..<cols, id: \.self) { col in
              let value = rowValues[col]
              let flatIndex = rowIndex * cols + col
              let fraction = flatIndex < fractions.count ? fractions[flatIndex] : 0
              HeatmapCell(
                intensity: max(fraction, HeatmapCell.minVisibleIntensity),
                isEmpty: value <= 0, accentHex: accentHex, tooltip: cellTooltip(rowIndex, col),
                isSelected: selected.map { $0 == (rowIndex, col) } ?? false, size: cell,
                width: cellWidth,
                onTap: (value > 0 && onTap != nil) ? { onTap?(rowIndex, col) } : nil)
            }
            Spacer(minLength: 0)
          }
        }
      }
    }
    .frame(height: CGFloat(values.count) * cell + CGFloat(max(values.count - 1, 0)) * gap)
  }

  /// Cell width AND the gap that goes with it, both sized so the row exactly spans the canvas.
  /// A 24-column Rhythm row and a 14-column Model × Day row widen toward `maxCellWidth`; a 90-day
  /// Model × Day row goes the other way and must SHRINK below the square cell size (with a tighter gap)
  /// rather than run off the right edge — at 90 columns the square size would need 1,740pt of a 663pt
  /// canvas.
  static func fittedLayout(width: CGFloat, columns: Int, rowLabelWidth: CGFloat)
    -> (cell: CGFloat, gap: CGFloat)
  {
    let standardGap = JPAppSpacing.analyticsHeatmapGap
    guard columns > 0, width > 0 else { return (JPAppSpacing.analyticsHeatmapCell, standardGap) }
    func fit(gap: CGFloat) -> CGFloat {
      (width - rowLabelWidth - gap * CGFloat(columns)) / CGFloat(columns)
    }
    let standard = fit(gap: standardGap)
    // Dense grids (90-day windows) get the tight gap so the cell itself keeps as much width as possible.
    let gap = standard < tightGapThreshold ? tightGap : standardGap
    let cell = min(max(gap == tightGap ? fit(gap: tightGap) : standard, minCellWidth), maxCellWidth)
    return (cell, gap)
  }

  private static let maxCellWidth: CGFloat = 64
  private static let minCellWidth: CGFloat = 3
  private static let tightGapThreshold: CGFloat = 8
  private static let tightGap: CGFloat = 1
}

// MARK: - Token-mix composition bar + legend

/// A horizontal stacked bar of the five token buckets — the dashboard's `Composition` tiled-`Rectangle`
/// idiom, each segment a distinct legible palette tint (never gold, which is mascot-art only). An empty
/// mix shows the bare track groove.
private struct TokenMixBar: View {
  let mix: TokenMix
  // Observe the theme so this pure-value leaf re-renders on a theme change (else it freezes at the
  // first-render palette). The tints are an INSTANCE computed property, not a `static let` — a static
  // color array snapshots `JP.*` once for the process lifetime and never re-tints (AGENTS.md "Theming").
  // periphery:ignore - intentional theme dependency.
  @ObservedObject private var themeManager = ThemeManager.shared

  private var segmentTints: [Color] { [JP.ginger, JP.sage, JP.honey, JP.coral, JP.inkSoft] }

  private var counts: [Int] { [mix.input, mix.output, mix.cache5m, mix.cache1h, mix.cacheRead] }

  var body: some View {
    GeometryReader { geo in
      let total = max(mix.total, 1)
      HStack(spacing: 0) {
        ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
          Rectangle()
            .fill(segmentTints[index].opacity(0.9))
            .frame(width: max(0, geo.size.width * Double(count) / Double(total)))
        }
      }
    }
    .frame(height: 10)
    .background(JP.trackFill, in: Capsule())
    .clipShape(Capsule())
    .overlay(Capsule().strokeBorder(JP.line.opacity(0.6), lineWidth: 0.5))
    .accessibilityHidden(true)
  }
}

private struct TokenMixLegend: View {
  // Zero-input static leaf: observe the theme (else it freezes) and keep `entries` an INSTANCE computed
  // property so each swatch re-reads `JP.*` per render instead of a process-lifetime `static let` snapshot.
  // periphery:ignore - intentional theme dependency.
  @ObservedObject private var themeManager = ThemeManager.shared

  private var entries: [(Color, String)] {
    [(JP.ginger, "In"), (JP.sage, "Out"), (JP.honey, "C5m"), (JP.coral, "C1h"), (JP.inkSoft, "Read")]
  }

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
        HStack(spacing: 3) {
          Circle().fill(entry.0.opacity(0.9)).frame(width: 6, height: 6)
          Text(entry.1).font(JPAppFont.micro).foregroundStyle(JP.inkFaint)
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Sortable per-model table

private struct AnalyticsModelTable: View {
  let totals: [AnalyticsModelTotal]
  @Binding var sort: AnalyticsTableSort

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(JP.line).frame(height: 1)
      if totals.isEmpty {
        Text("No model activity in this window.")
          .font(JPAppFont.caption)
          .foregroundStyle(JP.inkFaint)
          .padding(.vertical, JPAppSpacing.rowY)
      } else {
        ForEach(Array(totals.enumerated()), id: \.element.id) { offset, total in
          row(total)
          if offset != totals.count - 1 { Rectangle().fill(JP.line.opacity(0.5)).frame(height: 1) }
        }
      }
    }
    .padding(.horizontal, JPAppSpacing.metricCardX)
    .padding(.vertical, JPAppSpacing.metricCardY)
    .background(JP.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: JPAppRadius.metricCard, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: JPAppRadius.metricCard, style: .continuous)
        .strokeBorder(JP.line.opacity(0.85), lineWidth: 0.5))
  }

  private var header: some View {
    // Every column is sortable — MODEL sits left-aligned in the same fixed 150 width as its value
    // column; the numeric headers are trailing-aligned so each header sits directly above its numbers.
    HStack(spacing: 0) {
      headerCell("MODEL", .model, alignment: .leading, width: 150)
      headerCell("EVENTS", .events)
      headerCell("IN", .input)
      headerCell("OUT", .output)
      headerCell("C5M", .cache5m)
      headerCell("C1H", .cache1h)
      headerCell("READ", .cacheRead)
      headerCell("COST", .cost)
    }
    .padding(.bottom, 5)
  }

  private func headerCell(
    _ label: String, _ column: AnalyticsTableColumn,
    alignment: Alignment = .trailing, width: CGFloat? = nil
  ) -> some View {
    Button(action: {
      if sort.column == column {
        sort.ascending.toggle()
      } else {
        sort = AnalyticsTableSort(column: column, ascending: false)
      }
    }) {
      let content = HStack(spacing: 2) {
        Text(label)
          .font(JPAppFont.eyebrow)
          .foregroundStyle(sort.column == column ? JP.gingerDeep : JP.inkFaint)
        if sort.column == column {
          Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
            .font(JPAppFont.menuChevron)
            .foregroundStyle(JP.gingerDeep)
        }
      }
      Group {
        if let width {
          content.frame(width: width, alignment: alignment)
        } else {
          content.frame(maxWidth: .infinity, alignment: alignment)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Sort by \(label)")
  }

  private func row(_ total: AnalyticsModelTotal) -> some View {
    let basis = ProviderBasis.of(total.provider)
    return HStack(spacing: 0) {
      HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: JPAppRadius.tile, style: .continuous)
          .fill(JP.providerTint(analyticsTintHex(total.provider)))
          .frame(width: 9, height: 9)
        Text(analyticsShortModel(total.model))
          .font(JPAppFont.label)
          .foregroundStyle(JP.inkSoft)
          .lineLimit(1)
      }
      .frame(width: 150, alignment: .leading)
      numberCell("\(total.eventCount)")
      numberCell(TokenFormatter.compact(total.inputTokens))
      numberCell(TokenFormatter.compact(total.outputTokens))
      numberCell(TokenFormatter.compact(total.cache5mTokens))
      numberCell(TokenFormatter.compact(total.cache1hTokens))
      numberCell(TokenFormatter.compact(total.cacheReadTokens))
      costCell(total, basis: basis)
    }
    .padding(.vertical, JPAppSpacing.rowY)
    .accessibilityElement(children: .combine)
  }

  private func numberCell(_ text: String) -> some View {
    Text(text)
      .font(JPAppFont.metricSmall)
      .foregroundStyle(JP.inkSoft)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .trailing)
  }

  /// A fully-unpriced provider (Copilot) shows its TOKEN total, never a dead `$0.00`; Codex/Claude show
  /// dollars (Codex's notional basis is disclosed by the table footnote + the sidebar basis key).
  private func costCell(_ total: AnalyticsModelTotal, basis: ProviderBasis) -> some View {
    Text(basis.showsTokens ? TokenFormatter.compact(total.totalTokens) : MoneyFormatter.dollars(total.cost))
      .font(JPAppFont.metricSmall)
      .foregroundStyle(basis.showsTokens ? JP.gingerDeep : JP.ink)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .trailing)
  }
}

/// The Advanced Analytics deep-dive tray. Window mechanics — child-window attachment
/// (`addChildWindow(_:ordered:)`, explicitly NOT a second independent top-level window), anchoring, drag
/// lock, and observer teardown — live in `TrayChildWindowController`, which this and the Live Data /
/// Themes trays share. The deltas owned here: the hosted view, a fixed-default RESIZABLE canvas, staying
/// and staying NON-key.
@MainActor
final class AdvancedAnalyticsWindowController: TrayChildWindowController {
  private let index: UsageIndex?
  private let pricing: PricingTable
  private let windowRef = TrayWindowRef()

  init(
    index: UsageIndex?, pricing: PricingTable, dashboardChrome: DashboardChromeState,
    notificationCenter: NotificationCenter = .default
  ) {
    self.index = index
    self.pricing = pricing
    super.init(
      dashboardChrome: dashboardChrome,
      notificationCenter: notificationCenter,
      // A fixed-default, resizable canvas: the hosting view fills the window rather than shrinking to its
      // intrinsic content, and the min size floors a user resize.
      contentSizing: .fixedResizable(
        default: NSSize(
          width: JPAppSpacing.analyticsWindowW, height: JPAppSpacing.analyticsWindowH),
        min: NSSize(
          width: JPAppSpacing.analyticsWindowMinW, height: JPAppSpacing.analyticsWindowMinH)),
      // Stay non-key so the dashboard keeps key focus and its footer toggle icon stays single-click live:
      // clicking it a second time then reliably CLOSES the panel (a window that becomes key on
      // interaction swallows the next footer click as an AppKit first-mouse that only re-keys the
      // dashboard). The panel has no text-input fields, so this never blocks interaction — its
      // checkboxes/buttons/heatmap cells still respond.
      keyPolicy: .nonKeyOnlyIfNeeded)
  }

  override func makeRootView() -> AnyView {
    AnyView(AdvancedAnalyticsTrayView(index: index, pricing: pricing, windowRef: windowRef))
  }

  override func windowDidOpen(_ window: NSWindow) {
    windowRef.window = window
  }

  override func willTearDown() {
    windowRef.window = nil
  }
}
