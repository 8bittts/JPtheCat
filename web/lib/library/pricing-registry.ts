/**
 * Typed model registry over `pricing-data.ts`: canonical slug<->id map (URL-safe slugs from
 * dotted / `-preview` ids), vendor grouping, per-token->$/MTok helpers, and the field-weighted
 * anti-thin gate that decides which models earn a STANDALONE `/library/pricing/[model]` page vs.
 * only appearing in the vendor-family table (_docs/08-growth.md SEO guardrails).
 *
 * The shipped JSON is the sole source of model existence; this registry only annotates it.
 */

import { modelKey } from "@/lib/model-identity";
import {
	MODEL_IDS,
	type ModelId,
	type ModelPricing,
	PRICING_MODELS,
	RATE_MULTIPLIERS,
} from "./pricing-data";

export type PricingVendor =
	| "claude"
	| "openai"
	| "gemini"
	| "xai"
	| "meta"
	| "deepseek"
	| "opencode";

/** All possible LiteLLM price-field keys, used to count populated fields for the anti-thin gate. */
const PRICE_FIELD_KEYS: (keyof ModelPricing)[] = [
	"input_cost_per_token",
	"output_cost_per_token",
	"cache_creation_input_token_cost",
	"cache_creation_input_token_cost_above_1hr",
	"cache_read_input_token_cost",
	"input_cost_per_token_above_200k_tokens",
	"output_cost_per_token_above_200k_tokens",
	"cache_creation_input_token_cost_above_200k_tokens",
	"cache_creation_input_token_cost_above_1hr_above_200k_tokens",
	"cache_read_input_token_cost_above_200k_tokens",
];

/**
 * Human-facing display names (title/H1 surface). An accounting row reads as its model's name, a
 * middle dot, and the rate it selects: `Grok 4.7 · OpenCode`, `DeepSeek V4 Flash · Go peak`,
 * `Claude Opus 5.5 · Fast mode` (`library-pricing-registry.test.ts` derives each name from its base).
 */
export const MODEL_DISPLAY_NAME: Record<ModelId, string> = {
	"grok-4.7-opencode": "Grok 4.7 · OpenCode",
	"grok-4.6-opencode": "Grok 4.6 · OpenCode",
	"grok-4.5-opencode": "Grok 4.5 · OpenCode",
	"grok-build-0.1-opencode": "Grok Build 0.1 · OpenCode",
	"gpt-5-codex-zen": "GPT-5-Codex · Zen",
	"gpt-5.1-codex-zen": "GPT-5.1-Codex · Zen",
	"claude-opus-5-5": "Claude Opus 5.5",
	"claude-opus-5": "Claude Opus 5",
	"claude-opus-4-8": "Claude Opus 4.8",
	"claude-opus-5-5-fast-mode": "Claude Opus 5.5 · Fast mode",
	"claude-opus-5-fast-mode": "Claude Opus 5 · Fast mode",
	"claude-opus-4-8-fast-mode": "Claude Opus 4.8 · Fast mode",
	"claude-opus-4-7": "Claude Opus 4.7",
	"claude-opus-4-6": "Claude Opus 4.6",
	"claude-opus-4-5": "Claude Opus 4.5",
	"claude-fable-5-2": "Claude Fable 5.2",
	"claude-fable-5-1": "Claude Fable 5.1",
	"claude-mythos-5-1": "Claude Mythos 5.1",
	"claude-fable-5": "Claude Fable 5",
	"claude-mythos-5": "Claude Mythos 5",
	"claude-sonnet-5-5-zen": "Claude Sonnet 5.5 · Zen",
	"claude-sonnet-5-5": "Claude Sonnet 5.5",
	"claude-sonnet-5": "Claude Sonnet 5",
	"claude-sonnet-4-6": "Claude Sonnet 4.6",
	"claude-sonnet-4-5": "Claude Sonnet 4.5",
	"claude-haiku-5-5": "Claude Haiku 5.5",
	"claude-haiku-4-5": "Claude Haiku 4.5",
	"gpt-6.1-sol": "GPT-6.1 Sol",
	"gpt-6.1-terra": "GPT-6.1 Terra",
	"gpt-6-sol": "GPT-6 Sol",
	"gpt-6-luna": "GPT-6 Luna",
	"mimo-v2.6-flash": "MiMo V2.6 Flash",
	"mimo-v2.6-pro": "MiMo V2.6 Pro",
	"deepseek-v4.1-flash-zen": "DeepSeek V4.1 Flash · Zen",
	"deepseek-v4.1-flash-peak": "DeepSeek V4.1 Flash · Go peak",
	"deepseek-v4-flash-go-peak": "DeepSeek V4 Flash · Go peak",
	"deepseek-v4-flash-vision-exp-go-peak": "DeepSeek V4 Flash Vision (exp) · Go peak",
	"deepseek-v4-pro-go-peak": "DeepSeek V4 Pro · Go peak",
	"gpt-6-astra": "GPT-6 Astra",
	"gpt-5.6-sol": "GPT-5.6 Sol",
	"gpt-5.6-luna": "GPT-5.6 Luna",
	"gpt-5.6-terra": "GPT-5.6 Terra",
	"gpt-5.5": "GPT-5.5",
	"gpt-5.4": "GPT-5.4",
	"gpt-5.4-mini": "GPT-5.4 mini",
	"gpt-5.3-codex": "GPT-5.3-Codex",
	"gpt-5.3-codex-spark": "GPT-5.3-Codex-Spark",
	"gpt-5.2": "GPT-5.2",
	"gpt-5.2-codex": "GPT-5.2-Codex",
	"gpt-5.1-codex": "GPT-5.1-Codex",
	"gpt-5.1-codex-max": "GPT-5.1-Codex-Max",
	"gpt-5.1-codex-mini": "GPT-5.1-Codex-Mini",
	"gpt-5-codex": "GPT-5-Codex",
	"gemini-3-pro-preview": "Gemini 3 Pro",
	"gemini-3": "Gemini 3",
	"gemini-3-flash-preview": "Gemini 3 Flash",
	"gemini-2.5-pro": "Gemini 2.5 Pro",
	"gemini-2.5-flash": "Gemini 2.5 Flash",
	"gemini-2.5-flash-lite": "Gemini 2.5 Flash-Lite",
	"gemini-3.1-pro": "Gemini 3.1 Pro",
	"gemini-4-argon": "Gemini 4 Argon",
	"gemini-3.5-flash": "Gemini 3.5 Flash",
	"gemini-3.5-flash-lite": "Gemini 3.5 Flash-Lite",
	"grok-4.7": "Grok 4.7",
	"grok-4.7-fast": "Grok 4.7 Fast",
	"grok-4.6": "Grok 4.6",
	"grok-4.5": "Grok 4.5",
	"grok-4.3": "Grok 4.3",
	"grok-4.20-0309-reasoning": "Grok 4.20 Reasoning",
	"grok-4.20-0309-non-reasoning": "Grok 4.20 Non-reasoning",
	"grok-4.20-multi-agent-0309": "Grok 4.20 Multi-agent",
	"grok-build-0.1": "Grok Build 0.1",
	"grok-composer-2.5-fast": "Composer 2.5 Fast",
	"grok-composer-2.5": "Composer 2.5",
	"muse-spark-1.1": "Muse Spark 1.1",
	"muse-spark-1.2": "Muse Spark 1.2",
	"muse-spark-1.3": "Muse Spark 1.3",
	"muse-wonder-1.0": "Muse Wonder 1.0",
	"deepseek-v4-flash": "DeepSeek V4 Flash",
	"deepseek-v4-flash-vision-exp": "DeepSeek V4 Flash Vision (exp)",
	"deepseek-v4-pro": "DeepSeek V4 Pro",
	"deepseek-v4.1-flash": "DeepSeek V4.1 Flash",
	"deepseek-v4-flash-go": "DeepSeek V4 Flash · Go",
	"deepseek-v4-flash-vision-exp-go": "DeepSeek V4 Flash Vision (exp) · Go",
	"deepseek-v4-pro-go": "DeepSeek V4 Pro · Go",
	"big-pickle": "Big Pickle",
	"glm-5.3-flash": "GLM 5.3 Flash",
	"glm-5.3": "GLM 5.3",
	"glm-5.2": "GLM 5.2",
	"glm-5.1": "GLM 5.1",
	"kimi-k3": "Kimi K3",
	"kimi-k3.1-pro": "Kimi K3.1 Pro",
	"step-5-preview": "Step 5 Preview",
	"kimi-k2.7-code": "Kimi K2.7 Code",
	"kimi-k2.6": "Kimi K2.6",
	"longcat-2.0": "LongCat 2.0",
	"mimo-v2.5": "MiMo V2.5",
	"mimo-v2.5-pro": "MiMo V2.5 Pro",
	"minimax-m3": "MiniMax M3",
	"minimax-m3.1-flash": "MiniMax M3.1 Flash",
	"minimax-m2.7": "MiniMax M2.7",
	"qwen3.8-max": "Qwen 3.8 Max",
	"qwen3.8-flash": "Qwen 3.8 Flash",
	"qwen3.7-max": "Qwen 3.7 Max",
	"qwen3.7-plus": "Qwen 3.7 Plus",
	"qwen3.6-plus": "Qwen 3.6 Plus",
	"qwen3.5-plus": "Qwen 3.5 Plus",
	"hy4-preview": "Hy4 Preview",
	hy3: "Hy3",
	"space-bunny": "Space Bunny",
	"muse-spark-1.3-contributor": "Muse Spark 1.3 Contributor",
	"muse-spark-1.2-contributor": "Muse Spark 1.2 Contributor",
	"minimax-m2.5": "MiniMax M2.5",
	"union-alpha": "Union Alpha",
};

/**
 * Enrichment facts (from `_docs/03-data.md`, prose-only — never a priced field) that make a page distinct
 * from a flat vendor recap. `new-tokenizer`: ~30% more tokens for the same text. A context tier is
 * never an enrichment: page copy reads the model's own premium fields and threshold instead.
 */
export type ModelEnrichment =
	| "fast-mode"
	| "new-tokenizer"
	| "limited-availability"
	| "grok-notional"
	| "muse-spark-notional"
	| "opencode-notional";
export type ModelEffortLevel = "low" | "medium" | "high";

export function modelEffortLevelLabel(level: ModelEffortLevel): string {
	switch (level) {
		case "low":
			return "Low";
		case "medium":
			return "Medium";
		case "high":
			return "High";
	}
}

const MODEL_ENRICHMENTS: Partial<Record<ModelId, ModelEnrichment[]>> = {
	"claude-opus-5-5": ["new-tokenizer"],
	"claude-opus-5": ["new-tokenizer"],
	"claude-opus-4-8": ["new-tokenizer"],
	"claude-opus-5-5-fast-mode": ["fast-mode", "new-tokenizer"],
	"claude-opus-5-fast-mode": ["fast-mode", "new-tokenizer"],
	"claude-opus-4-8-fast-mode": ["fast-mode", "new-tokenizer"],
	"claude-opus-4-7": ["new-tokenizer"],
	"claude-fable-5-2": ["new-tokenizer"],
	"claude-fable-5-1": ["new-tokenizer"],
	"claude-mythos-5-1": ["new-tokenizer", "limited-availability"],
	"claude-fable-5": ["new-tokenizer"],
	"claude-mythos-5": ["new-tokenizer", "limited-availability"],
	"claude-haiku-5-5": ["new-tokenizer"],
	"claude-sonnet-5-5": ["new-tokenizer"],
	"claude-sonnet-5": ["new-tokenizer"],
	"mimo-v2.6-flash": ["opencode-notional"],
	"mimo-v2.6-pro": ["opencode-notional"],
	"deepseek-v4.1-flash-zen": ["opencode-notional"],
	"deepseek-v4.1-flash-peak": ["opencode-notional"],
	"deepseek-v4-flash-go-peak": ["opencode-notional"],
	"deepseek-v4-flash-vision-exp-go-peak": ["opencode-notional"],
	"deepseek-v4-pro-go-peak": ["opencode-notional"],
	"grok-4.7": ["grok-notional"],
	"grok-4.7-fast": ["grok-notional"],
	"grok-4.6": ["grok-notional"],
	"grok-4.5": ["grok-notional"],
	"grok-4.3": ["grok-notional"],
	"grok-4.20-0309-reasoning": ["grok-notional"],
	"grok-4.20-0309-non-reasoning": ["grok-notional"],
	"grok-4.20-multi-agent-0309": ["grok-notional"],
	"grok-build-0.1": ["grok-notional"],
	"grok-composer-2.5-fast": ["grok-notional"],
	"grok-composer-2.5": ["grok-notional"],
	"muse-spark-1.1": ["muse-spark-notional"],
	"muse-spark-1.2": ["muse-spark-notional"],
	"muse-spark-1.3": ["muse-spark-notional"],
	"muse-wonder-1.0": ["muse-spark-notional"],
	"deepseek-v4-flash": ["opencode-notional"],
	"deepseek-v4-flash-vision-exp": ["opencode-notional"],
	"deepseek-v4-pro": ["opencode-notional"],
	"deepseek-v4.1-flash": ["opencode-notional"],
	"deepseek-v4-flash-go": ["opencode-notional"],
	"deepseek-v4-flash-vision-exp-go": ["opencode-notional"],
	"deepseek-v4-pro-go": ["opencode-notional"],
	"big-pickle": ["opencode-notional"],
	"glm-5.3-flash": ["opencode-notional"],
	"glm-5.3": ["opencode-notional"],
	"glm-5.2": ["opencode-notional"],
	"glm-5.1": ["opencode-notional"],
	"kimi-k3": ["opencode-notional"],
	"kimi-k3.1-pro": ["opencode-notional"],
	"step-5-preview": ["opencode-notional"],
	"kimi-k2.7-code": ["opencode-notional"],
	"kimi-k2.6": ["opencode-notional"],
	"longcat-2.0": ["opencode-notional"],
	"mimo-v2.5": ["opencode-notional"],
	"mimo-v2.5-pro": ["opencode-notional"],
	"minimax-m3": ["opencode-notional"],
	"minimax-m3.1-flash": ["opencode-notional"],
	"minimax-m2.7": ["opencode-notional"],
	"qwen3.8-max": ["opencode-notional"],
	"qwen3.8-flash": ["opencode-notional"],
	"qwen3.7-max": ["opencode-notional"],
	"qwen3.7-plus": ["opencode-notional"],
	"qwen3.6-plus": ["opencode-notional"],
	"qwen3.5-plus": ["opencode-notional"],
	"hy4-preview": ["opencode-notional"],
	hy3: ["opencode-notional"],
	"space-bunny": ["opencode-notional"],
	"muse-spark-1.3-contributor": ["muse-spark-notional"],
	"muse-spark-1.2-contributor": ["muse-spark-notional"],
	"minimax-m2.5": ["opencode-notional"],
	"union-alpha": ["opencode-notional"],
};

/**
 * Curated standalone-page overrides: thin (3-field) models that STILL earn a standalone page
 * because a Codex-notional framing adds genuine, distinct value beyond the vendor-family table.
 * Kept to the flagship Codex models on purpose (_docs/08-growth.md SEO guardrails) — do NOT blanket-add all `gpt-*`.
 */
const STANDALONE_MODEL_OVERRIDES = new Set<ModelId>([
	"gpt-5.3-codex",
	"gpt-5.3-codex-spark",
	"gpt-5-codex",
]);

const MODEL_EFFORT_LEVELS: Partial<Record<ModelId, ModelEffortLevel>> = {
	"claude-opus-5-5": "high",
	"claude-opus-5": "high",
	"claude-opus-4-8": "high",
	"claude-opus-4-7": "high",
	"claude-opus-4-6": "high",
	"claude-opus-4-5": "high",
	"claude-fable-5-2": "high",
	"claude-fable-5-1": "high",
	"claude-mythos-5-1": "high",
	"claude-fable-5": "high",
	"claude-mythos-5": "high",
	"claude-sonnet-5-5": "high",
	"claude-sonnet-5": "high",
	"claude-sonnet-4-6": "high",
	"claude-sonnet-4-5": "high",
	"claude-haiku-5-5": "medium",
	"claude-haiku-4-5": "low",
	"gpt-6.1-sol": "high",
	"gpt-6.1-terra": "high",
	"gpt-6-sol": "high",
	"gpt-6-luna": "low",
	"mimo-v2.6-flash": "low",
	"mimo-v2.6-pro": "medium",
	"gpt-6-astra": "high",
	"gpt-5.6-sol": "high",
	"gpt-5.6-luna": "high",
	"gpt-5.6-terra": "high",
	"gpt-5.5": "high",
	"gpt-5.4": "high",
	"gpt-5.4-mini": "low",
	"gpt-5.3-codex": "high",
	"gpt-5.3-codex-spark": "high",
	"gpt-5.2": "high",
	"gpt-5.2-codex": "high",
	"gpt-5.1-codex": "medium",
	"gpt-5.1-codex-max": "high",
	"gpt-5.1-codex-mini": "low",
	"gpt-5-codex": "medium",
	"gemini-3-pro-preview": "high",
	"gemini-3": "high",
	"gemini-3-flash-preview": "low",
	"gemini-2.5-pro": "medium",
	"gemini-2.5-flash": "low",
	"gemini-2.5-flash-lite": "low",
	"grok-4.7": "high",
	"grok-4.7-fast": "high",
	"grok-4.6": "high",
	"grok-4.5": "high",
	"grok-4.3": "high",
	"grok-4.20-0309-reasoning": "high",
	"grok-4.20-0309-non-reasoning": "medium",
	"grok-4.20-multi-agent-0309": "high",
	"grok-build-0.1": "medium",
	"grok-composer-2.5-fast": "high",
	"grok-composer-2.5": "medium",
	"muse-spark-1.1": "high",
	"muse-spark-1.2": "high",
	"muse-spark-1.3": "high",
	"muse-wonder-1.0": "high",
	"glm-5.3-flash": "medium",
	"glm-5.3": "high",
	"glm-5.2": "high",
	"glm-5.1": "high",
	"kimi-k3": "high",
	"kimi-k3.1-pro": "high",
	"step-5-preview": "medium",
	"kimi-k2.7-code": "high",
	"kimi-k2.6": "high",
	"longcat-2.0": "medium",
	"mimo-v2.5": "low",
	"mimo-v2.5-pro": "medium",
	"minimax-m3": "medium",
	"minimax-m3.1-flash": "low",
	"minimax-m2.7": "medium",
	"qwen3.8-max": "high",
	"qwen3.8-flash": "low",
	"qwen3.7-max": "high",
	"qwen3.7-plus": "medium",
	"qwen3.6-plus": "medium",
	"hy4-preview": "medium",
	hy3: "low",
	"muse-spark-1.3-contributor": "high",
	"muse-spark-1.2-contributor": "high",
	"minimax-m2.5": "medium",
	"union-alpha": "low",
};

const VENDOR_NOTIONAL: Record<PricingVendor, boolean> = {
	claude: false,
	openai: true,
	gemini: true,
	xai: true,
	meta: true,
	deepseek: true,
	opencode: true,
};

export const VENDOR_LABEL: Record<PricingVendor, string> = {
	claude: "Claude (Anthropic)",
	openai: "OpenAI (GPT / Codex)",
	gemini: "Google Gemini",
	xai: "xAI (Grok)",
	meta: "Meta (Muse)",
	deepseek: "DeepSeek (via OpenCode Zen / Go)",
	opencode: "OpenCode Zen / Go models",
};

export function modelVendor(id: ModelId): PricingVendor {
	if (
		id.endsWith("-opencode") ||
		((id.startsWith("gpt-") || id.startsWith("claude-")) && id.endsWith("-zen"))
	)
		return "opencode";
	if (id.startsWith("claude-")) return "claude";
	if (id.startsWith("gpt-")) return "openai";
	if (id.startsWith("grok-")) return "xai";
	if (id.startsWith("muse-")) return "meta";
	if (id.startsWith("deepseek-")) return "deepseek";
	if (id.startsWith("gemini-")) return "gemini";
	// Every remaining id is an OpenCode Zen / Go gateway model (big-pickle, glm-*, kimi-*, qwen-*, etc.). A NEW vendor family must be
	// added above explicitly — falling through to a real vendor's label is how MiMo, DeepSeek and
	// Nemotron once shipped as "Google Gemini" models on the live library.
	return "opencode";
}

/** URL-safe slug: dotted ids -> dashes, drop a trailing `-preview`. */
function idToSlug(id: ModelId): string {
	return id.replace(/\./g, "-").replace(/-preview$/, "");
}

export const MODEL_SLUG: Record<ModelId, string> = Object.fromEntries(
	MODEL_IDS.map((id) => [id, idToSlug(id)]),
) as Record<ModelId, string>;

export const MODEL_SLUG_TO_ID: Record<string, ModelId> = Object.fromEntries(
	MODEL_IDS.map((id) => [MODEL_SLUG[id], id]),
);

export function modelIdFromSlug(slug: string): ModelId | undefined {
	return MODEL_SLUG_TO_ID[slug];
}

export function pricing(id: ModelId): ModelPricing {
	return PRICING_MODELS[id];
}

export function populatedPriceFieldCount(id: ModelId): number {
	const p: ModelPricing = PRICING_MODELS[id];
	return PRICE_FIELD_KEYS.filter((key) => p[key] !== undefined).length;
}

export function modelEnrichments(id: ModelId): ModelEnrichment[] {
	if (id.endsWith("-opencode") || id.endsWith("-zen")) return ["opencode-notional"];
	return MODEL_ENRICHMENTS[id] ?? [];
}

/** Claude rows older than 4.6, which reject `inference_geo`, so US-only inference never prices them. */
const CLAUDE_WITHOUT_INFERENCE_GEO = new Set<ModelId>([
	"claude-opus-4-5",
	"claude-sonnet-4-5",
	"claude-haiku-4-5",
]);

/** The US-only inference factor for a Claude 4.6+ row, or undefined where it cannot apply. */
export function usInferenceMultiplier(id: ModelId): number | undefined {
	if (modelVendor(id) !== "claude" || CLAUDE_WITHOUT_INFERENCE_GEO.has(id)) return undefined;
	return RATE_MULTIPLIERS["-us-inference"];
}

export function isSubscriptionNotional(id: ModelId): boolean {
	return VENDOR_NOTIONAL[modelVendor(id)];
}

/** Field-weighted anti-thin gate: >=5 populated price fields OR a curated standalone override. */
export function isModelPricingEligible(id: ModelId): boolean {
	return populatedPriceFieldCount(id) >= 5 || STANDALONE_MODEL_OVERRIDES.has(id);
}

export function eligibleModelIds(): ModelId[] {
	return MODEL_IDS.filter(isModelPricingEligible);
}

export function eligibleModelSlugs(): string[] {
	return eligibleModelIds().map((id) => MODEL_SLUG[id]);
}

export const VENDORS: PricingVendor[] = [
	"claude",
	"openai",
	"gemini",
	"xai",
	"meta",
	"deepseek",
	"opencode",
];

export function modelsForVendor(vendor: PricingVendor): ModelId[] {
	return MODEL_IDS.filter((id) => modelVendor(id) === vendor);
}

/**
 * Effort tier for a pricing row or a raw emitted id, resolved through `modelKey` so a gateway route
 * (`grok-4.7-opencode`), an alias (`gpt-reserve`), or a free tier reads its model's tier. An
 * unclassified model has none: callers omit the chip rather than show a guessed "Medium".
 */
export function modelEffortLevel(model: string): ModelEffortLevel | undefined {
	return MODEL_EFFORT_LEVELS[modelKey(model) as ModelId];
}

/** Per-token -> per-million-token dollars. */
export function perMillion(perToken: number): number {
	return perToken * 1e6;
}
