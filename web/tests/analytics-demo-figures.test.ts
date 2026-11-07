import { describe, expect, it } from "bun:test";
import { AGG, PROVIDERS, windowCost } from "../components/site/menubar-demo-series";

// The Advanced Analytics demo used to hardcode its own self-contained magic numbers
// ($18.42 / $11.96 / $30.38 / 682K hero + MODEL_ROWS) that did NOT derive from the canonical
// dashboard demo (`menubar-demo-series`), so the deep-dive modal contradicted the dashboard it
// opens from. The figures were reconciled to canonical (14-day base = `windowCost(week, 14)`, i.e.
// `week * 2`); this guards against a regression back to the old un-reconciled numbers and pins the
// canonical basis. The demo scales these bases by a `timeframeFactor` (days / 14) at render time, so
// the SOURCE carries the trimmed numeric base (e.g. `83.6`) while the sidebar keeps the `$83.60`
// literal — both forms are checked.
describe("advanced-analytics-demo reconciled figures", () => {
	it("carries the canonical 14-day-base figures, not the old magic numbers", async () => {
		const text = await Bun.file("components/site/advanced-analytics-demo.tsx").text();

		// `windowCost(week, 14) === week * 2`; the numeric base the render multiplies by timeframeFactor.
		const claudeBase = String(windowCost(PROVIDERS.claude.week, 14)); // "83.6"
		const codexBase = String(windowCost(PROVIDERS.codex.week, 14)); // "24.8"
		const aggBase = "AGG.week * 2"; // "108.4"

		expect(text).toContain(claudeBase);
		expect(text).toContain(codexBase);
		expect(text).toContain(aggBase);
		expect(windowCost(AGG.week, 14)).toBe(138.4);

		// The sidebar keeps the fully-formatted per-provider literals.
		expect(text).toContain(`$${windowCost(PROVIDERS.claude.week, 14).toFixed(2)}`); // "$83.60"
		expect(text).toContain(`$${windowCost(PROVIDERS.codex.week, 14).toFixed(2)}`); // "$24.80"

		// The old un-reconciled hero/per-provider magic numbers must not come back.
		for (const stale of ["18.42", "11.96", "30.38", "682K", "$12.64", "$8.74", "$5.78"]) {
			expect(text).not.toContain(stale);
		}
	});

	it("keeps the per-model claude costs summing to the claude provider total (honesty)", () => {
		expect(
			PROVIDERS.claude.byModel.reduce((sum, row) => sum + (row.cost ?? 0) * 2, 0).toFixed(2),
		).toBe(windowCost(PROVIDERS.claude.week, 14).toFixed(2));
	});
});
