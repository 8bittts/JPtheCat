"use client";

import { track } from "@vercel/analytics";

/**
 * Every Vercel Web Analytics custom event the site sends, in snake_case; add a new name here before
 * using it. They appear only in the Vercel dashboard (Title Case before 2026-10-22).
 */
export type ProductEventName =
	| "download_cta_clicked"
	| "download_modal_opened"
	| "library_download_cta_clicked"
	| "library_download_modal_opened"
	| "repo_link_clicked";

type ProductEventValue = string | number | boolean;
type ProductEventProperties = Record<string, ProductEventValue | null | undefined>;

// Vercel's custom-event limits: flat values, 255 characters, 8 properties on Web Analytics Plus.
const MAX_PROPERTY_LENGTH = 255;
const MAX_PROPERTIES = 8;

function sanitizeProperties(properties: ProductEventProperties): Record<string, ProductEventValue> {
	const sanitized: Record<string, ProductEventValue> = {};
	for (const [key, value] of Object.entries(properties)) {
		if (value === null || value === undefined) continue;
		if (Object.keys(sanitized).length === MAX_PROPERTIES) break;
		sanitized[key] = typeof value === "string" ? value.slice(0, MAX_PROPERTY_LENGTH) : value;
	}
	return sanitized;
}

export type RepoLinkPlacement = "home_callout" | "faq" | "footer" | "demo_settings";
export type RepoLinkTarget = "repo" | "contributing";

/** The one entry point for custom events; analytics must never break a CTA. */
export function trackProductEvent(
	name: ProductEventName,
	properties: ProductEventProperties = {},
): void {
	try {
		track(name, sanitizeProperties(properties));
	} catch {
		// Analytics must never block the visitor's workflow.
	}
}

export function trackRepoLink(placement: RepoLinkPlacement, target: RepoLinkTarget): void {
	trackProductEvent("repo_link_clicked", { placement, target });
}
