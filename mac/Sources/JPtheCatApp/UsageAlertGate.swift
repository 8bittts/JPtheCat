import Foundation

/// Pure rising-edge gate for a "provider hit N%" alert. Keeps the decision (fire once per window
/// instance, re-arm when the window rolls) testable without touching sound/notifications. A window is
/// identified by `(providerID, windowTag, resetEpoch)` — a new reset time is a new window, so crossing
/// the threshold again in the next window fires again, but a steady 82% across many 60s refreshes fires
/// once. `threshold` is per-instance so distinct tiers (80% warning, 95% critical) each own a gate.
struct UsageAlertGate {
	var threshold: Double
	private(set) var fired: Set<String> = []

	/// Default `80` keeps the warning gate a plain `UsageAlertGate()`; pass a higher value for the
	/// escalation tier (e.g. `UsageAlertGate(threshold: 95)`).
	init(threshold: Double = 80) {
		self.threshold = threshold
	}

	static func key(id: String, window: String, reset: Date?) -> String {
		"\(id):\(window):\(reset.map { Int($0.timeIntervalSince1970) } ?? 0)"
	}

	/// Returns true exactly once when `pct` first reaches the threshold for a given window instance.
	/// nil `pct` (provider exposes no limit) never fires. Dropping back below re-arms this instance.
	mutating func shouldFire(id: String, window: String, pct: Double?, reset: Date?) -> Bool {
		guard let pct else { return false }
		let key = Self.key(id: id, window: window, reset: reset)
		if pct >= threshold {
			guard !fired.contains(key) else { return false }
			fired.insert(key)
			return true
		}
		fired.remove(key)
		return false
	}

	/// Drops keys whose window has already reset (`resetEpoch < now`). Once a 5h/weekly window rolls it
	/// gets a NEW reset epoch, so its old `fired` key can never be re-evaluated (and thus never removed
	/// by `shouldFire`'s drop-below path) — without this, one dead key accumulates per 80% crossing for
	/// the entire process lifetime on the app-lifetime `UsageAlertCenter.shared` gate. Pruning on the
	/// embedded epoch (not "absent from this cycle's rows") is deliberate: a provider that flips to
	/// `stale` for a refresh and back must NOT re-alert, and its still-live window's epoch is future-dated
	/// so it's preserved. Keys with no reset time (epoch 0) are bounded by (providers × windows) and kept.
	mutating func pruneExpired(now: Date) {
		let nowEpoch = Int(now.timeIntervalSince1970)
		fired = fired.filter { key in
			guard let epoch = Self.resetEpoch(from: key) else { return true }
			return epoch == 0 || epoch >= nowEpoch
		}
	}

	/// The reset epoch embedded as the trailing component of a `key(id:window:reset:)` string. `id` and
	/// `window` never contain a colon, so the last colon-separated field is always the epoch integer.
	private static func resetEpoch(from key: String) -> Int? {
		key.split(separator: ":").last.flatMap { Int($0) }
	}
}
