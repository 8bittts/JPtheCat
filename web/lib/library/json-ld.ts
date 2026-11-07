/**
 * `@id`-anchored JSON-LD builders for `/library` (adapted from zoedate's structured-data engine).
 * Every page references the SAME Organization/WebSite nodes by `@id` (Google dedupes on `@id`)
 * instead of emitting a competing entity per page. Values come from trusted constants only.
 *
 * Deliberately NO fabricated AggregateRating/Review/Offer, and NO `FAQPage` as a rich-result bet
 * (Google restricted FAQ rich results in 2023) — `_docs/08-growth.md` SEO guardrails. `SoftwareApplication`
 * is emitted only on live-provider / JP product surfaces.
 */

import { SITE } from "@/lib/site";

const ORGANIZATION_ID = `${SITE.url}/#organization`;
const WEBSITE_ID = `${SITE.url}/#website`;

export interface Crumb {
	name: string;
	href: string;
}

function absolute(href: string): string {
	return href === "/" ? SITE.url : `${SITE.url}${href}`;
}

export function organizationNode() {
	return {
		"@type": "Organization",
		"@id": ORGANIZATION_ID,
		name: SITE.name,
		url: SITE.url,
		logo: `${SITE.url}${SITE.logo}`,
		description: SITE.description,
	};
}

export function webSiteNode() {
	return {
		"@type": "WebSite",
		"@id": WEBSITE_ID,
		name: SITE.name,
		url: SITE.url,
		inLanguage: "en-US",
		publisher: { "@id": ORGANIZATION_ID },
	};
}

export function breadcrumbListNode(crumbs: Crumb[]) {
	return {
		"@type": "BreadcrumbList",
		itemListElement: crumbs.map((crumb, index) => ({
			"@type": "ListItem",
			position: index + 1,
			name: crumb.name,
			item: absolute(crumb.href),
		})),
	};
}

export function collectionPageNode(path: string, name: string) {
	const url = absolute(path);
	return { "@type": "CollectionPage", "@id": url, url, name, isPartOf: { "@id": WEBSITE_ID } };
}

export function techArticleNode(path: string, name: string, description: string) {
	const url = absolute(path);
	return {
		"@type": "TechArticle",
		"@id": url,
		url,
		name,
		headline: name,
		description,
		isPartOf: { "@id": WEBSITE_ID },
		publisher: { "@id": ORGANIZATION_ID },
	};
}

export function definedTermNode(path: string, term: string, description: string) {
	return {
		"@type": "DefinedTerm",
		"@id": absolute(path),
		name: term,
		description,
		inDefinedTermSet: `${SITE.url}/library/glossary`,
	};
}

/** Only for live-provider / JP product surfaces (_docs/08-growth.md SEO guardrails). */
export function softwareApplicationNode() {
	return {
		"@type": "SoftwareApplication",
		"@id": `${SITE.url}/#app`,
		name: SITE.name,
		applicationCategory: "DeveloperApplication",
		operatingSystem: "macOS 14+",
		url: SITE.url,
		publisher: { "@id": ORGANIZATION_ID },
		// JP is a free download; same offer as the homepage graph.
		isAccessibleForFree: true,
		offers: {
			"@type": "Offer",
			price: "0",
			priceCurrency: "USD",
			availability: "https://schema.org/InStock",
			url: `${SITE.url}/#download`,
		},
	};
}

/** Wrap a list of nodes into a schema.org @graph document. */
export function graph(nodes: Record<string, unknown>[]) {
	return { "@context": "https://schema.org", "@graph": nodes };
}

/** Serialize for inline injection, escaping `<` so a value can't break out of the script tag. */
export function jsonLdString(document: Record<string, unknown>): string {
	return JSON.stringify(document).replace(/</g, "\\u003c");
}

/** Prepend the Home + Library crumbs shared by every `/library` page. */
export function libraryCrumbs(trail: Crumb[]): Crumb[] {
	return [{ name: "Home", href: "/" }, { name: "Library", href: "/library" }, ...trail];
}

/** Standard leaf graph: brand entity + breadcrumb + a TechArticle, plus any extra nodes. */
export function leafJsonLd(
	crumbs: Crumb[],
	path: string,
	name: string,
	description: string,
	extra: Record<string, unknown>[] = [],
) {
	return graph([
		organizationNode(),
		webSiteNode(),
		breadcrumbListNode(crumbs),
		techArticleNode(path, name, description),
		...extra,
	]);
}

/** Standard hub graph: brand entity + breadcrumb + a CollectionPage. */
export function collectionJsonLd(crumbs: Crumb[], path: string, name: string) {
	return graph([
		organizationNode(),
		webSiteNode(),
		breadcrumbListNode(crumbs),
		collectionPageNode(path, name),
	]);
}
