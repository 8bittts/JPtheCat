/**
 * The shared stroked-glyph registry — one 24×24, `strokeWidth={1.7}`, round-cap line-icon set used
 * by the homepage menu-bar demo chrome. It previously
 * hand-rolled byte-identical copies of the same paths; this is the single source of truth. Unknown
 * names fall back to a plain circle. (The Advanced Analytics close-X is a separate 16×16 glyph and
 * is intentionally NOT part of this set.)
 */
import type { ReactNode } from "react";

const GLYPHS: Record<string, ReactNode> = {
	gear: (
		<>
			<circle cx="12" cy="12" r="3.1" />
			<path d="M19.4 13a7.5 7.5 0 0 0 0-2l2-1.5-2-3.5-2.4 1a7.5 7.5 0 0 0-1.7-1L14 3h-4l-.6 2.5a7.5 7.5 0 0 0-1.7 1l-2.4-1-2 3.5 2 1.5a7.5 7.5 0 0 0 0 2l-2 1.5 2 3.5 2.4-1a7.5 7.5 0 0 0 1.7 1L10 21h4l.6-2.5a7.5 7.5 0 0 0 1.7-1l2.4 1 2-3.5-2-1.5Z" />
		</>
	),
	pin: (
		<>
			<path d="M9 3h6l-1 6 3 3v2H7v-2l3-3-1-6ZM12 14v7" />
		</>
	),
	gauge: (
		<>
			<path d="M4 15a8 8 0 0 1 16 0" />
			<path d="M12 15l4-3.5" />
			<circle cx="12" cy="15" r="1.2" fill="currentColor" stroke="none" />
		</>
	),
	grid: (
		<>
			<rect x="4" y="4" width="7" height="7" rx="1.6" />
			<rect x="13" y="4" width="7" height="7" rx="1.6" />
			<rect x="4" y="13" width="7" height="7" rx="1.6" />
			<rect x="13" y="13" width="7" height="7" rx="1.6" />
		</>
	),
	moon: (
		<>
			<path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5Z" />
		</>
	),
	sun: (
		<>
			<circle cx="12" cy="12" r="4" />
			<path d="M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.5 4.5l1.8 1.8M17.7 17.7l1.8 1.8M19.5 4.5l-1.8 1.8M6.3 17.7l-1.8 1.8" />
		</>
	),
	refresh: (
		<>
			<path d="M20 8a8 8 0 1 0 1 5M20 3v5h-5" />
		</>
	),
	download: (
		<>
			<path d="M12 3v10" />
			<path d="M8 11l4 4 4-4" />
			<path d="M5 19h14" />
		</>
	),
	globe: (
		<>
			<circle cx="12" cy="12" r="9" />
			<path d="M3 12h18M12 3c2.7 3 2.7 15 0 18M12 3c-2.7 3-2.7 15 0 18" />
		</>
	),
	help: (
		<>
			<circle cx="12" cy="12" r="9" />
			<path d="M9.7 9a2.4 2.4 0 0 1 4.6 1c0 1.8-2.3 2.1-2.3 4" />
			<path d="M12 17h.01" />
		</>
	),
	window: (
		<>
			<rect x="3" y="5" width="18" height="14" rx="2" />
			<path d="M3 9h18" />
		</>
	),
	menubar: (
		<>
			<rect x="3" y="5" width="18" height="14" rx="2" />
			<path d="M3 9h18" />
			<path d="M6 7h2" />
		</>
	),
	power: (
		<>
			<path d="M12 3v9" />
			<path d="M6.5 7a8 8 0 1 0 11 0" />
		</>
	),
	seal: (
		<>
			<path d="M12 2.5l2.4 1.8 3-.2 1 2.8 2.4 1.8-.9 2.9.9 2.9-2.4 1.8-1 2.8-3-.2L12 21.5l-2.4-1.8-3 .2-1-2.8L3.2 15.3l.9-2.9-.9-2.9 2.4-1.8 1-2.8 3 .2Z" />
			<path d="M9 12l2 2 4-4" />
		</>
	),
	bell: (
		<>
			<path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6ZM10 20a2 2 0 0 0 4 0" />
		</>
	),
	"chevron-right": (
		<>
			<path d="M9 6l6 6-6 6" />
		</>
	),
	chart: (
		<>
			<rect x="4" y="4" width="16" height="16" rx="2" />
			<path d="M8 15v-3M12 15V9M16 15v-5" />
		</>
	),
	lock: (
		<>
			<rect x="5" y="11" width="14" height="9" rx="1.6" />
			<path d="M8 11V8a4 4 0 0 1 8 0v3" />
		</>
	),
	badge: (
		<>
			<rect x="3" y="5" width="18" height="14" rx="2" />
			<circle cx="18" cy="7" r="3" fill="currentColor" stroke="none" />
		</>
	),
	speaker: (
		<>
			<path d="M4 9v6h3l5 4V5L7 9H4Z" />
			<path d="M15.5 9a4 4 0 0 1 0 6" />
		</>
	),
	play: (
		<>
			<circle cx="12" cy="12" r="9" />
			<path d="M10 8.5l6 3.5-6 3.5v-7Z" fill="currentColor" stroke="none" />
		</>
	),
	shield: (
		<>
			<path d="M12 3l7 3v5c0 5-3.5 8-7 10-3.5-2-7-5-7-10V6l7-3Z" />
			<path d="M9 12l2 2 4-4" />
		</>
	),
	quit: (
		<>
			<path d="M12 3v9" />
			<path d="M6.5 7a8 8 0 1 0 11 0" />
		</>
	),
	chevron: (
		<>
			<path d="M9 6l6 6-6 6" />
		</>
	),
	"chevron-down": (
		<>
			<path d="M6 9l6 6 6-6" />
		</>
	),
	bubbles: (
		<>
			<path d="M7 15.5 4 18v-3.5a6 6 0 1 1 3 1Z" />
			<path d="M14 6.5a5 5 0 0 1 3 9l3 2v-3a5 5 0 0 0-2-9.5" />
		</>
	),
	people: (
		<>
			<circle cx="9" cy="8" r="3" />
			<path d="M3.5 19a5.5 5.5 0 0 1 11 0" />
			<path d="M15 6.5a3 3 0 0 1 0 5.5M17 14a5 5 0 0 1 3.5 5" />
		</>
	),
	briefcase: (
		<>
			<rect x="3" y="7" width="18" height="12" rx="2" />
			<path d="M9 7V5h6v2M3 12h18" />
		</>
	),
	"text-bubble": (
		<>
			<path d="M5 17.5 3.5 21l4-2H18a3 3 0 0 0 3-3V7a3 3 0 0 0-3-3H6a3 3 0 0 0-3 3v7.5a3 3 0 0 0 2 3Z" />
			<path d="M8 9h8M8 13h5" />
		</>
	),
	mail: (
		<>
			<rect x="3" y="5" width="18" height="14" rx="2" />
			<path d="m4 7 8 6 8-6" />
		</>
	),
	link: (
		<>
			<path d="M10 13a5 5 0 0 0 7.1 0l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1" />
			<path d="M14 11a5 5 0 0 0-7.1 0l-2 2a5 5 0 0 0 7.1 7.1l1.1-1.1" />
		</>
	),
	check: (
		<>
			<path d="M5 13l4 4L19 7" />
		</>
	),
	"arrow-up-right": (
		<>
			<path d="M7 17 17 7M9 7h8v8" />
		</>
	),
	terminal: (
		<>
			<rect x="3" y="4" width="18" height="16" rx="2" />
			<path d="M7 9l3 3-3 3M13 15h4" />
		</>
	),
	braces: (
		<>
			<path d="M8 4c-2 0-2.5 1-2.5 3v3c0 1-.5 2-1.5 2 1 0 1.5 1 1.5 2v3c0 2 .5 3 2.5 3M16 4c2 0 2.5 1 2.5 3v3c0 1 .5 2 1.5 2-1 0-1.5 1-1.5 2v3c0 2-.5 3-2.5 3" />
		</>
	),
	sparkles: (
		<>
			<path d="M12 3l1.2 3.6L17 8l-3.8 1.4L12 13l-1.2-3.6L7 8l3.8-1.4L12 3Z" />
			<path d="M18.5 13.5l.7 2.1 2.1.7-2.1.7-.7 2.1-.7-2.1-2.1-.7 2.1-.7.7-2.1Z" />
			<path d="M6 14.5l.55 1.65L8.2 16.7l-1.65.55L6 18.9l-.55-1.65L3.8 16.7l1.65-.55L6 14.5Z" />
		</>
	),
	// Mirrors the native "More themes" tile glyph (SF Symbol `paintpalette`).
	palette: (
		<>
			<path d="M12 3a9 8 0 0 0 0 16c1.4 0 2-1 2-2s-.6-2 .5-2H16a3 3 0 0 0 3-3c0-4-3-7-7-7Z" />
			<circle cx="8" cy="10" r="1" fill="currentColor" stroke="none" />
			<circle cx="12" cy="7.5" r="1" fill="currentColor" stroke="none" />
			<circle cx="15.5" cy="10" r="1" fill="currentColor" stroke="none" />
		</>
	),
	// Copilot's provider glyph — mirrors the native `chevron.left.forwardslash.chevron.right`.
	code: <path d="M9 8l-4 4 4 4M15 8l4 4-4 4M13.5 6l-3 12" />,
};

export function Icon({
	name,
	className = "h-[15px] w-[15px]",
}: {
	name: string;
	className?: string;
}) {
	const p = GLYPHS[name] ?? <circle cx="12" cy="12" r="8" />;
	return (
		<svg
			viewBox="0 0 24 24"
			className={className}
			fill="none"
			stroke="currentColor"
			strokeWidth="1.7"
			strokeLinecap="round"
			strokeLinejoin="round"
			aria-hidden="true"
		>
			{p}
		</svg>
	);
}
