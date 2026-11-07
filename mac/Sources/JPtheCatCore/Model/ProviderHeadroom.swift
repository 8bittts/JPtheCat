import Foundation

/// Remaining room in the provider-reported subscription windows.
/// A zero allowance does not imply loss of access: a separate credit balance may fund further usage.
///
/// It is deliberately a THREE-state value, never a bare number, because most providers do not expose
/// an official limit and the app's honesty contract forbids inventing one (see AGENTS.md
/// "[HARD REQUIREMENT] Never hardcode or guess a subscription tier, plan ceiling, or access level").
/// A provider without a live official signal resolves to `.unknown` — the honest answer — rather than
/// a fabricated percentage. The ONLY source of an `.official` figure is a provider's own reported
/// window (`RateLimitSnapshot`: Codex's `used_percent`, or Claude's opt-in statusline capture).
public enum ProviderHeadroom: Sendable, Equatable {
	/// A live official window exists. `remainingPercent` is `100 − usedPercent` of the TIGHTEST current
	/// window (the one nearest its cap — the binding constraint), clamped to `0...100`. Carries that
	/// window's length and reset time so a caller can say "X% left, resets in …".
	case official(remainingPercent: Double, windowMinutes: Int, resetsAt: Date?)
	/// The provider's own signal indicates it has (almost certainly) run out — currently only Claude's
	/// "5h window high AND the capture froze" heuristic (`RateLimitSnapshot.likelyAtLimit`). We say
	/// "likely exhausted", never a fabricated 100%.
	case likelyExhausted
	/// No current official signal for this provider — headroom is genuinely UNKNOWN. Providers whose
	/// limits are not surfaced directly (Copilot, Gemini, OpenCode, or Claude before opt-in capture)
	/// resolve here. This is the honest default; it is NEVER a stand-in for "0% left" or "100% left".
	case unknown

	/// Stable machine token for JSON/automation surfaces.
	public var stateToken: String {
		switch self {
		case .official: "official"
		case .likelyExhausted: "likely_exhausted"
		case .unknown: "unknown"
		}
	}

	/// The remaining-percent figure, or `nil` for any non-`.official` state (never fabricated).
	public var remainingPercent: Double? {
		if case let .official(remaining, _, _) = self { return remaining }
		return nil
	}

	/// Resolve the honest headroom for a provider from its latest rate-limit snapshot.
	///
	/// - `nil` snapshot (no official feed for this provider) → `.unknown`.
	/// - `likelyAtLimit` (Claude frozen-high) → `.likelyExhausted`, checked BEFORE window expiry so a
	///   frozen-high reading isn't downgraded to `.unknown` just because its window boundary passed.
	/// - otherwise the tightest CURRENT window (`resetsAt > now`) → `.official`; if every window has
	///   expired, `.unknown` (a stale percentage is not a current answer).
	public static func resolve(from snapshot: RateLimitSnapshot?, now: Date = Date()) -> ProviderHeadroom {
		guard let snapshot else { return .unknown }
		if snapshot.likelyAtLimit(now: now) { return .likelyExhausted }
		guard let current = snapshot.current(at: now) else { return .unknown }
		let windows = [current.primary, current.secondary].compactMap { $0 }
		// Tightest = the window closest to its cap (highest used%). That's the binding constraint.
		guard let tightest = windows.max(by: { $0.usedPercent < $1.usedPercent }) else { return .unknown }
		let remaining = min(100, max(0, 100 - tightest.usedPercent))
		return .official(
			remainingPercent: remaining, windowMinutes: tightest.windowMinutes, resetsAt: tightest.resetsAt)
	}
}
