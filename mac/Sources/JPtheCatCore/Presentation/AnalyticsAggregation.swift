import Foundation

/// Which quantity the Advanced Analytics calendar heatmap (and the model table's sort accent) colors by.
/// `events` is the default — a pure activity count with zero tri-basis (real/notional/estimate) problem,
/// so the heatmap never has to reconcile Claude real dollars, Codex notional list price, and Copilot's
/// unpriced token estimate in one scale.
public enum AnalyticsMeasure: String, Sendable, CaseIterable {
	case events
	case tokens
	case cost
}

/// One local-calendar-day's rolled-up measure total for the heatmap. `day` is `calendar.startOfDay`.
public struct HeatmapDay: Sendable, Equatable, Identifiable {
	public let day: Date
	public let value: Double
	public var id: Date { day }
	public init(day: Date, value: Double) {
		self.day = day
		self.value = value
	}
}

/// One slot in a `CalendarMonthBlock` week column.
/// `.day` is a day inside the selected timeframe (colored by its measure value); `.outOfWindow` is a real
/// calendar day of that month that simply falls outside the timeframe (drawn recessive, never as "no
/// activity"); `.blank` is grid padding before the 1st / after the last of the month.
public enum CalendarSlot: Sendable, Equatable {
	case blank
	case outOfWindow(Date)
	case day(HeatmapDay)
}

/// One calendar month rendered as GitHub-style week COLUMNS × 7 weekday rows, so the calendar grain shows
/// whole months (not just the ragged 2–3 week columns a 14-day window would otherwise occupy).
public struct CalendarMonthBlock: Sendable, Equatable, Identifiable {
	public let monthStart: Date
	public let label: String
	/// `columns[week][weekdayRow]`, weekday row 0 = the calendar's first weekday.
	public let columns: [[CalendarSlot]]
	public var id: Date { monthStart }
}

/// Builds the calendar grain's month blocks: every calendar month spanned by `days` (oldest → newest),
/// each padded out to full weeks. Pure; guard: `CalendarMonthLayoutTests`.
public enum CalendarMonthLayout {
	public static func months(
		days: [HeatmapDay],
		calendar: Calendar = .current,
		labelFormatter: DateFormatter? = nil
	) -> [CalendarMonthBlock] {
		guard let first = days.first?.day, let last = days.last?.day else { return [] }
		// `uniquingKeysWith`, never `uniqueKeysWithValues` — the latter TRAPS on a duplicate day, and a
		// duplicated bucket would take the whole analytics window down rather than render one cell twice.
		let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.day), $0) }) { _, last in last }
		let formatter = labelFormatter ?? Self.defaultLabelFormatter
		var blocks: [CalendarMonthBlock] = []
		var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: first))
		let lastMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: last))

		while let monthStart = cursor, let end = lastMonthStart, monthStart <= end {
			guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { break }
			// Leading blanks so the 1st lands on its real weekday row.
			let lead = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
			var slots = [CalendarSlot](repeating: .blank, count: lead)
			for offset in 0..<range.count {
				guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
				if let hit = byDay[calendar.startOfDay(for: date)] {
					slots.append(.day(hit))
				} else {
					slots.append(.outOfWindow(date))
				}
			}
			while slots.count % 7 != 0 { slots.append(.blank) }
			let columns = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<($0 + 7)]) }
			blocks.append(
				CalendarMonthBlock(
					monthStart: monthStart, label: formatter.string(from: monthStart), columns: columns))
			cursor = calendar.date(byAdding: .month, value: 1, to: monthStart)
		}
		return blocks
	}

	private static let defaultLabelFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.setLocalizedDateFormatFromTemplate("MMM")
		return formatter
	}()
}

/// One `(provider, model)` collapsed total for the Advanced Analytics model table — every day's
/// `ModelDaySummary` rows for the same provider+model summed together.
public struct AnalyticsModelTotal: Sendable, Equatable, Identifiable {
	public let provider: ProviderID
	public let model: String
	public let eventCount: Int
	public let inputTokens: Int
	public let outputTokens: Int
	public let cache5mTokens: Int
	public let cache1hTokens: Int
	public let cacheReadTokens: Int
	public let cost: Double

	public var totalTokens: Int {
		inputTokens + outputTokens + cache5mTokens + cache1hTokens + cacheReadTokens
	}
	public var id: String { "\(provider.rawValue)::\(model)" }

	public init(
		provider: ProviderID, model: String, eventCount: Int, inputTokens: Int, outputTokens: Int,
		cache5mTokens: Int, cache1hTokens: Int, cacheReadTokens: Int, cost: Double
	) {
		self.provider = provider
		self.model = model
		self.eventCount = eventCount
		self.inputTokens = inputTokens
		self.outputTokens = outputTokens
		self.cache5mTokens = cache5mTokens
		self.cache1hTokens = cache1hTokens
		self.cacheReadTokens = cacheReadTokens
		self.cost = cost
	}
}

/// The five token buckets rolled up for the current analytics scope — the source for the token-mix
/// composition bar and its cache-efficiency caption. Cache read is the hit numerator; every bucket is
/// the denominator (`total`), so a high `cacheHitRate` means most tokens were served from cache.
public struct TokenMix: Sendable, Equatable {
	public let input: Int
	public let output: Int
	public let cache5m: Int
	public let cache1h: Int
	public let cacheRead: Int

	public init(input: Int, output: Int, cache5m: Int, cache1h: Int, cacheRead: Int) {
		self.input = input
		self.output = output
		self.cache5m = cache5m
		self.cache1h = cache1h
		self.cacheRead = cacheRead
	}

	public var total: Int { input + output + cache5m + cache1h + cacheRead }
	/// Cache read ÷ every token bucket; 0 when there are no tokens (never a divide-by-zero).
	public var cacheHitRate: Double { total == 0 ? 0 : Double(cacheRead) / Double(total) }
}

/// A models-as-rows × days-as-columns intensity grid for the Advanced Analytics "Model×Day" heatmap
/// grain — derived from the already-loaded `[ModelDaySummary]` (NO new query). Rows are sorted by the
/// scoped `measure` total (busiest model first) and capped at `topModels` so the grid stays within the
/// window's no-scroll budget; `days` is the dense window (one column per local day, oldest → newest).
public struct ModelDayGrid: Sendable, Equatable {
	public struct Row: Sendable, Equatable, Identifiable {
		public let provider: ProviderID
		public let model: String
		public let total: Double
		public var id: String { "\(provider.rawValue)::\(model)" }
		public init(provider: ProviderID, model: String, total: Double) {
			self.provider = provider
			self.model = model
			self.total = total
		}
	}

	public let rows: [Row]
	public let days: [Date]
	/// `values[rowIndex][dayIndex]` — the `measure` value for that (provider, model) on that day.
	public let values: [[Double]]

	public init(rows: [Row], days: [Date], values: [[Double]]) {
		self.rows = rows
		self.days = days
		self.values = values
	}
}

/// Which slice a heatmap cell click pins the model table to (Advanced Analytics drill-down). The
/// Rhythm grain resolves to a WEEKDAY (not weekday+hour): the by-model table is day-grained — a
/// `ModelDaySummary` carries no hour-of-day — so an hour filter is not representable there; the clicked
/// hour lives in the view's own selection (for the pill label + click-to-clear toggle), while the table
/// scopes to every matching weekday in the window.
public enum AnalyticsDrillFilter: Sendable, Equatable {
	case day(Date)
	case weekday(Int)  // Calendar weekday 1…7
	case modelDay(provider: ProviderID, model: String, day: Date)
}

/// Pure, testable client-side re-shaping of the already-loaded `[ModelDaySummary]` for the Advanced
/// Analytics readout canvas — NO new Core query. The tray already loads `modelDaySummaries` (Claude/Codex
/// via `UsageIndex`, Copilot via `ModelDaySummary.bucketed`), and these functions derive the calendar
/// heatmap, the model table, the model×day grid, the token mix, and the drill-down filter straight from
/// those rows, so the left canvas stays a pure rendering of (scope × timeframe × measure) with no second
/// on-disk scan.
public enum AnalyticsAggregation {
	/// The measure value of a single `(provider, model, day)` row.
	public static func value(_ row: ModelDaySummary, measure: AnalyticsMeasure) -> Double {
		switch measure {
		case .events:
			return Double(row.eventCount)
		case .tokens:
			return Double(
				row.inputTokens + row.outputTokens + row.cache5mTokens + row.cache1hTokens
					+ row.cacheReadTokens)
		case .cost:
			return row.cost
		}
	}

	/// Per-local-calendar-day totals for `measure`, DENSE (one entry per day in the window, zero-filled),
	/// oldest → newest with the last entry == today. `rows` should already be filtered to the providers
	/// you want counted (e.g. exclude Copilot for the `.cost` measure). `ModelDaySummary.day` is already
	/// `calendar.startOfDay`, so this is a pure re-bucket.
	public static func heatmapDays(
		rows: [ModelDaySummary],
		measure: AnalyticsMeasure,
		days: Int,
		now: Date = Date(),
		calendar: Calendar = .current
	) -> [HeatmapDay] {
		let count = max(days, 1)
		let startOfToday = calendar.startOfDay(for: now)
		guard let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday)
		else { return [] }

		var buckets = [Double](repeating: 0, count: count)
		for row in rows {
			let day = calendar.startOfDay(for: row.day)
			guard let offset = calendar.dateComponents([.day], from: windowStart, to: day).day,
				offset >= 0, offset < count
			else { continue }
			buckets[offset] += value(row, measure: measure)
		}

		return buckets.enumerated().compactMap { offset, total in
			guard let day = calendar.date(byAdding: .day, value: offset, to: windowStart) else { return nil }
			return HeatmapDay(day: day, value: total)
		}
	}

	/// Collapses `rows` to one total per `(provider, model)`, summing every day's counts/cost. Natural
	/// stable order (provider rawValue, then model); the view applies the user's chosen sort on top.
	public static func modelTotals(rows: [ModelDaySummary]) -> [AnalyticsModelTotal] {
		struct Key: Hashable { let provider: ProviderID; let model: String }
		var acc: [Key: AnalyticsModelTotal] = [:]
		var order: [Key] = []
		for row in rows {
			let key = Key(provider: row.provider, model: row.model)
			if let existing = acc[key] {
				acc[key] = AnalyticsModelTotal(
					provider: row.provider, model: row.model,
					eventCount: existing.eventCount + row.eventCount,
					inputTokens: existing.inputTokens + row.inputTokens,
					outputTokens: existing.outputTokens + row.outputTokens,
					cache5mTokens: existing.cache5mTokens + row.cache5mTokens,
					cache1hTokens: existing.cache1hTokens + row.cache1hTokens,
					cacheReadTokens: existing.cacheReadTokens + row.cacheReadTokens,
					cost: existing.cost + row.cost)
			} else {
				acc[key] = AnalyticsModelTotal(
					provider: row.provider, model: row.model, eventCount: row.eventCount,
					inputTokens: row.inputTokens, outputTokens: row.outputTokens,
					cache5mTokens: row.cache5mTokens, cache1hTokens: row.cache1hTokens,
					cacheReadTokens: row.cacheReadTokens, cost: row.cost)
				order.append(key)
			}
		}
		return
			order
			.compactMap { acc[$0] }
			.sorted { lhs, rhs in
				if lhs.provider.rawValue != rhs.provider.rawValue {
					return lhs.provider.rawValue < rhs.provider.rawValue
				}
				return lhs.model < rhs.model
			}
	}

	/// Sums the five token buckets across `rows` (already scoped to the checked/focused providers). Token
	/// counts have no real/notional/estimate basis problem, so this counts every scoped provider.
	public static func tokenMix(rows: [ModelDaySummary]) -> TokenMix {
		var input = 0, output = 0, cache5m = 0, cache1h = 0, cacheRead = 0
		for row in rows {
			input += row.inputTokens
			output += row.outputTokens
			cache5m += row.cache5mTokens
			cache1h += row.cache1hTokens
			cacheRead += row.cacheReadTokens
		}
		return TokenMix(input: input, output: output, cache5m: cache5m, cache1h: cache1h, cacheRead: cacheRead)
	}

	/// Builds the Model×Day heatmap grid: one row per `(provider, model)` (sorted by `measure` total
	/// descending, capped at `topModels`), one column per local day in the window (dense, oldest →
	/// newest). `rows` should already be filtered to the providers you want counted (e.g. exclude
	/// Copilot for the `.cost` measure — it is fully unpriced).
	public static func modelDayGrid(
		rows: [ModelDaySummary],
		measure: AnalyticsMeasure,
		days: Int,
		topModels: Int,
		now: Date = Date(),
		calendar: Calendar = .current
	) -> ModelDayGrid {
		let count = max(days, 1)
		let startOfToday = calendar.startOfDay(for: now)
		guard let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday)
		else { return ModelDayGrid(rows: [], days: [], values: []) }
		let dayColumns: [Date] = (0..<count).compactMap {
			calendar.date(byAdding: .day, value: $0, to: windowStart)
		}

		struct Key: Hashable { let provider: ProviderID; let model: String }
		var totals: [Key: Double] = [:]
		var perDay: [Key: [Int: Double]] = [:]
		var order: [Key] = []
		for row in rows {
			let key = Key(provider: row.provider, model: row.model)
			let day = calendar.startOfDay(for: row.day)
			guard let offset = calendar.dateComponents([.day], from: windowStart, to: day).day,
				offset >= 0, offset < count
			else { continue }
			let v = value(row, measure: measure)
			if totals[key] == nil { order.append(key) }
			totals[key, default: 0] += v
			perDay[key, default: [:]][offset, default: 0] += v
		}

		let ranked =
			order
			.sorted { (totals[$0] ?? 0) > (totals[$1] ?? 0) }
			.prefix(max(topModels, 0))

		let gridRows = ranked.map { ModelDayGrid.Row(provider: $0.provider, model: $0.model, total: totals[$0] ?? 0) }
		let values = ranked.map { key -> [Double] in
			(0..<count).map { perDay[key]?[$0] ?? 0 }
		}
		return ModelDayGrid(rows: gridRows, days: dayColumns, values: values)
	}

	/// The `rows` matching a drill-down cell selection (Advanced Analytics). `.weekday` matches every
	/// local weekday in the window (the by-model table is day-grained — see `AnalyticsDrillFilter`).
	public static func filteredRows(
		_ rows: [ModelDaySummary], matching filter: AnalyticsDrillFilter, calendar: Calendar = .current
	) -> [ModelDaySummary] {
		switch filter {
		case .day(let target):
			let start = calendar.startOfDay(for: target)
			return rows.filter { calendar.startOfDay(for: $0.day) == start }
		case .weekday(let weekday):
			return rows.filter { calendar.component(.weekday, from: $0.day) == weekday }
		case .modelDay(let provider, let model, let target):
			let start = calendar.startOfDay(for: target)
			return rows.filter {
				$0.provider == provider && $0.model == model && calendar.startOfDay(for: $0.day) == start
			}
		}
	}
}
