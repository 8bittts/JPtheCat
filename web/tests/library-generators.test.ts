import { describe, expect, it } from "bun:test";
import {
	pricingDescription,
	pricingFaq,
	pricingHonestyNote,
	pricingLead,
	pricingTitle,
} from "@/lib/library/content/pricing";
import {
	providerTrackBody,
	providerTrackDescription,
	providerTrackFaq,
	providerTrackLead,
	providerTrackTitle,
} from "@/lib/library/content/provider";
import {
	breadcrumbListNode,
	collectionPageNode,
	definedTermNode,
	graph,
	jsonLdString,
	organizationNode,
	softwareApplicationNode,
	techArticleNode,
	webSiteNode,
} from "@/lib/library/json-ld";
import { libraryPageMetadata } from "@/lib/library/metadata";
import { eligibleModelIds } from "@/lib/library/pricing-registry";
import { SEO_DESCRIPTION_MAX_LENGTH, SEO_TITLE_MAX_LENGTH } from "@/lib/seo";
import { PROVIDERS } from "@/lib/site";

describe("library generators", () => {
	it("pricing generator emits real, capped, non-empty content for every eligible model", () => {
		for (const id of eligibleModelIds()) {
			const title = pricingTitle(id);
			expect(title.length).toBeGreaterThan(0);
			expect(title.length).toBeLessThanOrEqual(SEO_TITLE_MAX_LENGTH);
			expect(pricingDescription(id)).toContain("$");
			expect(pricingLead(id)).toContain("per million");
			expect(pricingHonestyNote(id).length).toBeGreaterThan(0);
			expect(pricingFaq(id).length).toBeGreaterThanOrEqual(1);
		}
	});

	it("provider generator branches on live vs roadmap", () => {
		const claude = PROVIDERS.find((provider) => provider.id === "claude");
		const gemini = PROVIDERS.find((provider) => provider.id === "gemini");
		if (!claude || !gemini) {
			throw new Error("expected claude + gemini in the catalog");
		}
		expect(providerTrackTitle(claude)).toContain("Track Claude Code");
		expect(providerTrackDescription(claude)).toContain("tracks Claude Code");
		expect(providerTrackLead(claude)).toContain("tracks Claude Code");
		expect(providerTrackBody(claude)).toContain("local logs");
		expect(providerTrackFaq(claude)[0]?.answer).toContain("live");

		expect(providerTrackTitle(gemini)).toContain("roadmap");
		expect(providerTrackLead(gemini)).toContain("does not track Gemini");
	});

	it("json-ld builders anchor entities by @id and escape <", () => {
		const document = graph([
			organizationNode(),
			webSiteNode(),
			breadcrumbListNode([
				{ name: "Home", href: "/" },
				{ name: "Library", href: "/library" },
			]),
			collectionPageNode("/library", "Library"),
			techArticleNode("/library/pricing/claude-opus-4-8", "Opus pricing", "desc"),
		]);
		const serialized = jsonLdString(document);
		expect(serialized).toContain("https://jpthecat.com/#organization");
		expect(serialized).toContain("BreadcrumbList");
		expect(serialized).not.toContain("<");
		expect(
			definedTermNode("/library/glossary/prompt-caching", "Prompt caching", "d")["@type"],
		).toBe("DefinedTerm");
		expect(softwareApplicationNode()["@type"]).toBe("SoftwareApplication");
	});

	it("metadata clamps to SERP caps and uses the apex canonical", () => {
		const meta = libraryPageMetadata({
			title: `${"very long title segment ".repeat(6)}end`,
			description: "d".repeat(320),
			path: "/library/pricing/claude-opus-4-8",
		});
		const title = (meta.title as { absolute: string }).absolute;
		expect(title.length).toBeLessThanOrEqual(SEO_TITLE_MAX_LENGTH);
		expect(String(meta.description).length).toBeLessThanOrEqual(SEO_DESCRIPTION_MAX_LENGTH);
		expect(String(meta.alternates?.canonical)).toBe(
			"https://jpthecat.com/library/pricing/claude-opus-4-8",
		);
	});
});
