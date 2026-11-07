import { describe, expect, it } from "bun:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AdvancedAnalyticsDemo } from "@/components/site/advanced-analytics-demo";
import { MENU_BAR_FORMATS } from "@/components/site/menubar-demo-format";
import { AGG, ORDER, PROVIDERS as SERIES } from "@/components/site/menubar-demo-series";
import { StickerHome } from "@/components/sticker/home";
import { HOMEPAGE_PROVIDER_KEYS, HOMEPAGE_PROVIDERS } from "@/lib/homepage-providers";
import { PROVIDERS } from "@/lib/site";

const EXPECTED = ["claude", "codex", "grok", "museSpark", "cursor", "openCodeGo"] as const;
const OMITTED = ["Copilot", "OpenCode Zen", "Nemotron", "MiMo", "Big Pickle", "DeepSeek", "Gemini"];
describe("fixed homepage provider boundary", () => {
	it("keeps the homepage independent of the complete native and library catalog", () => {
		expect(HOMEPAGE_PROVIDER_KEYS).toEqual(EXPECTED);
		expect(ORDER).toEqual(EXPECTED);
		expect(HOMEPAGE_PROVIDERS.map((p) => p.id)).toEqual([
			"claude",
			"codex",
			"grok",
			"muse_spark",
			"cursor",
			"opencodego",
		]);
		expect(PROVIDERS).toHaveLength(64);
		expect(PROVIDERS.find((p) => p.id === "opencode")?.live).toBe(true);
		expect(PROVIDERS.some((p) => p.id === "cursor" || p.id === "grok_bot")).toBe(false);
		// Extra fixtures already exist: none can implicitly expand homepage controls or totals.
		expect(Object.keys(SERIES).length).toBeGreaterThan(ORDER.length);
		expect(AGG.today).toBe(10);
		expect(AGG.week).toBe(69.2);
		expect(AGG.shares.map((p) => p.key)).toEqual(["claude", "codex", "grok", "museSpark"]);
	});
	it("renders only the approved providers in analytics, the homepage and menu formats", () => {
		const html = renderToStaticMarkup(createElement(AdvancedAnalyticsDemo, { onClose: () => {} }));
		const faq = renderToStaticMarkup(createElement(StickerHome));
		for (const name of OMITTED) {
			expect(html).not.toContain(name);
			expect(faq).not.toContain(name);
			expect(MENU_BAR_FORMATS.some((item) => item.title.includes(name))).toBe(false);
		}
		for (const p of HOMEPAGE_PROVIDERS) expect(html).toContain(p.name);
	});
	it("pins Live Data membership and preserves native catalog parity as a separate gate", async () => {
		const settings = await Bun.file("components/site/menubar-demo-settings.tsx").text();
		const marks = [...settings.matchAll(/providerMark=\{\{ icon: PROVIDERS\.(\w+)\.icon/g)].map(
			(m) => m[1],
		);
		expect([...new Set(marks)]).toEqual([...EXPECTED]);
		expect(await Bun.file("tests/provider-catalog-parity.test.ts").text()).toContain(
			"swift.length",
		);
	});
});
