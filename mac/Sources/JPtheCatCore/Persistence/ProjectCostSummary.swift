import Foundation

/// Window totals for ONE project (the `cwd`/project attribution carried on each `UsageEvent`), summed
/// across every provider/model/day in the window — the "by project" slice of the analytics warehouse.
/// Events with no project attribution fold into a single `ProjectCostSummary.unattributed` bucket so a
/// nil project can never silently vanish from the totals. Pure value type; produced by
/// `UsageIndex.projectCostSummaries(...)`.
public struct ProjectCostSummary: Sendable, Equatable {
	/// Display label for events that carry no project (`project == nil`/empty on the event).
	public static let unattributed = "(unattributed)"

	public let project: String
	public var eventCount: Int
	public var inputTokens: Int
	public var outputTokens: Int
	public var cache5mTokens: Int
	public var cache1hTokens: Int
	public var cacheReadTokens: Int
	/// Priced-provider cost only (unpriced models contribute 0, same as every other analytics rollup).
	public var cost: Double

	public init(
		project: String, eventCount: Int, inputTokens: Int, outputTokens: Int, cache5mTokens: Int,
		cache1hTokens: Int, cacheReadTokens: Int, cost: Double
	) {
		self.project = project
		self.eventCount = eventCount
		self.inputTokens = inputTokens
		self.outputTokens = outputTokens
		self.cache5mTokens = cache5mTokens
		self.cache1hTokens = cache1hTokens
		self.cacheReadTokens = cacheReadTokens
		self.cost = cost
	}

	/// Total tokens across all types — the natural sort tiebreaker when two projects cost the same
	/// (e.g. both fully unpriced at `$0`).
	public var totalTokens: Int {
		inputTokens + outputTokens + cache5mTokens + cache1hTokens + cacheReadTokens
	}

	/// Buckets already-loaded `[UsageEvent]` by project — the SAME shape/rule as
	/// `UsageIndex.projectCostSummaries`, for callers that hold events directly (the CLI's non-indexed
	/// path, or a provider that bypasses the index). The caller pre-filters to the desired window;
	/// nil/empty projects fold into `unattributed`; returned most-expensive-first (ties → tokens → name).
	public static func bucketed(events: [UsageEvent], calculator: CostCalculator) -> [ProjectCostSummary] {
		var accumulators: [String: ProjectCostSummary] = [:]
		for event in events {
			let project = (event.project?.isEmpty ?? true) ? unattributed : event.project!
			let cost = calculator.cost(model: event.model, usage: event.usage) ?? 0
			if var existing = accumulators[project] {
				existing.eventCount += 1
				existing.inputTokens += event.usage.input
				existing.outputTokens += event.usage.output
				existing.cache5mTokens += event.usage.cacheCreate5m
				existing.cache1hTokens += event.usage.cacheCreate1h
				existing.cacheReadTokens += event.usage.cacheRead
				existing.cost += cost
				accumulators[project] = existing
			} else {
				accumulators[project] = ProjectCostSummary(
					project: project, eventCount: 1, inputTokens: event.usage.input,
					outputTokens: event.usage.output, cache5mTokens: event.usage.cacheCreate5m,
					cache1hTokens: event.usage.cacheCreate1h, cacheReadTokens: event.usage.cacheRead, cost: cost)
			}
		}
		return accumulators.values.sorted { lhs, rhs in
			if lhs.cost != rhs.cost { return lhs.cost > rhs.cost }
			if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
			return lhs.project < rhs.project
		}
	}
}
