"use client";

import { type ReactNode, useRef, useState } from "react";
import { createPortal } from "react-dom";

/**
 * A native `title` attribute renders clipped inside an `overflow-hidden` ancestor in some browser
 * engines (the demo card needs `overflow-hidden` for its rounded ledger-paper background) — this
 * portals the tooltip to `document.body` with fixed positioning so it always escapes the card.
 */
export function Tooltip({ label, children }: { label: string; children: ReactNode }) {
	const [pos, setPos] = useState<{ top: number; left: number } | null>(null);
	const wrapRef = useRef<HTMLSpanElement>(null);

	function show() {
		const rect = wrapRef.current?.getBoundingClientRect();
		if (!rect) return;
		setPos({ top: rect.top - 6, left: rect.left + rect.width / 2 });
	}
	function hide() {
		setPos(null);
	}

	return (
		// biome-ignore lint/a11y/noStaticElementInteractions: layout wrapper only, watching hover/focus bubbling from the interactive child button
		<span
			ref={wrapRef}
			className="inline-flex"
			onMouseEnter={show}
			onMouseLeave={hide}
			onFocus={show}
			onBlur={hide}
		>
			{children}
			{pos && typeof document !== "undefined"
				? createPortal(
						<span
							role="tooltip"
							className="pointer-events-none fixed z-[999] -translate-x-1/2 -translate-y-full whitespace-nowrap rounded-[7px] border border-line bg-ink px-2 py-1 font-medium text-[11px] text-paper shadow-[var(--shadow-pop)]"
							style={{ top: pos.top, left: pos.left }}
						>
							{label}
						</span>,
						document.body,
					)
				: null}
		</span>
	);
}
