import Foundation

/// Muse Spark is scoped to OpenCode sessions logged on this Mac — not the Meta account dashboard.
/// JP never calls Meta's API for billing history (no public usage endpoint as of mid-2026).
public enum MuseSparkScope {
	/// Shown in provider detail whenever Muse Spark is visible.
	public static let baseNote =
		"Counts OpenCode sessions on this Mac. Meta account totals can be higher when Muse Spark runs outside OpenCode."

	/// True when OpenCode's `auth.json` carries a configured Meta Model API key (presence only — key
	/// value is never read, stored, or transmitted).
	public static func hasMetaAPIKeyConfigured(opencodeRoot: URL) -> Bool {
		let auth = opencodeRoot.appendingPathComponent("auth.json")
		guard let data = try? Data(contentsOf: auth),
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let meta = json["meta"] as? [String: Any]
		else { return false }
		if let key = meta["key"] as? String, !key.isEmpty { return true }
		if let key = meta["apiKey"] as? String, !key.isEmpty { return true }
		return false
	}

	/// Provider-detail disclosure. Elevates the copy when a Meta key exists but local OpenCode logged
	/// very little — the common "JP shows pennies, Meta dashboard shows dollars" mismatch.
	public static func detailNote(weekEvents: Int, opencodeRoot: URL) -> String {
		guard hasMetaAPIKeyConfigured(opencodeRoot: opencodeRoot), weekEvents < 5 else {
			return baseNote
		}
		let turnWord = weekEvents == 1 ? "turn" : "turns"
		return
			"Meta API key is configured but OpenCode logged only \(weekEvents) \(turnWord) here — usage from other clients won't appear. \(baseNote)"
	}
}