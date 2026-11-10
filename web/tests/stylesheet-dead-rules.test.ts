import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Glob } from "bun";

// knip follows imports, so it never sees a class selector nobody applies. Forty-one of them, five
// unused custom properties, and six orphaned keyframes sat in the two stylesheets while every gate
// stayed green. This guard fails on the first rule a component stops using.

const root = join(import.meta.dir, "..");
const STYLESHEETS = ["app/globals.css", "app/sticker.css"];
const SOURCE_GLOBS = [
	"app/**/*.{ts,tsx}",
	"components/**/*.{ts,tsx}",
	"lib/**/*.{ts,tsx}",
	"emails/**/*.{ts,tsx}",
];

const stylesheets = STYLESHEETS.map((file) => ({
	file,
	css: readFileSync(join(root, file), "utf8").replace(/\/\*[\s\S]*?\*\//g, ""),
}));
const allCss = stylesheets.map((sheet) => sheet.css).join("\n");

const sourceFiles = SOURCE_GLOBS.flatMap((pattern) => [...new Glob(pattern).scanSync(root)]);
const STRING_LITERAL = /"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'|`((?:[^`\\]|\\.)*)`/g;
const literals = sourceFiles.flatMap((file) =>
	[...readFileSync(join(root, file), "utf8").matchAll(STRING_LITERAL)].map(
		(match) => match[1] ?? match[2] ?? match[3] ?? "",
	),
);
const literalText = literals.join("\n");
/** Every class-shaped token a string literal carries, with variant prefixes (`md:`) split off. */
const literalTokens = new Set(literals.flatMap((literal) => literal.split(/[^\w-]+/)));

function names(css: string, pattern: RegExp): string[] {
	return [...new Set([...css.matchAll(pattern)].map((match) => match[1] ?? ""))].sort();
}

/** Selector classes only: `url()` bodies and quoted values can hold a dot-prefixed word. */
function classSelectors(css: string): string[] {
	return names(css.replace(/url\([^)]*\)|"[^"]*"/g, ""), /\.(-?[_a-zA-Z][\w-]*)/g);
}

function isCustomPropertyUsed(name: string): boolean {
	if (allCss.includes(`var(${name})`) || allCss.includes(`var(${name},`)) return true;
	if (new RegExp(`${name}(?![\\w-])`).test(literalText)) return true;
	// A `@theme` token is also live through the utility Tailwind derives from it (`bg-paper-2`).
	const utility = name.replace(/^--(?:color|font)-/, "");
	return utility !== name && [...literalTokens].some((token) => token.endsWith(`-${utility}`));
}

function isKeyframeUsed(name: string): boolean {
	const inAnimation = new RegExp(`animation[^;{}]*[\\s:,]${name}(?![\\w-])`);
	return inAnimation.test(allCss) || literalTokens.has(name);
}

describe("stylesheet dead rules", () => {
	it("scans real stylesheets and real source", () => {
		expect(sourceFiles.length).toBeGreaterThan(100);
		expect(literalTokens.size).toBeGreaterThan(1000);
		for (const { file, css } of stylesheets) {
			expect(classSelectors(css).length, file).toBeGreaterThan(20);
		}
	});

	it("applies every class selector from a component", () => {
		const dead = stylesheets.flatMap(({ file, css }) =>
			classSelectors(css)
				.filter((name) => !literalTokens.has(name))
				.map((name) => `${file}: .${name}`),
		);
		expect(dead).toEqual([]);
	});

	it("reads every custom property it defines", () => {
		const dead = stylesheets.flatMap(({ file, css }) =>
			names(css, /(--[\w-]+)\s*:/g)
				.filter((name) => !isCustomPropertyUsed(name))
				.map((name) => `${file}: ${name}`),
		);
		expect(dead).toEqual([]);
	});

	it("plays every keyframe animation it declares", () => {
		const dead = stylesheets.flatMap(({ file, css }) =>
			names(css, /@keyframes\s+([\w-]+)/g)
				.filter((name) => !isKeyframeUsed(name))
				.map((name) => `${file}: @keyframes ${name}`),
		);
		expect(dead).toEqual([]);
	});
});
