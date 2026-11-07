"use client";

import { track } from "@vercel/analytics";

/**
 * Every Vercel Web Analytics custom event the site sends, in snake_case. The growth digest reads
 * these names back (`growth-source-vercel.ts`); add a new name here before using it.
 */
export type ProductEventName =
	| "download_cta_clicked"
	| "download_modal_opened"
	| "library_download_cta_clicked"
	| "library_download_modal_opened";

/**
 * The Title Case names these events carried until 2026-10-22. The digest counts both so its
 * rolling windows stay continuous; drop this map once no window reaches back before that date.
 */
export const LEGACY_PRODUCT_EVENT_NAMES: Readonly<Record<ProductEventName, string>> = {
	download_cta_clicked: "Download CTA Clicked",
	download_modal_opened: "Download Newsletter Modal Opened",
	library_download_cta_clicked: "Library Download CTA Clicked",
	library_download_modal_opened: "Library Download Modal Opened",
};

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
