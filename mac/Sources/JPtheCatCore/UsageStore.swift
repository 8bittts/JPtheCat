import Foundation

/// An aggregated slice of spend (a day, a week, one model).
public struct CostBucket: Sendable {
	public var cost: Double = 0
	public var usage: TokenUsage = .init()
	public var eventCount: Int = 0
	public var unpricedModels: Set<String> = []

	public init() {}

	public mutating func add(_ event: UsageEvent, cost: Double?) {
		usage += event.usage
		eventCount += 1
		if let cost { self.cost += cost } else { unpricedModels.insert(event.model) }
	}

	/// Adds an already-aggregated `(model, day, tier)` group in one shot: `count` events' summed tokens
	/// and their single group cost. Equivalent to calling `add` once per event in the group — every
	/// field of `CostBucket` is additive and the group's cost is linear once its >200K tier is fixed
	/// (see `CostCalculator.cost(model:usage:forceTier:)`). Backs the window-summary grouped scan.
	public mutating func addGrouped(model: String, usage: TokenUsage, cost: Double?, count: Int) {
		self.usage += usage
		eventCount += count
		if let cost { self.cost += cost } else { unpricedModels.insert(model) }
	}

	/// Adds another bucket's totals. Every field is additive, so merging already-priced buckets keeps
	/// their dollars exact.
	public mutating func merge(_ other: CostBucket) {
		cost += other.cost
		usage += other.usage
		eventCount += other.eventCount
		unpricedModels.formUnion(other.unpricedModels)
	}
}

public struct UsageRollup: Sendable {
	public let today: CostBucket
	/// The trailing-window bucket. Spans `windowDays` local days (inclusive of today), default 7.
	/// The `last7d`/`byModel7d` names are historical — read them as "the selected window."
	public let last7d: CostBucket
	public let byModel7d: [String: CostBucket]
	/// Number of local days the window bucket spans (default 7). Lets the UI label figures honestly
	/// when the user widens the timeframe (14 / 30 / 90).
	public let windowDays: Int

	public init(
		today: CostBucket, last7d: CostBucket, byModel7d: [String: CostBucket], windowDays: Int = 7
	) {
		self.today = today
		self.last7d = last7d
		self.byModel7d = byModel7d
		self.windowDays = windowDays
	}
}

extension UsageRollup {
	/// `byModel7d` regrouped by `ModelIdentity.presentationID`, so a gateway route (`-go`, `-zen`,
	/// `-peak`), a snapshot date, or a `[1m]` selector never splits one model into two display rows.
	/// Each emitted id was priced before the merge, so the merged dollars are exact. Free-tier ids keep
	/// their own row because they are unpriced.
	public var byPresentedModel7d: [String: CostBucket] {
		var merged: [String: CostBucket] = [:]
		for (model, bucket) in byModel7d {
			merged[ModelIdentity.presentationID(model), default: CostBucket()].merge(bucket)
		}
		return merged
	}
}

/// Rolls de-duplicated events into today / last-7-days / per-model buckets with dollar cost.
public struct UsageStore: Sendable {
	public let calculator: CostCalculator

	public init(calculator: CostCalculator = CostCalculator()) { self.calculator = calculator }

	public func rollup(
		_ events: [UsageEvent], days: Int = 7, now: Date = Date(), calendar: Calendar = .current
	) -> UsageRollup {
		let windowDays = max(days, 1)
		let startOfToday = calendar.startOfDay(for: now)
		let windowStart =
			calendar.date(byAdding: .day, value: -(windowDays - 1), to: startOfToday) ?? startOfToday

		var today = CostBucket()
		var window = CostBucket()
		var byModel: [String: CostBucket] = [:]

		for event in events {
			guard event.timestamp <= now else { continue }
			let cost = calculator.cost(model: event.model, usage: event.usage)
			if event.timestamp >= startOfToday { today.add(event, cost: cost) }
			if event.timestamp >= windowStart {
				window.add(event, cost: cost)
				byModel[event.model, default: CostBucket()].add(event, cost: cost)
			}
		}
		return UsageRollup(today: today, last7d: window, byModel7d: byModel, windowDays: windowDays)
	}
}
