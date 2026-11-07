#!/usr/bin/env bun
// WCAG 2.2 AA audit: runs axe-core against every public route at mobile and desktop widths.
// Exits non-zero on any violation, so it can gate a release.
//
// Usage: bun scripts/a11y-audit.ts [baseUrl]   (default http://localhost:4460; start `bun run dev` first)
import AxeBuilder from "@axe-core/playwright";
import { chromium } from "@playwright/test";

const base = (process.argv[2] ?? "http://localhost:4460").replace(/\/+$/, "");
const routes = (
	process.env.ROUTES ??
	"/,/contact,/terms,/library,/library/pricing,/library/alternatives,/does-not-exist"
).split(",");
const widths = (process.env.WIDTHS ?? "390,1440").split(",").map(Number);
// best-practice adds the landmark/heading-structure rules (region, landmark-one-main, heading-order).
const tags = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"];

const browser = await chromium.launch({ channel: process.env.PW_CHANNEL ?? "chrome" });
let failures = 0;
try {
	for (const width of widths) {
		const context = await browser.newContext({ viewport: { width, height: 900 } });
		const page = await context.newPage();
		for (const route of routes) {
			await page.goto(`${base}${route}`, { waitUntil: "networkidle" });
			// Next's dev overlay is not part of the page under test.
			const result = await new AxeBuilder({ page })
				.withTags(tags)
				.exclude("nextjs-portal")
				.analyze();
			for (const v of result.violations) {
				failures += 1;
				console.log(`✗ ${width}px ${route} [${v.impact}] ${v.id}: ${v.help}`);
				for (const node of v.nodes.slice(0, 5)) {
					console.log(
						`    ${node.target.join(" ")} — ${node.failureSummary?.split("\n")[1]?.trim() ?? ""}`,
					);
				}
			}
			if (result.violations.length === 0) console.log(`✓ ${width}px ${route}`);
		}
		await context.close();
	}
} finally {
	await browser.close();
}
console.log(failures === 0 ? "\naxe: 0 violations" : `\naxe: ${failures} violation group(s)`);
process.exit(failures === 0 ? 0 : 1);
