// Sunlit Ledger — shared brand tokens for every JP the Cat email.
// Hex values mirror web/app/globals.css (--color-*). Keep them in sync when the
// site palette changes. Tokens are consumed by emails/admin-email-shell.tsx, the
// spartan "Owner Ledger" for owner/admin notices: no decoration, issues first.
//
// Bright gold (#fdcd2d) is JP's MASCOT ART ONLY and is deliberately unused as a UI
// surface, bar, or fill. Warm accents are the homepage `honey -> ginger` gradient
// and cream/ginger washes; the CTA is ginger-deep. Email HTML has no `color-mix`,
// so every chip surface here is a SOLID hex, each verified for WCAG AA.

export const emailColors = {
	// Paper + panels (the cream "ledger paper" of the homepage).
	paper: "#faf6ec",
	paper2: "#f4ecda",
	card: "#fffdf7",
	cream: "#fff8e6",
	creamDeep: "#ecdcbd",
	white: "#ffffff",
	// Ink text ramp.
	ink: "#221d15",
	soft: "#665b4c", // 6.4:1 on card, 6.3:1 on cream — AA for body + captions.
	softest: "#756a55", // 5.6:1 on card — still AA for small supporting text.
	// Hairlines / ledger rules.
	line: "#e8ddc7",
	lineStrong: "#d9ccae",
	// Warm accents (homepage gauge gradient + CTA).
	ginger: "#df7a2e",
	gingerDeep: "#a84f16", // CTA / strong labels. #fff8ee on this is AA.
	honey: "#edb454",
	// Trust green (the app's `official` badge / receipt "verified" language).
	sage: "#3c7852",
	sageDeep: "#2f6042",
	// Attention (the app's "near or over limit" status). Admin emails use it ONLY for the
	// issue block, so an alert reads as an alert and nothing else does.
	coral: "#c1422a", // 6.3:1 on coralWash.
	coralWash: "#f9eae3", // ~10% coral over card, pre-mixed.
	coralLine: "#efcec4", // ~25% coral over card, the issue block's hairline.
	// Off-white CTA label — 5.25:1 on gingerDeep, warmer than pure white.
	ctaText: "#fff8ee",
	// Mascot art ONLY. Never a UI surface — kept out of chrome on purpose so the
	// design can never regress into a bright-gold block (guarded by tests).
	gold: "#fdcd2d",
	// Solid chip surfaces (email HTML has no color-mix; each is a pre-mixed wash).
	sageChip: "#e4efe7", // sageDeep text = 6.1:1.
	sageChipBorder: "#cfe1d4", // hairline around the sage status chip (one step deeper than sageChip).
	honeyChip: "#fbeccb", // gingerDeep text = 4.7:1.
	gingerWash: "#f8e1cf", // gingerDeep text = 4.8:1.
	// Warm ledger drop-shadow tint — the same ink brown as the homepage --shadow-* family
	// (rgba(96, 64, 22, …)); email HTML can't reference the CSS var, so the sheet shadow reads it here.
	sheetShadow: "0 20px 54px rgba(96, 64, 22, 0.12)",
};

// Radii mirror web/app/globals.css --radius-* (parity-tested), so admin mail never
// invents a corner of its own.
export const emailRadius = {
	card: "18px", // --radius-card: the outer sheet.
	compact: "9px", // --radius-compact: panels inside the sheet.
};

export const emailFonts = {
	// Body — Hanken Grotesk (homepage body face) named first, system fallback so the
	// layout is stable when Gmail/Outlook lack the webfont.
	sans: '"Hanken Grotesk", -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif',
	// Display — Fraunces (homepage headline serif); Georgia carries the same warm,
	// high-contrast serif voice when Fraunces is absent.
	serif: 'Fraunces, Georgia, "Iowan Old Style", "Times New Roman", serif',
	// Numbers / ledger — JetBrains Mono (the app's tabular figures) -> ui-monospace.
	mono: '"JetBrains Mono", ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace',
};
