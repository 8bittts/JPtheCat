import { describe, expect, it } from "bun:test";
import { CALCULATOR_DEFAULTS, priceTokenMix } from "@/lib/library/calculator-math";
import {
	calculatorBySlug,
	calculatorLeaf,
	calculatorMode,
	calculatorModels,
} from "@/lib/library/content/calculators";
import { modelsForVendor } from "@/lib/library/pricing-registry";

function models(slug: string) {
	const calc = calculatorBySlug(slug);
	expect(calc).toBeDefined();
	return calculatorModels(calc!);
}

function model(slug: string, id: string) {
	const found = models(slug).find((entry) => entry.id === id);
	expect(found).toBeDefined();
	return found!;
}

const perM = (perToken: number) => Math.round(perToken * 1e6 * 1e6) / 1e6;

describe("library calculators", () => {
	it("offers each live vendor's current flagship in the tokens-to-dollars picker", () => {
		const ids: string[] = models("tokens-to-dollars").map((entry) => entry.id);
		for (const id of [
			"claude-fable-5-2",
			"claude-opus-5-5",
			"claude-sonnet-5-5",
			"claude-haiku-5-5",
			"gpt-6-astra",
			"gpt-5.6-sol",
			"grok-4.7",
			"muse-spark-1.3",
		]) {
			expect(ids).toContain(id);
		}
		expect(model("tokens-to-dollars", "muse-spark-1.3").notional).toBe(true);
		expect(model("tokens-to-dollars", "claude-opus-5-5").notional).toBe(false);
	});

	it("uses each model's published cache rates, not a flat 0.1x", () => {
		// platform.claude.com/docs/en/about-claude/pricing
		const fable = model("tokens-to-dollars", "claude-fable-5-2");
		expect([perM(fable.input), perM(fable.cacheRead), perM(fable.cacheWrite)]).toEqual([
			8, 0.2, 10,
		]);
		const sol = model("tokens-to-dollars", "gpt-6.1-sol");
		expect([perM(sol.input), perM(sol.cacheRead), perM(sol.cacheWrite)]).toEqual([2, 0.1, 2.5]);
		const opus = model("tokens-to-dollars", "claude-opus-5-5");
		expect([perM(opus.input), perM(opus.output), perM(opus.cacheRead)]).toEqual([4, 20, 0.2]);
		// docs.x.ai/developers/pricing: grok-4.7 cached input is 0.25x, not 0.1x.
		expect(perM(model("tokens-to-dollars", "grok-4.7").cacheRead)).toBe(0.5);
	});

	it("prices cache writes at the model's 5-minute write rate", () => {
		const sonnet = model("claude-code-monthly-cost", "claude-sonnet-5-5");
		const mix = { input: 0, output: 0, cacheRead: 0, cacheWrite: 1000 };
		expect(priceTokenMix(sonnet, mix, false).cost).toBeCloseTo(2.5, 10);
	});

	it("keeps the Claude Code calculator to Claude models", () => {
		const ids: string[] = models("claude-code-monthly-cost").map((entry) => entry.id);
		expect(ids.length).toBeGreaterThan(0);
		expect(ids.every((id) => id.startsWith("claude-"))).toBe(true);
	});

	it("covers every direct OpenAI model Codex can emit, not only *-codex ids", () => {
		const ids: string[] = models("codex-notional-cost").map((entry) => entry.id);
		expect(ids).toEqual([...modelsForVendor("openai")] as string[]);
		for (const id of ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.5", "gpt-5.4", "gpt-5.3-codex"]) {
			expect(ids).toContain(id);
		}
		expect(ids.some((id) => id.endsWith("-zen"))).toBe(false);
	});

	it("applies the whole-request surcharge only in the per-request calculator", () => {
		const calc = calculatorBySlug("context-200k-surcharge")!;
		expect(calculatorMode(calc)).toBe("request");
		expect(calculatorMode(calculatorBySlug("tokens-to-dollars")!)).toBe("session");
		const surchargeModels = calculatorModels(calc);
		expect(surchargeModels.every((entry) => entry.tier !== undefined)).toBe(true);

		const astra = model("context-200k-surcharge", "gpt-6-astra");
		const defaults = CALCULATOR_DEFAULTS.request;
		const priced = priceTokenMix(astra, defaults, true);
		expect(priced.tiered).toBe(true);
		// 200K x $20 + 8K x $75 + 100K x $2 per MTok (developers.openai.com long-context rates).
		expect(priced.cost).toBeCloseTo(4 + 0.6 + 0.2, 10);
		expect(priceTokenMix(astra, defaults, false).tiered).toBe(false);
	});

	it("prices Haiku 5.5 per request at the exact 100K prompt boundary", () => {
		const haiku = model("context-200k-surcharge", "claude-haiku-5-5");
		expect(haiku.tier?.lastBaseTokens).toBe(100_000);
		const mix = { input: 25, output: 1, cacheRead: 50, cacheWrite: 25 };
		expect(priceTokenMix(haiku, mix, true).tiered).toBe(false);
		const over = priceTokenMix(haiku, { ...mix, input: 25.001 }, true);
		expect(over.tiered).toBe(true);
		expect(over.cost).toBeCloseTo(0.0125 + 0.0000005 + 0.0025 + 0.0025 + 0.015625, 12);
	});
	it("honors inclusive and exclusive thresholds exactly like CostCalculator", () => {
		const grok = model("context-200k-surcharge", "grok-4.7");
		expect(grok.tier?.lastBaseTokens).toBe(199_999);
		const at200k = { input: 200, output: 0, cacheRead: 0, cacheWrite: 0 };
		expect(priceTokenMix(grok, at200k, true).tiered).toBe(true);
		const fast = model("context-200k-surcharge", "grok-4.7-fast");
		expect(fast.tier?.lastBaseTokens).toBe(200_000);
		expect(priceTokenMix(fast, at200k, true).tiered).toBe(false);
		expect(priceTokenMix(fast, { ...at200k, input: 200.001 }, true).tiered).toBe(true);

		const astra = model("context-200k-surcharge", "gpt-6-astra");
		expect(astra.tier?.lastBaseTokens).toBe(272_000);
		const at272k = { input: 272, output: 0, cacheRead: 0, cacheWrite: 0 };
		expect(priceTokenMix(astra, at272k, true).tiered).toBe(false);
	});

	it("never trips the surcharge on summed session totals", () => {
		const astra = model("tokens-to-dollars", "gpt-6-astra");
		expect(priceTokenMix(astra, CALCULATOR_DEFAULTS.session, false).tiered).toBe(false);
	});

	it("does not claim a flat 0.1x cache discount", () => {
		for (const slug of ["tokens-to-dollars", "context-200k-surcharge", "prompt-cache-savings"]) {
			const leaf = calculatorLeaf(calculatorBySlug(slug)!);
			const text = [leaf.description, ...leaf.sections.map((section) => section.body)].join(" ");
			expect(text).not.toContain("0.1× the input rate");
			expect(text).not.toContain("0.1x cache-read");
		}
	});

	it("discloses mixed real vs notional basis on tokens-to-dollars", () => {
		const leaf = calculatorLeaf(calculatorBySlug("tokens-to-dollars")!);
		expect(leaf.honesty?.tone).toBe("neutral");
		expect(leaf.honesty?.text.toLowerCase()).toContain("notional");
		// Every non-Claude row (Codex, Gemini, Grok, Muse Spark, OpenCode) is notional list price.
		expect(leaf.honesty?.text).toContain("Every other selection is a notional list-price estimate");
	});
});
