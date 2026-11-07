/**
 * The SINGLE source of "which `/library` routes exist", consumed identically by route guards and
 * metadata (_docs/08-growth.md SEO guardrails). Search eligibility is intentionally stricter: the sitemap
 * keeps useful-but-thin roadmap provider references out until they gain provider-specific depth.
 * `status` (honesty) is handled separately in the generators.
 */

import { CALCULATOR_SLUGS } from "./calculators-manifest";
import { ALTERNATIVES_ANCHORS } from "./competitors-registry";
import { GLOSSARY_SLUGS } from "./glossary-registry";
import { GUIDE_SLUGS } from "./guides-manifest";
import { PLAN_SLUGS } from "./plans-registry";
import { eligibleModelSlugs, VENDORS } from "./pricing-registry";
import { eligibleProviderSlugs } from "./provider-registry";
import type { LibrarySectionSlug } from "./sections";

/** Minimum real tracker-catalog sources for a roadmap provider to earn a track page. */
export const LIBRARY_DATA_SCORE_GATE = 2;

/** Providers with documented limit mechanics (`_docs/03-data.md`). No fabricated leaves (_docs/08-growth.md SEO guardrails). */
export const LIMIT_PROVIDER_SLUGS = [
	"claude-code",
	"codex",
	"grok",
	"grok-bot",
	"opencodego",
	"cursor",
	"github-copilot",
];

/** Vendor-family pricing hubs — house every model (incl. the thin 3-field ones). */
export const VENDOR_FAMILY_SLUGS = [...VENDORS];

type CompareKind = "tool" | "model";
export interface ComparePair {
	slug: string;
	kind: CompareKind;
	a: string;
	b: string;
}

/** Allowlisted compare pairs — avoids the 253-model-pair doorway explosion (_docs/08-growth.md SEO guardrails). */
export const COMPARE_PAIRS: ComparePair[] = [
	{ slug: "jp-the-cat-vs-ccusage", kind: "tool", a: "jp-the-cat", b: "ccusage" },
	{ slug: "jp-the-cat-vs-sessionwatcher", kind: "tool", a: "jp-the-cat", b: "sessionwatcher" },
	{ slug: "jp-the-cat-vs-codexbar", kind: "tool", a: "jp-the-cat", b: "codexbar" },
	{ slug: "jp-the-cat-vs-codeburn", kind: "tool", a: "jp-the-cat", b: "codeburn" },
	{
		slug: "jp-the-cat-vs-tokens-4-breakfast",
		kind: "tool",
		a: "jp-the-cat",
		b: "tokens-4-breakfast",
	},
	{
		slug: "jp-the-cat-vs-claude-code-usage-monitor",
		kind: "tool",
		a: "jp-the-cat",
		b: "claude-code-usage-monitor",
	},
	{ slug: "ccusage-vs-codexbar", kind: "tool", a: "ccusage", b: "codexbar" },
	{ slug: "ccusage-vs-sessionwatcher", kind: "tool", a: "ccusage", b: "sessionwatcher" },
	{ slug: "sessionwatcher-vs-codexbar", kind: "tool", a: "sessionwatcher", b: "codexbar" },
	{
		slug: "claude-sonnet-4-6-vs-claude-opus-4-8",
		kind: "model",
		a: "claude-sonnet-4-6",
		b: "claude-opus-4-8",
	},
	{
		slug: "claude-opus-4-8-vs-claude-opus-4-5",
		kind: "model",
		a: "claude-opus-4-8",
		b: "claude-opus-4-5",
	},
	{
		slug: "claude-haiku-4-5-vs-claude-sonnet-4-6",
		kind: "model",
		a: "claude-haiku-4-5",
		b: "claude-sonnet-4-6",
	},
	{
		slug: "gpt-5-3-codex-vs-claude-opus-4-8",
		kind: "model",
		a: "gpt-5-3-codex",
		b: "claude-opus-4-8",
	},
	{
		slug: "gemini-3-pro-vs-claude-opus-4-8",
		kind: "model",
		a: "gemini-3-pro",
		b: "claude-opus-4-8",
	},
	{
		slug: "claude-sonnet-4-6-vs-gpt-5-3-codex",
		kind: "model",
		a: "claude-sonnet-4-6",
		b: "gpt-5-3-codex",
	},
];

export const COMPARE_SLUGS = COMPARE_PAIRS.map((pair) => pair.slug);

/** Eligible leaf slugs for a section — the set that renders 200 AND enters the sitemap. */
export function eligibleSlugsForSection(section: LibrarySectionSlug): string[] {
	switch (section) {
		case "track":
			return eligibleProviderSlugs();
		case "pricing":
			return eligibleModelSlugs();
		case "calculators":
			return [...CALCULATOR_SLUGS];
		case "limits":
			return [...LIMIT_PROVIDER_SLUGS];
		case "plans":
			return [...PLAN_SLUGS];
		case "compare":
			return [...COMPARE_SLUGS];
		case "alternatives":
			return [...ALTERNATIVES_ANCHORS];
		case "guides":
			return [...GUIDE_SLUGS];
		case "glossary":
			return [...GLOSSARY_SLUGS];
	}
}

export function isLibrarySlugEligible(section: LibrarySectionSlug, slug: string): boolean {
	return eligibleSlugsForSection(section).includes(slug);
}
