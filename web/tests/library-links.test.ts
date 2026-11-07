import { describe, expect, it } from "bun:test";
import { CALCULATORS } from "@/lib/library/calculators-manifest";
import { COMPETITORS } from "@/lib/library/competitors-registry";
import { alternativeAnchor, alternativesLeaf } from "@/lib/library/content/alternatives";
import { calculatorLeaf } from "@/lib/library/content/calculators";
import { compareBySlug, compareLeaf } from "@/lib/library/content/compare";
import { glossaryLeaf } from "@/lib/library/content/glossary";
import { guideLeaf } from "@/lib/library/content/guides";
import { limitLeaf } from "@/lib/library/content/limits";
import { planLeaf } from "@/lib/library/content/plans";
import { pricingLeaf } from "@/lib/library/content/pricing";
import { providerLeaf } from "@/lib/library/content/provider";
import type { LeafContent } from "@/lib/library/content/shared";
import { vendorLeaf } from "@/lib/library/content/vendor";
import {
	COMPARE_SLUGS,
	eligibleSlugsForSection,
	LIMIT_PROVIDER_SLUGS,
	VENDOR_FAMILY_SLUGS,
} from "@/lib/library/eligibility";
import { GLOSSARY } from "@/lib/library/glossary-registry";
import { GUIDES } from "@/lib/library/guides-manifest";
import { rootHubSections, sectionLinks } from "@/lib/library/hub";
import { PLANS } from "@/lib/library/plans-registry";
import { eligibleModelIds, VENDORS } from "@/lib/library/pricing-registry";
import { eligibleProviders, providerBySlug } from "@/lib/library/provider-registry";
import { LIBRARY_SECTIONS } from "@/lib/library/sections";

/** Every `/library` path a route renders with 200 — the hub, section hubs, leaves, and families. */
function routablePaths(): Set<string> {
	const paths = new Set<string>(["/library"]);
	for (const section of LIBRARY_SECTIONS) {
		paths.add(`/library/${section.slug}`);
		for (const slug of eligibleSlugsForSection(section.slug)) {
			paths.add(`/library/${section.slug}/${slug}`);
		}
	}
	for (const vendor of VENDOR_FAMILY_SLUGS) paths.add(`/library/pricing/family/${vendor}`);
	return paths;
}

function allLeaves(): { page: string; leaf: LeafContent }[] {
	return [
		...eligibleModelIds().map((id) => ({ page: `pricing/${id}`, leaf: pricingLeaf(id) })),
		...VENDORS.map((vendor) => ({ page: `family/${vendor}`, leaf: vendorLeaf(vendor) })),
		...eligibleProviders().map((p) => ({ page: `track/${p.id}`, leaf: providerLeaf(p) })),
		...LIMIT_PROVIDER_SLUGS.flatMap((slug) => {
			const provider = providerBySlug(slug);
			return provider ? [{ page: `limits/${slug}`, leaf: limitLeaf(provider) }] : [];
		}),
		...PLANS.map((plan) => ({ page: `plans/${plan.slug}`, leaf: planLeaf(plan) })),
		...COMPARE_SLUGS.flatMap((slug) => {
			const pair = compareBySlug(slug);
			return pair ? [{ page: `compare/${slug}`, leaf: compareLeaf(pair) }] : [];
		}),
		...COMPETITORS.flatMap((tool) => {
			const anchor = alternativeAnchor(tool.slug);
			return anchor ? [{ page: `alternatives/${tool.slug}`, leaf: alternativesLeaf(anchor) }] : [];
		}),
		...GUIDES.map((guide) => ({ page: `guides/${guide.slug}`, leaf: guideLeaf(guide) })),
		...GLOSSARY.map((term) => ({ page: `glossary/${term.slug}`, leaf: glossaryLeaf(term) })),
		...CALCULATORS.map((calc) => ({
			page: `calculators/${calc.slug}`,
			leaf: calculatorLeaf(calc),
		})),
	];
}

describe("library internal links", () => {
	it("points every generated /library link at a route that renders", () => {
		const routable = routablePaths();
		const leaves = allLeaves();
		expect(leaves.length).toBeGreaterThan(100);
		const broken: string[] = [];
		let checked = 0;
		for (const { page, leaf } of leaves) {
			const text = JSON.stringify(leaf);
			const hrefs = [
				...(leaf.related ?? []).map((link) => link.href),
				...[...text.matchAll(/\]\((\/library[^)#?\s]*)/g)].map((match) => match[1] ?? ""),
			];
			for (const href of hrefs) {
				if (!href.startsWith("/library")) continue;
				checked += 1;
				if (!routable.has(href)) broken.push(`${page} → ${href}`);
			}
		}
		expect(checked).toBeGreaterThan(200);
		expect(broken).toEqual([]);
	});

	it("points every hub and section-hub card at a route that renders", () => {
		const routable = routablePaths();
		const links = [
			...rootHubSections(),
			...LIBRARY_SECTIONS.flatMap((section) => sectionLinks(section.slug)),
		];
		expect(links.length).toBeGreaterThan(100);
		expect(links.map((link) => link.href).filter((href) => !routable.has(href))).toEqual([]);
	});
});
