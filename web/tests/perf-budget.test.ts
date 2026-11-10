import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { baseline, evaluate, type PrerenderManifest } from "../scripts/perf-budget";

const manifest: PrerenderManifest = { routes: { "/": {} }, dynamicRoutes: { "/p/[slug]": {} } };
const stats = [
	{ route: "/", firstLoadUncompressedJsBytes: 1000 },
	{ route: "/p/[slug]", firstLoadUncompressedJsBytes: 2000 },
	{ route: "/live", firstLoadUncompressedJsBytes: 3000 },
];
const SCRIPT = join(import.meta.dir, "../scripts/perf-budget.ts");
const run = (cwd: string) => spawnSync(process.execPath, [SCRIPT], { cwd });

describe("perf budget gate", () => {
	test("a baseline passes against the build it came from", () => {
		const budget = baseline(stats, manifest);
		expect(budget.routes["/"]).toEqual({ maxJsBytes: 2048, rendering: "static" });
		expect(budget.routes["/p/[slug]"]?.rendering).toBe("on-demand");
		expect(budget.routes["/live"]?.rendering).toBe("dynamic");
		expect(evaluate(stats, manifest, budget)).toEqual([]);
	});

	test("fails on growth, a rendering change, and unbudgeted or stale routes", () => {
		const budget = baseline(stats, manifest);
		const grown = stats.map((s) =>
			s.route === "/" ? { ...s, firstLoadUncompressedJsBytes: 5000 } : s,
		);
		expect(evaluate(grown, manifest, budget)[0]).toContain("exceeds cap");
		expect(evaluate(stats, { routes: {}, dynamicRoutes: {} }, budget)).toHaveLength(2);
		expect(evaluate(stats, manifest, { routes: {} })).toHaveLength(3);
		expect(evaluate(stats.slice(1), manifest, budget)[0]).toContain("budgeted but absent");
	});

	test("fails closed on zero routes", () => {
		expect(evaluate([], manifest, { routes: {} })).toEqual([
			"route-bundle-stats.json lists zero routes",
		]);
	});

	test("distinguishes timed regeneration from static parameter generation", () => {
		const timed = { routes: { "/": { initialRevalidateSeconds: 60 } }, dynamicRoutes: {} };
		expect(baseline(stats, timed).routes["/"]?.rendering).toBe("isr");
		const generated = {
			routes: { "/p/one": { srcRoute: "/p/[slug]", initialRevalidateSeconds: false as const } },
			dynamicRoutes: { "/p/[slug]": {} },
		};
		expect(baseline(stats, generated).routes["/p/[slug]"]?.rendering).toBe("static");
	});

	test("rejects malformed measurements and caps before comparison or baseline writes", () => {
		const budget = baseline(stats, manifest);
		for (const bytes of [undefined, null, -1, 0, Number.NaN, Number.POSITIVE_INFINITY]) {
			const invalid = [{ route: "/", firstLoadUncompressedJsBytes: bytes }] as typeof stats;
			expect(() => evaluate(invalid, manifest, budget)).toThrow("JS byte count");
			expect(() => baseline(invalid, manifest)).toThrow("JS byte count");
		}
		expect(() => baseline([], manifest)).toThrow("zero routes");
		expect(() => baseline([...stats, ...stats], manifest)).toThrow("duplicate route");
		expect(() =>
			evaluate(stats, manifest, {
				routes: { "/": { maxJsBytes: Number.NaN, rendering: "static" } },
			}),
		).toThrow("JS byte cap");
	});

	test("exits non-zero when build output or the budget file is missing", () => {
		const empty = mkdtempSync(join(tmpdir(), "perf-budget-"));
		expect(run(empty).status).toBe(1);
		mkdirSync(join(empty, ".next", "diagnostics"), { recursive: true });
		writeFileSync(
			join(empty, ".next", "diagnostics", "route-bundle-stats.json"),
			JSON.stringify(stats),
		);
		writeFileSync(join(empty, ".next", "prerender-manifest.json"), JSON.stringify(manifest));
		const noBudget = run(empty);
		expect(noBudget.status).toBe(1);
		expect(noBudget.stderr.toString()).toContain("perf-budget.json");
	});

	test("stays wired into build after compilation", async () => {
		const packageJson = JSON.parse(
			await readFile(new URL("../package.json", import.meta.url), "utf8"),
		) as { scripts: Record<string, string> };
		expect(packageJson.scripts.build).toContain("next build && bun run check:perf-budget");
		expect(packageJson.scripts["check:perf-budget"]).toBe("bun scripts/perf-budget.ts");
	});
});
