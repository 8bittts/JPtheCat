import Foundation

/// Reasoning-effort tier a model runs at. Raw values match the web twin's string union
/// (`"low" | "medium" | "high"` in `web/lib/library/pricing-registry.ts`) so the two stay
/// comparable. The SwiftUI chip colors for these tiers live App-side (they are presentation, not
/// classification); this Core type owns only the pure model→tier mapping.
public enum ModelEffortLevel: String, Sendable, CaseIterable {
	case low
	case medium
	case high

	/// Capitalized display label, identical to the web `modelEffortLevelLabel(...)`.
	public var label: String {
		switch self {
		case .low: "Low"
		case .medium: "Medium"
		case .high: "High"
		}
	}
}

/// Pure model → reasoning-effort classification, extracted from `DashboardView` so it is testable in
/// Core and can no longer silently drift from the web twin. The lookup table below MUST stay
/// byte-for-byte identical (same keys, same tiers) to `MODEL_EFFORT_LEVELS` in
/// `web/lib/library/pricing-registry.ts` — guarded by `ModelEffortTests`.
///
/// A model outside the table has NO tier: callers omit the chip rather than show a guessed "Medium".
public enum ModelEffort {
	/// Canonical model-id → effort tier. Keep in sync with the web `MODEL_EFFORT_LEVELS` map.
	public static let levels: [String: ModelEffortLevel] = [
		"claude-opus-5-5": .high,
		"claude-opus-5": .high,
		"claude-opus-4-8": .high,
		"claude-opus-4-7": .high,
		"claude-opus-4-6": .high,
		"claude-opus-4-5": .high,
		"claude-fable-5-2": .high,
		"claude-fable-5-1": .high,
		"claude-mythos-5-1": .high,
		"claude-fable-5": .high,
		"claude-mythos-5": .high,
		"claude-sonnet-5-5": .high,
		"claude-sonnet-5": .high,
		"claude-sonnet-4-6": .high,
		"claude-sonnet-4-5": .high,
		"claude-haiku-5-5": .medium,
		"claude-haiku-4-5": .low,
		"gpt-6.1-sol": .high,
		"gpt-6.1-terra": .high,
		"gpt-6-sol": .high,
		"gpt-6-luna": .low,
		"mimo-v2.6-flash": .low,
		"mimo-v2.6-pro": .medium,
		"gpt-6-astra": .high,
		"gpt-5.6-sol": .high,
		"gpt-5.6-luna": .high,
		"gpt-5.6-terra": .high,
		"gpt-5.5": .high,
		"gpt-5.4": .high,
		"gpt-5.4-mini": .low,
		"gpt-5.3-codex": .high,
		"gpt-5.3-codex-spark": .high,
		"gpt-5.2": .high,
		"gpt-5.2-codex": .high,
		"gpt-5.1-codex": .medium,
		"gpt-5.1-codex-max": .high,
		"gpt-5.1-codex-mini": .low,
		"gpt-5-codex": .medium,
		"gemini-3-pro-preview": .high,
		"gemini-3": .high,
		"gemini-3-flash-preview": .low,
		"gemini-2.5-pro": .medium,
		"gemini-2.5-flash": .low,
		"gemini-2.5-flash-lite": .low,
		"grok-4.7": .high,
		"grok-4.7-fast": .high,
		"grok-4.6": .high,
		"grok-4.5": .high,
		"grok-4.3": .high,
		"grok-4.20-0309-reasoning": .high,
		"grok-4.20-0309-non-reasoning": .medium,
		"grok-4.20-multi-agent-0309": .high,
		"grok-build-0.1": .medium,
		"grok-composer-2.5-fast": .high,
		"grok-composer-2.5": .medium,
		"muse-spark-1.1": .high,
		"muse-spark-1.2": .high,
		"muse-spark-1.3": .high,
		"muse-wonder-1.0": .high,
		"muse-spark-1.2-contributor": .high,
		"muse-spark-1.3-contributor": .high,
		"glm-5.3-flash": .medium,
		"glm-5.3": .high,
		"glm-5.2": .high,
		"glm-5.1": .high,
		"kimi-k3": .high,
		"kimi-k3.1-pro": .high,
		"step-5-preview": .medium,
		"kimi-k2.7-code": .high,
		"kimi-k2.6": .high,
		"longcat-2.0": .medium,
		"mimo-v2.5": .low,
		"mimo-v2.5-pro": .medium,
		"minimax-m3": .medium,
		"minimax-m3.1-flash": .low,
		"minimax-m2.7": .medium,
		"qwen3.8-max": .high,
		"qwen3.8-flash": .low,
		"qwen3.7-max": .high,
		"qwen3.7-plus": .medium,
		"qwen3.6-plus": .medium,
		"hy4-preview": .medium,
		"hy3": .low,
		"minimax-m2.5": .medium,
		"union-alpha": .low,
	]

	/// Effort tier for a raw emitted model string, or nil when the model is unclassified. The id is
	/// resolved through `ModelIdentity.modelKey`, the same decorator, gateway-route, free-tier, and alias
	/// rules pricing uses, so `grok-4.7-opencode`, `gpt-reserve`, and `mimo-v2.5-free` read the tier of
	/// the model they actually ran.
	public static func level(for model: String) -> ModelEffortLevel? {
		levels[ModelIdentity.modelKey(model)]
	}
}
