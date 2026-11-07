import { HOMEPAGE_PROVIDER_KEYS } from "@/lib/homepage-providers";
import { shortModel } from "@/lib/model-identity";

export type ProviderKey =
	| "claude"
	| "codex"
	| "grok"
	| "museSpark"
	| "nemotron"
	| "mimo"
	| "bigPickle"
	| "deepseek"
	| "copilot"
	| "cursor"
	| "openCodeZen"
	| "openCodeGo";
export type TimeframeDays = (typeof TIMEFRAME_OPTIONS)[number];

export type ModelLine = { model: string; cost: number | null; tokens: number; events: number };
export type RateWindow = {
	pct: number;
	label: string;
	official: boolean;
	resetsInMin: number;
	windowMinutes: number;
	/**
	 * True for a MEASURED window — local cost against the provider's published cap, not a
	 * provider-reported percentage (OpenCode Go today). Mirrors the native `ProviderRow.quotaIsMeasured`:
	 * it still draws a quota-shaped meter in the selector and is badged `measured`, never `official`,
	 * and it never carries a reset countdown.
	 */
	measured?: boolean;
};
export type Provider = {
	name: string;
	color: string; // brand chip tint (raw) — a white glyph sits on it, so it stays dark
	viz: { light: string; dark: string }; // data-viz tint, WCAG-lifted for the dark card
	icon: string; // self-hosted brand mark under /public/provider-icons
	notional?: boolean; // Codex — dollars are list-price, not spend
	// False for a provider that's visible with its own row/sparkline but deliberately excluded from
	// the aggregate total (Copilot's OTel-derived token estimate) — mirrors the native app's
	// `ProviderRow.isAggregable`. Defaults to true (aggregable) when omitted.
	isAggregable?: boolean;
	usesTokenDisplay?: boolean;
	today: number;
	week: number;
	todayTokens: number;
	todayEvents: number;
	weekTokens: number;
	weekEvents: number;
	ctx: { read: number; write5m: number; write1h: number; fresh: number };
	output: number;
	cacheSavings: number | null;
	byModel: ModelLine[];
	series: number[];
	// Selected-window daily TOKEN series — the token twin of `series` (dollars), for a fully-unpriced
	// provider (Copilot/Cursor) whose dollar series is a dead all-zero line. Mirrors the app's
	// `ProviderRow.tokenSeries`. Undefined for dollar-based providers (Claude/Codex).
	tokenSeries?: number[];
	peakDay: string;
	windows?: RateWindow[];
	/** Sample last-reported credits, separate from subscription windows and dollar totals. */
	credits?: { balance: number; reported: string };
	/** Provider-owned usage destination. Omitted when no honest account-usage page exists. */
	usageURL?: string;
	usageLinkLabel?: string;
	/**
	 * A sentence with more than one official page. Grok links Cursor and Grok. OpenCode links Zen and Go.
	 * Plain runs have no url. When set, this replaces the single `usageURL` link.
	 */
	usageLinkRuns?: { text: string; url?: string }[];
	/** Narrower-than-account scope disclosure (Muse Spark = OpenCode on this Mac). */
	sourceScopeNote?: string;
	/**
	 * Trailing-window AIU consumption (Copilot's real billing unit, from `github.copilot.nano_aiu`).
	 * A raw consumption count — NEVER dollars and NEVER a quota %. Undefined for every provider
	 * without a local AIU signal. Mirrors the app's `ProviderRow.aiuWindow`.
	 */
	aiuWindow?: number;
};

// Claude = real-dollar cost; Codex + Grok = subscription notional list-price dollars.
// Codex Pro currently reports a weekly allowance; credits remain a separate balance.
// Grok's SuperGrok weekly window is opt-in (Settings → Enable Grok live limits) — the homepage
// demo injects `GROK_SUPERGROK_WINDOW` when that toggle is on, mirroring `GrokRateLimitCapture`.
// Copilot is a separate kind: visible with its own row/sparkline (once OTel capture is on) but
// never aggregated — see `isAggregable` and the app AGENTS.md note on the same pattern.
export const PROVIDERS: Record<ProviderKey, Provider> = {
	claude: {
		name: "Claude Code",
		usageURL: "https://claude.ai/settings/usage",
		usageLinkLabel: "View official usage in Claude",
		color: "var(--color-p-claude)",
		viz: { light: "#d6783f", dark: "#e2894f" },
		icon: "/provider-icons/claude.svg",
		today: 4.9,
		week: 41.8,
		todayTokens: 2_100_000,
		todayEvents: 96,
		weekTokens: 28_400_000,
		weekEvents: 1240,
		ctx: { read: 24_800_000, write5m: 1_200_000, write1h: 400_000, fresh: 900_000 },
		output: 1_100_000,
		cacheSavings: 111.6,
		byModel: [
			{ model: "claude-opus-5-5", cost: 39.7, tokens: 25_900_000, events: 980 },
			{ model: "claude-haiku-4-5", cost: 2.1, tokens: 2_500_000, events: 260 },
		],
		series: [7.2, 6.5, 6.9, 5.8, 6.3, 4.2, 4.9],
		peakDay: "Sat",
	},
	codex: {
		name: "Codex",
		usageURL: "https://chatgpt.com/settings/usage?tab=overview",
		usageLinkLabel: "View official usage in Codex",
		credits: { balance: 1250.5, reported: "Sample reading" },
		color: "var(--color-p-codex)",
		// Codex charcoal vanishes on the dark card; the data-viz tint lifts to a legible grey.
		viz: { light: "#2f2f33", dark: "#a6aab4" },
		icon: "/provider-icons/codex.svg",
		notional: true,
		today: 2.4,
		week: 12.4,
		todayTokens: 720_000,
		todayEvents: 38,
		weekTokens: 8_200_000,
		weekEvents: 410,
		ctx: { read: 6_100_000, write5m: 0, write1h: 0, fresh: 1_400_000 },
		output: 700_000,
		cacheSavings: 7.6,
		byModel: [
			{ model: "gpt-6-astra", cost: 4.2, tokens: 2_500_000, events: 110 },
			{ model: "gpt-5.6-sol", cost: 4.2, tokens: 2_300_000, events: 105 },
			{ model: "gpt-6-sol", cost: 2.1, tokens: 1_700_000, events: 95 },
			{ model: "gpt-5.5", cost: 1.9, tokens: 1_700_000, events: 100 },
		],
		series: [0.9, 0.8, 1.1, 1.4, 2.1, 2.6, 3.5],
		peakDay: "Mon",
		windows: [
			{
				pct: 100,
				label: "Pro · 7-day window",
				official: true,
				resetsInMin: 5220,
				windowMinutes: 10080,
			},
		],
	},
	grok: {
		name: "Grok",
		usageURL: "https://grok.com/?_s=usage",
		usageLinkLabel: "View official Cursor or Grok plan usage.",
		usageLinkRuns: [
			{ text: "View official " },
			{ text: "Cursor", url: "https://cursor.com/dashboard/spending" },
			{ text: " or " },
			{ text: "Grok", url: "https://grok.com/?_s=usage" },
			{ text: " plan usage." },
		],
		color: "var(--color-p-grok)",
		// xAI black needs a lift on the dark card so the meter/glyph stay visible.
		viz: { light: "#111111", dark: "#a6a6a8" },
		icon: "/provider-icons/grok.svg",
		notional: true,
		today: 1.8,
		week: 9.6,
		todayTokens: 420_000,
		todayEvents: 24,
		weekTokens: 3_100_000,
		weekEvents: 180,
		ctx: { read: 1_800_000, write5m: 0, write1h: 0, fresh: 900_000 },
		output: 400_000,
		cacheSavings: 2.1,
		byModel: [{ model: "grok-4.7-build", cost: 9.6, tokens: 3_100_000, events: 180 }],
		series: [0.8, 1.1, 0.9, 1.4, 1.6, 2.0, 1.8],
		peakDay: "Sat",
		// Sample SuperGrok weekly % — real app only shows this after opt-in capture.
		// Homepage demo always shows the "capture on" state so the gauge is reviewable.
		windows: [
			{
				pct: 23,
				label: "SuperGrok · weekly",
				official: true,
				resetsInMin: 9_360,
				windowMinutes: 10_080,
			},
		],
	},
	museSpark: {
		name: "Muse Spark",
		usageURL: "https://dev.meta.ai/usage/",
		usageLinkLabel: "View official usage in Meta",
		color: "var(--color-p-muse-spark)",
		// Meta blue — legible on light card; lift slightly for dark card.
		viz: { light: "#0866ff", dark: "#5b9bff" },
		icon: "/provider-icons/muse-spark.svg",
		notional: true,
		today: 0.9,
		week: 5.4,
		todayTokens: 180_000,
		todayEvents: 12,
		weekTokens: 1_200_000,
		weekEvents: 90,
		ctx: { read: 600_000, write5m: 0, write1h: 0, fresh: 400_000 },
		output: 200_000,
		cacheSavings: 0.4,
		byModel: [{ model: "muse-spark-1.3", cost: 5.4, tokens: 1_200_000, events: 90 }],
		series: [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 0.9],
		peakDay: "Fri",
		// No official quota % — self-relative activity estimate feeds menu-bar rotation (~today ÷ week).
		windows: [
			{
				pct: 17,
				label: "Activity · estimated",
				official: false,
				resetsInMin: 0,
				windowMinutes: 0,
			},
		],
		sourceScopeNote:
			"Counts OpenCode sessions on this Mac. Meta account totals can be higher when Muse Spark runs outside OpenCode.",
	},
	copilot: {
		name: "Copilot",
		usageURL: "https://github.com/settings/copilot/features",
		usageLinkLabel: "View Copilot settings in GitHub",
		color: "var(--color-p-copilot)",
		// GitHub's copilot purple reads fine on the light card; lift it lighter for the dark card
		// (matches the shared --color-p-copilot token other surfaces use).
		viz: { light: "#8957e5", dark: "#b79cf2" },
		icon: "/provider-icons/copilot.svg",
		notional: true,
		isAggregable: false,
		usesTokenDisplay: true,
		today: 0,
		week: 0,
		todayTokens: 53_600,
		todayEvents: 1,
		weekTokens: 53_600,
		weekEvents: 1,
		ctx: { read: 34_800, write5m: 0, write1h: 0, fresh: 18_400 },
		output: 1_100,
		cacheSavings: null,
		byModel: [{ model: "gpt-5-mini", cost: null, tokens: 53_600, events: 1 }],
		// Dollar series stays all-zero (its dollars are genuinely $0 — gpt-5-mini is unpriced) so it
		// never distorts AGG's dollar aggregation; the chart instead reads `tokenSeries`.
		series: [0, 0, 0, 0, 0, 0, 0],
		tokenSeries: [0, 0, 0, 0, 0, 0, 53_600],
		peakDay: "Sun",
		// AIU consumed this window (consumption count, not $ or %) — mirrors the app's Copilot detail.
		aiuWindow: 1.43,
	},
	cursor: {
		name: "Cursor",
		usageURL: "https://cursor.com/dashboard/spending",
		usageLinkLabel: "View official usage in Cursor",
		color: "var(--color-p-cursor)",
		viz: { light: "#4a4a52", dark: "#a6aab4" },
		icon: "/provider-icons/cursor.svg",
		notional: true,
		isAggregable: false,
		usesTokenDisplay: true,
		today: 0,
		week: 0,
		todayTokens: 146_000,
		todayEvents: 8,
		weekTokens: 912_000,
		weekEvents: 52,
		ctx: { read: 528_000, write5m: 96_000, write1h: 0, fresh: 196_000 },
		output: 92_000,
		cacheSavings: null,
		byModel: [{ model: "auto", cost: null, tokens: 912_000, events: 52 }],
		series: [0, 0, 0, 0, 0, 0, 0],
		tokenSeries: [104_000, 126_000, 98_000, 152_000, 131_000, 155_000, 146_000],
		peakDay: "Sat",
	},
	// Nemotron and MiMo reach OpenCode only as Zen free tiers, and neither vendor publishes a
	// first-party per-token rate JP can cite, so both rows are fully unpriced: tokens, never a
	// notional dollar figure. Mirrors the native `ProviderRow.isFullyUnpriced` branch.
	nemotron: {
		usesTokenDisplay: true,
		sourceScopeNote: "OpenCode on this Mac · free tier · local tokens",
		tokenSeries: [700_000, 900_000, 1_050_000, 450_000, 800_000, 950_000, 850_000],
		name: "Nemotron",
		usageURL: "",
		usageLinkLabel: "",
		color: "var(--color-p-nemotron)",
		viz: { light: "#76b900", dark: "#8ec72e" },
		icon: "/provider-icons/nemotron.svg",
		notional: true,
		today: 0,
		week: 0,
		todayTokens: 840_000,
		todayEvents: 24,
		weekTokens: 5_700_000,
		weekEvents: 168,
		ctx: { read: 4_200_000, write5m: 600_000, write1h: 0, fresh: 900_000 },
		output: 420_000,
		cacheSavings: null,
		byModel: [{ model: "nemotron-3-ultra-free", cost: null, tokens: 5_700_000, events: 168 }],
		series: [0, 0, 0, 0, 0, 0, 0],
		peakDay: "Wed",
	},
	mimo: {
		usesTokenDisplay: true,
		sourceScopeNote: "OpenCode on this Mac · free tier · local tokens",
		tokenSeries: [1_100_000, 1_400_000, 1_250_000, 1_050_000, 1_350_000, 1_250_000, 1_400_000],
		name: "MiMo",
		usageURL: "",
		usageLinkLabel: "",
		color: "var(--color-p-mimo)",
		viz: { light: "#e74856", dark: "#f06878" },
		icon: "/provider-icons/mimo.svg",
		notional: true,
		today: 0,
		week: 0,
		todayTokens: 1_200_000,
		todayEvents: 32,
		weekTokens: 8_800_000,
		weekEvents: 224,
		ctx: { read: 6_400_000, write5m: 1_200_000, write1h: 0, fresh: 1_200_000 },
		output: 560_000,
		cacheSavings: null,
		byModel: [{ model: "mimo-v2.5-free", cost: null, tokens: 8_800_000, events: 224 }],
		series: [0, 0, 0, 0, 0, 0, 0],
		peakDay: "Tue",
	},
	bigPickle: {
		usesTokenDisplay: true,
		sourceScopeNote: "OpenCode on this Mac · free model · local tokens",
		tokenSeries: [150_000, 250_000, 180_000, 300_000, 170_000, 150_000, 200_000],
		name: "Big Pickle",
		usageURL: "",
		usageLinkLabel: "",
		color: "var(--color-p-big-pickle)",
		viz: { light: "#0d9488", dark: "#2dd4bf" },
		icon: "/provider-icons/big-pickle.svg",
		notional: true,
		today: 0,
		week: 0,
		todayTokens: 200_000,
		todayEvents: 4,
		weekTokens: 1_400_000,
		weekEvents: 28,
		ctx: { read: 1_000_000, write5m: 200_000, write1h: 0, fresh: 200_000 },
		output: 100_000,
		cacheSavings: null,
		byModel: [{ model: "big-pickle", cost: 0, tokens: 1_400_000, events: 28 }],
		series: [0, 0, 0, 0, 0, 0, 0],
		peakDay: "Thu",
	},
	openCodeZen: {
		name: "OpenCode Zen",
		// The app links `console/<workspace>/billing` and `console/<workspace>/go`.
		// This demo has no workspace id, so Zen opens the console and Go opens the public Go page.
		usageURL: "https://opencode.ai/console",
		usageLinkLabel: "View official Zen or Go usage.",
		usageLinkRuns: [
			{ text: "View official " },
			{ text: "Zen", url: "https://opencode.ai/console" },
			{ text: " or " },
			{ text: "Go", url: "https://opencode.ai/docs/go" },
			{ text: " usage." },
		],
		color: "var(--color-p-opencode)",
		viz: { light: "#d59a2e", dark: "#e8b45a" },
		icon: "/provider-icons/opencode.svg",
		notional: true,
		isAggregable: false,
		usesTokenDisplay: true,
		sourceScopeNote: "OpenCode Zen gateway on this Mac · excluded from combined totals",
		today: 0,
		week: 0,
		todayTokens: 640_000,
		todayEvents: 42,
		weekTokens: 4_300_000,
		weekEvents: 280,
		ctx: { read: 3_300_000, write5m: 400_000, write1h: 0, fresh: 600_000 },
		output: 300_000,
		cacheSavings: null,
		byModel: [{ model: "mimo-v2.5-free", cost: null, tokens: 4_300_000, events: 280 }],
		series: [0, 0, 0, 0, 0, 0, 0],
		tokenSeries: [500_000, 620_000, 580_000, 700_000, 640_000, 660_000, 640_000],
		peakDay: "Wed",
	},
	openCodeGo: {
		name: "OpenCode Go",
		// Same Zen / Go sentence as openCodeZen. The app appends the detected workspace id.
		usageURL: "https://opencode.ai/console",
		usageLinkLabel: "View official Zen or Go usage.",
		usageLinkRuns: [
			{ text: "View official " },
			{ text: "Zen", url: "https://opencode.ai/console" },
			{ text: " or " },
			{ text: "Go", url: "https://opencode.ai/docs/go" },
			{ text: " usage." },
		],
		color: "var(--color-p-opencodego)",
		viz: { light: "#3e7c8c", dark: "#66a8b8" },
		icon: "/provider-icons/opencodego.svg",
		notional: true,
		isAggregable: false,
		sourceScopeNote: "OpenCode Go gateway on this Mac · excluded from combined totals",
		today: 0.38,
		week: 0.9,
		todayTokens: 120_000,
		todayEvents: 14,
		weekTokens: 520_000,
		weekEvents: 60,
		ctx: { read: 380_000, write5m: 0, write1h: 0, fresh: 90_000 },
		output: 50_000,
		cacheSavings: null,
		byModel: [{ model: "deepseek-v4.1-flash", cost: 0.9, tokens: 520_000, events: 60 }],
		series: [0.1, 0.14, 0.12, 0.16, 0.13, 0.15, 0.1],
		peakDay: "Tue",
		// Go's three windows are MEASURED — local cost against the provider's published per-model monthly
		// cap (5-hour = 20% of it, weekly = 50%, monthly = 100%), never a provider-reported percentage.
		// Mirrors `OpenCodeGoLimits.measuredWindows`; OpenCode publishes the caps but no window boundary,
		// so `resetsInMin` stays 0 and no countdown is invented.
		windows: [
			{
				pct: 12,
				label: "Go · 5-hour window",
				official: false,
				measured: true,
				resetsInMin: 0,
				windowMinutes: 300,
			},
			{
				pct: 5,
				label: "Go · weekly window",
				official: false,
				measured: true,
				resetsInMin: 0,
				windowMinutes: 10080,
			},
			{
				pct: 2,
				label: "Go · monthly window",
				official: false,
				measured: true,
				resetsInMin: 0,
				windowMinutes: 43200,
			},
		],
	},
	deepseek: {
		name: "DeepSeek",
		usageURL: "",
		usageLinkLabel: "",
		color: "var(--color-p-deepseek)",
		viz: { light: "#1a56db", dark: "#3b82f6" },
		icon: "/provider-icons/deepseek.svg",
		notional: true,
		today: 0.21,
		week: 1.47,
		todayTokens: 1_500_000,
		todayEvents: 28,
		weekTokens: 10_500_000,
		weekEvents: 196,
		ctx: { read: 7_500_000, write5m: 1_500_000, write1h: 0, fresh: 1_500_000 },
		output: 700_000,
		cacheSavings: null,
		byModel: [{ model: "deepseek-v4-flash", cost: 1.47, tokens: 10_500_000, events: 196 }],
		series: [0.18, 0.25, 0.22, 0.19, 0.24, 0.18, 0.21],
		peakDay: "Tue",
	},
};

export const ORDER: readonly ProviderKey[] = HOMEPAGE_PROVIDER_KEYS;
// AGG deliberately reduces over only the AGGREGABLE providers — token estimates render their own rows
// via `ORDER` but must never leak into the combined total (mirrors the app's `isAggregable` filter).
const AGGREGABLE_ORDER = ORDER.filter((k) => PROVIDERS[k].isAggregable !== false);
export const TIMEFRAME_OPTIONS = [7, 14, 30, 90] as const;
export const DEFAULT_DAYS: TimeframeDays = 30;
const SPARKLINE_HEADROOM_FRACTION = 0.15;

type CapabilityTier = { family: string; rank: number } | null;

/** OpenAI's celestial tiers, strongest first: GPT-6 adds Astra above Sol; GPT-5.6 has Terra. */
function codexCelestialTier(model: string, tokens: string[]): CapabilityTier {
	if (model === "gpt-5.6") return { family: "codex-celestial", rank: 3 };
	if (!model.startsWith("gpt-")) return null;
	if (tokens.includes("astra")) return { family: "codex-celestial", rank: 4 };
	if (tokens.includes("sol")) return { family: "codex-celestial", rank: 3 };
	if (tokens.includes("terra")) return { family: "codex-celestial", rank: 2 };
	if (tokens.includes("luna")) return { family: "codex-celestial", rank: 1 };
	return null;
}

function claudeClassicTier(tokens: string[]): CapabilityTier {
	if (tokens.includes("fable") || tokens.includes("mythos")) {
		return { family: "claude-classic", rank: 4 };
	}
	if (tokens.includes("opus")) return { family: "claude-classic", rank: 3 };
	if (tokens.includes("sonnet")) return { family: "claude-classic", rank: 2 };
	if (tokens.includes("haiku")) return { family: "claude-classic", rank: 1 };
	return null;
}

function geminiSpeedTier(model: string, tokens: string[]): CapabilityTier {
	if (!model.includes("gemini")) return null;
	if (tokens.includes("pro")) return { family: "gemini-speed", rank: 3 };
	if (model.includes("flash-lite")) return { family: "gemini-speed", rank: 1 };
	if (tokens.includes("flash")) return { family: "gemini-speed", rank: 2 };
	return null;
}

function modelCapabilityTier(model: string): CapabilityTier {
	const tokens = model.split(/[^a-z]+/).filter(Boolean);
	return (
		codexCelestialTier(model, tokens) ?? claudeClassicTier(tokens) ?? geminiSpeedTier(model, tokens)
	);
}

function modelDisplayOrderKey(model: string) {
	let normalized = model.toLowerCase().split("/").at(-1) ?? model.toLowerCase();
	const dateMatch = normalized.match(/-(\d{8}|\d{4}-\d{2}-\d{2})$/);
	const snapshotDate = dateMatch ? Number(dateMatch[1].replaceAll("-", "")) : 0;
	if (dateMatch) normalized = normalized.slice(0, -dateMatch[0].length);
	return {
		version: normalized.match(/\d+/g)?.map(Number) ?? [],
		capability: modelCapabilityTier(normalized),
		snapshotDate,
	};
}

export function orderModelLinesForDisplay(lines: ModelLine[]) {
	return [...lines].sort((left, right) => {
		const leftKey = modelDisplayOrderKey(left.model);
		const rightKey = modelDisplayOrderKey(right.model);
		const leftVersion = leftKey.version;
		const rightVersion = rightKey.version;
		for (let index = 0; index < Math.max(leftVersion.length, rightVersion.length); index++) {
			const difference = (rightVersion[index] ?? 0) - (leftVersion[index] ?? 0);
			if (difference !== 0) return difference;
		}
		if (
			leftKey.capability &&
			rightKey.capability &&
			leftKey.capability.family === rightKey.capability.family &&
			leftKey.capability.rank !== rightKey.capability.rank
		) {
			return rightKey.capability.rank - leftKey.capability.rank;
		}
		if (leftKey.snapshotDate !== rightKey.snapshotDate) {
			return rightKey.snapshotDate - leftKey.snapshotDate;
		}
		return right.model.localeCompare(left.model, undefined, { numeric: true });
	});
}

export const AGG = {
	today: Number(AGGREGABLE_ORDER.reduce((s, k) => s + PROVIDERS[k].today, 0).toFixed(2)),
	week: Number(AGGREGABLE_ORDER.reduce((s, k) => s + PROVIDERS[k].week, 0).toFixed(2)),
	series: PROVIDERS.claude.series.map((_, i) =>
		Number(AGGREGABLE_ORDER.reduce((s, k) => s + PROVIDERS[k].series[i], 0).toFixed(2)),
	),
	includesNotional: AGGREGABLE_ORDER.some((k) => PROVIDERS[k].notional),
	shares: AGGREGABLE_ORDER.map((k) => ({
		key: k,
		name: PROVIDERS[k].name,
		week: PROVIDERS[k].week,
	})),
};

/// Compact "53.6K" formatting — the web twin of the app's `formatTokenCount(_:)`, for a
/// non-aggregable provider (Copilot) whose dollar figure would be a dead `$0.00`. No unit suffix,
/// mirroring how a dollar figure never appends "usd".
export function formatTokenCount(value: number): string {
	const abs = Math.abs(value);
	if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
	if (abs >= 1_000) return `${(value / 1_000).toFixed(1)}K`;
	return `${value}`;
}

// Internal to this module now that `derive()` lives here. `windowCost` stays exported — the
// analytics demo + tests read it directly.
function windowScale(days: TimeframeDays) {
	return days / 7;
}

export function windowCost(baseSevenDayCost: number, days: TimeframeDays) {
	return baseSevenDayCost * windowScale(days);
}

function windowCount(baseSevenDayCount: number, days: TimeframeDays) {
	return Math.round(baseSevenDayCount * windowScale(days));
}

export function windowSeries(baseSevenDaySeries: number[], days: TimeframeDays) {
	const mean = baseSevenDaySeries.reduce((s, v) => s + v, 0) / baseSevenDaySeries.length;
	return Array.from({ length: days }, (_, i) => {
		// Dampen the weekly base toward its mean so repeated weeks read as gentle waves,
		// not a hard sawtooth.
		const base = baseSevenDaySeries[i % baseSevenDaySeries.length];
		const softened = mean + (base - mean) * 0.45;
		const jitter = 0.98 + ((i * 17) % 5) / 100;
		const slope = baseSevenDaySeries.at(-1)! - baseSevenDaySeries[0];
		const direction = Math.sign(slope);
		const trend =
			direction < 0
				? 1.18 - (i / Math.max(days - 1, 1)) * 0.28
				: 0.72 + (i / Math.max(days - 1, 1)) * 0.56;
		return Number((softened * jitter * trend).toFixed(2));
	});
}

export function sparklineFractions(values: number[]) {
	if (values.length === 0) return [];
	const hi = Math.max(...values);
	const lo = Math.min(...values);
	const denom = Math.max(hi - lo, hi * SPARKLINE_HEADROOM_FRACTION, 0.000001);
	return values.map((v) => (v - lo) / denom);
}

export function linePath(values: number[], w: number, h: number, pad = 3) {
	const step = (w - pad * 2) / (values.length - 1);
	return values
		.map(
			(v, i) =>
				`${i === 0 ? "M" : "L"}${(pad + i * step).toFixed(1)},${(pad + (1 - v) * (h - pad * 2)).toFixed(1)}`,
		)
		.join(" ");
}

// ── Pure model math, colocated with the data it derives from ───────────────────────────────────────
// `derive`/`signature` turn a `Provider` + timeframe into the window-scaled readouts the demo card
// renders. Kept here (next to `PROVIDERS`) so they're unit-testable without importing the client
// component. Guard: `menubar-demo-series.test.ts`.

/** "42%" — integer-rounded percent, for cache-hit / share readouts. */
export const pct0 = (v: number) => `${Math.round(v)}%`;

export function derive(p: Provider, days: TimeframeDays) {
	const scale = windowScale(days);
	const ctx = {
		read: windowCount(p.ctx.read, days),
		write5m: windowCount(p.ctx.write5m, days),
		write1h: windowCount(p.ctx.write1h, days),
		fresh: windowCount(p.ctx.fresh, days),
	};
	const ctxTotal = ctx.read + ctx.write5m + ctx.write1h + ctx.fresh;
	const windowTotal = windowCost(p.week, days);
	const windowTokens = windowCount(p.weekTokens, days);
	const windowEvents = Math.max(1, windowCount(p.weekEvents, days));
	const output = windowCount(p.output, days);
	const series = windowSeries(p.series, days);
	const tokenSeries = windowSeries(p.tokenSeries ?? p.series, days);
	return {
		ctx,
		ctxTotal,
		windowTotal,
		windowTokens,
		windowEvents,
		byModel: orderModelLinesForDisplay(
			p.byModel.map((m) => ({
				...m,
				cost: m.cost == null ? null : m.cost * scale,
				tokens: windowCount(m.tokens, days),
				events: windowCount(m.events, days),
			})),
		),
		cacheSavings: p.cacheSavings == null ? null : p.cacheSavings * scale,
		cacheHit: ctxTotal > 0 ? (100 * ctx.read) / ctxTotal : 0,
		costPerTurn: windowEvents > 0 ? windowTotal / windowEvents : 0,
		blended: windowTokens > 0 ? windowTotal / (windowTokens / 1_000_000) : 0,
		tokensPerTurn: windowEvents > 0 ? Math.round(windowTokens / windowEvents) : 0,
		outputShare: ctx.fresh + output > 0 ? (100 * output) / (ctx.fresh + output) : 0,
		runRate30: (windowTotal / days) * 30,
		avg: windowTotal / days,
		peak: series.reduce((m, v) => Math.max(m, v), 0),
		tokenAvg: windowTokens / days,
		tokenPeak: tokenSeries.reduce((m, v) => Math.max(m, v), 0),
	};
}

function paceVerdict(pace: number): string {
	if (pace > 1.15) return "running hot";
	if (pace < 0.85) return "well under pace";
	return "on pace";
}

// Window noun follows the actual sample (5-hour / weekly SuperGrok), never hardcode 5h.
function windowNoun(windowMinutes: number): string {
	if (windowMinutes >= 10_000) return "weekly window";
	if (windowMinutes >= 250) return "5-hour window";
	return "window";
}

/** The cap noun for a MEASURED gateway window (OpenCode Go's 5-hour / weekly / monthly caps). */
function capNoun(windowMinutes: number): string {
	if (windowMinutes >= 43_200) return "monthly";
	if (windowMinutes >= 10_000) return "weekly";
	if (windowMinutes >= 250) return "5-hour";
	return "usage";
}

function windowSignature(p: Provider): { text: string; est: boolean } | null {
	const w = p.windows?.[0];
	if (!w) return null;
	// A burn-pace verdict needs a real window boundary. A MEASURED gateway window publishes a cap but no
	// reset, so there is no elapsed fraction to compare against — mirrors the native
	// `SignatureInsight.compute`, which requires `resetsAt5h` and therefore stays silent for Go.
	if (w.measured || !w.official || w.resetsInMin <= 0 || w.windowMinutes <= 0) return null;
	const elapsed = (w.windowMinutes - w.resetsInMin) / w.windowMinutes;
	if (elapsed <= 0.05) return null;
	const verdict = paceVerdict(w.pct / 100 / elapsed);
	return {
		text: `${pct0(w.pct)} used, ${pct0(elapsed * 100)} of the ${windowNoun(w.windowMinutes)} gone — ${verdict}.`,
		est: true,
	};
}

function costliestModel(priced: Provider["byModel"], p: Provider) {
	let top = priced[0];
	let best = -1;
	for (const m of priced) {
		const score = (m.cost as number) / p.week - m.events / p.weekEvents;
		if (score > best) {
			best = score;
			top = m;
		}
	}
	return top;
}

function costShareSignature(p: Provider): { text: string; est: boolean } | null {
	const priced = p.byModel.filter((m) => m.cost != null);
	if (p.week <= 0 || p.weekEvents <= 0 || priced.length <= 1) return null;
	const top = costliestModel(priced, p);
	const costShare = (top.cost as number) / p.week;
	const evtShare = top.events / p.weekEvents;
	if (costShare - evtShare <= 0.1) return null;
	return {
		text: `${shortModel(top.model)} ran ${pct0(evtShare * 100)} of your turns but ${pct0(costShare * 100)} of the ${p.notional ? "notional cost" : "bill"}.`,
		est: false,
	};
}

export function signature(p: Provider): { text: string; est: boolean } | null {
	return windowSignature(p) ?? costShareSignature(p);
}

/** A quota pill requires a current official window; every other row charts its own activity. */
export function selectorPresentation(p: Provider, days: TimeframeDays) {
	// Two honest kinds of quota-shaped meter: an OFFICIAL window the provider reported with a reset
	// still ahead, or a MEASURED gateway window — local cost against the provider's published cap, which
	// has no boundary to age out. Mirrors the native `ProviderRow.selectorQuota`. A self-relative
	// activity share is still never quota-shaped.
	const officialQuota = p.windows?.find(
		(w) => w.official && w.resetsInMin > 0 && Number.isFinite(w.pct),
	);
	const measuredQuota = p.windows?.find((w) => w.measured && Number.isFinite(w.pct));
	const quota = officialQuota ?? measuredQuota;
	const tokenBased = p.usesTokenDisplay === true;
	return {
		share: quota ? Math.min(100, Math.max(0, quota.pct)) : 0,
		series: quota
			? undefined
			: sparklineFractions(windowSeries(tokenBased ? (p.tokenSeries ?? []) : p.series, days)),
		description: quota
			? officialQuota
				? `${Math.round(quota.pct)}% of ${quota.label} window used`
				: `Measured ${Math.round(quota.pct)}% of the ${capNoun(quota.windowMinutes)} cap used — local usage, no provider reset reported`
			: `${tokenBased ? "Local token" : p.notional ? "Notional cost" : "Spend"} activity, last ${days} days — quota unavailable`,
	};
}

/** Mirrors native `heroWindowSecondaryText` — official windows show the window total; otherwise
 * self-relative activity (~NN%) when the provider carries an estimate (Muse Spark). */
export function heroWindowSecondaryDisplay(
	active: Provider | null,
	windowTotalDisplay: string,
): string {
	if (!active) return windowTotalDisplay;
	const quotaWindow = active.windows?.find((w) => w.official || w.measured);
	if (quotaWindow) return windowTotalDisplay;
	const estimatePct = active.windows?.find((w) => !w.official)?.pct;
	if (estimatePct != null) return `~${Math.round(estimatePct)}% activity`;
	return windowTotalDisplay;
}
