import { afterEach, describe, expect, it, mock } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const sent: Array<{ name: string; data: Record<string, unknown> }> = [];
mock.module("@vercel/analytics", () => ({
	track: (name: string, data: Record<string, unknown>) => sent.push({ name, data }),
}));

const { trackProductEvent } = await import("../lib/analytics/product-analytics");

afterEach(() => {
	sent.length = 0;
});

describe("trackProductEvent", () => {
	it("sends flat, truncated, capped properties and drops empty values", () => {
		const many = Object.fromEntries(Array.from({ length: 10 }, (_, index) => [`k${index}`, index]));
		trackProductEvent("download_cta_clicked", { source: "s".repeat(300), skipped: null, ...many });
		expect(sent).toHaveLength(1);
		const data = sent[0]?.data ?? {};
		expect(Object.keys(data)).toHaveLength(8);
		expect(String(data.source)).toHaveLength(255);
		expect("skipped" in data).toBe(false);
	});
});

describe("custom event entry point", () => {
	it("imports track from @vercel/analytics only in lib/analytics/product-analytics.ts", () => {
		const offenders: string[] = [];
		const walk = (dir: string) => {
			for (const entry of readdirSync(dir)) {
				const path = join(dir, entry);
				if (statSync(path).isDirectory()) walk(path);
				else if (
					/\.tsx?$/.test(entry) &&
					/import\s*\{[^}]*\btrack\b[^}]*\}\s*from\s*"@vercel\/analytics/.test(
						readFileSync(path, "utf8"),
					)
				)
					offenders.push(path);
			}
		};
		for (const root of ["app", "components", "lib"]) walk(root);
		expect(offenders).toEqual(["lib/analytics/product-analytics.ts"]);
	});
});
