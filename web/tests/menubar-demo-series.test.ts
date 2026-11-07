import { describe, expect, it } from "bun:test";
import {
	AGG,
	derive,
	heroWindowSecondaryDisplay,
	linePath,
	ORDER,
	orderModelLinesForDisplay,
	PROVIDERS,
	pct0,
	selectorPresentation,
	signature,
	sparklineFractions,
	TIMEFRAME_OPTIONS,
	windowCost,
	windowSeries,
} from "@/components/site/menubar-demo-series";
import { analyticsShortModel, shortModel } from "@/lib/model-identity";

describe("model version ordering", () => {
	it("keeps measured caps out of self-relative activity labels", () => {
		expect(heroWindowSecondaryDisplay(PROVIDERS.openCodeGo, "$3.86")).toBe("$3.86");
		expect(heroWindowSecondaryDisplay(PROVIDERS.museSpark, "$9.00")).toContain("% activity");
	});
	it("keeps gateway display units separate from aggregation", () => {
		const go = PROVIDERS.openCodeGo;
		expect(go.isAggregable).toBe(false);
		expect(go.usesTokenDisplay).not.toBe(true);
		const activity = selectorPresentation({ ...go, windows: [] }, 14);
		expect(activity.description).toContain("Notional cost activity");
		expect(activity.series).toEqual(sparklineFractions(windowSeries(go.series, 14)));
		for (const p of [PROVIDERS.copilot, PROVIDERS.cursor, PROVIDERS.openCodeZen]) {
			expect(p.usesTokenDisplay).toBe(true);
		}
	});
	it("keeps the newest model first regardless of cost", () => {
		const ordered = orderModelLinesForDisplay([
			{ model: "gpt-5.5", cost: 100, tokens: 1, events: 1 },
			{ model: "gpt-5.3-codex-spark", cost: 50, tokens: 1, events: 1 },
			{ model: "gpt-5.4", cost: 25, tokens: 1, events: 1 },
			{ model: "gpt-5.6-sol", cost: 1, tokens: 1, events: 1 },
		]);

		expect(ordered.map((line) => line.model)).toEqual([
			"gpt-5.6-sol",
			"gpt-5.5",
			"gpt-5.4",
			"gpt-5.3-codex-spark",
		]);
	});

	it("orders Codex capability strongest-first within one version", () => {
		const ordered = orderModelLinesForDisplay([
			{ model: "gpt-5.6-terra", cost: 1, tokens: 1, events: 1 },
			{ model: "gpt-5.6-luna", cost: 1, tokens: 1, events: 1 },
			{ model: "gpt-5.5", cost: 1, tokens: 1, events: 1 },
			{ model: "gpt-5.6-sol", cost: 1, tokens: 1, events: 1 },
		]);

		expect(ordered.map((line) => line.model)).toEqual([
			"gpt-5.6-sol",
			"gpt-5.6-terra",
			"gpt-5.6-luna",
			"gpt-5.5",
		]);
	});

	it("keeps codex spark as its own model row", () => {
		expect(
			orderModelLinesForDisplay([
				{ model: "gpt-5.6-terra", cost: 1, tokens: 1, events: 1 },
				{ model: "gpt-5.3-codex-spark", cost: 1, tokens: 1, events: 1 },
				{ model: "gpt-5.6-luna", cost: 1, tokens: 1, events: 1 },
				{ model: "gpt-5.6-sol", cost: 1, tokens: 1, events: 1 },
				{ model: "gpt-5.5", cost: 1, tokens: 1, events: 1 },
			]).map((line) => line.model),
		).toEqual(["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.3-codex-spark"]);
	});

	it("keeps capability ahead of compact and hyphenated snapshot dates", () => {
		const line = (model: string) => ({ model, cost: 1, tokens: 1, events: 1 });

		expect(
			orderModelLinesForDisplay([
				line("openai/gpt-5.6-luna-20260713"),
				line("openai/gpt-5.6-sol-2026-07-01"),
				line("openai/gpt-5.6-terra-2026-07-12"),
			]).map((item) => item.model),
		).toEqual([
			"openai/gpt-5.6-sol-2026-07-01",
			"openai/gpt-5.6-terra-2026-07-12",
			"openai/gpt-5.6-luna-20260713",
		]);
	});

	it("orders other known capability families strongest-first", () => {
		const line = (model: string) => ({ model, cost: 1, tokens: 1, events: 1 });

		expect(
			orderModelLinesForDisplay([
				line("claude-haiku-4-5"),
				line("claude-opus-4-5"),
				line("claude-sonnet-4-5"),
			]).map((item) => item.model),
		).toEqual(["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"]);
	});

	it("ranks GPT-6 Astra above Sol and Claude Fable above Opus, like the app", () => {
		const line = (model: string) => ({ model, cost: 1, tokens: 1, events: 1 });
		const order = (models: string[]) =>
			orderModelLinesForDisplay(models.map(line)).map((item) => item.model);

		expect(order(["gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol"])).toEqual([
			"gpt-6-astra",
			"gpt-6-sol",
			"gpt-6-luna",
			"gpt-5.6-sol",
		]);
		expect(order(["claude-opus-5", "claude-sonnet-5", "claude-fable-5"])).toEqual([
			"claude-fable-5",
			"claude-opus-5",
			"claude-sonnet-5",
		]);
	});
});

function demoPath(values: number[]) {
	return linePath(sparklineFractions(values), 232, 56);
}

function rowPath(values: number[]) {
	return linePath(sparklineFractions(values), 100, 16, 1.5);
}

function moneySum(values: number[]) {
	return Number(values.reduce((sum, value) => sum + value, 0).toFixed(2));
}

describe("homepage menubar demo series", () => {
	it("links every verified provider-owned usage destination", () => {
		expect(PROVIDERS.claude.usageURL).toBe("https://claude.ai/settings/usage");
		expect(PROVIDERS.codex.usageURL).toBe("https://chatgpt.com/settings/usage?tab=overview");
		expect(PROVIDERS.grok.usageURL).toBe("https://grok.com/?_s=usage");
		expect(PROVIDERS.grok.usageLinkRuns?.map((run) => run.url).filter(Boolean)).toEqual([
			"https://cursor.com/dashboard/spending",
			"https://grok.com/?_s=usage",
		]);
		expect(PROVIDERS.openCodeGo.usageLinkRuns?.map((run) => run.text).join("")).toBe(
			"View official Zen or Go usage.",
		);
		expect(PROVIDERS.museSpark.usageURL).toBe("https://dev.meta.ai/usage/");
		expect(PROVIDERS.copilot.usageURL).toBe("https://github.com/settings/copilot/features");
		expect(PROVIDERS.cursor.usageURL).toBe("https://cursor.com/dashboard/spending");
		expect(PROVIDERS.openCodeZen.usageURL).toBe("https://opencode.ai/console");
		expect(PROVIDERS.openCodeGo.usageURL).toBe("https://opencode.ai/console");
	});

	it("keeps aggregate series mathematically aligned with provider rows", () => {
		expect(AGG.series).toEqual(
			PROVIDERS.claude.series.map((claudeValue, index) =>
				Number(
					(
						claudeValue +
						PROVIDERS.codex.series[index] +
						PROVIDERS.grok.series[index] +
						PROVIDERS.museSpark.series[index]
					).toFixed(2),
				),
			),
		);
		expect(moneySum(PROVIDERS.claude.series)).toBe(PROVIDERS.claude.week);
		expect(moneySum(PROVIDERS.codex.series)).toBe(PROVIDERS.codex.week);
		expect(moneySum(PROVIDERS.grok.series)).toBe(PROVIDERS.grok.week);
		expect(moneySum(PROVIDERS.museSpark.series)).toBe(PROVIDERS.museSpark.week);
		expect(moneySum(AGG.series)).toBe(AGG.week);
	});

	it("keeps Claude jagged while drifting down and All providers drifting up", () => {
		for (const days of TIMEFRAME_OPTIONS) {
			const aggregate = windowSeries(AGG.series, days);
			const claude = windowSeries(PROVIDERS.claude.series, days);

			expect(claude[0]).toBeGreaterThan(claude.at(-1)!);
			expect(aggregate[0]).toBeLessThan(aggregate.at(-1)!);
			expect(claude.some((value, index) => index > 0 && value > claude[index - 1])).toBe(true);
			expect(claude.some((value, index) => index > 0 && value < claude[index - 1])).toBe(true);
		}
	});

	it("keeps All providers and Claude Code charts visually distinct for every timeframe", () => {
		for (const days of TIMEFRAME_OPTIONS) {
			const aggregatePath = demoPath(windowSeries(AGG.series, days));
			const claudePath = demoPath(windowSeries(PROVIDERS.claude.series, days));

			expect(aggregatePath).not.toBe(claudePath);
		}
	});

	it("keeps selector-row sparklines data-backed and provider-specific", () => {
		for (const days of TIMEFRAME_OPTIONS) {
			const aggregatePath = rowPath(windowSeries(AGG.series, days));
			const claudePath = rowPath(windowSeries(PROVIDERS.claude.series, days));
			const codexPath = rowPath(windowSeries(PROVIDERS.codex.series, days));

			expect(aggregatePath).not.toBe(claudePath);
			expect(aggregatePath).not.toBe(codexPath);
			expect(claudePath).not.toBe(codexPath);
		}
	});
});

describe("model math (derive / signature), colocated with the series data", () => {
	it("pct0 rounds to an integer percent", () => {
		expect(pct0(0)).toBe("0%");
		expect(pct0(49.4)).toBe("49%");
		expect(pct0(49.6)).toBe("50%");
	});

	it("shortModel trims a trailing date and known vendor prefixes", () => {
		expect(shortModel("claude-opus-4-1-20260514")).toBe("opus-4-1");
		// The redundant `codex` token is dropped under the Codex family (gpt- already signals it).
		expect(shortModel("openai/gpt-5.2-codex")).toBe("5.2");
		expect(shortModel("openai/gpt-5.3-codex-spark")).toBe("5.3-spark");
		// A vendor prefix never changes the label.
		expect(shortModel("anthropic/claude-sonnet")).toBe("sonnet");
		expect(shortModel("gpt-5-mini")).toBe("5-mini");
		expect(shortModel("grok-4.5")).toBe("4.5");
		expect(shortModel("grok-4.5-build")).toBe("4.5");
		expect(shortModel("grok-4.6")).toBe("4.6");
		expect(shortModel("grok-4.6-build")).toBe("4.6");
	});

	it("analyticsShortModel keeps GPT family context in larger model lists", () => {
		expect(analyticsShortModel("openai/gpt-5.6-codex")).toBe("gpt-5.6");
		expect(analyticsShortModel("openai/gpt-5.6-codex-spark-2026-07-13")).toBe("gpt-5.6-spark");
		expect(analyticsShortModel("gpt-5-mini")).toBe("gpt-5-mini");
		expect(analyticsShortModel("gpt-5-mini-20260713")).toBe("gpt-5-mini");
		expect(analyticsShortModel("claude-opus-4-1")).toBe("opus-4-1");
	});

	it("derive scales the window total linearly with the timeframe", () => {
		const p = PROVIDERS.claude;
		for (const days of TIMEFRAME_OPTIONS) {
			expect(derive(p, days).windowTotal).toBeCloseTo(windowCost(p.week, days), 6);
		}
		// 14 days is exactly double the 7-day base.
		expect(derive(p, 14).windowTotal).toBeCloseTo(derive(p, 7).windowTotal * 2, 6);
	});

	it("derive keeps cache-hit a valid percentage and events at least 1", () => {
		for (const key of ORDER) {
			const d = derive(PROVIDERS[key], 14);
			expect(d.cacheHit).toBeGreaterThanOrEqual(0);
			expect(d.cacheHit).toBeLessThanOrEqual(100);
			expect(d.windowEvents).toBeGreaterThanOrEqual(1);
			expect(d.byModel.length).toBe(PROVIDERS[key].byModel.length);
		}
	});

	it("keeps Codex credits separate from an exhausted subscription and notional costs", () => {
		const p = PROVIDERS.codex;
		expect(p.credits?.balance).toBeGreaterThan(0);
		expect(p.windows?.map((w) => [w.windowMinutes, w.pct])).toEqual([[10080, 100]]);
		expect(derive({ ...p, credits: undefined }, 14)).toEqual(derive(p, 14));
		expect(selectorPresentation({ ...p, credits: undefined }, 14)).toEqual(
			selectorPresentation(p, 14),
		);
	});

	it("calls a notional cost concentration notional, without claiming it is a bill", () => {
		const p = {
			...PROVIDERS.codex,
			windows: undefined,
			week: 100,
			weekEvents: 100,
			byModel: [
				{ model: "gpt-6-astra", cost: 90, tokens: 100, events: 10 },
				{ model: "gpt-6-luna", cost: 10, tokens: 100, events: 90 },
			],
		};
		expect(signature(p)?.text).toContain("90% of the notional cost");
	});

	it("signature reports live-window pace when a rate window is present", () => {
		const withWindow = {
			...PROVIDERS.codex,
			windows: [{ label: "5h", pct: 80, resetsInMin: 60, windowMinutes: 300, official: true }],
		} as (typeof PROVIDERS)["codex"];
		const sig = signature(withWindow);
		expect(sig).not.toBeNull();
		expect(sig?.est).toBe(true);
		expect(sig?.text).toContain("5-hour window");
	});

	it("ships a SuperGrok weekly sample window for Grok (opt-in capture demo state)", () => {
		const win = PROVIDERS.grok.windows?.[0];
		expect(win).toBeDefined();
		expect(win?.official).toBe(true);
		expect(win?.windowMinutes).toBe(10_080);
		expect(win?.label.toLowerCase()).toContain("supergrok");
		const sig = signature(PROVIDERS.grok);
		expect(sig?.text).toContain("weekly window");
	});

	it("never invents a burn pace for a measured window", () => {
		// Go's measured windows carry no reset boundary, so there is no elapsed fraction to compare
		// against — mirrors the native SignatureInsight, which requires a reset to compute pace.
		expect(signature(PROVIDERS.openCodeGo)?.text ?? "").not.toContain("window gone");
		// A provider that leads with a measured window must not have pace computed from it either.
		const mixed = {
			...PROVIDERS.codex,
			windows: [
				{
					label: "Go · 5-hour window",
					pct: 90,
					official: false,
					measured: true,
					resetsInMin: 0,
					windowMinutes: 300,
				},
				...(PROVIDERS.codex.windows ?? []),
			],
		} as (typeof PROVIDERS)["codex"];
		expect(signature(mixed)?.text ?? "").not.toContain("window gone");
	});

	it("signature flags a cost-heavy model, else returns null", () => {
		const heavy = {
			...PROVIDERS.claude,
			windows: undefined,
			week: 100,
			weekEvents: 100,
			byModel: [
				{ model: "claude-opus", cost: 80, tokens: 1, events: 20 },
				{ model: "claude-haiku", cost: 20, tokens: 1, events: 80 },
			],
		} as (typeof PROVIDERS)["claude"];
		const sig = signature(heavy);
		expect(sig?.est).toBe(false);
		expect(sig?.text).toContain("of the bill");

		const flat = {
			...heavy,
			byModel: [{ model: "solo", cost: 10, tokens: 1, events: 1 }],
		} as (typeof PROVIDERS)["claude"];
		expect(signature(flat)).toBeNull();
	});
});

describe("provider selector presentation", () => {
	it("uses activity for every provider without a current official quota", () => {
		for (const id of ORDER) {
			const p = { ...PROVIDERS[id], windows: [] };
			const presentation = selectorPresentation(p, 14);
			expect(presentation.series).toBeDefined();
			expect(presentation.share).toBe(0);
			expect(presentation.description).toContain("quota unavailable");
		}
	});
	it("keeps zero official quotas and rejects expired or unofficial readings", () => {
		const p = PROVIDERS.codex;
		const window = { pct: 0, official: true, resetsInMin: 10, windowMinutes: 300, label: "5-hour" };
		expect(selectorPresentation({ ...p, windows: [window] }, 14).series).toBeUndefined();
		for (const invalid of [
			{ ...window, resetsInMin: 0 },
			{ ...window, official: false },
		]) {
			expect(selectorPresentation({ ...p, windows: [invalid] }, 14).series).toBeDefined();
		}
	});
	it("charts free tokens and priced costs without changing aggregation", () => {
		expect(selectorPresentation(PROVIDERS.bigPickle, 14).series).toEqual(
			sparklineFractions(windowSeries(PROVIDERS.bigPickle.tokenSeries ?? [], 14)),
		);
		// MiMo and Nemotron are fully unpriced (Zen free tiers, no first-party rate), so they chart
		// tokens like Big Pickle; DeepSeek is the priced brand row and charts dollars.
		for (const free of [PROVIDERS.mimo, PROVIDERS.nemotron]) {
			expect(free.usesTokenDisplay).toBe(true);
			expect(free.byModel.every((m) => m.cost === null)).toBe(true);
			expect(selectorPresentation(free, 14).series).toEqual(
				sparklineFractions(windowSeries(free.tokenSeries ?? [], 14)),
			);
		}
		expect(selectorPresentation(PROVIDERS.deepseek, 14).series).toEqual(
			sparklineFractions(windowSeries(PROVIDERS.deepseek.series, 14)),
		);
	});

	it("gives OpenCode Go a measured quota-shaped meter instead of an activity sparkline", () => {
		// Go's windows are measured against its published per-model caps, so they draw the same
		// quota-shaped bar as an official window — but every one is badged `measured`, and none of them
		// claims a reset countdown (OpenCode publishes no window boundary).
		const windows = PROVIDERS.openCodeGo.windows ?? [];
		expect(windows.map((w) => w.windowMinutes)).toEqual([300, 10_080, 43_200]);
		expect(windows.every((w) => w.measured === true)).toBe(true);
		expect(windows.every((w) => w.official === false)).toBe(true);
		expect(windows.every((w) => w.resetsInMin === 0)).toBe(true);

		const presentation = selectorPresentation(PROVIDERS.openCodeGo, 14);
		expect(presentation.series).toBeUndefined();
		expect(presentation.share).toBe(12);
		expect(presentation.description).toContain("Measured 12% of the 5-hour cap used");
		expect(presentation.description).toContain("no provider reset reported");
	});

	it("keeps a pay-as-you-go gateway on its activity sparkline", () => {
		// Zen has no usage window at all — only a prepaid balance — so it must stay unfabricated.
		expect(selectorPresentation(PROVIDERS.openCodeZen, 14).series).toBeDefined();
		expect(selectorPresentation(PROVIDERS.openCodeZen, 14).description).toContain(
			"quota unavailable",
		);
	});
});
