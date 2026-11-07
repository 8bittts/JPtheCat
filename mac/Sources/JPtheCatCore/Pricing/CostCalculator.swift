import Foundation

/// Turns normalized `TokenUsage` into dollars. Two load-bearing details:
///  1. the 5-minute and 1-hour cache-creation buckets are priced SEPARATELY (1.25x vs 2x input) —
///     pricing all cache-creation at the single 5m rate is ccusage #899's 37.5% under-bill.
///  2. model-specific context surcharges: when a turn crosses the model's published threshold,
///     the WHOLE request is billed at the higher tier. Ignoring it under-bills long-context turns.
public struct CostCalculator: Sendable {
	public let pricing: PricingTable
	static let contextTierThreshold = 200_000

	public init(pricing: PricingTable) { self.pricing = pricing }

	public init() { self.pricing = .bundledDefault() }

	/// Whether one event's usage clears the >200K-context surcharge cliff. Pure function of the token
	/// mix and the threshold — no pricing lookup — so an aggregation layer can compute the SAME flag in
	/// SQL (`input + cache_read + cache5m + cache1h > 200000`) and group rows by it before pricing.
	public static func exceedsContextTier(_ usage: TokenUsage) -> Bool {
		usage.input + usage.cacheRead + usage.cacheCreate5m + usage.cacheCreate1h > contextTierThreshold
	}

	/// Dollar cost for one event's usage. Returns `nil` for an unpriced model so the caller can
	/// badge it "unpriced" rather than silently bill $0. The model's tier is decided per-event here.
	public func cost(model: String, usage: TokenUsage) -> Double? {
		let threshold = pricing.price(for: model)?.lastBaseContextTokenCount ?? Self.contextTierThreshold
		let context = usage.input + usage.cacheRead + usage.cacheCreate5m + usage.cacheCreate1h
		return cost(model: model, usage: usage, forceTier: context > threshold)
	}

	/// Cost with the >200K tier decision supplied by the caller instead of re-derived from `usage`.
	///
	/// The window-summary grouped scan sums many events' tokens per `(provider, model, day, tiered)`
	/// bucket, where `tiered` is the model-specific per-event tier decided from the SQL context bucket. Within one
	/// bucket every event shares a tier, so pricing the summed tokens once equals summing per-event
	/// costs — BUT only if the tier is the pre-decided bucket flag, never re-derived from the summed
	/// context (summing many sub-200K events easily crosses 200K and would falsely trip the surcharge).
	/// This entry point is what keeps that aggregation exact. For a model with no above-200K pricing the
	/// flag is inert (base rates either way), so splitting such a model across both buckets is harmless.
	public func cost(model: String, usage: TokenUsage, forceTier: Bool) -> Double? {
		guard let p = pricing.price(for: model) else { return nil }

		let tiered = forceTier && p.inputCostPerTokenAbove200k != nil

		let inP = tiered ? (p.inputCostPerTokenAbove200k ?? p.inputCostPerToken) : p.inputCostPerToken
		let outP =
			tiered ? (p.outputCostPerTokenAbove200k ?? p.outputCostPerToken) : p.outputCostPerToken
		let write5m =
			(tiered ? p.cacheCreationInputTokenCostAbove200k : nil)
			?? p.cacheCreationInputTokenCost ?? (inP * 1.25)
		let write1h =
			(tiered ? p.cacheCreationInputTokenCostAbove1hrAbove200k : nil)
			?? p.cacheCreationInputTokenCostAbove1hr ?? (inP * 2.0)
		let read =
			(tiered ? p.cacheReadInputTokenCostAbove200k : nil)
			?? p.cacheReadInputTokenCost ?? (inP * 0.1)

		return Double(usage.input) * inP
			+ Double(usage.output) * outP
			+ Double(usage.cacheCreate5m) * write5m
			+ Double(usage.cacheCreate1h) * write1h
			+ Double(usage.cacheRead) * read
	}

	/// Dollars a model's cache reads saved vs paying full input price for the same tokens:
	/// `cacheRead × (inputRate − cacheReadRate)`. Deliberately uses the BASE (non-tiered) rates so
	/// the figure is a conservative lower bound safe to sum over an already-aggregated bucket — the
	/// >200K tier is per-request and can't be recovered from summed tokens, and its true saving is
	/// only ever larger, so under-counting here never overstates. `nil` for an unpriced model.
	public func cacheReadSavings(model: String, usage: TokenUsage) -> Double? {
		guard usage.cacheRead > 0, let p = pricing.price(for: model) else { return nil }
		let read = p.cacheReadInputTokenCost ?? (p.inputCostPerToken * 0.1)
		return max(0, Double(usage.cacheRead) * (p.inputCostPerToken - read))
	}
}
