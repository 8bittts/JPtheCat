/**
 * Pure generator for the search-eligible `/library` URL set: the hub, nine section hubs, vendor
 * families, every substantive leaf, and live-provider track pages. Useful roadmap-provider
 * references remain linked routes but stay out until their own content clears the search-quality
 * bar. Deterministic + eligibility-gated (_docs/08-growth.md SEO guardrails).
 */

import { eligibleSlugsForSection, VENDOR_FAMILY_SLUGS } from "./eligibility";
import { indexableProviderSlugs } from "./provider-registry";
import { LIBRARY_SECTIONS } from "./sections";

export interface LibraryUrl {
	path: string;
	priority: number;
}

export function libraryUrlEntries(): LibraryUrl[] {
	const entries: LibraryUrl[] = [{ path: "/library", priority: 0.7 }];

	for (const section of LIBRARY_SECTIONS) {
		entries.push({ path: `/library/${section.slug}`, priority: 0.6 });
		const slugs =
			section.slug === "track" ? indexableProviderSlugs() : eligibleSlugsForSection(section.slug);
		for (const slug of slugs) {
			entries.push({ path: `/library/${section.slug}/${slug}`, priority: 0.5 });
		}
	}

	for (const vendor of VENDOR_FAMILY_SLUGS) {
		entries.push({ path: `/library/pricing/family/${vendor}`, priority: 0.55 });
	}

	return entries;
}

export function libraryUrlPaths(): string[] {
	return libraryUrlEntries().map((entry) => entry.path);
}
