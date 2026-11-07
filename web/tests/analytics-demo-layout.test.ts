import { describe, expect, it } from "bun:test";

describe("advanced-analytics-demo provider controls", () => {
	it("uses one fixed checkbox column and provider-specific selection colors", async () => {
		const text = await Bun.file("components/site/advanced-analytics-demo.tsx").text();

		expect(text.match(/grid-cols-\[minmax\(0,1fr\)_18px\]/g)).toHaveLength(2);
		// Both label rows must share the provider row's 4px/6px padding/gap.
		expect(text).toContain(
			"className={`flex min-w-0 items-center gap-1.5 px-1 text-left font-semibold text-[11px]",
		);
		expect(text).not.toContain("items-center gap-2 text-left font-semibold text-[11px]");
		expect(text).toContain('className="m-0 h-3.5 w-3.5 justify-self-center"');
		expect(text).toContain("style={{ accentColor: provider.tint }}");
		expect(text).toContain("var(--provider-tint)_12%");
		// Metadata starts after the same 18px mark + 6px gap as the provider name above it.
		expect(text).toContain('className="mt-0.5 flex items-center gap-1 pl-6"');
		expect(text).not.toContain("pl-[26px]");
		expect(text).not.toContain("accent-[var(--color-ginger-deep)]");
	});

	it("keeps every normalized provider trend visually distinct", async () => {
		const text = await Bun.file("components/site/advanced-analytics-demo.tsx").text();
		const trendBlock = text.match(/const TREND:[\s\S]+?\n};/)?.[0] ?? "";
		const series = [...trendBlock.matchAll(/\t(claude|codex|grok|cursor): \[([^\]]+)]/g)].map(
			([, id, values]) => ({
				id,
				values: values.split(",").map(Number),
			}),
		);

		expect(series).toHaveLength(4);
		const directionSignatures = series.map(({ values }) =>
			values
				.slice(1)
				.map((value, index) => Math.sign(value - values[index]))
				.join(","),
		);
		expect(new Set(directionSignatures).size).toBe(4);
		for (const { id, values } of series) {
			expect(values, `${id} should contain 14 daily points`).toHaveLength(14);
			expect(values.at(-1) ?? 0, `${id} should show net growth`).toBeGreaterThan(values[0]);
		}
	});
});
