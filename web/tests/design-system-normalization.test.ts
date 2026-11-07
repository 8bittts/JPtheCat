import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Glob } from "bun";
import { emailColors, emailRadius } from "@/emails/email-styles";

const root = join(import.meta.dir, "..");
const css = readFileSync(join(root, "app/globals.css"), "utf8");

function cssColor(name: string): string {
	const match = css.match(new RegExp(`--color-${name}:\\s*(#[0-9a-fA-F]{6})`));
	expect(match, `missing --color-${name}`).not.toBeNull();
	return match?.[1].toLowerCase() ?? "";
}

const SOURCE_GLOBS = [
	"app/**/*.{ts,tsx}",
	"components/**/*.{ts,tsx}",
	"lib/**/*.{ts,tsx}",
	"emails/**/*.{ts,tsx}",
];
const COLOR_UTILITY =
	/(?<![\w-])(?:[a-z0-9-]+:)*!?(?:bg|text|border|ring|outline|fill|stroke|from|via|to|decoration|divide|placeholder|caret|accent|shadow)(?:-[trblxy]{1,2})?-([a-z][a-z0-9-]*?)(?:\/(?:\d+|\[[^\]]+\]))?(?=[\s"'`}]|$)/g;
const PALETTE_NAME =
	/^(?:(?:ink|paper|card|line|ginger|honey|gold|sage|coral|cta|cream|track)(?:-|$)|p-)/;
const DEFAULT_PALETTE =
	/^(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\d{2,3}$/;

/** Palette-shaped utilities and `var(--color-*)` references in one file that name no defined token. */
function colorTokenProblems(file: string, source: string, defined: Set<string>): string[] {
	const utilityProblems = [...source.matchAll(COLOR_UTILITY)].flatMap((match) => {
		const name = match[1] ?? "";
		if (DEFAULT_PALETTE.test(name)) return [`${file}: ${match[0]} (default palette)`];
		return PALETTE_NAME.test(name) && !defined.has(name) ? [`${file}: ${match[0]}`] : [];
	});
	const variableProblems = [...source.matchAll(/var\(--color-([a-z0-9-]+)/g)].flatMap((match) =>
		defined.has(match[1] ?? "") ? [] : [`${file}: --color-${match[1]}`],
	);
	return [...utilityProblems, ...variableProblems];
}

describe("web design-system normalization", () => {
	it("keeps the shared type, measure, radius, dialog, and form roles defined", () => {
		for (const role of [
			"ui-title",
			"ui-copy",
			"ui-label",
			"ui-control-copy",
			"ui-action-copy",
			"ui-item-copy",
			"dialog-title",
			"reading-shell",
			"copy-measure",
			"compact-radius",
			"prose-measure",
			"form-measure",
			"dialog-panel",
			"dialog-surface",
			"compact-field",
			"compact-action",
		]) {
			expect(css).toContain(`.${role}`);
		}
	});

	it("prevents live support and download dialogs from reintroducing private geometry", () => {
		for (const file of [
			"components/site/contact-support-cta.tsx",
			"components/site/demo-dialogs.tsx",
			"components/site/download-cta.tsx",
		]) {
			const source = readFileSync(join(root, file), "utf8");
			expect(source, file).toContain("dialog-panel");
			expect(source, file).not.toMatch(/w-\[min\(92vw,(?:320|330|340|400|420|430)px\)\]/);
		}
	});

	it("keeps the modal backdrop dark when a demo overrides its theme colors", () => {
		expect(css).toContain("--dialog-backdrop: rgba(34, 29, 21, 0.45)");
		expect(css).toContain("background: var(--dialog-backdrop)");
		expect(css).not.toContain(".dialog-panel::backdrop {\n\t\tbackground: color-mix");
	});

	it("uses Sticker Bomb form typography on the library calculator", () => {
		const calculator = readFileSync(join(root, "components/library/calculator.tsx"), "utf8");
		expect(calculator).toContain("sb-form-control");
		expect(calculator).toContain("sb-form-label");
	});

	it("keeps legal pages on one shared rail and reading-column contract", () => {
		const shell = readFileSync(join(root, "components/legal/legal-document.tsx"), "utf8");
		expect(shell).toContain("lg:grid-cols-[300px_1fr]");
		// The content rhythm is a prop with the legal-page default baked in (the release page overrides
		// it via contentClassName); the default keeps the space-y-10 reading contract.
		expect(shell).toContain('contentClassName = "space-y-10"');

		for (const file of ["app/terms/page.tsx"]) {
			const source = readFileSync(join(root, file), "utf8");
			expect(source, file).toContain("<LegalDocument");
			expect(source, file).not.toContain("lg:grid-cols-[300px_1fr]");
		}
	});

	it("keeps email brand colors in parity with the website source of truth", () => {
		expect(emailColors.paper).toBe(cssColor("paper"));
		expect(emailColors.paper2).toBe(cssColor("paper-2"));
		expect(emailColors.card).toBe(cssColor("card"));
		expect(emailColors.ink).toBe(cssColor("ink"));
		expect(emailColors.line).toBe(cssColor("line"));
		expect(emailColors.lineStrong).toBe(cssColor("line-strong"));
		expect(emailColors.ginger).toBe(cssColor("ginger"));
		expect(emailColors.gingerDeep).toBe(cssColor("cta"));
		expect(emailColors.honey).toBe(cssColor("honey"));
		expect(emailColors.creamDeep).toBe(cssColor("cream-deep"));
		expect(emailColors.gold).toBe(cssColor("gold"));
		expect(emailColors.sage).toBe(cssColor("sage"));
		expect(emailColors.coral).toBe(cssColor("coral"));
	});

	it("keeps email radii in parity with the website radius tokens", () => {
		for (const [name, value] of Object.entries(emailRadius)) {
			expect(css, name).toContain(`--radius-${name}: ${value};`);
		}
	});

	/**
	 * Tailwind emits no rule for an unknown color, so a plausible palette name that was never defined
	 * (`ginger-dark`, `ginger-light`, `paper-deep` all shipped) silently falls back to `currentColor`
	 * or to nothing. Every palette-shaped color utility and CSS color variable must name a token
	 * defined in `globals.css`, and Tailwind's default palette stays off-brand.
	 */
	it("names only defined color tokens in utilities and CSS variables", () => {
		const defined = new Set([...css.matchAll(/--color-([a-z0-9-]+):/g)].map((m) => m[1] ?? ""));
		const files = SOURCE_GLOBS.flatMap((pattern) => [...new Glob(pattern).scanSync(root)]);
		const problems = files.flatMap((file) =>
			colorTokenProblems(file, readFileSync(join(root, file), "utf8"), defined),
		);
		expect(files.length).toBeGreaterThan(100);
		expect(defined.has("ginger-deep")).toBe(true);
		expect(problems).toEqual([]);
	});
});
