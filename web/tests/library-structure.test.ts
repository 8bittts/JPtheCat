import { describe, expect, it } from "bun:test";
import { CALCULATOR_SLUGS, CALCULATORS } from "@/lib/library/calculators-manifest";
import {
	ALTERNATIVES_ANCHORS,
	COMPETITORS,
	JP_COMPETITOR_ROW,
} from "@/lib/library/competitors-registry";
import { vendorLeaf } from "@/lib/library/content/vendor";
import {
	COMPARE_PAIRS,
	COMPARE_SLUGS,
	eligibleSlugsForSection,
	isLibrarySlugEligible,
	LIBRARY_DATA_SCORE_GATE,
	LIMIT_PROVIDER_SLUGS,
	VENDOR_FAMILY_SLUGS,
} from "@/lib/library/eligibility";
import { GLOSSARY, GLOSSARY_SLUGS } from "@/lib/library/glossary-registry";
import { GUIDE_SLUGS, GUIDES } from "@/lib/library/guides-manifest";
import { PLAN_SLUGS, PLANS } from "@/lib/library/plans-registry";
import { MODEL_IDS } from "@/lib/library/pricing-data";
import { eligibleModelSlugs, modelIdFromSlug, VENDORS } from "@/lib/library/pricing-registry";
import {
	eligibleProviderSlugs,
	eligibleProviders,
	indexableProviderSlugs,
	PROVIDER_SLUG,
	PROVIDER_SLUG_TO_ID,
	providerBySlug,
	providerLibraryDataScore,
	providerSlug,
} from "@/lib/library/provider-registry";
import { LIBRARY_SECTIONS } from "@/lib/library/sections";
import { libraryUrlEntries, libraryUrlPaths } from "@/lib/library/sitemap-entries";
import { PROVIDERS } from "@/lib/site";

describe("library structure & registries", () => {
	it("freezes registry counts (computed by the gate, never a hand-picked target)", () => {
		expect(MODEL_IDS.length).toBe(112);
		expect(eligibleModelSlugs()).toHaveLength(49);
		expect(VENDORS).toHaveLength(7);
		expect(VENDOR_FAMILY_SLUGS).toHaveLength(7);
		expect(LIBRARY_SECTIONS).toHaveLength(9);
		expect(PLANS).toHaveLength(9);
		expect(PLAN_SLUGS).toHaveLength(9);
		expect(COMPETITORS).toHaveLength(10);
		expect(ALTERNATIVES_ANCHORS).toHaveLength(8);
		expect(CALCULATORS).toHaveLength(9);
		expect(CALCULATOR_SLUGS).toHaveLength(9);
		expect(GUIDES).toHaveLength(13);
		expect(GUIDE_SLUGS).toHaveLength(13);
		expect(GLOSSARY).toHaveLength(14);
		expect(GLOSSARY_SLUGS).toHaveLength(14);
		expect(COMPARE_PAIRS).toHaveLength(15);
		expect(COMPARE_SLUGS).toHaveLength(15);
		expect(LIMIT_PROVIDER_SLUGS).toHaveLength(7);
		expect(LIMIT_PROVIDER_SLUGS).toContain("grok");
		expect(LIBRARY_DATA_SCORE_GATE).toBe(2);
		expect(JP_COMPETITOR_ROW.slug).toBe("jp-the-cat");
	});

	it("gates provider-track to live + >=2 source providers (_docs/08-growth.md SEO guardrails)", () => {
		expect(eligibleProviders()).toHaveLength(21);
		const slugs = eligibleProviderSlugs();
		for (const live of ["claude-code", "codex", "grok", "muse-spark", "opencode", "opencodego"]) {
			expect(slugs).toContain(live);
		}
		for (const roadmap of ["gemini", "github-copilot", "antigravity"]) {
			expect(slugs).toContain(roadmap);
		}
		expect(indexableProviderSlugs().sort()).toEqual([
			"claude-code",
			"codex",
			"grok",
			"muse-spark",
			"opencode",
			"opencodego",
		]);
		// Single-source stubs stay below the gate.
		expect(slugs).not.toContain("aider");
		expect(slugs).not.toContain("ollama");
		expect(providerLibraryDataScore(providerBySlug("claude-code")!)).toBeGreaterThanOrEqual(4);
	});

	it("gives every provider a unique slug that round-trips", () => {
		const slugs = PROVIDERS.map((provider) => PROVIDER_SLUG[provider.id]);
		expect(new Set(slugs).size).toBe(PROVIDERS.length);
		expect(PROVIDER_SLUG_TO_ID["claude-code"]).toBe("claude");
		expect(PROVIDER_SLUG_TO_ID["github-copilot"]).toBe("copilot");
		expect(providerSlug(providerBySlug("codex")!)).toBe("codex");
		expect(modelIdFromSlug("gpt-5-3-codex")).toBe("gpt-5.3-codex");
	});

	it("builds a deterministic, eligibility-gated sitemap URL set", () => {
		const paths = libraryUrlPaths();
		const indexableLeaves = LIBRARY_SECTIONS.reduce(
			(total, section) =>
				total +
				(section.slug === "track"
					? indexableProviderSlugs().length
					: eligibleSlugsForSection(section.slug).length),
			0,
		);
		expect(paths).toContain("/library");
		expect(paths).toContain("/library/pricing");
		expect(paths).toContain("/library/pricing/family/claude");
		expect(paths).toContain("/library/pricing/claude-opus-4-8");
		expect(paths).toContain("/library/pricing/claude-sonnet-5");
		expect(paths).toContain("/library/pricing/claude-sonnet-5-5");
		expect(paths).toContain("/library/pricing/claude-haiku-5-5");
		expect(paths).toContain("/library/pricing/gpt-6-1-sol");
		expect(paths).toContain("/library/pricing/gpt-5-3-codex-spark");
		// hub + 9 sections + 5 vendor-family + all eligible leaves.
		expect(paths).toHaveLength(1 + 9 + 7 + indexableLeaves);
		expect(paths).toContain("/library/pricing/family/meta");
		expect(paths).toContain("/library/track/muse-spark");
		expect(paths).not.toContain("/library/track/github-copilot");
		expect(paths).not.toContain("/library/track/cursor");
		// No ineligible slug leaks into the sitemap.
		expect(paths).not.toContain("/library/pricing/gpt-5-4-mini");
		expect(paths).not.toContain("/library/track/aider");
		expect(isLibrarySlugEligible("pricing", "gpt-5-4-mini")).toBe(false);
		expect(isLibrarySlugEligible("pricing", "claude-opus-4-8")).toBe(true);
		// Deterministic + unique.
		expect(libraryUrlPaths()).toEqual(paths);
		expect(new Set(paths).size).toBe(paths.length);
		expect(libraryUrlEntries().every((entry) => entry.priority > 0 && entry.priority <= 1)).toBe(
			true,
		);
	});

	it("every vendor family page's related links point at an eligible (non-404) pricing route", () => {
		const eligiblePricingPaths = new Set(
			eligibleModelSlugs().map((slug) => `/library/pricing/${slug}`),
		);
		for (const vendor of VENDORS) {
			for (const link of vendorLeaf(vendor).related ?? []) {
				expect(
					eligiblePricingPaths.has(link.href),
					`${vendor} links ${link.href}, which is not an eligible pricing route`,
				).toBe(true);
			}
		}
	});

	it("every glossary term's related link resolves to a real (non-404) library route", () => {
		const validPaths = new Set(libraryUrlPaths());
		for (const term of GLOSSARY) {
			expect(
				validPaths.has(term.related),
				`glossary "${term.slug}" links ${term.related}, which is not a live library route`,
			).toBe(true);
		}
	});
});
