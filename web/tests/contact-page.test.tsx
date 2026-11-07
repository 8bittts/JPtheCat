import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import ContactPage, { metadata } from "@/app/contact/page";
import { PAGE_SEO } from "@/lib/seo";
import { SITE } from "@/lib/site";

describe("contact page", () => {
	it("renders a JP-branded support handoff for the free app", () => {
		const html = renderToStaticMarkup(<ContactPage />);

		// Page-specific title AND social cards — not the inherited home OG (see lib/seo.ts).
		expect(metadata.title).toEqual({ absolute: PAGE_SEO.contact.title });
		expect(metadata.openGraph?.title).toBe(PAGE_SEO.contact.title);
		expect(metadata.openGraph?.url).toBe(`${SITE.url}/contact`);
		expect(metadata.twitter?.title).toBe(PAGE_SEO.contact.title);
		expect(html).toContain("Need a");
		expect(html).toContain("A number looks off");
		expect(html).not.toMatch(/license|checkout|purchase|refund/i);
		expect(html).toContain("no secrets");
		expect(html).toContain("Get Support");
		expect(html).toContain(SITE.email);
		expect(html).toContain("Do not paste prompts, source code, transcripts, or OAuth tokens.");
		expect(html).toContain("sb-hero");
		expect(html).not.toContain("LetterHero");
		expect(html).not.toContain("ledger");
	});

	it("keeps the canonical contact route in site copy", () => {
		expect(SITE.contactHref).toBe("/contact");
		expect(SITE.email).toBe("support@jpthecat.com");
	});
});
