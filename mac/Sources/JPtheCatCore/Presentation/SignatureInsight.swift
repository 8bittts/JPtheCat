import Foundation

/// JP's one "signature" opinion about a provider row — the surprising combined number shown in the
/// detail callout. This is honesty-load-bearing (a wrong burn-pace verdict or cost-concentration claim
/// misleads the user about their spend), so the DECISION logic lives here as a pure, unit-tested value
/// rather than as a private SwiftUI View property. The View maps the structured result to wording and
/// supplies the estimate badge via `isEstimate`.
public enum SignatureInsight: Equatable, Sendable {
	/// Claude has gone quiet at a high reading — almost certainly rate-limiting, and the statusline
	/// can't report the real (likely 100%) number. Show the frozen reading, badged as an estimate.
	case limitFrozen(usedPct: Double)
	/// How the current 5-hour burn compares to a linear pace through the window.
	case burnPace(usedPct: Double, windowElapsedFraction: Double, verdict: BurnVerdict)
	/// One model eats a disproportionate share of the bill relative to its share of turns.
	case costConcentration(model: String, turnShare: Double, billShare: Double)

	public enum BurnVerdict: Equatable, Sendable {
		case runningHot  // pace > 1.15× linear
		case onPace
		case wellUnderPace  // pace < 0.85× linear
	}

	/// A single priced/unpriced model's window spend, decoupled from the app-target `ModelLine`.
	public struct ModelSpend: Equatable, Sendable {
		public let model: String
		public let cost: Double?
		public let eventCount: Int
		public init(model: String, cost: Double?, eventCount: Int) {
			self.model = model
			self.cost = cost
			self.eventCount = eventCount
		}
	}

	/// Rate-limit-derived insights are estimates (badged); the cost-concentration fact is exact.
	public var isEstimate: Bool {
		switch self {
		case .limitFrozen, .burnPace: true
		case .costConcentration: false
		}
	}

	/// The `usedPct` inputs are on a 0–100 scale; `turnShare`/`billShare`/`windowElapsedFraction`
	/// outputs are 0–1 fractions. Returns nil (callout collapses) when nothing is honestly computable.
	public static func compute(
		limitLikelyHit: Bool,
		usedPct: Double?,
		resetsAt5h: Date?,
		windowMinutes5h: Int?,
		week: Double,
		weekEvents: Int,
		models: [ModelSpend],
		now: Date
	) -> SignatureInsight? {
		if limitLikelyHit, let used = usedPct {
			return .limitFrozen(usedPct: used)
		}
		if let used = usedPct, let reset = resetsAt5h, let win = windowMinutes5h, win > 0 {
			let minsUntil = max(0, reset.timeIntervalSince(now) / 60)
			let elapsed = (Double(win) - minsUntil) / Double(win)
			if elapsed > 0.05 {
				let pace = (used / 100) / elapsed
				let verdict: BurnVerdict = pace > 1.15 ? .runningHot : (pace < 0.85 ? .wellUnderPace : .onPace)
				return .burnPace(usedPct: used, windowElapsedFraction: elapsed, verdict: verdict)
			}
		}
		let priced = models.filter { $0.cost != nil }
		guard week > 0, weekEvents > 0, priced.count > 1 else { return nil }
		let scored = priced.map {
			(model: $0.model, cost: ($0.cost ?? 0) / week, evt: Double($0.eventCount) / Double(weekEvents))
		}
		guard let top = scored.max(by: { ($0.cost - $0.evt) < ($1.cost - $1.evt) }), top.cost - top.evt > 0.10
		else { return nil }
		return .costConcentration(model: top.model, turnShare: top.evt, billShare: top.cost)
	}
}
