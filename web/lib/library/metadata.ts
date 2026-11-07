/**
 * Per-page metadata for `/library` routes — routes through the shared `@/lib/seo` builder so
 * canonical/OG/Twitter stay consistent with the rest of the site, and clamps to the 60/160 SERP
 * caps (_docs/08-growth.md SEO guardrails).
 */

import type { Metadata } from "next";
import { pageMetadata, SEO_DESCRIPTION_MAX_LENGTH, SEO_TITLE_MAX_LENGTH } from "@/lib/seo";
import { clampLength } from "./content/shared";
import { LIBRARY_SECTIONS, type LibrarySection, type LibrarySectionSlug } from "./sections";

export interface LibraryMetaInput {
	title: string;
	description: string;
	path: `/library${string}`;
}

export function libraryPageMetadata(input: LibraryMetaInput): Metadata {
	return pageMetadata({
		path: input.path,
		title: clampLength(input.title, SEO_TITLE_MAX_LENGTH),
		description: clampLength(input.description, SEO_DESCRIPTION_MAX_LENGTH),
	});
}

export function librarySection(slug: LibrarySectionSlug): LibrarySection {
	const found = LIBRARY_SECTIONS.find((entry) => entry.slug === slug);
	if (!found) {
		throw new Error(`unknown section ${slug}`);
	}
	return found;
}

export function sectionHubMetadata(slug: LibrarySectionSlug): Metadata {
	const current = librarySection(slug);
	return libraryPageMetadata({
		title: current.title,
		description: current.description,
		path: `/library/${slug}`,
	});
}
