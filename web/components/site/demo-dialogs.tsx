"use client";

import dynamic from "next/dynamic";
import Image from "next/image";
import { type CSSProperties, useEffect, useId, useRef } from "react";
import { trapDialogTab } from "@/lib/dialog-focus-trap";
import { SHARE_DESTINATIONS } from "@/lib/share";
import { useCopyLink } from "@/lib/share-copy";
import { BrandMark } from "./brand";
import { Icon } from "./icon";

// [NOTE] `advanced-analytics-demo` is ~1k lines and is unreachable until a visitor clicks the demo
// card's chart button, so a static import would park it in the homepage first-load JS for everyone.
// `menubar-demo.tsx` already renders `AdvancedAnalyticsPopup` only while `advancedAnalyticsOpen` is
// true, making this a pure conditional-render payload. `ssr: false` because the tray is a native
// `<dialog>` opened from a client-only interaction and has no server-rendered form.
const AdvancedAnalyticsDemo = dynamic(
	() => import("./advanced-analytics-demo").then((m) => m.AdvancedAnalyticsDemo),
	{ ssr: false },
);

// The demo card's modal popups, extracted from `menubar-demo.tsx` so that ~2k-line file stays focused
// on the card/chrome/model-math. Each dialog is a real top-layer `<dialog>` (native Esc + focus trap +
// backdrop) and carries its own dark theme vars so it matches the card it opened from. Parity guard:
// `scripts/verify-app-demo-parity.sh` scans THIS file (plus `menubar-demo.tsx`) for the widget-gallery
// explanation copy.

export function SharePopup({
	onClose,
	onDestinationClick,
}: {
	onClose: () => void;
	/** Plays the demo's soft "bottom click" cue on each share destination / copy tap (kept in the parent
	 * so the whole audio subsystem stays in `menubar-demo.tsx`). */
	onDestinationClick?: () => void;
}) {
	const titleId = useId();
	const descId = useId();
	const dialogRef = useRef<HTMLDialogElement>(null);
	const { copied, copyLink } = useCopyLink();

	useEffect(() => {
		const dialog = dialogRef.current;
		dialog?.showModal();
		dialog?.querySelector<HTMLElement>("a, button")?.focus();
		return () => dialog?.close();
	}, []);

	return (
		<dialog
			ref={dialogRef}
			aria-labelledby={titleId}
			aria-describedby={descId}
			onClose={onClose}
			onClick={(e) => {
				if (e.target === dialogRef.current) dialogRef.current?.close();
			}}
			onKeyDown={trapDialogTab}
			className="dialog-panel dialog-panel-sm p-4"
		>
			<div className="flex items-start gap-3">
				<BrandMark size={34} className="h-[34px] w-[34px] shrink-0 rounded-[8px]" />
				<div className="min-w-0 flex-1">
					<h3 id={titleId} className="ui-title">
						Tell others about JP
					</h3>
					<p id={descId} className="demo-caption mt-0.5">
						Share the cute and useful token cat!
					</p>
				</div>
				<form method="dialog" className="shrink-0">
					<button
						type="submit"
						aria-label="Close share dialog"
						className="grid h-7 w-7 place-items-center rounded-lg border border-line bg-paper text-[16px] leading-none text-ink-soft transition-colors hover:border-ginger hover:text-ginger-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
					>
						×
					</button>
				</form>
			</div>
			<div className="mt-3.5 grid grid-cols-2 gap-1.5">
				{SHARE_DESTINATIONS.map((destination) => (
					<a
						key={destination.id}
						href={destination.href}
						target={destination.href.startsWith("mailto:") ? undefined : "_blank"}
						rel={destination.href.startsWith("mailto:") ? undefined : "noopener noreferrer"}
						onClick={() => onDestinationClick?.()}
						aria-label={destination.description}
						className="group flex items-center gap-2.5 rounded-[8px] border border-line/35 bg-paper/70 px-2.5 py-2 text-left transition hover:border-ginger/45 hover:bg-honey/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
					>
						<Icon name={destination.icon} className="h-[18px] w-[18px] shrink-0 text-ginger-deep" />
						<span className="ui-item-copy min-w-0 flex-1">{destination.label}</span>
						<Icon
							name="arrow-up-right"
							className="h-[12px] w-[12px] shrink-0 text-ink-faint transition group-hover:text-ginger-deep"
						/>
					</a>
				))}
				<button
					type="button"
					onClick={() => {
						onDestinationClick?.();
						void copyLink();
					}}
					aria-label="Put jpthecat.com on the clipboard"
					className="flex w-full items-center gap-2.5 rounded-[8px] border border-line/35 bg-paper/70 px-2.5 py-2 text-left transition hover:border-ginger/45 hover:bg-honey/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
				>
					<Icon
						name={copied ? "check" : "link"}
						className={`h-[18px] w-[18px] shrink-0 ${copied ? "text-sage-deep" : "text-ginger-deep"}`}
					/>
					<span className="ui-item-copy min-w-0 flex-1">
						{copied ? "Copied link" : "Copy link"}
					</span>
				</button>
			</div>
		</dialog>
	);
}

/** Mirrors the app's JP-branded WidgetGalleryOpener alert (mascot + 3 numbered steps + "Got it"). */
const WIDGET_STEPS = [
	"Right-click your desktop (or open Notification Center) and choose “Edit Widgets”.",
	"Search “JP the Cat”.",
	"Drag the Small, Medium, or Large size into place.",
];

export function WidgetPopup({
	themeStyle,
	onClose,
}: {
	themeStyle: CSSProperties | undefined;
	onClose: () => void;
}) {
	const titleId = useId();
	const descId = useId();
	const dialogRef = useRef<HTMLDialogElement>(null);

	// Open as a real top-layer modal on mount (native Esc + focus trap + backdrop), close on dismiss.
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
			aria-describedby={descId}
			onClose={onClose}
			onClick={(e) => {
				if (e.target === dialogRef.current) dialogRef.current?.close();
			}}
			onKeyDown={trapDialogTab}
			// The dialog carries its own theme vars so the JP-branded alert matches the card it opened from.
			style={themeStyle}
			className="dialog-panel dialog-panel-sm p-4"
		>
			<div className="flex items-start gap-3">
				<BrandMark size={34} className="h-[34px] w-[34px] shrink-0 rounded-[8px]" />
				<div className="min-w-0">
					<h3 id={titleId} className="ui-title">
						Add the JP the Cat widget
					</h3>
					<p id={descId} className="demo-caption mt-0.5">
						macOS doesn't let apps open the widget gallery, so add it the standard way:
					</p>
				</div>
			</div>
			<ol className="mt-3.5 space-y-2.5">
				{WIDGET_STEPS.map((s, i) => (
					<li key={s} className="flex items-start gap-2.5">
						<span className="tnum grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full border border-line-strong bg-track font-semibold text-[11px] text-ginger-deep">
							{i + 1}
						</span>
						<span className="text-[12px] text-ink leading-snug">{s}</span>
					</li>
				))}
			</ol>
			<form method="dialog" className="mt-4 flex justify-end">
				<button
					type="submit"
					className="rounded-[9px] border border-line-strong bg-paper-2 px-3.5 py-1.5 font-semibold text-[12px] text-ink transition hover:border-ginger hover:text-ginger-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
				>
					Got it
				</button>
			</form>
		</dialog>
	);
}

export function AdvancedAnalyticsPopup({
	themeStyle,
	onClose,
}: {
	themeStyle: CSSProperties | undefined;
	onClose: () => void;
}) {
	return <AdvancedAnalyticsDemo style={themeStyle} onClose={onClose} />;
}

export function SupportReportPopup({
	themeStyle,
	onClose,
}: {
	themeStyle: CSSProperties | undefined;
	onClose: () => void;
}) {
	const titleId = useId();
	const descId = useId();
	const dialogRef = useRef<HTMLDialogElement>(null);

	useEffect(() => {
		const dialog = dialogRef.current;
		dialog?.showModal();
		dialog?.querySelector<HTMLInputElement>("input")?.focus();
		return () => dialog?.close();
	}, []);

	return (
		<dialog
			ref={dialogRef}
			aria-labelledby={titleId}
			aria-describedby={descId}
			onClose={onClose}
			onClick={(e) => {
				if (e.target === dialogRef.current) onClose();
			}}
			onKeyDown={trapDialogTab}
			style={themeStyle}
			className="dialog-panel dialog-panel-lg p-4"
		>
			<div className="flex items-start gap-2.5">
				<Image
					src="/jpthecat-logo.png"
					alt=""
					width={40}
					height={40}
					className="rounded-[9px]"
					unoptimized
				/>
				<div>
					<h3 id={titleId} className="ui-title">
						Send a support report
					</h3>
					<p id={descId} className="ui-copy mt-0.5">
						JP will email support@JPtheCat.com with a report.
					</p>
				</div>
			</div>
			<div className="mt-3 space-y-2">
				<label className="block">
					<span className="ui-label mb-1 block">Your email (optional)</span>
					<input readOnly placeholder="you@example.com" className="compact-field" />
				</label>
				<label className="block">
					<span className="ui-label mb-1 block">What happened? (optional)</span>
					<textarea
						readOnly
						placeholder="Add context if you want."
						className="compact-field h-16 resize-none"
					/>
				</label>
				<div className="rounded-[8px] border border-line bg-paper/75 p-2 font-mono text-[10px] text-ink-soft leading-snug">
					JP the Cat support report
					<br />
					Privacy: No request text, code, conversation logs, token payloads, secrets, or raw file
					paths are included.
				</div>
			</div>
			<div className="mt-3.5 flex justify-end gap-2">
				<button
					type="button"
					onClick={onClose}
					className="compact-action border border-line text-ink-soft hover:bg-paper-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
				>
					Cancel
				</button>
				<button
					type="button"
					onClick={onClose}
					className="compact-action hover:brightness-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ginger/45"
					style={{
						background: "linear-gradient(180deg, var(--color-cta), var(--color-cta-deep))",
						color: "var(--color-cta-text)",
					}}
				>
					Send
				</button>
			</div>
		</dialog>
	);
}
