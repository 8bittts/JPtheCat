import { describe, expect, it } from "bun:test";
import { PROVIDERS } from "../components/site/menubar-demo-series";

// The Advanced Analytics demo used to hardcode its own provider tints, contradicting the canonical
// dashboard demo (`menubar-demo-series`) — most visibly Codex as green `#5f8f78` vs the canonical
// charcoal `#2f2f33`, so opening Analytics flipped a provider's color. It now derives every tint from
// the one source; this guards against a regression back to hardcoded hexes.
describe("advanced-analytics-demo provider tints", () => {
	it("derives tints from the canonical menubar-demo-series module", async () => {
		const text = await Bun.file("components/site/advanced-analytics-demo.tsx").text();
		expect(text).toMatch(/import \{[^}]*PROVIDERS as SERIES[^}]*\} from "\.\/menubar-demo-series"/);
		expect(text).toContain("tint: SERIES.claude.viz.light");
		expect(text).toContain("tint: SERIES.codex.viz.light");
		expect(text).toContain("tint: SERIES.cursor.viz.light");
		expect(text).toContain("PROVIDERS.find((provider) => provider.id === focused)?.tint");
		// The old, contradicting hardcoded hexes must not come back.
		for (const stale of ["#5f8f78", "#c97945", "#7767a8"]) {
			expect(text).not.toContain(stale);
		}
		for (const staleRgb of ['"95 143 120"', '"119 103 168"']) {
			expect(text).not.toContain(staleRgb);
		}
	});

	it("keeps Codex a legible non-green tint on the light card (matches the dashboard)", () => {
		// Sanity-pins the canonical values the demo now inherits, so a future palette edit that broke
		// legibility would fail here too.
		expect(PROVIDERS.codex.viz.light).toBe("#2f2f33");
		expect(PROVIDERS.claude.viz.light).toBe("#d6783f");
		expect(PROVIDERS.copilot.viz.light).toBe("#8957e5");
	});
});
