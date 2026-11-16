import Foundation

/// Claude Code's own cache of its last official usage response, `~/.claude.json`
/// `cachedUsageUtilization`. It is the one local source that still carries the per-model weekly
/// bars (Fable) after Claude Code 2.1.325 dropped `rate_limits.model_scoped` from the statusline.
///
/// Claude Code writes the cache only when it fetches usage (for example `/usage`), so a row can be
/// hours or days old. JP reads it locally, never sends it anywhere, and uses it only to fill a
/// per-model bar the statusline capture did not report. Each row keeps its own `resets_at` as the
/// only display gate and carries `fetchedAtMs` as `reportedAt`, so the detail can say how old it is.
public enum ClaudeUsageCache {
	/// `~/.claude.json`, the exact home-root path Claude Code writes. Never enumerates `$HOME`.
	public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
		home.appendingPathComponent(".claude.json")
	}

	/// Per-model weekly windows from the cache, or empty when the file, the cache, or a matching
	/// account is missing. Expired rows are kept here; `RateLimitSnapshot.current(at:)` drops them.
	public static func modelWindows(url: URL? = nil) -> [ModelScopedRateLimitWindow] {
		guard let data = try? Data(contentsOf: url ?? defaultURL()) else { return [] }
		return modelWindows(in: data)
	}

	/// Pure decoder. Reads only `cachedUsageUtilization` and `oauthAccount.accountUuid`.
	///
	/// A row counts only when `kind == "weekly_scoped"` and `scope.model.display_name` is a real
	/// label. A missing name or a non-numeric `percent` is skipped, never turned into 0%.
	/// A row without a readable `resets_at` is skipped too: the cache can be days old, and its reset
	/// is the only thing that can retire the row.
	/// The cache counts only when its `accountUuid` equals the signed-in `oauthAccount.accountUuid`;
	/// a missing or different account on either side is ignored.
	static func modelWindows(in data: Data) -> [ModelScopedRateLimitWindow] {
		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let cache = root["cachedUsageUtilization"] as? [String: Any],
			accountMatches(cache: cache, root: root),
			let utilization = cache["utilization"] as? [String: Any],
			let limits = utilization["limits"] as? [Any]
		else { return [] }
		let reportedAt = JSONNumber.double(cache["fetchedAtMs"]).map { Date(timeIntervalSince1970: $0 / 1000) }
		var seen = Set<String>()
		var windows: [ModelScopedRateLimitWindow] = []
		for raw in limits {
			guard let window = scopedWindow(from: raw, reportedAt: reportedAt),
				seen.insert(window.label.lowercased()).inserted
			else { continue }
			windows.append(window)
		}
		return windows
	}

	private static func accountMatches(cache: [String: Any], root: [String: Any]) -> Bool {
		guard let cached = cache["accountUuid"] as? String,
			let current = (root["oauthAccount"] as? [String: Any])?["accountUuid"] as? String
		else { return false }
		return cached == current
	}

	private static func scopedWindow(from raw: Any, reportedAt: Date?) -> ModelScopedRateLimitWindow? {
		guard let row = raw as? [String: Any], row["kind"] as? String == "weekly_scoped",
			let model = (row["scope"] as? [String: Any])?["model"] as? [String: Any],
			let name = (model["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
			!name.isEmpty,
			let percent = JSONNumber.double(row["percent"]),
			let resetsAt = ClaudeRateLimitStore.resetDate(row["resets_at"])
		else { return nil }
		let window = RateLimitWindow(usedPercent: min(100, max(0, percent)), windowMinutes: 10080, resetsAt: resetsAt)
		return ModelScopedRateLimitWindow(
			key: "model_scoped:\(name)", window: window, displayName: name, reportedAt: reportedAt)
	}
}
