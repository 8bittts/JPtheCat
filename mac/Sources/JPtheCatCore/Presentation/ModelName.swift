import Foundation

/// Display-shortening for a model identifier, shared by every tight name column (dashboard
/// per-model list, provider-focus signature line, Advanced Analytics table) so the recipe
/// can't drift between call sites.
public enum ModelName {
	/// Short display form of an emitted model id for tight name columns. Starts from
	/// `ModelIdentity.presentationID` (no vendor prefix, `[1m]` selector, snapshot date, or gateway
	/// accounting suffix), then drops the family prefix the surrounding provider already names:
	/// `claude-opus-4-5-20251101` → `opus-4-5`, `gpt-5.3-codex-spark` → `5.3-spark`,
	/// `grok-4.7-build` → `4.7`, `deepseek-v4-flash-go-peak` → `deepseek-v4-flash`. A free-tier id keeps
	/// a visible marker (`mimo-v2.5-free` → `mimo-v2.5 free`) because it is unpriced and must not read
	/// as the paid model. Case is preserved; this is a DISPLAY transform, never a lookup key.
	/// `web/components/site/menubar-demo-series.ts` `shortModel` follows the same cases
	/// (`model-identity-cases.json`, guarded on both sides).
	public static func short(_ model: String) -> String {
		var s = ModelIdentity.presentationID(model)
		let isFree = ModelIdentity.isFreeTier(s) && s.count > ModelIdentity.freeTierSuffix.count
		if isFree { s.removeLast(ModelIdentity.freeTierSuffix.count) }
		let lower = s.lowercased()
		if lower.hasPrefix("grok-"), lower.hasSuffix("-build"), lower != "grok-build" {
			s.removeLast("-build".count)
		}
		if s.lowercased().hasPrefix("claude-") {
			s.removeFirst("claude-".count)
		} else if s.lowercased().hasPrefix("gpt-") {
			s.removeFirst("gpt-".count)
			// Under the Codex provider the `codex` token is redundant — `gpt-` already signals the
			// family — so drop it: gpt-5.3-codex-spark → 5.3-spark, gpt-5.1-codex-max → 5.1-max,
			// gpt-5.3-codex → 5.3.
			s = s.split(separator: "-", omittingEmptySubsequences: true)
				.filter { $0.lowercased() != "codex" }
				.joined(separator: "-")
		} else if s.lowercased().hasPrefix("grok-") {
			s.removeFirst("grok-".count)
		}
		return isFree ? "\(s) free" : s
	}

	/// Advanced Analytics' model label: `short(_:)`, but a GPT model keeps its `gpt-` family prefix
	/// because the analytics table mixes every provider's models in one column
	/// (`gpt-5.3-codex-spark` → `gpt-5.3-spark`).
	public static func analyticsShort(_ model: String) -> String {
		let short = short(model)
		let isGPT = ModelIdentity.presentationID(model).lowercased().hasPrefix("gpt-")
		return isGPT && !short.lowercased().hasPrefix("gpt-") ? "gpt-\(short)" : short
	}

	/// Compact dashboard ordering: newest model version first, then the provider's capability tier
	/// strongest-to-lightest, then snapshot date and a deterministic natural-name fallback.
	///
	/// The `By model` list shows every model used in the window (no top-N cap); version stays the primary
	/// key so a newly-used family always reads above an older premium model. Capability breaks ties inside one version family — notably
	/// GPT `astra` → `sol` → `terra` → `luna` and Claude Fable/Mythos → Opus → Sonnet → Haiku, whose
	/// alphabetical order is not their power order.
	public static func sortsBeforeForCompactDisplay(_ left: String, _ right: String) -> Bool {
		let leftKey = displayOrderKey(left)
		let rightKey = displayOrderKey(right)
		for index in 0 ..< max(leftKey.version.count, rightKey.version.count) {
			let leftPart = index < leftKey.version.count ? leftKey.version[index] : 0
			let rightPart = index < rightKey.version.count ? rightKey.version[index] : 0
			if leftPart != rightPart { return leftPart > rightPart }
		}
		if let leftCapability = leftKey.capability, let rightCapability = rightKey.capability,
			leftCapability.family == rightCapability.family,
			leftCapability.rank != rightCapability.rank
		{
			return leftCapability.rank > rightCapability.rank
		}
		if leftKey.snapshotDate != rightKey.snapshotDate {
			return leftKey.snapshotDate > rightKey.snapshotDate
		}
		return left.localizedStandardCompare(right) == .orderedDescending
	}

	private static func displayOrderKey(_ model: String) -> (
		version: [Int], capability: (family: String, rank: Int)?, snapshotDate: Int
	) {
		let normalized = ModelIdentity.presentationID(model).lowercased()
		let version = normalized.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
		return (version, capabilityTier(normalized), ModelIdentity.snapshotDate(model) ?? 0)
	}

	/// Compare capability only inside an explicitly ordered product family. Unknown or unrelated names
	/// fall through to deterministic natural ordering instead of guessing how they compare.
	private static func capabilityTier(_ model: String) -> (family: String, rank: Int)? {
		let tokens = model.split(whereSeparator: { !$0.isLetter }).map(String.init)
		if model == "gpt-5.6" { return ("codex-celestial", 3) }
		// OpenAI's celestial tiers, strongest first: GPT-6 adds Astra above Sol; GPT-5.6 has Terra.
		if model.hasPrefix("gpt-") {
			if tokens.contains("astra") { return ("codex-celestial", 4) }
			if tokens.contains("sol") { return ("codex-celestial", 3) }
			if tokens.contains("terra") { return ("codex-celestial", 2) }
			if tokens.contains("luna") { return ("codex-celestial", 1) }
		}

		if tokens.contains("fable") || tokens.contains("mythos") { return ("claude-classic", 4) }
		if tokens.contains("opus") { return ("claude-classic", 3) }
		if tokens.contains("sonnet") { return ("claude-classic", 2) }
		if tokens.contains("haiku") { return ("claude-classic", 1) }

		if model.contains("gemini"), tokens.contains("pro") { return ("gemini-speed", 3) }
		if model.contains("gemini"), model.contains("flash-lite") { return ("gemini-speed", 1) }
		if model.contains("gemini"), tokens.contains("flash") { return ("gemini-speed", 2) }
		return nil
	}
}
