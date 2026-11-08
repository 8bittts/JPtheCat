"use client";

import Image from "next/image";
import { type ReactNode, useState } from "react";
import { RELEASE } from "@/lib/release";
import { SITE } from "@/lib/site";
import { BrandMark } from "./brand";
import { SharePopup } from "./demo-dialogs";
import { Icon } from "./icon";
import { playBottomClick, playToggleSound, playTopClick } from "./menubar-demo-audio";
import { Tooltip } from "./tooltip";

// The chrome shared by BOTH demo faces (dashboard and settings): the top control cluster, the shared
// card footer, and the settings-row primitives. Extracted from `menubar-demo.tsx` so neither face
// re-declares them and so the two can never drift. Exports components ONLY (Fast Refresh /
// react-doctor `only-export-components`); the audio cues live in `menubar-demo-audio.ts` and the
// menu-bar display cycle in `menubar-demo-format.ts`.

const APP_VERSION = `v${RELEASE.version}`;

// ── Top chrome ─────────────────────────────────────────────────────────────────────────────────

/** Icon-only chrome control chip — mirrors the app's SettingsLink/PinButton/WidgetGalleryButton. */
export function ChromeButton({
	label,
	active,
	tone = "neutral",
	onClick,
	children,
}: {
	label: string;
	active?: boolean;
	tone?: "neutral" | "sage";
	onClick: () => void;
	children: ReactNode;
}) {
	const activeChip =
		tone === "sage"
			? "bg-sage/16 text-sage-deep ring-1 ring-sage/34"
			: "bg-paper-2/70 text-ginger-deep ring-1 ring-line-strong";
	return (
		<Tooltip label={label}>
			<button
				type="button"
				onClick={() => {
					playTopClick();
					onClick();
				}}
				aria-label={label}
				aria-pressed={active}
				className={`grid h-[26px] w-[26px] place-items-center rounded-[7px] text-ink-soft transition hover:bg-paper-2/70 hover:text-ginger-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45 ${
					active ? activeChip : "ring-1 ring-transparent"
				}`}
			>
				{children}
			</button>
		</Tooltip>
	);
}

// Small green "on air" light for the top-right chrome cluster that gently/slowly pulses while the
// menu-bar pill is on a rotating display format, and collapses to nothing otherwise. The native twin
// is `RotationIndicatorLight`; the pulse honors reduced-motion (steady light, no blink).
export function RotationLight({ active }: { active: boolean }) {
	if (!active) return null;
	return (
		<span
			aria-hidden="true"
			title="Menu bar is rotating through providers"
			className="mr-0.5 inline-block size-[7px] rounded-full bg-sage shadow-[0_0_4px_var(--color-sage)] animate-pulse motion-reduce:animate-none"
		/>
	);
}

export function ChromeBar({ children }: { children: ReactNode }) {
	return (
		<div className="flex h-8 items-center gap-2 bg-card pr-3.5 pl-4">
			<span className="font-semibold text-[13px] text-ink leading-none">JP the Cat 🐾</span>
			<span className="ml-auto flex items-center gap-1">{children}</span>
		</div>
	);
}

// ── Settings-row primitives (also used by the Live Data popup) ─────────────────────────────────

export function Section({ title, children }: { title: string; children: ReactNode }) {
	return (
		<div className="space-y-1.5">
			{/* No eyebrow when title is empty — the Live Data popup's chrome already says "Live data". */}
			{title ? <div className="demo-eyebrow !text-ink-faint">{title.toUpperCase()}</div> : null}
			<div className="divide-y divide-line/70 overflow-hidden rounded-[10px] border border-line/85 bg-paper/70">
				{children}
			</div>
		</div>
	);
}

export function ToggleRow({
	icon,
	title,
	subtitle,
	on,
	onToggle,
	providerMark,
}: {
	icon: string;
	title: string;
	subtitle?: string;
	on: boolean;
	onToggle: () => void;
	// When set, render the provider's real brand-mark chip (white `/provider-icons/*.svg` glyph on the
	// brand tint) instead of the stroked `Icon` — mirrors the native Live Data window's provider chips
	// and the dashboard selector. `undefined` keeps the plain glyph for every other toggle.
	providerMark?: { icon: string; color: string };
}) {
	return (
		<div className="flex items-center gap-2.5 px-2.5 py-2">
			{providerMark ? (
				// Decorative provider brand-mark chip — the interactive target in this row is the Switch
				// (h-6 w-10). Kept at the 18px row-icon house size and, unlike an interactive control, WITHOUT
				// a shrink lock (matching the other decorative 18px chip in this file) so it stays clear of the
				// WCAG 2.2 target-size guard in site-copy.test.ts (which forbids the shrink-locked 18px grid
				// signature on INTERACTIVE controls); the min-w-0 flex-1 title sibling absorbs any flex shrink,
				// so the chip holds 18px in practice.
				<span
					aria-hidden="true"
					className="grid h-[18px] w-[18px] place-items-center rounded-[5px] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.22)]"
					style={{ background: providerMark.color }}
				>
					<Image
						src={providerMark.icon}
						alt=""
						width={12}
						height={12}
						className="h-3 w-3 object-contain"
						unoptimized
					/>
				</span>
			) : (
				<span className="w-[18px] shrink-0 text-ink-soft">
					<Icon name={icon} />
				</span>
			)}
			<span className="min-w-0 flex-1">
				<span className="block font-semibold text-[13px] text-ink">{title}</span>
				{subtitle ? <span className="demo-caption block">{subtitle}</span> : null}
			</span>
			<Switch on={on} label={title} onToggle={onToggle} />
		</div>
	);
}

/** A tap-to-cycle settings row (mirrors the app's cycle rows like "Menu bar display"/"Refresh rate"). */
export function CycleRow({
	icon,
	title,
	subtitle,
	onCycle,
}: {
	icon: string;
	title: string;
	subtitle: string;
	onCycle: () => void;
}) {
	return (
		<button
			type="button"
			onClick={() => {
				playTopClick();
				onCycle();
			}}
			className="flex w-full items-center gap-2.5 px-2.5 py-2 text-left transition hover:bg-paper-2/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
		>
			<span className="w-[18px] shrink-0 text-ink-soft">
				<Icon name={icon} />
			</span>
			<span className="min-w-0 flex-1">
				<span className="block font-semibold text-[13px] text-ink">{title}</span>
				<span className="demo-caption block">{subtitle}</span>
			</span>
			<Icon name="chevron" className="h-[13px] w-[13px] shrink-0 text-ink-faint" />
		</button>
	);
}

/** The toggle itself. Deliberately NOT exported — every caller goes through `ToggleRow`, so the
 *  switch geometry (`relative h-6 w-10 shrink-0`, pinned by tests/site-copy.test.ts for WCAG 2.2
 *  target size) has exactly one definition. */
function Switch({ on, label, onToggle }: { on: boolean; label: string; onToggle: () => void }) {
	return (
		<button
			type="button"
			role="switch"
			aria-checked={on}
			aria-label={label}
			onClick={() => {
				playToggleSound(!on);
				onToggle();
			}}
			className="relative h-6 w-10 shrink-0 rounded-full ring-1 ring-transparent transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
			style={{ background: on ? "var(--color-ginger)" : "var(--color-line-strong)" }}
		>
			<span
				className={`absolute top-[3px] left-[3px] h-[18px] w-[18px] rounded-full bg-white shadow-sm transition-transform ${on ? "translate-x-4" : "translate-x-0"}`}
			/>
		</button>
	);
}

// ── Shared footer ──────────────────────────────────────────────────────────────────────────────

// Social-share copy + destinations live in one place (`@/lib/share`) for the demo,
// action row, so the two can't drift.

/** Mirrors the app's `UpdateStatusDot`. */
export function UpdateDotButton() {
	const [updateChecks, setUpdateChecks] = useState(0);
	const title =
		updateChecks > 0
			? `${APP_VERSION} · up to date — checked just now`
			: `${APP_VERSION} · up to date — click to check`;
	const label =
		updateChecks > 0
			? `Version ${APP_VERSION}, up to date, checked just now`
			: `Version ${APP_VERSION}, up to date`;
	return (
		<Tooltip label={title}>
			<button
				type="button"
				onClick={() => {
					playBottomClick();
					setUpdateChecks((v) => v + 1);
				}}
				className="grid h-6 w-6 shrink-0 place-items-center rounded-full transition hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
				aria-label={label}
			>
				<span
					className="h-[9px] w-[9px] rounded-full ring-1 ring-ink/10"
					style={{ background: "var(--color-sage)" }}
				/>
			</button>
		</Tooltip>
	);
}

export function CardFooter({
	leadingText,
	onRefresh,
	onOpenAdvancedAnalytics,
	accessory,
}: {
	leadingText: string;
	onRefresh: () => void;
	onOpenAdvancedAnalytics?: () => void;
	accessory?: ReactNode;
}) {
	const [shareOpen, setShareOpen] = useState(false);
	return (
		<div className="mt-1 flex items-center gap-2 border-line border-t bg-paper-2/50 px-[18px] py-2.5">
			<span className="min-w-0 flex-1 truncate demo-caption !text-ink-soft">{leadingText}</span>
			<button
				type="button"
				aria-label="Refresh now"
				title="Refresh now"
				onClick={() => {
					playBottomClick();
					onRefresh();
				}}
				className="grid h-6 w-6 shrink-0 place-items-center text-ink-soft transition hover:text-ginger-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
			>
				<Icon name="refresh" />
			</button>
			{onOpenAdvancedAnalytics ? (
				<button
					type="button"
					aria-label="Advanced Analytics"
					title="Advanced Analytics"
					onClick={() => {
						playBottomClick();
						onOpenAdvancedAnalytics();
					}}
					className="grid h-6 w-6 shrink-0 place-items-center text-ink-soft transition hover:text-ginger-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
				>
					<Icon name="chart" />
				</button>
			) : null}
			<a
				href={SITE.url}
				aria-label="Open JP the Cat website"
				title="Open JP the Cat website"
				target="_blank"
				rel="noopener noreferrer"
				onClick={() => playBottomClick()}
				className="grid h-6 w-6 shrink-0 place-items-center text-ink-soft transition hover:text-ginger-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
			>
				<Icon name="help" />
			</a>
			{accessory}
			{/* Quit sits immediately before the JP mark, not between Refresh and Help — matches the
			    native DashboardCardFooter's ordering (DashboardView.swift). */}
			<button
				type="button"
				aria-label="Quit JP the Cat"
				title="Quit JP the Cat"
				onClick={() => playBottomClick()}
				className="grid h-6 w-6 shrink-0 place-items-center text-ginger-deep transition hover:text-ginger-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
			>
				<Icon name="quit" />
			</button>
			<button
				type="button"
				aria-label="Tell others about JP"
				title="Tell others about JP"
				onClick={() => {
					playBottomClick();
					setShareOpen(true);
				}}
				className="grid h-6 w-6 shrink-0 place-items-center rounded-[5px] transition hover:ring-1 hover:ring-ginger/55 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
			>
				<BrandMark size={18} className="h-[18px] w-[18px] rounded-[5px]" />
			</button>
			{shareOpen ? (
				<SharePopup onClose={() => setShareOpen(false)} onDestinationClick={playBottomClick} />
			) : null}
		</div>
	);
}
