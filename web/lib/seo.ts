import type { Metadata } from "next";
import { SITE } from "./site";

// SERP display budgets. Enforced by tests/seo.test.ts so a too-long title/description
// can't ship silently.
export const SEO_TITLE_MAX_LENGTH = 60;
export const SEO_DESCRIPTION_MAX_LENGTH = 160;

export type PageSeo = { path: string; title: string; description: string };

// `title` is the FULL rendered <title> (brand already included where needed).
export const PAGE_SEO = {
	home: {
		path: "/",
		title: `${SITE.seoName} — ${SITE.tagline}`,
		description: SITE.description,
	},
	terms: {
		path: "/terms",
		title: `Privacy and Terms — ${SITE.seoName}`,
		description: `Privacy policy and terms of service for ${SITE.seoName}. Usage data stays on your Mac.`,
	},
	contact: {
		path: "/contact",
		title: `Contact — ${SITE.seoName}`,
		description: `Get help with ${SITE.seoName} — downloads, provider setup, and Mac questions.`,
	},
} satisfies Record<string, PageSeo>;

// Absolute canonical URL on the apex host.
export function canonicalUrl(path: string): string {
	return `${SITE.url}${path === "/" ? "" : path}`;
}

/**
 * Full per-page Metadata for a subpage (privacy, terms, …). Without this, a
 * subpage that only sets `title`/`description` inherits the root layout's
 * OpenGraph + Twitter block — so its social cards would show the HOME title,
 * description, and URL. This overrides all three (title, description, canonical
 * URL) for OG and Twitter while keeping the shared OG image.
 */
export function pageMetadata(page: PageSeo): Metadata {
	const url = canonicalUrl(page.path);
	return {
		title: { absolute: page.title },
		description: page.description,
		alternates: { canonical: url },
		openGraph: {
			type: "website",
			url,
			title: page.title,
			description: page.description,
			siteName: SITE.name,
			locale: "en_US",
			images: [{ url: SITE.ogImage, width: 1200, height: 630, alt: page.title }],
		},
		twitter: {
			card: "summary_large_image",
			title: page.title,
			description: page.description,
			site: SITE.twitter,
			creator: SITE.twitter,
			images: [SITE.ogImage],
		},
	};
}
