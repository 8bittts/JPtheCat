import { describe, expect, it } from "bun:test";
import { generateMetadata as trackProviderMetadata } from "@/app/library/track/[provider]/page";
import { metadata as notFoundMetadata } from "@/app/not-found";
import sitemap from "@/app/sitemap";
import { homeJsonLd, jsonLdText } from "@/lib/home-json-ld";
import {
	canonicalUrl,
	PAGE_SEO,
	SEO_DESCRIPTION_MAX_LENGTH,
	SEO_TITLE_MAX_LENGTH,
} from "@/lib/seo";

describe("SEO guardrails", () => {
	it("home: title uses the spaced JP the Cat name", () => {
		expect(PAGE_SEO.home.title).toBe("JP the Cat — The cat that counts your agent tokens.");
		expect(PAGE_SEO.home.description).toContain("Cursor tokens");
	});

	for (const [key, page] of Object.entries(PAGE_SEO)) {
		it(`${key}: title <= ${SEO_TITLE_MAX_LENGTH} chars`, () => {
			expect(page.title.length).toBeLessThanOrEqual(SEO_TITLE_MAX_LENGTH);
		});

		it(`${key}: description <= ${SEO_DESCRIPTION_MAX_LENGTH} chars`, () => {
			expect(page.description.length).toBeLessThanOrEqual(SEO_DESCRIPTION_MAX_LENGTH);
		});

		it(`${key}: canonical uses the apex host`, () => {
			const url = canonicalUrl(page.path);
			expect(url.startsWith("https://jpthecat.com")).toBe(true);
			expect(url.includes("www.")).toBe(false);
		});
	}

	it("home SoftwareApplication JSON-LD carries the free download offer without fake ratings", () => {
		const nodes = homeJsonLd();
		const app = nodes.find((node) => node["@type"] === "SoftwareApplication");

		expect(app).toBeDefined();
		expect(app?.offers).toEqual({
			"@type": "Offer",
			price: "0",
			priceCurrency: "USD",
			availability: "https://schema.org/InStock",
			url: "https://jpthecat.com/#download",
		});
		expect(app?.isAccessibleForFree).toBe(true);
		expect(JSON.stringify(nodes)).not.toContain("aggregateRating");
		expect(JSON.stringify(nodes)).not.toContain("review");
		expect(jsonLdText(nodes)).not.toContain("<");
	});

	it("404 route does not inherit indexable homepage metadata", () => {
		expect(notFoundMetadata.robots).toEqual({ index: false, follow: false });
		expect(notFoundMetadata.title).toEqual({ absolute: "404 — JP the Cat" });
		expect(notFoundMetadata.description).toContain("not found");
		expect(notFoundMetadata.alternates).toEqual({});
		expect(notFoundMetadata.openGraph).toMatchObject({
			title: "404 — JP the Cat",
			description: "That JP the Cat page was not found.",
		});
	});

	it("sitemap includes every important static page and omits transactional routes", () => {
		const urls = sitemap().map((entry) => entry.url);
		expect(urls).toContain("https://jpthecat.com/contact");
		expect(urls).not.toContain("https://jpthecat.com/confirmed");
		expect(urls).not.toContain("https://jpthecat.com/thanks");
	});

	it("does not emit Google's ignored meta-keywords field", async () => {
		const layout = await Bun.file("app/layout.tsx").text();
		expect(layout).not.toContain("\tkeywords:");
	});

	it("indexes live provider leaves but noindexes thin roadmap references", async () => {
		const live = await trackProviderMetadata({
			params: Promise.resolve({ provider: "claude-code" }),
		});
		const roadmap = await trackProviderMetadata({
			params: Promise.resolve({ provider: "github-copilot" }),
		});
		expect(live.robots).toEqual({ index: true, follow: true });
		expect(roadmap.robots).toEqual({
			index: false,
			follow: true,
			googleBot: { index: false, follow: true },
		});
	});
});
