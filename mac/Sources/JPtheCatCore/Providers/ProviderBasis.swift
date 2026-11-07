import Foundation

/// The cost basis of a provider — the app's one honesty contract about what a provider's figures
/// MEAN (Claude = real dollars, Codex/Grok/Muse Spark = notional list-price dollars, Copilot/Cursor =
/// an unpriced token estimate excluded from every `$` aggregate).
///
/// [CRITICAL] Single source of truth for a provider's cost basis, including the badge vocabulary in
/// `DashboardView.selectorBadge(for:)`. A new provider must be added HERE ONLY, never at a call site,
/// or it silently defaults into being dollar-aggregable.
/// Guard: `ProviderBasisTests` pins the FULL `ProviderID` -> basis mapping.
public enum ProviderBasis: Sendable, Equatable, CaseIterable {
	/// Real-dollar spend (Claude Code).
	case real
	/// Notional list-price dollars — a subscription, never real API spend (Codex, Grok, Muse Spark).
	case notional
	/// Token estimate with no trustworthy local dollars; excluded from every `$` aggregate
	/// (Copilot, Cursor).
	case estimate
	/// A GATEWAY ROLLUP (OpenCode Zen / OpenCode Go): real usage that ALSO appears under whichever
	/// model-brand provider owns each model, so it must never enter the aggregate `$` total or alerts
	/// even though its figures ARE dollars. This is the one deliberate double-DISPLAY / single-COUNT
	/// state: the gateway answers "what am I spending through this gateway", the brand rows answer
	/// "what is this model costing me", and only the brand rows are summed. Because it is dollar-based
	/// (not a token estimate) a fully-free gateway still falls back to tokens via
	/// `ProviderRow.isFullyUnpriced`.
	case gateway
	/// Official plan usage with no local token/cost ledger on the Mac (Grok Bot weekly included pool).
	case officialPlan

	/// Whether this provider's dollars may be summed into the aggregate `$` total.
	public var isAggregable: Bool { self == .real || self == .notional }

	/// Whether this provider shows TOKENS instead of a (dead `$0.00`) dollar figure.
	public var showsTokens: Bool { self == .estimate }

	/// Whether this provider's dollars are list-price rather than billed spend. Feeds the dashboard
	/// row's `notional` flag and the "incl notional" disclosure.
	public var isNotional: Bool { self != .real && self != .officialPlan }

	/// The selector-row / analytics-sidebar badge vocabulary. One string table so the dashboard and
	/// the Advanced Analytics window can never disagree about what a row is.
	public var badge: String {
		switch self {
		case .real: "real"
		case .notional: "notional"
		case .estimate: "estimate"
		case .gateway: "gateway"
		case .officialPlan: "official"
		}
	}

	/// The Advanced Analytics BASIS key wording — one string table next to `badge` so a new basis
	/// cannot ship without its explanation.
	public var keyMeaning: String {
		switch self {
		case .real: "real $"
		case .notional: "notional list price"
		case .estimate: "estimate (tokens)"
		case .gateway: "gateway · shown, not summed"
		case .officialPlan: "official plan usage"
		}
	}

	public static func of(_ id: ProviderID) -> ProviderBasis {
		switch id {
		case .codex, .grok, .cursor, .grokBot, .museSpark, .nemotron, .mimo, .deepseek, .bigPickle:
			.notional
		case .opencode, .opencodego:
			// OpenCode Zen and OpenCode Go are gateway rollups: their usage is already counted under
			// the model-brand rows (Muse Spark/Nemotron/MiMo/Big Pickle/DeepSeek), so summing them
			// again would double-count. They stay visible with real dollar/token figures but are
			// excluded from every aggregate and alert.
			.gateway
		case .copilot: .estimate
		default: .real
		}
	}

	/// Basis for a raw `ProviderRow.id` string. Dashboard rows carry the `ProviderID` rawValue as a
	/// `String`; an unrecognized id falls back to `.real` exactly as the `ProviderID` switch does.
	public static func of(rawID: String) -> ProviderBasis {
		ProviderID(rawValue: rawID).map(of) ?? .real
	}
}
