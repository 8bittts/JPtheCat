import Foundation

/// A 7×24 punchcard of usage activity — weekday (Calendar `.weekday`, 1…7 where 1 = Sunday) × hour of
/// day (0…23) — for the Advanced Analytics window's Rhythm heatmap grain. Each cell carries all THREE
/// measures (events / total tokens / cost) so the Rhythm grid's Measure switch (Events | Tokens | $)
/// needs NO re-query — exactly the pattern `ModelDaySummary` uses for the model table.
///
/// Binning is done with the caller's `Calendar` in LOCAL time (`.current` by default), matching the
/// `startOfDay` convention the rest of `UsageIndex`/`AnalyticsAggregation` uses rather than a UTC
/// `strftime` path — so a 3 PM local event lands in the local 15:00 column, not a UTC-shifted one.
///
/// Pure value type (no I/O, no SwiftUI/AppKit) so it lives in Core: one builder reads from the SQLite
/// index (`UsageIndex.hourWeekdayBins`), a twin builder (`bucketed(events:…)`) reads from an
/// already-loaded `[UsageEvent]` for a provider that bypasses the index entirely (Copilot). Guarded by
/// `HourWeekdayMatrixTests`.
public struct HourWeekdayMatrix: Sendable, Equatable {
	public static let weekdayCount = 7
	public static let hourCount = 24

	/// One (weekday, hour) bin's three parallel measure totals.
	public struct Cell: Sendable, Equatable {
		public var events: Double
		public var tokens: Double
		public var cost: Double
		public init(events: Double = 0, tokens: Double = 0, cost: Double = 0) {
			self.events = events
			self.tokens = tokens
			self.cost = cost
		}
	}

	/// Row-major `[7][24]` grid: `cells[weekdayIndex][hour]` where `weekdayIndex == Calendar weekday − 1`
	/// (0 = Sunday … 6 = Saturday) and `hour` is 0…23.
	public private(set) var cells: [[Cell]]

	public init(cells: [[Cell]]) { self.cells = cells }

	/// An all-zero matrix.
	public static var zero: HourWeekdayMatrix {
		HourWeekdayMatrix(
			cells: Array(
				repeating: Array(repeating: Cell(), count: hourCount), count: weekdayCount))
	}

	/// Adds one bin's activity. `weekday` is the Calendar weekday (1…7); `hour` is 0…23. Out-of-range
	/// indices are ignored so a malformed component can never crash the grid.
	public mutating func add(weekday: Int, hour: Int, events: Double, tokens: Double, cost: Double) {
		guard weekday >= 1, weekday <= Self.weekdayCount, hour >= 0, hour < Self.hourCount else { return }
		cells[weekday - 1][hour].events += events
		cells[weekday - 1][hour].tokens += tokens
		cells[weekday - 1][hour].cost += cost
	}

	/// The cell at Calendar `weekday` (1…7) × `hour` (0…23); an all-zero cell for out-of-range indices.
	public func cell(weekday: Int, hour: Int) -> Cell {
		guard weekday >= 1, weekday <= Self.weekdayCount, hour >= 0, hour < Self.hourCount else {
			return Cell()
		}
		return cells[weekday - 1][hour]
	}

	/// The `measure`'s value at (weekday, hour).
	public func value(weekday: Int, hour: Int, measure: AnalyticsMeasure) -> Double {
		let c = cell(weekday: weekday, hour: hour)
		switch measure {
		case .events: return c.events
		case .tokens: return c.tokens
		case .cost: return c.cost
		}
	}

	/// Whether every cell of `measure` is zero (no activity) — the grid renders bare track grooves.
	public func isEmpty(measure: AnalyticsMeasure) -> Bool {
		for weekday in 1...Self.weekdayCount {
			for hour in 0..<Self.hourCount where value(weekday: weekday, hour: hour, measure: measure) > 0 {
				return false
			}
		}
		return true
	}

	/// The single busiest (weekday, hour) bin for `measure`, or `nil` when there is no activity. Ties
	/// resolve to the earliest weekday then earliest hour (stable scan order).
	public func peak(measure: AnalyticsMeasure) -> (weekday: Int, hour: Int, value: Double)? {
		var best: (weekday: Int, hour: Int, value: Double)?
		for weekday in 1...Self.weekdayCount {
			for hour in 0..<Self.hourCount {
				let v = value(weekday: weekday, hour: hour, measure: measure)
				guard v > 0 else { continue }
				if best == nil || v > best!.value { best = (weekday, hour, v) }
			}
		}
		return best
	}

	/// Element-wise sum of several matrices (used to fold the checked providers' per-provider matrices
	/// into one displayed grid).
	public static func summed(_ matrices: [HourWeekdayMatrix]) -> HourWeekdayMatrix {
		var out = HourWeekdayMatrix.zero
		for matrix in matrices {
			for weekdayIndex in 0..<weekdayCount {
				for hour in 0..<hourCount {
					out.cells[weekdayIndex][hour].events += matrix.cells[weekdayIndex][hour].events
					out.cells[weekdayIndex][hour].tokens += matrix.cells[weekdayIndex][hour].tokens
					out.cells[weekdayIndex][hour].cost += matrix.cells[weekdayIndex][hour].cost
				}
			}
		}
		return out
	}

	/// Buckets already-loaded `UsageEvent`s into the 7×24 grid — the SAME weekday/hour binning as
	/// `UsageIndex.hourWeekdayBins`, but for a provider whose events never pass through the SQLite index
	/// (Copilot; see `ModelDaySummary.bucketed`). Pure, no I/O. Binning uses `calendar` in local time.
	public static func bucketed(
		events: [UsageEvent],
		calculator: CostCalculator,
		calendar: Calendar = .current
	) -> HourWeekdayMatrix {
		var matrix = HourWeekdayMatrix.zero
		for event in events {
			let weekday = calendar.component(.weekday, from: event.timestamp)
			let hour = calendar.component(.hour, from: event.timestamp)
			let cost = calculator.cost(model: event.model, usage: event.usage) ?? 0
			matrix.add(
				weekday: weekday, hour: hour, events: 1, tokens: Double(event.usage.total), cost: cost)
		}
		return matrix
	}
}
