"use client";

import Image from "next/image";
import { useEffect, useId, useRef, useState } from "react";
import { modelEffortLevel, modelEffortLevelLabel } from "@/lib/library/pricing-registry";
import { shortModel } from "@/lib/model-identity";
import { BrandMark } from "./brand";
import { AdvancedAnalyticsPopup, SupportReportPopup, WidgetPopup } from "./demo-dialogs";
import { DEFAULT_THEME_ID, getDemoTheme, themeVars } from "./demo-themes";
import { EFFORT_CHIP_TONE } from "./effort-tone";
import { Icon } from "./icon";
import { playSelectorClick } from "./menubar-demo-audio";
import {
	CardFooter,
	ChromeBar,
	ChromeButton,
	RotationLight,
	UpdateDotButton,
} from "./menubar-demo-chrome";
import { isRotatingFormat, MENU_BAR_FORMATS } from "./menubar-demo-format";
import {
	AGG,
	DEFAULT_DAYS,
	derive,
	formatTokenCount,
	heroWindowSecondaryDisplay,
	linePath,
	ORDER,
	PROVIDERS,
	type Provider,
	type ProviderKey,
	pct0,
	type RateWindow,
	selectorPresentation,
	signature,
	sparklineFractions,
	TIMEFRAME_OPTIONS,
	type TimeframeDays,
	windowCost,
	windowSeries,
} from "./menubar-demo-series";
import { SettingsFace } from "./menubar-demo-settings";
import { TickerBand } from "./ticker-band";

type View = "all" | ProviderKey;
type Face = "dashboard" | "settings";

const money = (v: number) => `$${v.toFixed(2)}`;
const compact = (n: number) => {
	const a = Math.abs(n);
	if (a >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
	if (a >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
	return `${n}`;
};
const fmtReset = (min: number) => {
	if (min < 60) return `${Math.max(1, Math.round(min))}m`;
	const h = Math.floor(min / 60);
	const m = Math.round(min % 60);
	if (h < 24) return m > 0 ? `${h}h ${m}m` : `${h}h`;
	const d = Math.floor(h / 24);
	const rh = h % 24;
	return rh > 0 ? `${d}d ${rh}h` : `${d}d`;
};

// Stable, module-level token formatter for the count-up hero. `SplitFlapMoney`'s effect keys on the
// `format` ref, so it must NOT be inlined at the call site (an inline arrow is a fresh ref every
// render and would restart the animation on unrelated re-renders). Rounds the interpolated value so
// mid-count-up frames never flash raw decimals (formatTokenCount leaves sub-1000 values un-rounded);
// the money path passes the already-stable `money` ref directly.
const flapTokens = (n: number) => formatTokenCount(Math.round(n));

/**
 * The web twin of the app's `SplitFlapMoney` (DashboardView.swift): the hero total renders as a row
 * of paper flap tiles and counts up/down to `value` whenever it changes — on mount it grows from
 * zero so the ledger reads as a live, accumulating total rather than a dead number, and on a
 * provider-view switch it rolls to the new figure. Reduced-motion snaps straight to the final value.
 */
function SplitFlapMoney({
	value,
	format,
	className,
}: {
	value: number;
	format: (n: number) => string;
	className?: string;
}) {
	const [display, setDisplay] = useState(() => format(value));
	const fromRef = useRef(0);

	useEffect(() => {
		const target = value;
		const from = fromRef.current;
		fromRef.current = target;
		if (
			typeof window !== "undefined" &&
			window.matchMedia("(prefers-reduced-motion: reduce)").matches
		) {
			setDisplay(format(target));
			return;
		}
		let raf = 0;
		let start: number | null = null;
		const duration = 1500;
		const tick = (t: number) => {
			if (start === null) start = t;
			const progress = Math.min(1, (t - start) / duration);
			const eased = 1 - (1 - progress) ** 3; // easeOutCubic — quick then settles
			setDisplay(format(from + (target - from) * eased));
			if (progress < 1) raf = requestAnimationFrame(tick);
			else setDisplay(format(target));
		};
		raf = requestAnimationFrame(tick);
		return () => cancelAnimationFrame(raf);
	}, [value, format]);

	return (
		<div className={className} role="img" aria-label={format(value)}>
			<span className="flap-money" aria-hidden="true">
				{Array.from(display).map((ch, i) => (
					<span
						key={`${i}-${ch}`}
						className={`flap-tile${ch === "." || ch === "," ? " flap-tile--narrow" : ""}`}
					>
						{ch}
					</span>
				))}
			</span>
		</div>
	);
}

// Mirrors the native app's per-model effort chip (ProviderDetail.effortChip) and the
// `/library` pricing table chip classes, sourced from the ONE effort registry.

function basisLabel(view: View, notional: boolean, isTokenBased: boolean) {
	if (view === "all")
		return AGG.includesNotional ? "REAL + NOTIONAL LIST-PRICE · TODAY" : "REAL SPEND · TODAY";
	if (isTokenBased) return "LOCAL TOKENS · TODAY";
	return notional ? "NOTIONAL LIST-PRICE · TODAY" : "REAL SPEND · TODAY";
}

// ── Root ─────────────────────────────────────────────────────────────────────────────────────────

export function MenubarDemo() {
	const [view, setView] = useState<View>("all");
	const [days, setDays] = useState<TimeframeDays>(DEFAULT_DAYS);
	const [face, setFace] = useState<Face>("dashboard");
	// The active theme drives both the card's light/dark viz picks (`dark`) AND the full palette applied
	// as inline CSS vars (`themeStyle`) — mirroring the app's named-theme system where every surface
	// re-themes from `ThemeManager`. The two inline themes plus 22 more live in `THEME_CATALOG`.
	const [themeId, setThemeId] = useState(DEFAULT_THEME_ID);
	const theme = getDemoTheme(themeId);
	const dark = theme.isDark;
	const themeStyle = themeVars(theme);
	// Mirrors the app: the dashboard starts pinned above every screen.
	const [pinned, setPinned] = useState(true);
	const [widgetOpen, setWidgetOpen] = useState(false);
	const [advancedAnalyticsOpen, setAdvancedAnalyticsOpen] = useState(false);
	const [supportReportOpen, setSupportReportOpen] = useState(false);
	const [menuBarFormat, setMenuBarFormat] = useState(0);
	const [refreshNonce, setRefreshNonce] = useState(0);
	const rawFillId = useId();
	const fillId = `demo-fill-${rawFillId.replace(/:/g, "")}-${refreshNonce}`;
	const refreshDemo = () => setRefreshNonce((value) => value + 1);

	return (
		<div
			className="relative w-[calc(100vw-48px)] max-w-[384px] select-none sm:w-full"
			data-menubar-demo
		>
			{/* popover dashboard / settings card */}
			<div
				className="card animate-float-shadow relative overflow-hidden rounded-[18px] bg-card"
				data-demo-card
				style={themeStyle}
			>
				{face === "dashboard" ? (
					<DashboardFace
						view={view}
						setView={setView}
						days={days}
						setDays={setDays}
						dark={dark}
						onRefresh={refreshDemo}
						onSettings={() => setFace("settings")}
						fillId={fillId}
						menuBarFormat={menuBarFormat}
						onCycleMenuBarFormat={() =>
							setMenuBarFormat((value) => (value + 1) % MENU_BAR_FORMATS.length)
						}
						onOpenAdvancedAnalytics={() => setAdvancedAnalyticsOpen(true)}
					/>
				) : (
					<SettingsFace
						themeId={themeId}
						themeStyle={themeStyle}
						onSelectTheme={setThemeId}
						pinned={pinned}
						onPin={() => setPinned((p) => !p)}
						onRefresh={refreshDemo}
						onWidget={() => setWidgetOpen(true)}
						onBack={() => setFace("dashboard")}
						onSupport={() => setSupportReportOpen(true)}
						onOpenAdvancedAnalytics={() => setAdvancedAnalyticsOpen(true)}
						menuBarFormat={menuBarFormat}
						onCycleMenuBarFormat={() =>
							setMenuBarFormat((value) => (value + 1) % MENU_BAR_FORMATS.length)
						}
					/>
				)}
			</div>

			{widgetOpen ? (
				<WidgetPopup themeStyle={themeStyle} onClose={() => setWidgetOpen(false)} />
			) : null}
			{advancedAnalyticsOpen ? (
				<AdvancedAnalyticsPopup
					themeStyle={themeStyle}
					onClose={() => setAdvancedAnalyticsOpen(false)}
				/>
			) : null}
			{supportReportOpen ? (
				<SupportReportPopup themeStyle={themeStyle} onClose={() => setSupportReportOpen(false)} />
			) : null}
		</div>
	);
}

// ── Dashboard face ──────────────────────────────────────────────────────────────────────────────

function dashboardViewData(view: View, days: TimeframeDays, dark: boolean) {
	const active = view === "all" ? null : PROVIDERS[view];
	// A fully-unpriced or token-only provider (Copilot) charts its token series and shows token
	// counts instead of a dead $0.00 — mirrors the app's `ProviderRow.isFullyUnpriced` display swap.
	const isTokenBased = active?.usesTokenDisplay === true;
	const viz = active ? active.viz[dark ? "dark" : "light"] : "var(--color-ginger)";
	const rawSeries = windowSeries(active ? (active.tokenSeries ?? active.series) : AGG.series, days);
	const series = sparklineFractions(rawSeries);
	const windowTotal = windowCost(active ? active.week : AGG.week, days);
	return {
		active,
		isTokenBased,
		viz,
		series,
		markerEvery: Math.max(1, Math.ceil(series.length / 14)),
		name: active ? active.name : "All providers",
		today: active ? active.today : AGG.today,
		windowTotalDisplay: isTokenBased
			? formatTokenCount(active ? derive(active, days).windowTokens : 0)
			: money(windowTotal),
	};
}

function selectorAmount(p: Provider): string {
	return p.usesTokenDisplay ? `${formatTokenCount(p.todayTokens)} tok` : money(p.today);
}

function selectorNote(p: Provider): string {
	if (p.isAggregable === false && p.usesTokenDisplay) return "local";
	if (p.isAggregable === false) return "gateway";
	return p.notional ? "notional" : "real";
}

function DashboardFace({
	view,
	setView,
	days,
	setDays,
	dark,
	onRefresh,
	onSettings,
	fillId,
	onOpenAdvancedAnalytics,
	menuBarFormat,
	onCycleMenuBarFormat,
}: {
	view: View;
	setView: (v: View) => void;
	days: TimeframeDays;
	setDays: (days: TimeframeDays) => void;
	dark: boolean;
	onRefresh: () => void;
	onSettings: () => void;
	onOpenAdvancedAnalytics: () => void;
	menuBarFormat: number;
	onCycleMenuBarFormat: () => void;
	fillId: string;
}) {
	const isAll = view === "all";
	const { active, isTokenBased, viz, series, markerEvery, name, today, windowTotalDisplay } =
		dashboardViewData(view, days, dark);
	const heroSecondaryDisplay = heroWindowSecondaryDisplay(active, windowTotalDisplay);
	const lastVal = series[series.length - 1];
	const w = 232;
	const h = 56;

	return (
		<div className="demo-face-enter">
			{/* top bar — menu-bar display cycle + Settings. Pin belongs on the settings face. */}
			<ChromeBar>
				<RotationLight active={isRotatingFormat(menuBarFormat)} />
				<ChromeButton
					label={`Cycle menu bar display — current: ${MENU_BAR_FORMATS[menuBarFormat].title}`}
					onClick={onCycleMenuBarFormat}
				>
					<Icon name="menubar" />
				</ChromeButton>
				<ChromeButton label="Settings" onClick={onSettings}>
					<Icon name="gear" />
				</ChromeButton>
			</ChromeBar>

			{/* header — the selected view's today, with its honest animated basis-label ticker */}
			<div className="border-line border-t border-b px-[18px] pt-3 pb-3">
				<TickerBand text={basisLabel(view, active?.notional ?? false, isTokenBased)} />
				<div className="mt-2.5 flex items-center justify-between">
					<SplitFlapMoney
						className="tnum demo-total"
						value={isTokenBased ? (active?.todayTokens ?? 0) : today}
						format={isTokenBased ? flapTokens : money}
					/>
					<div className="shrink-0 text-right">
						<div className="demo-eyebrow mb-0.5">{name}</div>
						<div className="tnum demo-value-lg">{heroSecondaryDisplay}</div>
						<div className="demo-caption">last {days} days</div>
					</div>
				</div>
			</div>

			{/* selected-window line chart for the selected view (shared vertical scale) */}
			<div className="px-[18px] pt-3">
				<div className="demo-caption mb-1 flex items-center justify-between">
					<span className="inline-flex items-center gap-1.5">
						<span>{name} ·</span>
						<TimeframePicker days={days} onSelect={setDays} />
					</span>
					<span className="tnum">{windowTotalDisplay}</span>
				</div>
				<div className="relative">
					<svg
						viewBox={`0 0 ${w} ${h}`}
						className="h-[56px] w-full"
						preserveAspectRatio="none"
						role="img"
						aria-label={`${name} ${isTokenBased ? "token usage" : "spend"}, last ${days} days`}
					>
						<defs>
							<linearGradient id={fillId} x1="0" x2="0" y1="0" y2="1">
								<stop offset="0%" stopColor={viz} stopOpacity="0.24" />
								<stop offset="100%" stopColor={viz} stopOpacity="0" />
							</linearGradient>
						</defs>
						<path
							d={`${linePath(series, w, h)} L${w - 3},${h - 3} L3,${h - 3} Z`}
							fill={`url(#${fillId})`}
						/>
						<path
							d={linePath(series, w, h)}
							fill="none"
							stroke={viz}
							strokeWidth="2.2"
							strokeLinecap="round"
							strokeLinejoin="round"
						/>
					</svg>
					{series.map((v, i) => {
						if (i % markerEvery !== 0 && i !== series.length - 1) return null;
						const left = ((3 + i * ((w - 6) / (series.length - 1))) / w) * 100;
						return (
							<span
								key={`${i}-${left}`}
								className="pointer-events-none absolute h-1 w-1 -translate-x-1/2 -translate-y-1/2 rounded-full ring-1 ring-card"
								style={{ left: `${left}%`, top: `${3 + (1 - v) * (h - 6)}px`, background: viz }}
							/>
						);
					})}
					<span
						className="pointer-events-none absolute"
						style={{
							left: `${((w - 3) / w) * 100}%`,
							top: `${3 + (1 - lastVal) * (h - 6)}px`,
							transform: "translate(-50%, -50%)",
						}}
					>
						<span
							className="-inset-1 absolute animate-ping rounded-full opacity-40"
							style={{ background: viz }}
						/>
						<span
							className="relative block h-2 w-2 rounded-full ring-2 ring-card"
							style={{ background: viz }}
						/>
					</span>
				</div>
			</div>

			{/* selector — All providers + each provider; drives the chart above */}
			<div className="space-y-1.5 px-3.5 pt-3">
				<SelectorRow
					label="All providers"
					amount={money(AGG.today)}
					barColor="var(--color-ginger)"
					share={100}
					series={sparklineFractions(windowSeries(AGG.series, days))}
					active={isAll}
					onSelect={() => setView("all")}
				/>
				{ORDER.map((k) => (
					<SelectorRow
						key={k}
						label={PROVIDERS[k].name}
						amount={selectorAmount(PROVIDERS[k])}
						icon={PROVIDERS[k].icon}
						chipColor={PROVIDERS[k].color}
						barColor={PROVIDERS[k].viz[dark ? "dark" : "light"]}
						{...selectorPresentation(PROVIDERS[k], days)}
						note={selectorNote(PROVIDERS[k])}
						active={view === k}
						onSelect={() => setView(k)}
					/>
				))}
			</div>

			{/* detail — spend split for All providers, or the selected provider's full drawer */}
			{active ? (
				<ProviderDetail provider={active} viz={viz} days={days} />
			) : (
				<Composition dark={dark} days={days} />
			)}

			<CardFooter
				leadingText="Updated just now"
				onRefresh={onRefresh}
				onOpenAdvancedAnalytics={onOpenAdvancedAnalytics}
				accessory={<UpdateDotButton />}
			/>
		</div>
	);
}

function TimeframePicker({
	days,
	onSelect,
}: {
	days: TimeframeDays;
	onSelect: (days: TimeframeDays) => void;
}) {
	return (
		<label className="relative inline-flex min-h-6 items-center rounded-[7px] border border-line bg-paper px-1.5 py-0.5 text-ink-soft transition hover:border-line-strong hover:bg-paper-2 focus-within:ring-2 focus-within:ring-ginger/45">
			<span className="sr-only">Timeframe</span>
			<select
				aria-label="Timeframe"
				value={days}
				onChange={(event) => {
					const next = Number(event.currentTarget.value) as TimeframeDays;
					if (TIMEFRAME_OPTIONS.includes(next)) onSelect(next);
				}}
				className="tnum appearance-none bg-transparent pr-4 font-semibold text-[10px] text-ink-soft leading-none outline-none focus-visible:rounded-sm focus-visible:outline-solid focus-visible:outline-2 focus-visible:outline-ginger-deep focus-visible:outline-offset-2"
			>
				{TIMEFRAME_OPTIONS.map((option) => (
					<option key={option} value={option}>
						last {option} days
					</option>
				))}
			</select>
			<Icon
				name="chevron-down"
				className="pointer-events-none absolute right-1.5 h-2.5 w-2.5 text-ink-faint"
			/>
		</label>
	);
}

function SelectorRow({
	label,
	amount,
	icon,
	chipColor,
	barColor,
	share,
	series,
	description,
	note,
	active,
	onSelect,
}: {
	label: string;
	amount: string;
	icon?: string;
	chipColor?: string;
	barColor: string;
	share: number;
	series?: number[];
	description?: string;
	note?: string;
	active: boolean;
	onSelect: () => void;
}) {
	return (
		<button
			type="button"
			onClick={() => {
				playSelectorClick();
				onSelect();
			}}
			aria-pressed={active}
			title={description}
			className={`flex w-full items-center gap-2 rounded-[9px] px-2 py-1.5 text-left transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45 md:gap-3 ${
				active ? "bg-track ring-1 ring-line-strong" : "hover:bg-paper-2/60"
			}`}
		>
			{icon ? (
				<span
					className="grid h-4 w-4 shrink-0 place-items-center rounded-[5px] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.22)]"
					style={{ background: chipColor }}
				>
					<Image
						src={icon}
						alt=""
						width={11}
						height={11}
						className="h-[11px] w-[11px] object-contain"
						unoptimized
					/>
				</span>
			) : (
				<BrandMark size={16} className="h-4 w-4 shrink-0 rounded-[5px]" />
			)}
			<span
				className={`demo-value w-[84px] shrink-0 !font-normal ${
					active ? "!text-ink" : "!text-ink-soft"
				}`}
			>
				{label}
			</span>
			{series ? (
				<RowSparkline color={barColor} values={series} />
			) : (
				<span className="h-[5px] flex-1 overflow-hidden rounded-full bg-track ring-1 ring-ink-faint/50">
					<span
						className="block h-full rounded-full"
						style={{
							width: `${share}%`,
							background: barColor,
							opacity: "var(--bar-fill-opacity)",
						}}
					/>
				</span>
			)}
			{note ? (
				// "estimate" (a non-aggregable row, e.g. Copilot) gets a visually DISTINCT tint from
				// "notional"/other basis notes — it means something categorically different (a whole row
				// excluded from every total, not just a caveat on real dollar figures) — using the row's
				// own brand tint at a light wash, mirroring the native app's SelectorRow.badgeLabel.
				// "real" (real-dollar spend) uses the sage pill, the same basis vocabulary the Advanced
				// Analytics window uses — sage means real dollars, honey means notional list price.
				<span
					className={
						note === "local"
							? "demo-micro demo-badge rounded-[5px] font-medium"
							: note === "real"
								? "demo-micro demo-badge rounded-[5px] bg-sage/20 font-medium !text-sage-deep"
								: "demo-micro demo-badge rounded-[5px] bg-honey/25 font-medium !text-ginger-deep"
					}
					style={
						note === "local"
							? { background: `color-mix(in srgb, ${barColor} 18%, transparent)`, color: barColor }
							: undefined
					}
				>
					{note}
				</span>
			) : null}
			<span className="tnum demo-value w-[72px] shrink-0 whitespace-nowrap text-right">
				{amount}
			</span>
		</button>
	);
}

/** Selector-row trend, driven by the same selected-window data as the main chart. */
function RowSparkline({ color, values }: { color: string; values: number[] }) {
	const d = linePath(values, 100, 16, 1.5);
	const last = values[values.length - 1] ?? 0;
	return (
		<span className="relative h-[16px] flex-1">
			<svg
				viewBox="0 0 100 16"
				preserveAspectRatio="none"
				className="h-full w-full"
				aria-hidden="true"
			>
				<path
					d={d}
					fill="none"
					stroke={color}
					strokeOpacity="0.6"
					strokeWidth="1.4"
					strokeLinecap="round"
					strokeLinejoin="round"
					vectorEffect="non-scaling-stroke"
				/>
			</svg>
			<span
				className="absolute h-[7px] w-[7px] -translate-x-1/2 -translate-y-1/2"
				style={{
					left: "98.5%",
					top: `${1.5 + (1 - last) * 13}px`,
				}}
			>
				<span
					className="absolute inset-0 animate-ping rounded-full opacity-40"
					style={{ background: color }}
				/>
				<span
					className="relative block h-full w-full rounded-full ring-[1.5px] ring-card"
					style={{ background: color }}
				/>
			</span>
		</span>
	);
}

// ── Provider detail drawer ──────────────────────────────────────────────────────────────────────

function EstBadge() {
	return (
		<span className="demo-micro demo-badge rounded-[4px] bg-honey/20 font-medium !text-ginger-deep">
			est.
		</span>
	);
}

function SignatureCallout({ insight }: { insight: { text: string; est: boolean } }) {
	return (
		<div className="flex items-start gap-2 rounded-[9px] border border-sage/40 bg-sage/12 px-2.5 py-2">
			<span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-sage" />
			<span className="demo-label font-semibold !text-ink">{insight.text}</span>
			{insight.est ? <EstBadge /> : null}
		</div>
	);
}

function ScopeNoteCallout({ text }: { text: string }) {
	return (
		<div
			role="note"
			className="flex items-start gap-2 rounded-[9px] border border-ginger-deep/35 bg-ginger-deep/[0.08] px-2.5 py-2"
		>
			<span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-ginger-deep" />
			<span className="demo-label font-semibold !text-ink">{text}</span>
		</div>
	);
}

function formatAiu(value: number): string {
	const rounded = Math.round(value * 100) / 100;
	return `${rounded} AIU`;
}

// AIU consumption over the window — Copilot's real billing unit (github.copilot.nano_aiu). A raw
// consumption count, deliberately NOT dollars and NOT a quota %. Styled in the row's viz tint
// (Copilot purple) to match the estimate badge — a different KIND of number than the dollar surfaces.
function AiuCallout({ aiu, viz, days }: { aiu: number; viz: string; days: TimeframeDays }) {
	return (
		<div
			className="flex items-baseline gap-2 rounded-[9px] border px-2.5 py-2"
			style={{ borderColor: `${viz}59`, background: `${viz}1a` }}
		>
			<span className="h-1.5 w-1.5 shrink-0 self-center rounded-full" style={{ background: viz }} />
			<span className="demo-label font-semibold !text-ink">AIU used · {days} days</span>
			<span className="tnum ml-auto font-semibold" style={{ color: viz }}>
				{formatAiu(aiu)}
			</span>
		</div>
	);
}

function Gauge({ win, color }: { win: RateWindow; color: string }) {
	return (
		<div>
			<div className="demo-label mb-1 flex items-center justify-between">
				<span className="text-ink-soft">{win.label} used</span>
				<span className="inline-flex items-center gap-1.5">
					<span className="tnum font-semibold text-ink">{win.pct}%</span>
					<span
						className={`demo-micro demo-badge rounded-[4px] font-medium ${
							win.official ? "bg-sage/20 text-sage-deep" : "bg-honey/25 text-ginger-deep"
						}`}
					>
						{win.official ? "official" : win.measured ? "measured" : "est."}
					</span>
				</span>
			</div>
			<div className="h-2 w-full overflow-hidden rounded-full bg-track ring-1 ring-ink-faint/50">
				<div
					className="h-full rounded-full"
					style={{
						width: `${win.pct}%`,
						background: color,
						opacity: "var(--bar-fill-opacity)",
					}}
				/>
			</div>
			{win.official && win.resetsInMin > 0 ? (
				<div className="demo-micro mt-1">resets in {fmtReset(win.resetsInMin)}</div>
			) : null}
		</div>
	);
}

function Metric({ label, value, caption }: { label: string; value: string; caption: string }) {
	return (
		<div className="flex-1 rounded-[7px] border border-line/85 bg-paper/80 px-2.5 py-[7px]">
			<div className="demo-eyebrow">{label}</div>
			<div className="tnum font-semibold text-[16px] text-ink">{value}</div>
			<div className="demo-micro">{caption}</div>
		</div>
	);
}

function CompositionBar({ d, days }: { d: ReturnType<typeof derive>; days: TimeframeDays }) {
	const denom = d.ctx.read + d.ctx.write5m + d.ctx.write1h + d.ctx.fresh || 1;
	const segs = [
		{ v: d.ctx.read, c: "var(--color-sage)", o: 0.9 },
		{ v: d.ctx.write5m, c: "var(--color-honey)", o: 1 },
		{ v: d.ctx.write1h, c: "var(--color-ginger-deep)", o: 0.85 },
		{ v: d.ctx.fresh, c: "var(--color-ginger)", o: 0.85 },
	];
	return (
		<div>
			<div className="demo-caption mb-1.5 flex items-center justify-between">
				<span className="text-ink-soft">Context tokens · last {days} days</span>
				<span className="tnum text-ink-faint">{pct0(d.cacheHit)} cached</span>
			</div>
			<div className="flex h-2 w-full overflow-hidden rounded-full bg-track">
				{segs.map((s, i) => (
					<span
						key={s.c}
						className={i === 0 ? "h-full" : "h-full border-card/40 border-l"}
						style={{ width: `${(s.v / denom) * 100}%`, background: s.c, opacity: s.o }}
					/>
				))}
			</div>
			<div className="demo-micro mt-1">
				read {compact(d.ctx.read)} · write 5m {compact(d.ctx.write5m)} · write 1h{" "}
				{compact(d.ctx.write1h)} · fresh {compact(d.ctx.fresh)}
			</div>
		</div>
	);
}

/** Mirrors the native tile: a classified model shows its tier; an unclassified one keeps the slot. */
function EffortBadge({ model }: { model: string }) {
	const level = modelEffortLevel(model);
	if (!level) return <span aria-hidden="true" className="demo-badge w-[42px]" />;
	return (
		<span
			className={`demo-micro demo-badge min-w-[42px] rounded border ${EFFORT_CHIP_TONE[level]}`}
		>
			{modelEffortLevelLabel(level)}
		</span>
	);
}

function ModelList({
	d,
	viz,
	days,
}: {
	d: ReturnType<typeof derive>;
	viz: string;
	days: TimeframeDays;
}) {
	return (
		<div className="space-y-1.5">
			<div className="demo-caption !text-ink-soft">By model · last {days} days</div>
			{d.byModel.map((m) => (
				<div key={m.model} className="flex items-center gap-2">
					<span className="demo-label w-[78px] shrink-0 truncate">{shortModel(m.model)}</span>
					<span className="h-[5px] flex-1 overflow-hidden rounded-full bg-track ring-1 ring-ink-faint/50">
						<span
							className="block h-full rounded-full"
							style={{
								width: `${
									m.cost != null && d.windowTotal > 0
										? (m.cost / d.windowTotal) * 100
										: d.windowTokens > 0
											? (m.tokens / d.windowTokens) * 100
											: 0
								}%`,
								background: viz,
								opacity: "var(--bar-fill-opacity)",
							}}
						/>
					</span>
					{m.cost != null ? (
						<span className="tnum demo-label w-[60px] shrink-0 text-right font-medium !text-ink">
							{money(m.cost)}
						</span>
					) : (
						<span className="demo-micro w-[60px] shrink-0 text-right !text-ginger-deep">
							{formatTokenCount(m.tokens)}
						</span>
					)}
					<EffortBadge model={m.model} />
				</div>
			))}
		</div>
	);
}

function TrendStrip({
	p,
	d,
	days,
}: {
	p: Provider;
	d: ReturnType<typeof derive>;
	days: TimeframeDays;
}) {
	// A non-aggregable, fully-unpriced provider (Copilot) has an all-zero dollar series, so the dollar
	// trend numbers here would otherwise read "$0.00" three times over — mirrors the app's
	// `row.isFullyUnpriced` branch on the same trend strip (DashboardView.swift `trendAmount`).
	const isTokenBased = p.usesTokenDisplay === true;
	const today = isTokenBased ? p.todayTokens : p.today;
	const avg = isTokenBased ? d.tokenAvg : d.avg;
	const peak = isTokenBased ? d.tokenPeak : d.peak;
	const windowTotalDisplay = isTokenBased ? formatTokenCount(d.windowTokens) : money(d.windowTotal);
	const delta = today - avg;
	const sign = Math.abs(delta) < 0.005 ? "±" : delta > 0 ? "+" : "-";
	const deltaDisplay = isTokenBased ? formatTokenCount(Math.abs(delta)) : money(Math.abs(delta));
	const peakDisplay = isTokenBased ? formatTokenCount(peak) : money(peak);
	return (
		<div className="demo-micro flex items-center justify-between gap-2">
			<span className="tnum">
				{days}d {windowTotalDisplay}
			</span>
			<span className="tnum font-medium text-ink-soft">
				{sign}
				{deltaDisplay} vs {isTokenBased ? "daily avg" : "avg"}
			</span>
			<span className="tnum">
				peak {peakDisplay} {p.peakDay}
			</span>
		</div>
	);
}

function ActivityMetrics({
	p,
	d,
	days,
	isTokenBased,
}: {
	p: Provider;
	d: ReturnType<typeof derive>;
	days: TimeframeDays;
	isTokenBased: boolean;
}) {
	return (
		<div className="flex gap-2">
			<Metric
				label={isTokenBased ? "Tokens · today" : "Today"}
				value={isTokenBased ? formatTokenCount(p.todayTokens) : money(p.today)}
				caption={
					isTokenBased
						? `${p.todayEvents} turns`
						: `${compact(p.todayTokens)} tok · ${p.todayEvents} turns`
				}
			/>
			<Metric
				label={isTokenBased ? `Tokens · ${days} days` : `${days} days`}
				value={isTokenBased ? formatTokenCount(d.windowTokens) : money(d.windowTotal)}
				caption={
					isTokenBased
						? `${d.windowEvents} turns`
						: `${compact(d.windowTokens)} tok · ${d.windowEvents} turns`
				}
			/>
		</div>
	);
}

function CacheMetrics({
	p,
	d,
	days,
	isTokenBased,
}: {
	p: Provider;
	d: ReturnType<typeof derive>;
	days: TimeframeDays;
	isTokenBased: boolean;
}) {
	return (
		<div className="flex gap-2">
			<Metric
				label={isTokenBased ? "Cached context" : "Cache hit"}
				value={pct0(d.cacheHit)}
				caption="of context from cache"
			/>
			{d.cacheSavings != null ? (
				<Metric
					label="Saved by cache"
					value={money(d.cacheSavings)}
					caption={p.notional ? "est. · notional" : "est. vs no cache"}
				/>
			) : isTokenBased ? (
				<Metric
					label="Context / turn"
					value={compact(d.tokensPerTurn)}
					caption={`${days}-day average`}
				/>
			) : (
				<Metric
					label="Cost / turn"
					value={`$${d.costPerTurn.toFixed(3)}`}
					caption={`${days}-day average`}
				/>
			)}
		</div>
	);
}

function basisFootnote(p: Provider, isTokenBased: boolean): string {
	if (isTokenBased) {
		return "JP counts locally observed tokens. The provider calculates plan usage separately.";
	}
	return p.notional
		? "Notional list-price dollars from local usage logs."
		: "Real-dollar spend from local usage logs.";
}

function OfficialUsageSentence({ provider }: { provider: Provider }) {
	const linkClass =
		"underline-offset-2 hover:underline focus-visible:rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45";
	if (provider.usageLinkRuns?.length) {
		return (
			<p className="font-semibold text-[11px] text-ginger-deep">
				{provider.usageLinkRuns.map((run) =>
					run.url ? (
						<a key={run.url} href={run.url} target="_blank" rel="noreferrer" className={linkClass}>
							{run.text}
							<Icon name="arrow-up-right" className="ml-0.5 inline h-2.5 w-2.5" />
						</a>
					) : (
						<span key={run.text}>{run.text}</span>
					),
				)}
			</p>
		);
	}
	if (!provider.usageURL || !provider.usageLinkLabel) return null;
	return (
		<a
			href={provider.usageURL}
			target="_blank"
			rel="noreferrer"
			className={`inline-flex items-center gap-1.5 font-semibold text-[11px] text-ginger-deep ${linkClass}`}
		>
			{provider.usageLinkLabel}
			<Icon name="arrow-up-right" className="h-2.5 w-2.5" />
		</a>
	);
}

function ProviderDetail({
	provider: p,
	viz,
	days,
}: {
	provider: Provider;
	viz: string;
	days: TimeframeDays;
}) {
	const d = derive(p, days);
	const insight = signature(p);
	const isTokenBased = p.usesTokenDisplay === true;
	return (
		<div className="mt-3 space-y-3 border-line border-t bg-paper-2/50 px-[18px] py-3.5">
			{insight ? <SignatureCallout insight={insight} /> : null}
			{p.sourceScopeNote ? <ScopeNoteCallout text={p.sourceScopeNote} /> : null}

			{p.windows ? (
				<div className="space-y-2">
					{p.windows.map((win) => (
						<Gauge key={win.label} win={win} color={viz} />
					))}
				</div>
			) : null}

			{p.credits ? (
				<div className="space-y-1.5">
					<div className="flex items-baseline justify-between gap-2">
						<span className="demo-label">Credits remaining</span>
						<span className="demo-value-lg tnum">
							{p.credits.balance.toLocaleString("en-US", { maximumFractionDigits: 2 })}
						</span>
					</div>
					<p className="demo-caption">Separate from the included allowance and notional dollars.</p>
					<p className="demo-caption">{p.credits.reported}</p>
				</div>
			) : null}

			{p.isAggregable === false && !p.sourceScopeNote ? (
				<div
					role="note"
					className="flex items-start gap-2 rounded-[9px] border border-line-strong bg-paper px-2.5 py-2"
				>
					<span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-ink-soft" />
					<span className="demo-label font-semibold !text-ink">
						Local activity only · Not {p.name} plan or billing usage
					</span>
				</div>
			) : null}

			<OfficialUsageSentence provider={p} />

			<div className="space-y-1.5">
				<div className="demo-label font-medium">
					{p.name} local {isTokenBased ? "token " : ""}activity
				</div>
				<ActivityMetrics p={p} d={d} days={days} isTokenBased={isTokenBased} />
				<CacheMetrics p={p} d={d} days={days} isTokenBased={isTokenBased} />
				<div className="demo-caption">
					{isTokenBased ? null : <>{money(d.blended)}/1M tok · </>}
					{compact(d.tokensPerTurn)} tok/turn · {pct0(d.outputShare)} generated output
				</div>
				{isTokenBased ? null : (
					<div className="demo-caption flex items-center justify-between">
						<span className="text-ink-faint">At this pace</span>
						<span className="inline-flex items-center gap-1.5">
							<span className="tnum font-semibold text-ink">
								~${d.runRate30 < 1 ? d.runRate30.toFixed(2) : Math.round(d.runRate30)} / 30 days
							</span>
							<EstBadge />
						</span>
					</div>
				)}
				<div className="demo-caption">{basisFootnote(p, isTokenBased)}</div>
			</div>

			<CompositionBar d={d} days={days} />
			<ModelList d={d} viz={viz} days={days} />
			{p.aiuWindow != null ? <AiuCallout aiu={p.aiuWindow} viz={viz} days={days} /> : null}
			<TrendStrip p={p} d={d} days={days} />
		</div>
	);
}

function Composition({ dark, days }: { dark: boolean; days: TimeframeDays }) {
	const total = windowCost(AGG.week, days);
	return (
		<div className="mt-3 min-h-[96px] border-line border-t bg-paper-2/50 px-[18px] py-3.5">
			<div className="demo-label mb-1.5 flex items-center justify-between">
				<span className="text-ink-soft">Spend by provider · last {days} days</span>
				<span className="tnum font-semibold text-ink">{money(total)}</span>
			</div>
			<div className="flex h-2.5 w-full overflow-hidden rounded-full bg-track">
				{AGG.shares.map((s) => (
					<span
						key={s.key}
						className="h-full"
						style={{
							width: `${(s.week / AGG.week) * 100}%`,
							background: PROVIDERS[s.key].viz[dark ? "dark" : "light"],
							opacity: 0.85,
						}}
					/>
				))}
			</div>
		</div>
	);
}
