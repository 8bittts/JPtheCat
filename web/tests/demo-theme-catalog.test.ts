import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { type DemoThemePalette, THEME_CATALOG } from "@/components/site/demo-themes";

// The homepage demo's theme catalog (demo-themes.ts) is a hand-free mirror of the native app's
// JPTheme.all in Theme.swift. This test re-parses Theme.swift and asserts the web catalog matches it
// 1:1 — same order, same names/flags, and byte-identical palette hex for every role token — so the
// Appearance switcher on the site can never silently drift from the app's real palette.

const PALETTE_FIELDS: (keyof DemoThemePalette)[] = [
	"paper",
	"paper2",
	"card",
	"ink",
	"inkSoft",
	"inkFaint",
	"line",
	"lineStrong",
	"track",
	"ginger",
	"gingerDeep",
	"sage",
	"sageSoft",
	"honey",
	"creamDeep",
	"gold",
	"cta",
	"ctaDeep",
	"coral",
	"sageDeep",
	"ctaText",
];

type ParsedTheme = {
	id: string;
	name: string;
	isDark: boolean;
	inMoreThemes: boolean;
	palette: DemoThemePalette;
};

function parseThemeSwift(): ParsedTheme[] {
	const src = readFileSync(
		join(import.meta.dir, "../../mac/Sources/JPtheCatApp/Theme.swift"),
		"utf8",
	);
	const allBlock = src.match(/static let all: \[JPTheme\] = \[([\s\S]*?)\]/)?.[1] ?? "";
	const order = (allBlock.replace(/\/\/.*$/gm, "").match(/[a-zA-Z0-9]+/g) ?? []).filter(
		(w) => w !== "JPTheme",
	);

	const byVar = new Map<string, ParsedTheme>();
	const re = /static let (\w+) = JPTheme\(([\s\S]*?)\)\n/g;
	let m: RegExpExecArray | null = re.exec(src);
	while (m !== null) {
		const [, varName, body] = m;
		const hex: Record<string, string> = {};
		for (const pm of body.matchAll(/(\w+):\s*"([0-9A-Fa-f]{6})"/g)) {
			hex[pm[1]] = `#${pm[2].toUpperCase()}`;
		}
		const id = body.match(/id:\s*"([^"]+)"/)?.[1] ?? "";
		const name = body.match(/name:\s*"([^"]+)"/)?.[1] ?? "";
		const palette = {} as DemoThemePalette;
		for (const f of PALETTE_FIELDS) palette[f] = hex[f];
		byVar.set(varName, {
			id,
			name,
			isDark: /isDark:\s*true/.test(body),
			inMoreThemes: /inMoreThemes:\s*true/.test(body),
			palette,
		});
		m = re.exec(src);
	}

	return order.map((v) => byVar.get(v)).filter((t): t is ParsedTheme => t !== undefined);
}

describe("demo theme catalog mirrors Theme.swift", () => {
	const parsed = parseThemeSwift();

	it("has the same number of themes, in the same order", () => {
		expect(parsed.length).toBeGreaterThan(0);
		expect(THEME_CATALOG.map((t) => t.id)).toEqual(parsed.map((t) => t.id));
	});

	it("keeps exactly two free themes (Sunlit, Midnight)", () => {
		expect(THEME_CATALOG.filter((t) => !t.inMoreThemes).map((t) => t.id)).toEqual([
			"sunlit",
			"midnight",
		]);
	});

	for (const source of parseThemeSwift()) {
		it(`matches ${source.id} name/flags/palette exactly`, () => {
			const web = THEME_CATALOG.find((t) => t.id === source.id);
			expect(web).toBeDefined();
			if (!web) return;
			expect(web.name).toBe(source.name);
			expect(web.isDark).toBe(source.isDark);
			expect(web.inMoreThemes).toBe(source.inMoreThemes);
			for (const f of PALETTE_FIELDS) {
				expect(web.palette[f]).toBe(source.palette[f]);
			}
		});
	}
});
