import { describe, expect, it } from "bun:test";
import {
	MODEL_ID_ALIASES,
	MODEL_IDS,
	PRICING_MODELS,
	RATE_MULTIPLIERS,
} from "@/lib/library/pricing-data";

// [CRITICAL] Drift guard: the web mirror must equal the shipped app pricing table exactly.
// The mac JSON is the SOLE source of model existence + numbers (_docs/08-growth.md SEO guardrails).
describe("library pricing parity", () => {
	it("web mirror deep-equals the shipped mac pricing-default.json models", async () => {
		const macJsonText = await Bun.file(
			"../mac/Sources/JPtheCatCore/Resources/pricing-default.json",
		).text();
		const macJson = JSON.parse(macJsonText) as {
			models: Record<string, unknown>;
			aliases: Record<string, string>;
			rate_multipliers: Record<string, number>;
		};

		expect(PRICING_MODELS as Record<string, unknown>).toEqual(macJson.models);
		expect(MODEL_ID_ALIASES as Record<string, string>).toEqual(macJson.aliases);
		expect(Object.keys(MODEL_ID_ALIASES).length).toBeGreaterThan(0);
		expect(RATE_MULTIPLIERS as Record<string, number>).toEqual(macJson.rate_multipliers);
	});

	it("mirrors exactly 112 models", () => {
		expect(MODEL_IDS.length).toBe(112);
	});
});
