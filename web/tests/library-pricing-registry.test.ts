import { describe, expect, it } from "bun:test";
import { MODEL_ID_ALIASES, MODEL_IDS, type ModelId } from "@/lib/library/pricing-data";
import {
	eligibleModelSlugs,
	isModelPricingEligible,
	MODEL_DISPLAY_NAME,
	MODEL_SLUG,
	MODEL_SLUG_TO_ID,
	modelsForVendor,
	modelVendor,
	perMillion,
	populatedPriceFieldCount,
	pricing,
	VENDORS,
} from "@/lib/library/pricing-registry";
import { modelKey, presentationModelId } from "@/lib/model-identity";

describe("library pricing registry", () => {
	it("gives every model a unique URL-safe slug that round-trips", () => {
		const slugs = MODEL_IDS.map((id) => MODEL_SLUG[id]);
		expect(new Set(slugs).size).toBe(MODEL_IDS.length);
		for (const slug of slugs) {
			expect(slug).toMatch(/^[a-z0-9-]+$/);
			expect(MODEL_SLUG_TO_ID[slug]).toBeDefined();
		}
		// Dotted ids + `-preview` suffixes normalise; slugs reverse cleanly (_docs/08-growth.md SEO guardrails).
		expect(MODEL_SLUG["gemini-3-pro-preview"]).toBe("gemini-3-pro");
		expect(MODEL_SLUG["gpt-5.3-codex"]).toBe("gpt-5-3-codex");
		expect(MODEL_SLUG_TO_ID["gpt-5-3-codex"]).toBe("gpt-5.3-codex");
	});

	it("admits exactly the 51 standalone-eligible model pages (field-weighted gate)", () => {
		expect(eligibleModelSlugs().sort()).toEqual(
			[
				"claude-fable-5",
				"claude-fable-5-1",
				"claude-fable-5-2",
				"claude-mythos-5",
				"claude-mythos-5-1",
				"claude-haiku-5-5",
				"claude-haiku-4-5",
				"claude-opus-5",
				"claude-opus-5-5",
				"claude-opus-4-5",
				"claude-opus-4-6",
				"claude-opus-4-7",
				"claude-opus-4-8",
				"claude-opus-5-5-fast-mode",
				"claude-opus-5-fast-mode",
				"claude-opus-4-8-fast-mode",
				"claude-sonnet-5-5",
				"claude-sonnet-5",
				"claude-sonnet-4-5",
				"claude-sonnet-4-6",
				"gemini-2-5-pro",
				"gemini-3",
				"gemini-3-pro",
				"gemini-3-1-pro",
				"gpt-5-3-codex",
				"gpt-5-3-codex-spark",
				"gpt-5-codex",
				"gpt-5-4",
				"gpt-5-5",
				"gpt-5-6-luna",
				"gpt-5-6-sol",
				"gpt-5-6-terra",
				"gpt-6-astra",
				"gpt-6-luna",
				"gpt-6-1-sol",
				"gpt-6-1-terra",
				"gpt-6-sol",
				"qwen3-6-plus",
				"qwen3-7-plus",

				"grok-4-20-0309-non-reasoning",
				"grok-4-20-0309-reasoning",
				"grok-4-20-multi-agent-0309",
				"grok-4-3",
				"grok-4-5",
				"grok-4-5-opencode",
				"grok-4-6-opencode",
				"grok-4-7-opencode",
				"grok-4-6",
				"grok-4-7",
				"grok-4-7-fast",
				"grok-build-0-1",
			].sort(),
		);
	});

	it("defines display names for every model id", () => {
		for (const id of MODEL_IDS) {
			expect(MODEL_DISPLAY_NAME[id]).toBeTypeOf("string");
		}
	});

	it("names every accounting row as its model plus one rate label", () => {
		const routeLabel = (id: string): string => {
			if (id.endsWith("-fast-mode")) return "Fast mode";
			if (id.endsWith("-opencode")) return "OpenCode";
			if (id.endsWith("-zen")) return "Zen";
			if (id.endsWith("-peak")) return "Go peak";
			return "Go";
		};
		let routes = 0;
		for (const id of MODEL_IDS) {
			const base = presentationModelId(id);
			if (base === id) continue;
			routes += 1;
			expect(MODEL_IDS).toContain(base as ModelId);
			expect([id, MODEL_DISPLAY_NAME[id]]).toEqual([
				id,
				`${MODEL_DISPLAY_NAME[base as ModelId]} · ${routeLabel(id)}`,
			]);
		}
		expect(routes).toBe(18);
	});

	it("folds thin 3-field models out of standalone pages (into the vendor-family table)", () => {
		expect(isModelPricingEligible("gpt-5.4-mini")).toBe(false);
		expect(isModelPricingEligible("gemini-2.5-flash")).toBe(false);
		expect(populatedPriceFieldCount("gpt-5.4-mini")).toBe(3);
		expect(populatedPriceFieldCount("claude-opus-4-8")).toBe(5);
		expect(populatedPriceFieldCount("claude-sonnet-4-5")).toBe(10);
	});

	it("groups all 114 models under exactly seven vendor families", () => {
		const total = VENDORS.reduce((n, vendor) => n + modelsForVendor(vendor).length, 0);
		expect(total).toBe(114);
		expect(VENDORS).toEqual(["claude", "openai", "gemini", "xai", "meta", "deepseek", "opencode"]);
		expect(modelVendor("gpt-5-codex")).toBe("openai");
		expect(modelVendor("gemini-3")).toBe("gemini");
		expect(modelVendor("claude-opus-4-8")).toBe("claude");
		expect(modelVendor("grok-4.5")).toBe("xai");
		expect(modelVendor("muse-spark-1.1")).toBe("meta");
		expect(modelVendor("muse-spark-1.3")).toBe("meta");
		expect(modelVendor("muse-wonder-1.0")).toBe("meta");
		// [Regression guard] Every OpenCode-family id has its OWN vendor; the fall-through once filed
		// MiMo, DeepSeek, Nemotron and Big Pickle under "Google Gemini" on the live library.
		expect(modelVendor("deepseek-v4-flash")).toBe("deepseek");
		expect(modelVendor("deepseek-v4-pro")).toBe("deepseek");
		expect(modelVendor("big-pickle")).toBe("opencode");
		expect(modelVendor("glm-5.3-flash")).toBe("opencode");
		expect(modelVendor("qwen3.8-max")).toBe("opencode");
		expect(modelVendor("minimax-m2.5")).toBe("opencode");
		expect(modelVendor("union-alpha")).toBe("opencode");
		expect(modelVendor("muse-spark-1.3-contributor")).toBe("meta");
		for (const id of MODEL_IDS) {
			if (modelVendor(id) === "gemini") expect(id.startsWith("gemini-")).toBe(true);
		}
	});

	it("keeps Zen Sonnet's undocumented one-hour write rate out of the published table", () => {
		const zen = pricing("claude-sonnet-5-5-zen");
		expect(zen.cache_read_input_token_cost).toBe(2e-7);
		expect(zen.cache_creation_input_token_cost).toBe(2.5e-6);
		expect(zen.cache_creation_input_token_cost_above_1hr).toBeUndefined();
		expect(populatedPriceFieldCount("claude-sonnet-5-5-zen")).toBe(4);
		expect(isModelPricingEligible("claude-sonnet-5-5-zen")).toBe(false);
		expect(modelVendor("claude-sonnet-5-5-zen")).toBe("opencode");
	});
	it("converts per-token to per-MTok", () => {
		expect(perMillion(5e-6)).toBeCloseTo(5);
		expect(perMillion(25e-6)).toBeCloseTo(25);
	});

	it("resolves the locally emitted Grok Build alias to canonical Grok 4.5 pricing", () => {
		expect(MODEL_ID_ALIASES["grok-4.5-build"]).toBe("grok-4.5");
		const id = modelKey("grok-4.5-build") as ModelId;
		expect(id).toBe("grok-4.5");
		expect(id && pricing(id)).toMatchObject({
			input_cost_per_token: 2e-6,
			cache_read_input_token_cost: 0.3e-6,
			output_cost_per_token: 6e-6,
		});
	});

	it("resolves the locally emitted grok-4.7-build alias to Grok 4.7 list rates", () => {
		expect(MODEL_ID_ALIASES["grok-4.7-build"]).toBe("grok-4.7");
		const id = modelKey("grok-4.7-build") as ModelId;
		expect(id).toBe("grok-4.7");
		expect(id && pricing(id)).toMatchObject({
			input_cost_per_token: 2e-6,
			cache_read_input_token_cost: 0.5e-6,
			output_cost_per_token: 6e-6,
			input_cost_per_token_above_200k_tokens: 4e-6,
			cache_read_input_token_cost_above_200k_tokens: 1e-6,
			output_cost_per_token_above_200k_tokens: 1.2e-5,
		});
	});

	it("prices Fable 5.2 below Fable 5.1 and aliases Cursor's Opus 5.5 medium id", () => {
		expect(pricing("claude-fable-5-2")).toMatchObject({
			input_cost_per_token: 8e-6,
			output_cost_per_token: 4e-5,
			cache_creation_input_token_cost: 1e-5,
			cache_creation_input_token_cost_above_1hr: 1.6e-5,
			cache_read_input_token_cost: 2e-7,
		});
		expect(pricing("claude-fable-5-2").input_cost_per_token).not.toBe(
			pricing("claude-fable-5-1").input_cost_per_token,
		);
		expect(MODEL_ID_ALIASES["claude-opus-5-5-medium"]).toBe("claude-opus-5-5");
		expect(modelKey("claude-opus-5-5-medium")).toBe("claude-opus-5-5");
	});

	it("prices Grok 4.7 Fast at the published 2x and 1.5x rates", () => {
		expect(MODEL_ID_ALIASES["grok-4.7-high-fast"]).toBe("grok-4.7-fast");
		expect(pricing("grok-4.7-fast")).toMatchObject({
			input_cost_per_token: 4e-6,
			cache_read_input_token_cost: 1e-6,
			output_cost_per_token: 1.2e-5,
			input_cost_per_token_above_200k_tokens: 6e-6,
			cache_read_input_token_cost_above_200k_tokens: 1.5e-6,
			output_cost_per_token_above_200k_tokens: 1.8e-5,
		});
		expect(pricing("grok-4.7-fast").context_tier_inclusive).toBeUndefined();
	});

	it("prices Claude Opus 5.5 cache hits at 0.05x input, not 0.1x", () => {
		expect(pricing("claude-opus-5-5")).toMatchObject({
			input_cost_per_token: 4e-6,
			output_cost_per_token: 2e-5,
			cache_creation_input_token_cost: 5e-6,
			cache_creation_input_token_cost_above_1hr: 8e-6,
			cache_read_input_token_cost: 2e-7,
		});
	});

	it("resolves the locally emitted grok-4.6-build alias to distinct Grok 4.6 cached rates", () => {
		expect(MODEL_ID_ALIASES["grok-4.6-build"]).toBe("grok-4.6");
		const id = modelKey("grok-4.6-build") as ModelId;
		expect(id).toBe("grok-4.6");
		expect(id && pricing(id)).toMatchObject({
			input_cost_per_token: 2e-6,
			cache_read_input_token_cost: 0.5e-6,
			output_cost_per_token: 6e-6,
			cache_read_input_token_cost_above_200k_tokens: 1e-6,
		});
		expect(pricing("grok-4.6").cache_read_input_token_cost).not.toBe(
			pricing("grok-4.5").cache_read_input_token_cost,
		);
	});
});
