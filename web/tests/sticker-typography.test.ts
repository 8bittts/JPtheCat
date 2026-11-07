import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Glob } from "bun";

const root = join(import.meta.dir, "..");

const MARKETING_GLOBS = [
	"app/contact/**/*.tsx",
	"app/not-found.tsx",
	"app/terms/**/*.tsx",
	"app/library/**/*.tsx",
	"components/library/**/*.tsx",
	"components/site/footer.tsx",
	"components/site/download-cta.tsx",
	"components/site/homebrew-install-callout.tsx",
	"components/site/contact-support-cta.tsx",
	"components/sticker/**/*.tsx",
	"components/legal/legal-document.tsx",
];

/** Sticker Bomb marketing surfaces use `sb-*` type roles — not arbitrary `text-[…]` sizes. */
describe("sticker typography normalization", () => {
	it("keeps marketing routes free of arbitrary text size utilities", () => {
		const files = MARKETING_GLOBS.flatMap((pattern) => [...new Glob(pattern).scanSync(root)]);
		const problems = files.flatMap((file) => {
			const source = readFileSync(join(root, file), "utf8");
			return source.includes("text-[") ? [`${file}: text-[`] : [];
		});
		expect(files.length).toBeGreaterThan(20);
		expect(problems).toEqual([]);
	});

	it("keeps marketing surfaces on the warm Sticker Bomb palette", () => {
		const files = MARKETING_GLOBS.flatMap((pattern) => [...new Glob(pattern).scanSync(root)]);
		const banned = ["--sb-mint", "4dd0a6", "border-line bg-paper", "bg-paper-2"];
		const problems = files.flatMap((file) => {
			const source = readFileSync(join(root, file), "utf8");
			return banned.flatMap((token) => (source.includes(token) ? [`${file}: ${token}`] : []));
		});
		expect(problems).toEqual([]);
	});

	it("documents the shared Sticker Bomb type roles in sticker.css", () => {
		const css = readFileSync(join(root, "app/sticker.css"), "utf8");
		for (const role of [
			".sb-page-title",
			".sb-page-kicker",
			".sb-section-title",
			".sb-body",
			".sb-meta",
			".sb-dialog-title",
			".sb-footer-legal",
		]) {
			expect(css).toContain(role);
		}
	});
});
