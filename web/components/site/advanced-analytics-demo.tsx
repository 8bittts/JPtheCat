"use client";

import Image from "next/image";
import { type CSSProperties, useEffect, useId, useReducer, useRef, useState } from "react";
import { HOMEPAGE_PROVIDER_KEYS, type HomepageProviderKey } from "@/lib/homepage-providers";
import { analyticsShortModel } from "@/lib/model-identity";
import { AGG, formatTokenCount, PROVIDERS as SERIES, windowSeries } from "./menubar-demo-series";
import { TickerBand } from "./ticker-band";

type ProviderId = HomepageProviderKey;
type Measure = "Events" | "Tokens" | "$";
type Grain = "Calendar" | "Rhythm" | "Model × Day";
type TimeframeDays = 7 | 14 | 30 | 90;
type SortKey = "model" | "events" | "input" | "output" | "c5m" | "c1h" | "read" | "cost";

type AnalyticsState = {
	focused?: ProviderId;
	measure: Measure;
	grain: Grain;
	drill?: string;
	sortKey: SortKey;
	sortAscending: boolean;
};

type AnalyticsAction =
	| { type: "grain"; value: Grain }
	| { type: "drill"; value?: string }
	| { type: "sort"; key: SortKey }
	| { type: "focus"; id?: ProviderId }
	| { type: "measure"; value: Measure };

const INITIAL_ANALYTICS_STATE: AnalyticsState = {
	measure: "Events",
	grain: "Calendar",
	sortKey: "events",
	sortAscending: false,
};

function analyticsReducer(state: AnalyticsState, action: AnalyticsAction): AnalyticsState {
	switch (action.type) {
		case "grain":
			return { ...state, grain: action.value, drill: undefined };
		case "drill":
			return { ...state, drill: action.value };
		case "sort":
			return state.sortKey === action.key
				? { ...state, sortAscending: !state.sortAscending }
				: { ...state, sortKey: action.key, sortAscending: action.key === "model" };
		case "focus":
			return { ...state, focused: action.id, drill: undefined };
		case "measure":
			return {
				...state,
				measure: action.value,
				sortKey:
					action.value === "Events" ? "events" : action.value === "Tokens" ? "input" : "cost",
				sortAscending: false,
			};
	}
}

// Provider tints derive from the ONE canonical source (`menubar-demo-series`, the same module the
// dashboard demo uses) so opening Analytics can never flip a provider's color — e.g. Codex reads the
// charcoal `viz.light`, never a green invented here. Guard: analytics-demo-tints.test.ts.
const ANALYTICS_PROVIDERS = [
	{
		id: "claude",
		name: "Claude Code",
		short: "Claude",
		basis: "real",
		figure: "$83.60",
		tint: SERIES.claude.viz.light,
	},
	{
		id: "codex",
		name: "Codex",
		short: "Codex",
		basis: "notional",
		figure: "$24.80",
		tint: SERIES.codex.viz.light,
	},
	{
		id: "grok",
		name: "Grok",
		short: "Grok",
		basis: "notional",
		figure: "$19.20",
		tint: SERIES.grok.viz.light,
	},
	{
		id: "museSpark",
		name: "Muse Spark",
		short: "Muse Spark",
		basis: "notional",
		figure: "$10.80",
		tint: SERIES.museSpark.viz.light,
	},
	{
		id: "openCodeGo",
		name: "OpenCode Go",
		short: "OpenCode Go",
		basis: "gateway",
		figure: "$1.80",
		tint: SERIES.openCodeGo.viz.light,
	},
	{
		id: "cursor",
		name: "Cursor",
		short: "Cursor",
		basis: "estimate",
		figure: "1.8M",
		tint: SERIES.cursor.viz.light,
	},
] as const;
const PROVIDERS = HOMEPAGE_PROVIDER_KEYS.map((key) => {
	const provider = ANALYTICS_PROVIDERS.find((item) => item.id === key);
	if (!provider) throw new Error(`Missing analytics provider: ${key}`);
	return provider;
});

const TREND: Record<ProviderId, number[]> = {
	// Distinct growth signatures keep the small multiples useful at a glance: steady compounding,
	// launch-and-cooldown, plateau breakout, and bursty adoption. Avoid four copies of the same
	// alternating sawtooth — normalization makes near-identical rhythms especially obvious.
	claude: [4, 5, 5, 7, 8, 8, 10, 11, 13, 13, 16, 18, 21, 25],
	codex: [3, 4, 6, 9, 13, 18, 23, 19, 16, 14, 13, 15, 17, 16],
	grok: [2, 5, 8, 9, 9, 10, 11, 11, 12, 13, 18, 16, 21, 24],
	museSpark: [1, 2, 3, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13],
	openCodeGo: SERIES.openCodeGo.series,
	cursor: [3, 5, 4, 7, 9, 8, 12, 15, 13, 18, 17, 21, 24, 26],
};
const HEAT_LEGEND = [0.14, 0.28, 0.44, 0.62, 0.82] as const;

// 14-day bases are `windowCost(week, 14)` from menubar-demo-series (claude 83.6, codex 24.8,
// grok 19.2, museSpark 10.8, aggregable total 138.4). Guard: analytics-demo-figures.test.ts.
const HERO_COST_BASE: Partial<Record<ProviderId, number>> = {
	claude: 83.6,
	codex: 24.8,
	grok: 19.2,
	museSpark: 10.8,
};
const HERO_COST_TOTAL = AGG.week * 2;
const HERO_BASIS_LABEL: Partial<Record<ProviderId, string>> = {
	claude: "REAL COST",
	codex: "NOTIONAL",
	grok: "NOTIONAL",
	museSpark: "NOTIONAL",
	openCodeGo: "GATEWAY",
};
const PEAK_CALLOUT: Record<Measure, string> = {
	Events: "Busiest: Thu · 184 events",
	Tokens: "Busiest: Tue · 10.0M tokens",
	$: "Busiest: Fri · $17.20",
};

function heroFigure(
	focused: ProviderId | undefined,
	focusedIsEstimate: boolean,
	timeframeFactor: number,
): string {
	if (focused === "openCodeGo") return `$${(1.8 * timeframeFactor).toFixed(2)}`;
	if (focusedIsEstimate) {
		return formatTokenCount(SERIES.cursor.weekTokens * 2 * timeframeFactor);
	}
	const base = focused ? (HERO_COST_BASE[focused] ?? HERO_COST_TOTAL) : HERO_COST_TOTAL;
	return `$${(base * timeframeFactor).toFixed(2)}`;
}

function heroLabelFor(
	focused: ProviderId | undefined,
	focusedIsEstimate: boolean,
	days: TimeframeDays,
): string {
	if (focused === "openCodeGo") return `GATEWAY · NOT IN TOTAL · LAST ${days} DAYS`;
	if (focusedIsEstimate) return `TOKEN ESTIMATE · LAST ${days} DAYS`;
	const basis = (focused && HERO_BASIS_LABEL[focused]) || "MIXED BASIS";
	return `${basis} · LAST ${days} DAYS`;
}

function compareModelRows(
	left: (typeof MODEL_ROWS)[number],
	right: (typeof MODEL_ROWS)[number],
	sortKey: SortKey,
	sortAscending: boolean,
): number {
	const lhs = rowSortValue(left, sortKey);
	const rhs = rowSortValue(right, sortKey);
	const comparison =
		typeof lhs === "string" && typeof rhs === "string"
			? lhs.localeCompare(rhs)
			: Number(lhs) - Number(rhs);
	return sortAscending ? comparison : -comparison;
}

const MODEL_ROWS = HOMEPAGE_PROVIDER_KEYS.flatMap((provider) => {
	const p = SERIES[provider];
	return p.byModel.map((line) => {
		const weight = line.tokens / p.weekTokens;
		const tokens = (amount: number) => (amount > 0 ? formatTokenCount(amount * weight * 2) : "—");
		return {
			provider,
			model: line.model,
			events: line.events * 2,
			input: tokens(p.ctx.fresh),
			output: tokens(p.output),
			c5m: tokens(p.ctx.write5m),
			c1h: tokens(p.ctx.write1h),
			read: tokens(p.ctx.read),
			cost:
				line.cost === null
					? `${formatTokenCount(line.tokens * 2)} tok`
					: `$${(line.cost * 2).toFixed(2)}`,
		};
	});
});

const HEATMAP_MODEL_LABELS = [...MODEL_ROWS.map((row) => analyticsShortModel(row.model)), "other"];

// Demo-only deterministic "filter" so a heatmap drill-down actually subsets the model table below,
// instead of showing a "Filtered:" chip for a filter that never happens. The same cell always yields
// the same non-empty subset (mock stand-in for "the models active in that period").
function drilledModelRows(drill: string): Array<(typeof MODEL_ROWS)[number]> {
	const seed = [...drill].reduce((sum, ch) => sum + ch.charCodeAt(0), 0);
	const subset = MODEL_ROWS.filter((_, index) => (index + seed) % 3 !== 0);
	return subset.length > 0 ? subset : [...MODEL_ROWS];
}

function Sparkline({ id, tint }: { id: ProviderId; tint: string }) {
	const values = TREND[id];
	const lo = Math.min(...values);
	const hi = Math.max(...values);
	const points = values
		.map(
			(value, index) =>
				`${(index / (values.length - 1)) * 100},${38 - ((value - lo) / (hi - lo)) * 32}`,
		)
		.join(" ");
	return (
		<svg viewBox="0 0 100 40" preserveAspectRatio="none" className="h-8 w-full" aria-hidden="true">
			<polyline
				points={points}
				fill="none"
				stroke={tint}
				strokeWidth="2"
				vectorEffect="non-scaling-stroke"
			/>
			<circle cx="100" cy={points.split(" ").at(-1)?.split(",")[1]} r="2.2" fill={tint} />
		</svg>
	);
}

function Segments<T extends string>({
	values,
	selected,
	onSelect,
}: {
	values: readonly T[];
	selected: T;
	onSelect: (value: T) => void;
}) {
	return (
		<div className="grid grid-flow-col overflow-hidden rounded-[7px] border border-line bg-paper">
			{values.map((value) => (
				<button
					key={value}
					type="button"
					onClick={() => onSelect(value)}
					aria-pressed={selected === value}
					className={`min-h-7 border-line px-2 font-semibold text-[10px] first:border-l-0 border-l transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ginger/45 ${selected === value ? "bg-ginger-deep/10 text-ginger-deep" : "text-ink-soft hover:text-ink"}`}
				>
					{value}
				</button>
			))}
		</div>
	);
}

const MEASURE_OFFSET: Record<Measure, number> = { Events: 3, Tokens: 6, $: 9 };
const MEASURE_UNIT: Record<Measure, string> = { Events: "events", Tokens: "tokens", $: "cost" };

function heatmapLayout(grain: Grain): { columns: number; rows: number; labels: string[] } {
	if (grain === "Rhythm") {
		return { columns: 24, rows: 7, labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] };
	}
	if (grain === "Model × Day") return { columns: 14, rows: 5, labels: HEATMAP_MODEL_LABELS };
	return { columns: 10, rows: 7, labels: ["", "Mon", "", "Wed", "", "Fri", ""] };
}

function heatmapDrillLabel(grain: Grain, label: string, row: number, column: number): string {
	if (grain === "Rhythm") return `${label} ${column}:00`;
	if (grain === "Model × Day") return `${label} · day ${column + 1}`;
	return `Day ${column * 7 + row + 1}`;
}

function Heatmap({
	grain,
	measure,
	focused,
	onDrill,
}: {
	grain: Grain;
	measure: Measure;
	focused?: ProviderId;
	onDrill: (label: string) => void;
}) {
	const { columns, rows, labels } = heatmapLayout(grain);
	const tint = focused
		? (PROVIDERS.find((provider) => provider.id === focused)?.tint ?? "var(--color-ginger-deep)")
		: "var(--color-ginger-deep)";
	const measureOffset = MEASURE_OFFSET[measure];
	const measureUnit = MEASURE_UNIT[measure];
	return (
		<div>
			<div
				className="grid gap-[3px]"
				style={{
					gridTemplateColumns: `minmax(${grain === "Model × Day" ? 72 : 24}px,auto) repeat(${columns},minmax(5px,1fr))`,
				}}
			>
				{Array.from({ length: rows }).flatMap((_, row) => [
					<span
						key={`l-${row}`}
						className="flex h-[11px] items-center justify-end pr-1 text-[9px] text-ink-faint"
					>
						{labels[row]}
					</span>,
					...Array.from({ length: columns }).map((__, column) => {
						const intensity = ((row * 7 + column * 11 + measureOffset) % 10) / 10;
						const empty = (row + column * 2) % 9 === 0;
						return (
							<button
								key={`${row}-${column}`}
								type="button"
								onClick={() => onDrill(heatmapDrillLabel(grain, labels[row] ?? "", row, column))}
								aria-label={`${labels[row] || "day"} ${column + 1} ${measureUnit} activity`}
								className="h-[11px] min-w-0 rounded-[2px] border border-line/50 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ink"
								style={{
									background: empty
										? "var(--color-track)"
										: `color-mix(in srgb, ${tint} ${(12 + intensity * 68).toFixed(0)}%, transparent)`,
								}}
							/>
						);
					}),
				])}
			</div>
			{grain === "Rhythm" ? (
				<div className="ml-8 mt-1 flex justify-between text-[9px] text-ink-faint">
					<span>12a</span>
					<span>6a</span>
					<span>12p</span>
					<span>6p</span>
					<span>11p</span>
				</div>
			) : null}
			{grain === "Model × Day" ? (
				<p className="mt-1 text-[9px] text-ink-faint">columns = days (oldest → newest, local)</p>
			) : null}
		</div>
	);
}

/** 18×18 brand chip — white glyph on provider tint (mirrors native `AnalyticsProviderMark`). */
function ProviderMarkChip({
	icon,
	tint,
	bare,
}: {
	icon: string;
	tint?: string;
	/** Bare JP mark (All providers) — no tint fill. */
	bare?: boolean;
}) {
	return (
		<span
			aria-hidden="true"
			className={`grid h-[18px] w-[18px] shrink-0 place-items-center overflow-hidden rounded-[5px] ${
				bare ? "" : "shadow-[inset_0_0_0_1px_rgba(255,255,255,0.22)]"
			}`}
			style={bare ? undefined : { background: tint }}
		>
			<Image
				src={icon}
				alt=""
				width={16}
				height={16}
				className={bare ? "h-4 w-4 object-contain" : "h-4 w-4 object-contain brightness-0 invert"}
				unoptimized
			/>
		</span>
	);
}

function ProviderSidebar({
	checked,
	focused,
	onChecked,
	onFocus,
}: {
	checked: Set<ProviderId>;
	focused?: ProviderId;
	onChecked: (id: ProviderId) => void;
	onFocus: (id?: ProviderId) => void;
}) {
	return (
		<section>
			<h4 className="font-semibold text-[10px] text-ink-soft tracking-[0.12em]">PROVIDERS</h4>
			<div className="mt-2 grid min-h-7 grid-cols-[minmax(0,1fr)_18px] items-center gap-1.5">
				<button
					type="button"
					onClick={() => onFocus()}
					className={`flex min-w-0 items-center gap-1.5 px-1 text-left font-semibold text-[11px] ${focused ? "text-ink" : "text-ginger-deep"}`}
				>
					<ProviderMarkChip icon="/jp-menubar.png" bare />
					<span>All providers</span>
				</button>
				<span className="grid h-[18px] w-[18px] place-items-center text-ginger-deep">
					{focused ? "" : "✓"}
				</span>
			</div>
			<div className="space-y-1.5">
				{PROVIDERS.map((provider) => {
					const series = SERIES[provider.id];
					return (
						<div
							key={provider.id}
							className="grid min-h-9 grid-cols-[minmax(0,1fr)_18px] items-center gap-1.5"
						>
							<button
								type="button"
								onClick={() => onFocus(focused === provider.id ? undefined : provider.id)}
								className={`min-w-0 rounded-[6px] px-1 py-1 text-left ${focused === provider.id ? "bg-[color-mix(in_srgb,var(--provider-tint)_12%,transparent)]" : "hover:bg-track/60"}`}
								style={{ "--provider-tint": provider.tint } as CSSProperties}
							>
								<span className="flex items-center gap-1.5">
									<ProviderMarkChip icon={series.icon} tint={provider.tint} />
									<span className="truncate font-semibold text-[11px] text-ink">
										{provider.name}
									</span>
									{focused === provider.id ? (
										<svg
											aria-hidden="true"
											viewBox="0 0 24 24"
											className="h-[10px] w-[10px] shrink-0 text-ginger-deep"
											fill="none"
											stroke="currentColor"
											strokeWidth={2}
										>
											<circle cx="12" cy="12" r="9" />
											<circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none" />
											<path d="M12 3v3M12 18v3M3 12h3M18 12h3" />
										</svg>
									) : null}
								</span>
								<span className="mt-0.5 flex items-center gap-1 pl-6">
									<span
										className={`demo-badge demo-micro rounded-full ${
											provider.basis === "real"
												? "bg-sage/20 text-sage-deep"
												: provider.basis === "estimate"
													? "text-[color:var(--color-p-copilot)]"
													: "bg-honey/25 text-ginger-deep"
										}`}
										style={
											provider.basis === "estimate"
												? {
														background:
															"color-mix(in srgb, var(--color-p-copilot) 18%, transparent)",
													}
												: undefined
										}
									>
										{provider.basis}
									</span>
									<span className="tnum text-[9px] text-ink-faint">{provider.figure}</span>
								</span>
							</button>
							<input
								type="checkbox"
								checked={checked.has(provider.id)}
								onChange={() => onChecked(provider.id)}
								aria-label={`Include ${provider.name} in view and export`}
								className="m-0 h-3.5 w-3.5 justify-self-center"
								style={{ accentColor: provider.tint }}
							/>
						</div>
					);
				})}
			</div>
		</section>
	);
}

function AnalyticsSidebar({
	checked,
	focused,
	measure,
	onChecked,
	onFocus,
	onMeasure,
}: {
	checked: Set<ProviderId>;
	focused?: ProviderId;
	measure: Measure;
	onChecked: (id: ProviderId) => void;
	onFocus: (id?: ProviderId) => void;
	onMeasure: (measure: Measure) => void;
}) {
	return (
		<aside className="flex flex-col border-line border-l bg-paper-2 px-4 py-4 max-[760px]:border-t max-[760px]:border-l-0">
			<ProviderSidebar
				checked={checked}
				focused={focused}
				onChecked={onChecked}
				onFocus={onFocus}
			/>
			<section className="mt-4">
				<h4 className="font-semibold text-[10px] text-ink-soft tracking-[0.12em]">MEASURE</h4>
				<div className="mt-2">
					<Segments
						values={["Events", "Tokens", "$"] as const}
						selected={measure}
						onSelect={onMeasure}
					/>
				</div>
			</section>
			<section className="mt-4">
				<h4 className="font-semibold text-[10px] text-ink-soft tracking-[0.12em]">BASIS</h4>
				<div className="mt-2 space-y-1 text-[9px] leading-snug text-ink-faint">
					<p>
						<b className="text-ink">Claude</b> = real $
					</p>
					<p>
						<b className="text-ink">Codex</b> = notional list price
					</p>
					<p>
						<b className="text-ink">Grok</b> = notional list price
					</p>
					<p>
						<b className="text-ink">Muse Spark</b> = notional list price
					</p>
					<p>
						<b className="text-ink">Cursor</b> = estimate (tokens)
					</p>
					<p>
						<b className="text-ink">OpenCode Go</b> = gateway (excluded from totals)
					</p>
				</div>
			</section>
			<button
				type="button"
				disabled
				title="CSV, JSON, and Markdown export are available in the JP the Cat app"
				aria-label="Export analytics — CSV, JSON, or Markdown (available in the app)"
				className="mt-6 flex min-h-8 w-full items-center justify-center gap-1.5 rounded-[7px] border border-line bg-paper font-semibold text-[10px] text-ginger-deep disabled:text-ink-faint min-[760px]:mt-auto min-[760px]:pt-6"
			>
				⇧ Export
			</button>
		</aside>
	);
}

function AnalyticsChrome({
	days,
	onDays,
	onClose,
}: {
	days: TimeframeDays;
	onDays: (days: TimeframeDays) => void;
	onClose: () => void;
}) {
	return (
		<div className="flex h-8 items-center gap-2 border-line border-b bg-card px-3.5">
			<span className="font-semibold text-[13px] leading-none">JP the Cat 🐾</span>
			<span className="font-semibold text-[13px] text-ink-soft leading-none">
				— Advanced Analytics
			</span>
			<select
				aria-label="Analytics timeframe"
				value={days}
				onChange={(event) => onDays(Number(event.target.value) as TimeframeDays)}
				className="ml-auto h-6 rounded-[7px] border border-line bg-paper px-2 text-[11px] text-ink"
			>
				<option value={7}>last 7 days</option>
				<option value={14}>last 14 days</option>
				<option value={30}>last 30 days</option>
				<option value={90}>last 90 days</option>
			</select>
			<button
				type="button"
				onClick={onClose}
				aria-label="Close Advanced Analytics"
				className="grid h-6 w-6 shrink-0 place-items-center rounded-[7px] text-ink-soft transition hover:bg-track hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
			>
				<svg viewBox="0 0 16 16" aria-hidden="true" className="h-3.5 w-3.5">
					<path
						d="M4 4l8 8m0-8-8 8"
						fill="none"
						stroke="currentColor"
						strokeWidth="1.6"
						strokeLinecap="round"
					/>
				</svg>
			</button>
		</div>
	);
}

const TABLE_HEADERS: ReadonlyArray<{ label: string; key: SortKey }> = [
	{ label: "MODEL", key: "model" },
	{ label: "EVENTS", key: "events" },
	{ label: "IN", key: "input" },
	{ label: "OUT", key: "output" },
	{ label: "C5M", key: "c5m" },
	{ label: "C1H", key: "c1h" },
	{ label: "READ", key: "read" },
	{ label: "COST", key: "cost" },
];

function sortableNumber(value: string | number) {
	if (typeof value === "number") return value;
	if (value === "—") return 0;
	const number = Number.parseFloat(value.replace(/[^0-9.]/g, ""));
	if (!Number.isFinite(number)) return 0;
	if (value.includes("M")) return number * 1_000_000;
	if (value.includes("K")) return number * 1_000;
	return number;
}

function rowSortValue(row: (typeof MODEL_ROWS)[number], key: SortKey): string | number {
	if (key === "model") return analyticsShortModel(row.model);
	if (key === "events") return row.events;
	if (key === "input") return sortableNumber(row.input);
	if (key === "output") return sortableNumber(row.output);
	if (key === "c5m") return sortableNumber(row.c5m);
	if (key === "c1h") return sortableNumber(row.c1h);
	if (key === "read") return sortableNumber(row.read);
	return row.cost.includes("tok") ? 0 : sortableNumber(row.cost);
}

function scaledCompact(value: string, factor: number) {
	if (value === "—") return value;
	if (value.startsWith("$")) return `$${(sortableNumber(value) * factor).toFixed(2)}`;
	const scaled = sortableNumber(value) * factor;
	const suffix = value.includes("tok") ? " tok" : "";
	if (scaled >= 1_000_000) return `${(scaled / 1_000_000).toFixed(1)}M${suffix}`;
	if (scaled >= 1_000) return `${Math.round(scaled / 1_000)}K${suffix}`;
	return `${Math.round(scaled)}${suffix}`;
}

function AnalyticsModelTable({
	days,
	drill,
	modelRows,
	hiddenModelCount,
	sortKey,
	sortAscending,
	timeframeFactor,
	onClearDrill,
	onSort,
}: {
	days: TimeframeDays;
	drill?: string;
	modelRows: Array<(typeof MODEL_ROWS)[number]>;
	hiddenModelCount: number;
	sortKey: SortKey;
	sortAscending: boolean;
	timeframeFactor: number;
	onClearDrill: () => void;
	onSort: (key: SortKey) => void;
}) {
	return (
		<section>
			<div className="flex items-center">
				<h4 className="text-[11px] text-ink-soft">By model · last {days} days</h4>
				{drill ? (
					<span className="demo-badge demo-micro ml-2 gap-1 rounded-full bg-ginger-deep/10 text-ginger-deep">
						<svg
							aria-hidden="true"
							viewBox="0 0 24 24"
							className="h-[10px] w-[10px]"
							fill="none"
							stroke="currentColor"
							strokeWidth={2}
						>
							<path d="M3 5h18l-7 8v6l-4-2v-4z" />
						</svg>
						Filtered: {drill}
						<button
							type="button"
							onClick={onClearDrill}
							aria-label="Clear filter"
							className="ml-0.5 flex h-[14px] w-[14px] items-center justify-center rounded-full hover:bg-ginger-deep/15"
						>
							×
						</button>
					</span>
				) : null}
			</div>
			<div className="mt-1.5 overflow-hidden rounded-[8px] border border-line/80 bg-paper/60">
				<table className="w-full table-fixed text-[9px]">
					<thead className="text-ink-soft">
						<tr>
							{TABLE_HEADERS.map((heading) => (
								<th
									key={heading.key}
									className={`${heading.key === "model" ? "w-[26%] text-left" : "text-right"} px-1.5 py-1.5 font-semibold`}
								>
									<button
										type="button"
										onClick={() => onSort(heading.key)}
										className={`w-full rounded-[3px] focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ginger/45 ${heading.key === "model" ? "text-left" : "text-right"}`}
									>
										{heading.label}
										{sortKey === heading.key ? (sortAscending ? "⌃" : "⌄") : ""}
									</button>
								</th>
							))}
						</tr>
					</thead>
					<tbody>
						{modelRows.map((row) => (
							<tr key={row.model} className="border-line/50 border-t">
								<td className="truncate px-1.5 py-1 font-medium">
									{analyticsShortModel(row.model)}
								</td>
								{[
									Math.round(row.events * timeframeFactor),
									scaledCompact(row.input, timeframeFactor),
									scaledCompact(row.output, timeframeFactor),
									scaledCompact(row.c5m, timeframeFactor),
									scaledCompact(row.c1h, timeframeFactor),
									scaledCompact(row.read, timeframeFactor),
									scaledCompact(row.cost, timeframeFactor),
								].map((value, index) => (
									<td
										key={`${row.model}-${index}`}
										className="tnum px-1.5 py-1 text-right text-ink-soft"
									>
										{value}
									</td>
								))}
							</tr>
						))}
					</tbody>
				</table>
			</div>
			{hiddenModelCount > 0 ? (
				<p className="mt-1 text-[9px] text-ink-faint">
					+ {hiddenModelCount} more {hiddenModelCount === 1 ? "model" : "models"} — included in
					Export
				</p>
			) : null}
			<p className="mt-1 text-[9px] text-ink-faint">
				{
					"Codex, Grok & Muse Spark $ = notional list price · Cursor shows tokens (estimate, excluded from $ totals)."
				}
			</p>
		</section>
	);
}

function scopeFigures(
	scoped: readonly (typeof PROVIDERS)[number][],
	days: TimeframeDays,
	focused?: ProviderId,
) {
	const rows = scoped.map((p) => SERIES[p.id]);
	const priced = rows.filter((p) => focused || p.isAggregable !== false);
	const dailySeries = priced.map((p) => windowSeries(p.series, days));
	const costSeries = Array.from({ length: days }, (_, i) =>
		dailySeries.reduce((sum, values) => sum + values[i], 0),
	);
	const tokenMix = rows.reduce(
		(mix, row) =>
			mix.map(
				(n, i) =>
					n + [row.ctx.fresh, row.output, row.ctx.write5m, row.ctx.write1h, row.ctx.read][i],
			),
		[0, 0, 0, 0, 0],
	);
	const tokenMixTotal = tokenMix.reduce((sum, value) => sum + value, 0);
	const inputTotal = tokenMixTotal - tokenMix[1];
	return {
		totalCost: priced.reduce((sum, p) => sum + (p.week * days) / 7, 0),
		todayCost: priced.reduce((sum, p) => sum + p.today, 0),
		tokenTotal: rows.reduce((sum, p) => sum + (p.weekTokens * days) / 7, 0),
		costSeries,
		tokenMix,
		mixWidths: tokenMix.map((value) =>
			tokenMixTotal > 0 ? `${(value / tokenMixTotal) * 100}%` : "0%",
		),
		cacheHit: inputTotal > 0 ? `${Math.round((tokenMix[4] / inputTotal) * 100)}%` : "—",
	};
}

function analyticsStatTiles(
	scoped: readonly (typeof PROVIDERS)[number][],
	days: TimeframeDays,
	focusedIsEstimate: boolean,
	totalCost: number,
	tokenTotal: number,
	costSeries: number[],
) {
	const statTiles = [
		[
			focusedIsEstimate ? "AVG TOKENS/DAY" : "AVG $/DAY",
			focusedIsEstimate ? formatTokenCount(tokenTotal / days) : `$${(totalCost / days).toFixed(2)}`,
			focusedIsEstimate ? "local tokens" : "incl notional",
		],
		[
			"PEAK DAY",
			focusedIsEstimate ? "—" : `$${Math.max(0, ...costSeries).toFixed(2)}`,
			focusedIsEstimate ? "local tokens" : "incl notional",
		],
		[
			"EVENTS",
			`${Math.round(scoped.reduce((sum, p) => sum + (SERIES[p.id].weekEvents * days) / 7, 0))}`,
			"across scope",
		],
	];
	return statTiles;
}

export function AdvancedAnalyticsDemo({
	style,
	onClose,
}: {
	style?: CSSProperties;
	onClose: () => void;
}) {
	const titleId = useId();
	const dialogRef = useRef<HTMLDialogElement>(null);
	const [checked, setChecked] = useState<Set<ProviderId>>(
		() => new Set(PROVIDERS.map((provider) => provider.id)),
	);
	const [days, setDays] = useState<TimeframeDays>(14);
	const [{ focused, measure, grain, drill, sortKey, sortAscending }, dispatch] = useReducer(
		analyticsReducer,
		INITIAL_ANALYTICS_STATE,
	);

	useEffect(() => {
		const dialog = dialogRef.current;
		if (!dialog) return;
		dialog.showModal();
		return () => dialog.close();
	}, []);
	const scoped = focused
		? PROVIDERS.filter((provider) => provider.id === focused)
		: PROVIDERS.filter((provider) => checked.has(provider.id));
	const timeframeFactor = days / 14;
	const focusedProvider = PROVIDERS.find((provider) => provider.id === focused);
	const focusedIsEstimate = focusedProvider?.basis === "estimate";
	const { totalCost, todayCost, tokenTotal, costSeries, mixWidths, cacheHit } = scopeFigures(
		scoped,
		days,
		focused,
	);
	const hero = focused
		? heroFigure(focused, focusedIsEstimate, timeframeFactor)
		: `$${totalCost.toFixed(2)}`;
	const heroLabel = heroLabelFor(focused, focusedIsEstimate, days);
	const modelRows = [...(drill ? drilledModelRows(drill) : MODEL_ROWS)]
		.filter((row) => scoped.some((p) => p.id === row.provider))
		.sort((left, right) => compareModelRows(left, right, sortKey, sortAscending));
	const modelRowLimit = Math.max(3, 7 - 2 * (Math.max(1, Math.ceil(scoped.length / 4)) - 1));
	const peakCallout =
		measure === "$"
			? `Peak daily cost · $${Math.max(0, ...costSeries).toFixed(2)}`
			: PEAK_CALLOUT[measure];
	const statTiles = analyticsStatTiles(
		scoped,
		days,
		focusedIsEstimate,
		totalCost,
		tokenTotal,
		costSeries,
	);

	return (
		<dialog
			ref={dialogRef}
			aria-labelledby={titleId}
			onClose={onClose}
			style={style}
			className="fixed inset-0 z-50 m-auto w-[min(96vw,960px)] overflow-hidden rounded-[14px] border border-line bg-card p-0 text-ink shadow-[var(--shadow-pop)] backdrop:bg-ink/45"
		>
			<h3 id={titleId} className="sr-only">
				Advanced Analytics
			</h3>
			<AnalyticsChrome days={days} onDays={setDays} onClose={() => dialogRef.current?.close()} />

			<div className="grid max-h-[calc(100dvh-96px)] grid-cols-[minmax(0,1fr)_252px] overflow-y-auto max-[760px]:grid-cols-1">
				<main className="min-w-0 space-y-4 overflow-hidden px-[22px] py-4 max-[760px]:overflow-visible">
					<section>
						<TickerBand text={heroLabel} />
						<div className="mt-2 flex items-end justify-between">
							<div>
								<div className="tnum font-serif font-semibold text-[34px] leading-none">{hero}</div>
								<p className="mt-1 text-[10px] text-ink-faint">last {days} days</p>
							</div>
							<div className="text-right">
								<p className="font-semibold text-[9px] text-ginger-deep tracking-[0.12em]">
									{focused
										? PROVIDERS.find((provider) => provider.id === focused)?.short.toUpperCase()
										: "ALL PROVIDERS"}
								</p>
								<p className="tnum font-semibold text-[17px]">
									{focusedIsEstimate
										? formatTokenCount(SERIES.cursor.todayTokens)
										: `$${todayCost.toFixed(2)}`}
								</p>
								<p className="text-[9px] text-ink-faint">
									today{focusedIsEstimate ? " · tokens" : ""}
								</p>
							</div>
						</div>
						{!focused && checked.has("cursor") ? (
							<p className="mt-1 text-[9px] text-ink-faint">
								+ {formatTokenCount((SERIES.cursor.weekTokens * days) / 7)} Cursor tokens ·
								estimates, excluded from $
							</p>
						) : null}
					</section>

					<section className="grid grid-cols-3 gap-2">
						{statTiles.map(([label, value, caption]) => (
							<div
								key={label}
								className="rounded-[8px] border border-line/80 bg-paper/60 px-2.5 py-2"
							>
								<p className="font-semibold text-[9px] text-ink-soft tracking-[0.1em]">{label}</p>
								<p className="tnum mt-0.5 font-semibold text-[15px]">{value}</p>
								<p className="text-[9px] text-ink-faint">{caption}</p>
							</div>
						))}
					</section>

					<section>
						<h4 className="text-[11px] text-ink-soft">Daily trend · last {days} days</h4>
						<div
							className="mt-1 grid grid-cols-[repeat(var(--trend-columns),minmax(0,1fr))] gap-3 max-[760px]:grid-cols-[repeat(min(2,var(--trend-columns)),minmax(0,1fr))]"
							style={
								{ "--trend-columns": Math.max(Math.min(scoped.length, 4), 1) } as CSSProperties
							}
						>
							{scoped.map((provider) => (
								<div key={provider.id}>
									<div className="flex items-center gap-1.5">
										<span
											className="h-1.5 w-1.5 rounded-full"
											style={{ background: provider.tint }}
										/>
										<span
											className="min-w-0 truncate text-[9px] text-ink-soft"
											title={provider.name}
										>
											{provider.short}
										</span>
										<span className="tnum ml-auto min-w-0 truncate font-semibold text-[10px]">
											{scaledCompact(provider.figure, timeframeFactor)}
										</span>
									</div>
									<Sparkline id={provider.id} tint={provider.tint} />
								</div>
							))}
						</div>
					</section>

					<section>
						<div className="flex items-center">
							<h4 className="text-[11px] text-ink-soft">Token mix · last {days} days</h4>
							<span className="tnum ml-auto min-w-0 truncate font-semibold text-[10px]">
								{formatTokenCount(tokenTotal)}
							</span>
						</div>
						<div className="mt-1.5 flex h-2.5 overflow-hidden rounded-full border border-line/60 bg-track">
							<span className="bg-ginger/90" style={{ width: mixWidths[0] }} />
							<span className="bg-sage/90" style={{ width: mixWidths[1] }} />
							<span className="bg-honey/90" style={{ width: mixWidths[2] }} />
							<span className="bg-coral/90" style={{ width: mixWidths[3] }} />
							<span className="bg-ink-soft/80" style={{ width: mixWidths[4] }} />
						</div>
						<div className="mt-1 flex gap-3 text-[9px] text-ink-faint">
							<span className="text-ginger">● In</span>
							<span className="text-sage">● Out</span>
							<span className="text-honey">● C5m</span>
							<span className="text-coral">● C1h</span>
							<span className="text-ink-soft">● Read</span>
							<span className="ml-auto">Cache hit rate {cacheHit}</span>
						</div>
					</section>

					<section>
						<div className="flex items-center">
							<h4 className="text-[11px] text-ink-soft">
								Activity · {measure === "$" ? "Spend" : measure}
							</h4>
							<div className="ml-auto flex items-center gap-1 text-[9px] text-ink-faint">
								<span>Less</span>
								{HEAT_LEGEND.map((alpha) => (
									<span
										key={alpha}
										className="h-2.5 w-2.5 rounded-[2px] border border-line/50 bg-ginger-deep"
										style={{ opacity: alpha }}
									/>
								))}
								<span>More</span>
							</div>
						</div>
						<div className="mt-1.5">
							<Segments
								values={["Calendar", "Rhythm", "Model × Day"] as const}
								selected={grain}
								onSelect={(value) => dispatch({ type: "grain", value })}
							/>
						</div>
						<div className="mt-2">
							<Heatmap
								grain={grain}
								measure={measure}
								focused={focused}
								onDrill={(value) => dispatch({ type: "drill", value })}
							/>
						</div>
						<div className="mt-1.5 flex text-[9px] text-ink-faint">
							<span>{peakCallout}</span>
							{measure === "$" ? (
								<span className="ml-auto">incl notional · Cursor and gateways excluded from $</span>
							) : null}
						</div>
					</section>

					<AnalyticsModelTable
						days={days}
						drill={drill}
						modelRows={modelRows.slice(0, modelRowLimit)}
						hiddenModelCount={Math.max(0, modelRows.length - modelRowLimit)}
						sortKey={sortKey}
						sortAscending={sortAscending}
						timeframeFactor={timeframeFactor}
						onClearDrill={() => dispatch({ type: "drill" })}
						onSort={(key) => dispatch({ type: "sort", key })}
					/>
				</main>

				<AnalyticsSidebar
					checked={checked}
					focused={focused}
					measure={measure}
					onChecked={(id) =>
						setChecked((previous) => {
							const next = new Set(previous);
							if (next.has(id)) next.delete(id);
							else next.add(id);
							return next;
						})
					}
					onFocus={(id) => dispatch({ type: "focus", id })}
					onMeasure={(value) => dispatch({ type: "measure", value })}
				/>
			</div>
		</dialog>
	);
}
