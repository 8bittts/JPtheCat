import type { ModelId } from "./pricing-data";

// Retained for historical local accounting; the current first-party audit could not verify these rates.
export const UNVERIFIED_PRICING_IDS: readonly ModelId[] = [
	"gemini-3",
	"gemini-3-pro-preview",
	"union-alpha",
	"gpt-5.3-codex-spark",
];
const HISTORICAL_FIELD_CAVEATS: Partial<Record<ModelId, string>> = {
	"qwen3.6-plus":
		"Base rates match Zen. The context premium is retained from earlier Go pricing and is absent from the current Go table.",
	"minimax-m2.5":
		"Base rates match Zen. The cache-write rate is retained from earlier Go pricing and is absent from current tables.",
};

export function pricingCaveat(id: ModelId): string | undefined {
	if (UNVERIFIED_PRICING_IDS.includes(id))
		return "Historical bundled rate; not verified against current published pricing.";
	return HISTORICAL_FIELD_CAVEATS[id];
}
