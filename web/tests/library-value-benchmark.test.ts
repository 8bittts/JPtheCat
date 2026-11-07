import { describe, expect, it } from "bun:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { LibraryValueBenchmark } from "@/components/library/value-benchmark";
import { MODEL_IDS } from "@/lib/library/pricing-data";
import { modelEffortLevel } from "@/lib/library/pricing-registry";
import {
	benchmarkSessionCost,
	benchmarkValueScore,
	bestValueByEffort,
	distinctBenchmarkModelIds,
	topValueBenchmarkRows,
} from "@/lib/library/value-benchmark";

describe("library value benchmark", () => {
	it("dedupes alias models that share the same rates and effort", () => {
		expect(distinctBenchmarkModelIds().length).toBeLessThan(MODEL_IDS.length);
		expect(distinctBenchmarkModelIds()).not.toContain("muse-spark");
		expect(distinctBenchmarkModelIds()).toContain("muse-spark-1.1");
	});

	it("ranks cheaper low-effort models ahead of pricey high-effort ones on raw session cost", () => {
		const haiku = benchmarkSessionCost("claude-haiku-4-5");
		const opus = benchmarkSessionCost("claude-opus-4-8");
		expect(haiku).toBeLessThan(opus);
	});

	it("weights effort into the value score (same vendor, higher tier costs more)", () => {
		const haiku = benchmarkValueScore("claude-haiku-4-5");
		const sonnet = benchmarkValueScore("claude-sonnet-4-6");
		expect(sonnet).toBeLessThan(haiku);
		expect(benchmarkSessionCost("claude-sonnet-4-6")).toBeGreaterThan(
			benchmarkSessionCost("claude-haiku-4-5"),
		);
	});

	it("returns stable top picks with unique ranks", () => {
		const rows = topValueBenchmarkRows(8);
		expect(rows).toHaveLength(8);
		expect(rows[0]?.rank).toBe(1);
		expect(new Set(rows.map((row) => row.id)).size).toBe(8);
		expect(rows[0]?.valueScore).toBeGreaterThanOrEqual(rows[1]?.valueScore ?? 0);
	});

	it("picks one best model per effort tier", () => {
		const picks = bestValueByEffort();
		expect(picks.low?.effort).toBe("low");
		expect(picks.medium?.effort).toBe("medium");
		expect(picks.high?.effort).toBe("high");
		const competitorIds = (tier: "low" | "medium" | "high", pickId: string) =>
			distinctBenchmarkModelIds().filter((id) => id !== pickId && modelEffortLevel(id) === tier);
		for (const tier of ["low", "medium", "high"] as const) {
			const pick = picks[tier];
			if (!pick) continue;
			for (const id of competitorIds(tier, pick.id)) {
				expect(benchmarkValueScore(id)).toBeLessThanOrEqual(pick.valueScore);
			}
		}
	});

	it("renders the benchmark with honesty markers and pricing links", () => {
		const html = renderToStaticMarkup(createElement(LibraryValueBenchmark));
		expect(html).toContain("Best bang for the buck");
		expect(html).toContain("notional list price");
		expect(html).toContain("Session cost");
		expect(html).toContain("/library/pricing/");
	});
});
