import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { StickerHome } from "@/components/sticker/home";
import { NAV } from "@/lib/site";

// The `/library` hub is crawlable via the sitemap only — never linked from site chrome
// (_docs/08-growth.md SEO guardrails). This keeps the polished marketing site clean, while exactly one
// low-prominence in-content link (the FAQ) passes crawl equity from the homepage into the hub.
describe("library stays crawlable-but-unlinked", () => {
	it("never appears in the global nav constant", () => {
		expect(NAV.map((item) => item.href).join(" ")).not.toContain("/library");
	});

	it("never appears in the rendered nav or footer chrome", async () => {
		const nav = await Bun.file("components/site/nav.tsx").text();
		const footer = await Bun.file("components/site/footer.tsx").text();
		expect(nav).not.toContain("/library");
		expect(footer).not.toContain("/library");
	});

	it("keeps the one in-content crawl-equity link from the homepage FAQ", () => {
		expect(renderToStaticMarkup(StickerHome())).toContain('href="/library/pricing"');
	});
});
