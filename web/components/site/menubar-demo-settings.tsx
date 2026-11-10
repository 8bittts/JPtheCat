"use client";

import { type CSSProperties, useEffect, useId, useRef, useState } from "react";
import { trackRepoLink } from "@/lib/analytics/product-analytics";
import { trapDialogTab } from "@/lib/dialog-focus-trap";
import { SITE } from "@/lib/site";
import { BrandMark } from "./brand";
import { type DemoTheme, getDemoTheme, THEME_CATALOG } from "./demo-themes";
import { Icon } from "./icon";
import {
	playDemoAudio,
	playDemoMeow,
	playTopClick,
	setDemoUISoundsEnabled,
	UI_SOUND,
} from "./menubar-demo-audio";
import {
	CardFooter,
	ChromeButton,
	CycleRow,
	RotationLight,
	Section,
	ToggleRow,
	UpdateDotButton,
} from "./menubar-demo-chrome";
import { isRotatingFormat, MENU_BAR_FORMATS } from "./menubar-demo-format";
import { PROVIDERS } from "./menubar-demo-series";

// The demo card's SETTINGS face and its exclusive children, extracted from `menubar-demo.tsx` so that
// file holds only the dashboard face it shares nothing with. Both faces still share their chrome, the
// card footer, and the settings-row primitives via `menubar-demo-chrome.tsx`, so a change to either
// stays in lockstep. Parity guard: `scripts/verify-app-demo-parity.sh` scans THIS file for the
// settings chrome and theme controls; `tests/site-copy.test.ts` pins its copy and geometry.
// Exports components ONLY (Fast Refresh / react-doctor `only-export-components`).

// Mirrors the app's RefreshCadence presets (Settings → "Refresh rate"). Balanced is the default.
const REFRESH_CADENCES = [
	{ title: "Live", subtitle: "Every 30s when open" },
	{ title: "Balanced", subtitle: "Every 60s when open" },
	{ title: "Relaxed", subtitle: "Every 2 min when open" },
	{ title: "Battery saver", subtitle: "Every 5 min when open" },
] as const;
const DEFAULT_CADENCE_INDEX = 1;

export function SettingsFace({
	themeId,
	themeStyle,
	onSelectTheme,
	pinned,
	onPin,
	onRefresh,
	onWidget,
	onBack,
	onSupport,
	onOpenAdvancedAnalytics,
	menuBarFormat,
	onCycleMenuBarFormat,
}: {
	themeId: string;
	themeStyle: CSSProperties | undefined;
	onSelectTheme: (id: string) => void;
	pinned: boolean;
	onPin: () => void;
	onRefresh: () => void;
	onWidget: () => void;
	onBack: () => void;
	onSupport: () => void;
	onOpenAdvancedAnalytics: () => void;
	menuBarFormat: number;
	onCycleMenuBarFormat: () => void;
}) {
	// All toggles are real, clickable local state — mirroring the app's default-on switches.
	const [showDock, setShowDock] = useState(true);
	const [launchAtLogin, setLaunchAtLogin] = useState(false);
	const [cadenceIndex, setCadenceIndex] = useState(DEFAULT_CADENCE_INDEX);
	const [autoUpdates, setAutoUpdates] = useState(true);
	// Provider enable/disable — defaults on, mirrors SettingsStore.defaultProviderEnabled.
	const [claudeEnabled, setClaudeEnabled] = useState(true);
	const [codexEnabled, setCodexEnabled] = useState(true);
	const [grokEnabled, setGrokEnabled] = useState(true);
	const [museSparkEnabled, setMuseSparkEnabled] = useState(true);
	const [openCodeGoEnabled, setOpenCodeGoEnabled] = useState(true);
	const [claudeLimits, setClaudeLimits] = useState(false);
	const [grokLimits, setGrokLimits] = useState(false);
	const [cursorHook, setCursorHook] = useState(false);
	const [usageAlerts, setUsageAlerts] = useState(true);
	const [banner, setBanner] = useState(true);
	const [meow, setMeow] = useState(true);
	const [interactiveSounds, setInteractiveSounds] = useState(true);
	const [testMeowNotice, setTestMeowNotice] = useState(false);
	// "Live data" is a single row that opens a dedicated popup (mirroring the native app's
	// LiveDataWindowController) — the full provider/live-limit list lives THERE, not inline, so it can
	// grow without lengthening this settings face.
	const [liveDataOpen, setLiveDataOpen] = useState(false);
	// The Appearance "More themes" tile opens a dedicated popup with the full catalog — mirrors the
	// native `ThemesWindowController` opened from the compact picker.
	const [themesOpen, setThemesOpen] = useState(false);
	// Keep the shared UI-sound master (used by ChromeButton/CardFooter, which live outside this scope)
	// in sync with the demo's interactive-sounds toggle — the app's global master, mirrored on the web.
	useEffect(() => {
		setDemoUISoundsEnabled(interactiveSounds);
	}, [interactiveSounds]);

	return (
		<div className="demo-face-enter flex flex-col">
			{/* top bar — brand + the settings chrome cluster (Pin, Widget, Dashboard). Theme selection
			    lives in the Appearance body section, not the chrome — matching the real app. Refresh
			    lives ONLY in the shared footer (both faces) — never the top chrome row. */}
			<div className="flex h-8 items-center gap-2 bg-card pr-3.5 pl-4">
				<span className="font-semibold text-[13px] text-ink leading-none">JP the Cat 🐾</span>
				<span className="ml-auto flex items-center gap-1">
					<RotationLight active={isRotatingFormat(menuBarFormat)} />
					<ChromeButton
						label={`Cycle menu bar display — current: ${MENU_BAR_FORMATS[menuBarFormat].title}`}
						onClick={onCycleMenuBarFormat}
					>
						<Icon name="menubar" />
					</ChromeButton>
					<ChromeButton
						label={pinned ? "Unpin dashboard" : "Pin dashboard"}
						active={pinned}
						tone="sage"
						onClick={onPin}
					>
						<Icon name="pin" />
					</ChromeButton>
					<ChromeButton label="How to add the widget" onClick={onWidget}>
						<Icon name="grid" />
					</ChromeButton>
					<ChromeButton label="Back to dashboard" onClick={onBack}>
						<Icon name="gauge" />
					</ChromeButton>
				</span>
			</div>
			<div className="border-line border-t" />

			<div className="space-y-3.5 px-[18px] py-3.5">
				<Section title="General">
					<NavRow
						icon="help"
						title="Support report"
						subtitle="Send a redacted report — no prompts or code leave your Mac"
						onOpen={onSupport}
					/>
					<NavRow
						icon="code"
						title="Open source"
						subtitle="MIT licensed — read the code and contribute on GitHub"
						onOpen={() => {
							trackRepoLink("demo_settings", "repo");
							window.open(SITE.repoUrl, "_blank", "noopener,noreferrer");
						}}
					/>
					<CycleRow
						icon="menubar"
						title="Menu bar display"
						subtitle={`${MENU_BAR_FORMATS[menuBarFormat].title} — ${MENU_BAR_FORMATS[menuBarFormat].subtitle}`}
						onCycle={onCycleMenuBarFormat}
					/>
					<CycleRow
						icon="refresh"
						title="Refresh rate"
						subtitle={`${REFRESH_CADENCES[cadenceIndex].title} — ${REFRESH_CADENCES[cadenceIndex].subtitle}`}
						onCycle={() => setCadenceIndex((i) => (i + 1) % REFRESH_CADENCES.length)}
					/>
					<ToggleRow
						icon="window"
						title="Show Dock icon"
						subtitle={showDock ? "Keep JP the Cat in the Dock and app switcher" : "Menu-bar only"}
						on={showDock}
						onToggle={() => setShowDock((v) => !v)}
					/>
					<ToggleRow
						icon="power"
						title="Launch at login"
						subtitle={
							launchAtLogin
								? "Starts automatically when you sign in"
								: "Start JP the Cat automatically when you sign in"
						}
						on={launchAtLogin}
						onToggle={() => setLaunchAtLogin((v) => !v)}
					/>
					<ToggleRow
						icon="download"
						title="Automatic updates"
						subtitle="Check for new versions automatically"
						on={autoUpdates}
						onToggle={() => setAutoUpdates((v) => !v)}
					/>
				</Section>

				<Section title="Live data">
					<NavRow
						icon="chart"
						title="Providers & live limits"
						subtitle="Choose which providers show and enable official limits"
						onOpen={() => setLiveDataOpen(true)}
					/>
				</Section>

				<Section title="Alerts">
					<ToggleRow
						icon="bell"
						title="Usage alerts at 80%"
						subtitle="Watch all provider windows"
						on={usageAlerts}
						onToggle={() => setUsageAlerts((v) => !v)}
					/>
					<ToggleRow
						icon="badge"
						title="Show notification banner"
						subtitle={
							banner ? "Pop a macOS banner as you near a limit" : "Off — meow only, no banner"
						}
						on={banner}
						onToggle={() => setBanner((v) => !v)}
					/>
					<ToggleRow
						icon="speaker"
						title="Meow on alerts"
						subtitle="JP meows with each alert"
						on={meow}
						onToggle={() => setMeow((v) => !v)}
					/>
					<ToggleRow
						icon="speaker"
						title="Interactive sounds"
						subtitle="Allow JP's meows and UI sounds"
						on={interactiveSounds}
						onToggle={() => {
							// The master itself: sync the shared flag now, and confirm ENABLING audibly (the
							// generic Switch cue is self-gated and would be suppressed while sounds were off) —
							// matching the app, where turning "Interactive sounds" on plays the on-cue.
							const next = !interactiveSounds;
							setDemoUISoundsEnabled(next);
							if (next) playDemoAudio(UI_SOUND.toggleOn, 0.6);
							setInteractiveSounds(next);
						}}
					/>
					<JPFaceActionRow
						title="Test meow"
						subtitle="Tap JP to hear her roar!"
						onClick={() => {
							// Mirror the native app: Test meow reproduces the alert meow, so it gates on
							// "Meow on alerts" (meow) under the global "Interactive sounds" master.
							if (meow && interactiveSounds) playDemoMeow();
							setTestMeowNotice(true);
							if (typeof window !== "undefined" && "Notification" in window) {
								void Notification.requestPermission().then((permission) => {
									if (permission === "granted") {
										new Notification("JP the Cat", { body: "JP says meow. Test sound worked." });
									}
								});
							}
						}}
					/>
					{testMeowNotice ? (
						<div className="px-2.5 py-2 text-[12px] text-sage-deep" role="status">
							JP meowed. Test banner sent.
						</div>
					) : null}
				</Section>

				{/* Appearance sits LAST, matching the native app's Settings section order
				    (General → Live data → Alerts → Appearance). */}
				<Section title="Appearance">
					<ThemePickerRow
						activeThemeId={themeId}
						onSelectTheme={onSelectTheme}
						onOpenThemes={() => setThemesOpen(true)}
					/>
				</Section>
			</div>

			<CardFooter
				leadingText="Settings"
				onRefresh={onRefresh}
				onOpenAdvancedAnalytics={onOpenAdvancedAnalytics}
				accessory={<UpdateDotButton />}
			/>

			{themesOpen ? (
				<ThemesPopup
					themeStyle={themeStyle}
					activeThemeId={themeId}
					onSelectTheme={onSelectTheme}
					onClose={() => setThemesOpen(false)}
				/>
			) : null}

			{liveDataOpen ? (
				<LiveDataPopup
					themeStyle={themeStyle}
					onClose={() => setLiveDataOpen(false)}
					claudeEnabled={claudeEnabled}
					setClaudeEnabled={setClaudeEnabled}
					codexEnabled={codexEnabled}
					setCodexEnabled={setCodexEnabled}
					grokEnabled={grokEnabled}
					setGrokEnabled={setGrokEnabled}
					museSparkEnabled={museSparkEnabled}
					setMuseSparkEnabled={setMuseSparkEnabled}
					openCodeGoEnabled={openCodeGoEnabled}
					setOpenCodeGoEnabled={setOpenCodeGoEnabled}
					claudeLimits={claudeLimits}
					setClaudeLimits={setClaudeLimits}
					grokLimits={grokLimits}
					setGrokLimits={setGrokLimits}
					cursorHook={cursorHook}
					setCursorHook={setCursorHook}
				/>
			) : null}
		</div>
	);
}

/** A tappable settings row that opens another surface (chevron affordance) — mirrors the native
 *  `SettingsRow` used for "Live data". Semantically a navigation rather than a value cycle, but the
 *  native rows are pixel-identical, so this renders `CycleRow` instead of restating its markup —
 *  one definition of the chevron-row geometry, exactly as `Switch` backs every `ToggleRow`. */
function NavRow({
	icon,
	title,
	subtitle,
	onOpen,
}: {
	icon: string;
	title: string;
	subtitle: string;
	onOpen: () => void;
}) {
	return <CycleRow icon={icon} title={title} subtitle={subtitle} onCycle={onOpen} />;
}

/** The compact Appearance picker — mirrors the native `ThemePickerRow`: a 3-column row of the two free
 *  swatch tiles (Sunlit, Midnight) plus a "More themes" tile that opens the full catalog popup. The
 *  growing theme catalog lives in the popup, not inline, so this row never lengthens the settings
 *  face. */
function ThemePickerRow({
	activeThemeId,
	onSelectTheme,
	onOpenThemes,
}: {
	activeThemeId: string;
	onSelectTheme: (id: string) => void;
	onOpenThemes: () => void;
}) {
	const freeThemes = THEME_CATALOG.filter((t) => !t.inMoreThemes);
	const activeIsMore = getDemoTheme(activeThemeId).inMoreThemes;
	return (
		<div className="grid grid-cols-3 gap-1.5 px-2.5 py-1.5">
			{freeThemes.map((theme) => (
				<ThemeSwatchTile
					key={theme.id}
					theme={theme}
					active={theme.id === activeThemeId}
					onTap={() => {
						playTopClick();
						onSelectTheme(theme.id);
					}}
				/>
			))}
			<button
				type="button"
				onClick={() => {
					playTopClick();
					onOpenThemes();
				}}
				aria-label={`More themes, opens the catalog of ${THEME_CATALOG.length} themes`}
				className={`flex h-[30px] items-center justify-center gap-1 rounded-[7px] bg-honey/14 font-semibold text-[11px] text-ginger-deep transition hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45 ${activeIsMore ? "ring-[1.5px] ring-ginger-deep" : "ring-1 ring-ginger-deep/35"}`}
			>
				<Icon name="palette" className="h-[13px] w-[13px]" />
				<span className="truncate">More themes</span>
			</button>
		</div>
	);
}

/** A swatch tile previewing a theme's OWN card/ink/ginger so legibility is judged before switching —
 *  mirrors the native `ThemeSwatchTile`. Preview colors come from the theme's own palette (literal hex),
 *  NOT the active `--color-*` vars. `large` is the taller catalog-grid variant. */
function ThemeSwatchTile({
	theme,
	active,
	large = false,
	onTap,
}: {
	theme: DemoTheme;
	active: boolean;
	large?: boolean;
	onTap: () => void;
}) {
	const p = theme.palette;
	return (
		<button
			type="button"
			onClick={onTap}
			aria-label={theme.name}
			aria-pressed={active}
			title={theme.name}
			className={`relative flex items-end overflow-hidden rounded-[7px] transition hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45 ${large ? "h-10" : "h-[30px]"} ${active ? "ring-[1.5px] ring-ginger-deep" : "ring-[0.5px] ring-line-strong/70"}`}
			style={{ background: p.card }}
		>
			<span
				className="absolute inset-x-0 bottom-0"
				style={{ height: large ? 5 : 4, background: p.ginger }}
			/>
			<span
				className={`relative z-10 truncate font-medium ${large ? "px-2 pb-1.5 text-[13px]" : "px-1.5 pb-1 text-[11px]"}`}
				style={{ color: p.ink }}
			>
				{theme.name}
			</span>
		</button>
	);
}

/** The full theme catalog popup — mirrors the native `ThemesWindowController` + `ThemesWindowGrid`:
 *  every theme in a larger, readable 2-column grid. Opened from the compact picker's "More themes"
 *  tile. Every pack is unlocked and selectable. */
function ThemesPopup({
	themeStyle,
	activeThemeId,
	onSelectTheme,
	onClose,
}: {
	themeStyle: CSSProperties | undefined;
	activeThemeId: string;
	onSelectTheme: (id: string) => void;
	onClose: () => void;
}) {
	const titleId = useId();
	const dialogRef = useRef<HTMLDialogElement>(null);

	useEffect(() => {
		const dialog = dialogRef.current;
		dialog?.showModal();
		dialog?.querySelector<HTMLButtonElement>("button")?.focus();
		return () => dialog?.close();
	}, []);

	return (
		<dialog
			ref={dialogRef}
			aria-labelledby={titleId}
			onClose={onClose}
			onClick={(e) => {
				if (e.target === dialogRef.current) dialogRef.current?.close();
			}}
			onKeyDown={trapDialogTab}
			style={themeStyle}
			className="dialog-panel dialog-panel-sm overflow-hidden !p-0"
		>
			<div className="flex h-8 items-center gap-1.5 bg-card pr-3.5 pl-4">
				<span className="font-semibold text-[13px] text-ink leading-none">JP the Cat 🐾</span>
				<span id={titleId} className="font-semibold text-[13px] text-ink-faint leading-none">
					— Themes
				</span>
			</div>
			<div className="border-line border-t" />
			<div className="max-h-[70dvh] overflow-y-auto px-[18px] py-3.5">
				<div className="grid grid-cols-2 gap-2">
					{THEME_CATALOG.map((theme) => (
						<ThemeSwatchTile
							key={theme.id}
							theme={theme}
							active={theme.id === activeThemeId}
							large
							onTap={() => {
								playTopClick();
								onSelectTheme(theme.id);
							}}
						/>
					))}
				</div>
			</div>
		</dialog>
	);
}

/** The provider and live-limit switches the Live data popup hands straight to its one section. */
type LiveDataToggles = {
	claudeEnabled: boolean;
	setClaudeEnabled: (fn: (v: boolean) => boolean) => void;
	codexEnabled: boolean;
	setCodexEnabled: (fn: (v: boolean) => boolean) => void;
	grokEnabled: boolean;
	setGrokEnabled: (fn: (v: boolean) => boolean) => void;
	museSparkEnabled: boolean;
	setMuseSparkEnabled: (fn: (v: boolean) => boolean) => void;
	openCodeGoEnabled: boolean;
	setOpenCodeGoEnabled: (fn: (v: boolean) => boolean) => void;
	claudeLimits: boolean;
	setClaudeLimits: (fn: (v: boolean) => boolean) => void;
	grokLimits: boolean;
	setGrokLimits: (fn: (v: boolean) => boolean) => void;
	cursorHook: boolean;
	setCursorHook: (fn: (v: boolean) => boolean) => void;
};

/** The dedicated "Live data" popup — mirrors the native app's `LiveDataWindowController`. Opens as a
 *  real top-layer modal (native Esc + focus trap + backdrop) carrying the same `JP the Cat 🐾 — Live
 *  data` chrome as the analytics window, and hosts the same `LiveDataSection` rows. */
function LiveDataPopup({
	themeStyle,
	onClose,
	...section
}: {
	themeStyle: CSSProperties | undefined;
	onClose: () => void;
} & LiveDataToggles) {
	const titleId = useId();
	const dialogRef = useRef<HTMLDialogElement>(null);

	useEffect(() => {
		const dialog = dialogRef.current;
		dialog?.showModal();
		dialog?.querySelector<HTMLButtonElement>("button")?.focus();
		return () => dialog?.close();
	}, []);

	return (
		<dialog
			ref={dialogRef}
			aria-labelledby={titleId}
			onClose={onClose}
			onClick={(e) => {
				if (e.target === dialogRef.current) dialogRef.current?.close();
			}}
			onKeyDown={trapDialogTab}
			style={themeStyle}
			className="dialog-panel overflow-hidden !p-0"
		>
			<div className="flex h-8 items-center gap-1.5 bg-card pr-3.5 pl-4">
				<span className="font-semibold text-[13px] text-ink leading-none">JP the Cat 🐾</span>
				<span id={titleId} className="font-semibold text-[13px] text-ink-faint leading-none">
					— Live data
				</span>
			</div>
			<div className="border-line border-t" />
			<div className="max-h-[70dvh] overflow-y-auto px-[18px] py-3.5">
				<LiveDataSection {...section} />
			</div>
		</dialog>
	);
}

/** The "Live data" section — split out of SettingsFace so that component stays under the giant-component
 *  threshold. Mirrors the app's Settings → "Live data": per-provider enable/disable (Claude Code, Codex,
 *  Grok when detected) plus opt-in live-capture toggles (Grok SuperGrok weekly, Claude limits, Cursor CLI). */
function LiveDataSection({
	claudeEnabled,
	setClaudeEnabled,
	codexEnabled,
	setCodexEnabled,
	grokEnabled,
	setGrokEnabled,
	museSparkEnabled,
	setMuseSparkEnabled,
	openCodeGoEnabled,
	setOpenCodeGoEnabled,
	claudeLimits,
	setClaudeLimits,
	grokLimits,
	setGrokLimits,
	cursorHook,
	setCursorHook,
}: LiveDataToggles) {
	return (
		<Section title="">
			{/* No section title — the popup chrome already reads "Live data". Grouped by provider so each
			    provider's enable + its live-limit opt-in sit together: Claude, Codex, Grok, Muse Spark, Cursor, OpenCode Go —
			    mirrors LiveDataWindowContent. */}
			<ToggleRow
				icon="terminal"
				providerMark={{ icon: PROVIDERS.claude.icon, color: PROVIDERS.claude.color }}
				title="Claude Code"
				subtitle={
					claudeEnabled
						? "Real spend · in totals, widgets & alerts"
						: "Hidden from dashboard, widgets & alerts"
				}
				on={claudeEnabled}
				onToggle={() => setClaudeEnabled((v) => !v)}
			/>
			<ToggleRow
				icon="terminal"
				providerMark={{ icon: PROVIDERS.claude.icon, color: PROVIDERS.claude.color }}
				title={claudeLimits ? "Claude live limits · on" : "Enable Claude live limits"}
				subtitle={
					claudeLimits
						? "Official 5-hour & weekly % · statusline feed"
						: "Shows official 5-hour & weekly % · edits your statusline"
				}
				on={claudeLimits}
				onToggle={() => setClaudeLimits((v) => !v)}
			/>
			<ToggleRow
				icon="braces"
				providerMark={{ icon: PROVIDERS.codex.icon, color: PROVIDERS.codex.color }}
				title="Codex"
				subtitle={
					codexEnabled
						? "Notional list price · in totals, widgets & alerts"
						: "Hidden from dashboard, widgets & alerts"
				}
				on={codexEnabled}
				onToggle={() => setCodexEnabled((v) => !v)}
			/>
			{/* Always shown in the homepage demo (mirrors a machine with Grok Build installed).
			    The native app only renders this row when GrokProvider.isGrokBuildDetected(). */}
			<ToggleRow
				icon="sparkles"
				providerMark={{ icon: PROVIDERS.grok.icon, color: PROVIDERS.grok.color }}
				title="Grok"
				subtitle={
					grokEnabled
						? "Build, Cursor & Grok Bot · notional list price · in totals, widgets & alerts"
						: "Hidden from dashboard, widgets & alerts"
				}
				on={grokEnabled}
				onToggle={() => setGrokEnabled((v) => !v)}
			/>
			{/* Native app only shows this when Grok Build is detected (same gate as the Grok row). */}
			<ToggleRow
				icon="sparkles"
				providerMark={{ icon: PROVIDERS.grok.icon, color: PROVIDERS.grok.color }}
				title={grokLimits ? "Grok live limits · on" : "Enable Grok live limits"}
				subtitle={
					grokLimits
						? "Official SuperGrok weekly % · Grok Build log"
						: "Shows official SuperGrok weekly % · adds a Grok hook"
				}
				on={grokLimits}
				onToggle={() => setGrokLimits((v) => !v)}
			/>
			{/* Always shown in the homepage demo (mirrors a machine with Muse Spark usage in OpenCode).
			    The native app only renders this row when MuseSparkProvider.isAvailable(). */}
			<ToggleRow
				icon="flame"
				providerMark={{ icon: PROVIDERS.museSpark.icon, color: PROVIDERS.museSpark.color }}
				title="Muse Spark"
				subtitle={
					museSparkEnabled
						? "OpenCode on this Mac · notional list price · in totals & widgets"
						: "Hidden from dashboard & widgets"
				}
				on={museSparkEnabled}
				onToggle={() => setMuseSparkEnabled((v) => !v)}
			/>
			<ToggleRow
				icon="code"
				providerMark={{ icon: PROVIDERS.cursor.icon, color: PROVIDERS.cursor.color }}
				title={cursorHook ? "Cursor CLI live data · on" : "Enable Cursor CLI live data"}
				subtitle={
					cursorHook
						? "Feeds the Grok row at notional list price"
						: "Adds a Cursor stop hook · agent turns feed the Grok row"
				}
				on={cursorHook}
				onToggle={() => setCursorHook((v) => !v)}
			/>
			<ToggleRow
				icon="gauge.with.dots.needle.33percent"
				providerMark={{ icon: PROVIDERS.openCodeGo.icon, color: PROVIDERS.openCodeGo.color }}
				title="OpenCode Go"
				subtitle={
					openCodeGoEnabled
						? "Gateway view · not in totals or alerts · measured 5-hour & weekly usage vs Go's caps"
						: "Go section hidden from the OpenCode row & widget"
				}
				on={openCodeGoEnabled}
				onToggle={() => setOpenCodeGoEnabled((v) => !v)}
			/>
		</Section>
	);
}

function JPFaceActionRow({
	title,
	subtitle,
	onClick,
}: {
	title: string;
	subtitle?: string;
	onClick: () => void;
}) {
	return (
		<div className="flex items-center gap-2.5 px-2.5 py-2">
			<span className="w-[18px] shrink-0 text-ink-soft">
				<Icon name="play" />
			</span>
			<span className="min-w-0 flex-1">
				<span className="block font-semibold text-[13px] text-ink">{title}</span>
				{subtitle ? <span className="demo-caption block truncate">{subtitle}</span> : null}
			</span>
			<button
				type="button"
				onClick={onClick}
				aria-label="Test meow"
				title="Test meow"
				className="grid h-[26px] w-[26px] shrink-0 place-items-center overflow-hidden rounded-full ring-1 ring-line-strong/65 transition hover:scale-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
			>
				<BrandMark size={26} className="h-[26px] w-[26px] scale-[1.18] object-cover" />
			</button>
		</div>
	);
}
