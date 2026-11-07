import Foundation

/// Stable display order for dashboard selector rows and matching provider lists.
public enum ProviderDashboardOrder {
	private static let brandRank: [String: Int] = [
		"claude": 0, "codex": 1, "grok": 2, "muse_spark": 3,
		"nemotron": 4, "mimo": 5, "big_pickle": 6, "deepseek": 7, "copilot": 8,
	]

	/// When `grok` is among `rowIDs`, `grok_bot` sorts immediately after it; otherwise `grok_bot` keeps its
	/// normal rank (unlisted ids sink to the end, tie-broken by `name`).
	public static func sortsBefore(
		_ lhs: String, _ rhs: String, rowIDs: some Collection<String>, name: (String) -> String
	) -> Bool {
		let grokPresent = rowIDs.contains("grok")
		let left = sortKey(for: lhs, grokPresent: grokPresent)
		let right = sortKey(for: rhs, grokPresent: grokPresent)
		if left.primary != right.primary { return left.primary < right.primary }
		if left.secondary != right.secondary { return left.secondary < right.secondary }
		return name(lhs) < name(rhs)
	}

	private struct SortKey: Equatable {
		let primary: Int
		let secondary: Int
	}

	private static func sortKey(for id: String, grokPresent: Bool) -> SortKey {
		let primary = brandRank[id] ?? Int.max
		if grokPresent {
			if id == "grok" { return SortKey(primary: 2, secondary: 0) }
			if id == "grok_bot" { return SortKey(primary: 2, secondary: 1) }
		}
		return SortKey(primary: primary, secondary: 0)
	}
}
