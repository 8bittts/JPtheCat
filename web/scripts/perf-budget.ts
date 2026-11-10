// Fleet performance budget gate. 8leeai owns the canonical copy; other repos carry
// an identical file. Run after `next build` (Turbopack writes the stats file).
// `--baseline` rewrites perf-budget.json from the current build with 5% headroom.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

type Rendering = "static" | "isr" | "dynamic" | "on-demand";

export interface RouteStat {
	route: string;
	firstLoadUncompressedJsBytes: number;
}

export interface PrerenderManifest {
	routes: Record<string, { initialRevalidateSeconds?: number | false; srcRoute?: string | null }>;
	dynamicRoutes: Record<string, unknown>;
}

export interface RouteBudget {
	maxJsBytes: number;
	rendering: Rendering;
}

export interface Budget {
	routes: Record<string, RouteBudget>;
}

const HEADROOM = 1.05;
const BUILD_HINT = "run next build with Turbopack first";

export function renderingOf(route: string, manifest: PrerenderManifest): Rendering {
	const entries = Object.entries(manifest.routes).filter(
		([path, entry]) => path === route || entry.srcRoute === route,
	);
	if (entries.some(([, entry]) => typeof entry.initialRevalidateSeconds === "number")) {
		return "isr";
	}
	if (entries.length > 0) return "static";
	if (route in manifest.dynamicRoutes) return "on-demand";
	return "dynamic";
}

function checkRoute(stat: RouteStat, budget: RouteBudget | undefined, rendering: Rendering) {
	if (!budget) {
		return [`${stat.route}: no budget; run with --baseline and commit perf-budget.json`];
	}
	const failures: string[] = [];
	if (stat.firstLoadUncompressedJsBytes > budget.maxJsBytes) {
		failures.push(
			`${stat.route}: ${stat.firstLoadUncompressedJsBytes} JS bytes exceeds cap ${budget.maxJsBytes}`,
		);
	}
	if (rendering !== budget.rendering) {
		failures.push(`${stat.route}: rendering is ${rendering}, budget expects ${budget.rendering}`);
	}
	return failures;
}

function validateStats(stats: RouteStat[]) {
	if (!Array.isArray(stats) || stats.length === 0) {
		throw new Error("route-bundle-stats.json lists zero routes or is not an array");
	}
	const seen = new Set<string>();
	for (const stat of stats) {
		if (!stat || typeof stat.route !== "string" || !stat.route.startsWith("/")) {
			throw new Error("invalid route in route-bundle-stats.json");
		}
		if (seen.has(stat.route)) throw new Error(`duplicate route: ${stat.route}`);
		seen.add(stat.route);
		if (
			!Number.isSafeInteger(stat.firstLoadUncompressedJsBytes) ||
			stat.firstLoadUncompressedJsBytes <= 0
		) {
			throw new Error(`${stat.route}: missing or invalid JS byte count`);
		}
	}
}

function validateBudget(budget: Budget) {
	for (const [route, entry] of Object.entries(budget.routes)) {
		if (!(entry && Number.isSafeInteger(entry.maxJsBytes)) || entry.maxJsBytes <= 0) {
			throw new Error(`${route}: missing or invalid JS byte cap`);
		}
		if (!["static", "isr", "dynamic", "on-demand"].includes(entry.rendering)) {
			throw new Error(`${route}: invalid rendering mode`);
		}
	}
}

export function evaluate(stats: RouteStat[], manifest: PrerenderManifest, budget: Budget) {
	if (stats.length === 0) {
		return ["route-bundle-stats.json lists zero routes"];
	}
	validateStats(stats);
	validateBudget(budget);
	const seen = new Set(stats.map((stat) => stat.route));
	const failures = stats.flatMap((stat) =>
		checkRoute(stat, budget.routes[stat.route], renderingOf(stat.route, manifest)),
	);
	for (const route of Object.keys(budget.routes)) {
		if (!seen.has(route)) {
			failures.push(
				`${route}: budgeted but absent from the build; remove it from perf-budget.json`,
			);
		}
	}
	return failures;
}

export function baseline(stats: RouteStat[], manifest: PrerenderManifest): Budget {
	validateStats(stats);
	const routes: Record<string, RouteBudget> = {};
	for (const stat of [...stats].sort((a, b) => a.route.localeCompare(b.route))) {
		routes[stat.route] = {
			maxJsBytes: Math.ceil((stat.firstLoadUncompressedJsBytes * HEADROOM) / 1024) * 1024,
			rendering: renderingOf(stat.route, manifest),
		};
	}
	return { routes };
}

function readJson<T>(path: string, hint: string): T {
	if (!existsSync(path)) {
		throw new Error(`missing ${path}; ${hint}`);
	}
	return JSON.parse(readFileSync(path, "utf8")) as T;
}

function main() {
	const root = process.cwd();
	const stats = readJson<RouteStat[]>(
		join(root, ".next", "diagnostics", "route-bundle-stats.json"),
		BUILD_HINT,
	);
	const manifest = readJson<PrerenderManifest>(
		join(root, ".next", "prerender-manifest.json"),
		BUILD_HINT,
	);
	const budgetPath = join(root, "perf-budget.json");
	if (process.argv.includes("--baseline")) {
		writeFileSync(budgetPath, `${JSON.stringify(baseline(stats, manifest), null, 2)}\n`);
		console.log(`perf-budget: wrote ${stats.length} routes to perf-budget.json`);
		return;
	}
	const failures = evaluate(
		stats,
		manifest,
		readJson<Budget>(budgetPath, "run with --baseline and commit it"),
	);
	if (failures.length > 0) {
		console.error(`perf-budget: FAILED\n${failures.join("\n")}`);
		process.exit(1);
	}
	console.log(`perf-budget: ${stats.length} routes within budget`);
}

if (import.meta.main) {
	try {
		main();
	} catch (error) {
		console.error(`perf-budget: FAILED\n${(error as Error).message}`);
		process.exit(1);
	}
}
