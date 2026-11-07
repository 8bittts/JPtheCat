import { describe, expect, it } from "bun:test";
import { ALTERNATIVES_ANCHORS } from "@/lib/library/competitors-registry";
import { alternativeAnchor, alternativesLeaf } from "@/lib/library/content/alternatives";
import { compareBySlug, compareLeaf } from "@/lib/library/content/compare";
import { guideBySlug, guideLeaf } from "@/lib/library/content/guides";
import { limitLeaf } from "@/lib/library/content/limits";
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
import { COMPARE_SLUGS } from "@/lib/library/eligibility";
import { GLOSSARY } from "@/lib/library/glossary-registry";
import { GUIDE_SLUGS } from "@/lib/library/guides-manifest";
import { PLANS } from "@/lib/library/plans-registry";
import type { ModelId } from "@/lib/library/pricing-data";
import { eligibleModelIds, isSubscriptionNotional } from "@/lib/library/pricing-registry";
import { eligibleProviders, liveProviderIds } from "@/lib/library/provider-registry";
import type { Provider } from "@/lib/site";

function escapeRegExp(text: string): string {
	return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function providerPageText(provider: Provider): string {
	return [
		providerTrackTitle(provider),
		providerTrackDescription(provider),
		providerTrackLead(provider),
		providerTrackBody(provider),
		...providerTrackFaq(provider).flatMap((item) => [item.question, item.answer]),
	].join(" ");
}

function pricingPageText(id: ModelId): string {
	return [
		pricingTitle(id),
		pricingDescription(id),
		pricingLead(id),
		pricingHonestyNote(id),
		...pricingFaq(id).flatMap((item) => [item.question, item.answer]),
	].join(" ");
}

// [CRITICAL] The honesty gate asserts on RENDERED generator output, not registry inspection
// (_docs/08-growth.md SEO guardrails).
describe("library honesty gate", () => {
	it("keeps the live set to the shipped agents and the two OpenCode gateways", () => {
		expect(liveProviderIds().sort()).toEqual([
			"claude",
			"codex",
			"grok",
			"muse_spark",
			"opencode",
			"opencodego",
		]);
	});

	it("never lets a roadmap provider page claim JP tracks it today", () => {
		for (const provider of eligibleProviders().filter((candidate) => !candidate.live)) {
			const text = providerPageText(provider);
			const overclaim = new RegExp(
				`tracks?\\s+${escapeRegExp(provider.name)}[^.]*\\b(today|now|live)\\b`,
				"i",
			);
			expect(text).not.toMatch(overclaim);
			expect(text.toLowerCase()).toContain("does not track");
			expect(text).toContain(provider.statusLabel);
		}
	});

	it("lets live provider pages say JP tracks them", () => {
		for (const provider of eligibleProviders().filter((candidate) => candidate.live)) {
			expect(providerPageText(provider)).toMatch(
				new RegExp(`tracks ${escapeRegExp(provider.name)}`),
			);
		}
	});

	it("scopes Muse Spark to OpenCode on this Mac, not the Meta account dashboard", () => {
		const muse = eligibleProviders().find((candidate) => candidate.id === "muse_spark");
		expect(muse).toBeDefined();
		const text = providerPageText(muse as Provider).toLowerCase();
		expect(text).toContain("opencode");
		expect(text).toContain("meta account dashboard");
		expect(text).not.toMatch(/official 5-hour and weekly/);
	});

	it("marks every subscription-notional model page with a notional/list-price basis", () => {
		for (const id of eligibleModelIds()) {
			const text = pricingPageText(id).toLowerCase();
			if (isSubscriptionNotional(id)) {
				expect(text).toContain("notional");
				expect(text).toContain("list price");
			} else {
				expect(text).toContain("real");
				expect(text).not.toContain("notional");
			}
		}
	});

	it("describes the ccusage #899 cache-write bug only as fixed history", () => {
		const leaves = [
			...GUIDE_SLUGS.flatMap((slug) => {
				const guide = guideBySlug(slug);
				return guide ? [guideLeaf(guide)] : [];
			}),
			...COMPARE_SLUGS.flatMap((slug) => {
				const pair = compareBySlug(slug);
				return pair ? [compareLeaf(pair)] : [];
			}),
			...ALTERNATIVES_ANCHORS.flatMap((slug) => {
				const anchor = alternativeAnchor(slug);
				return anchor ? [alternativesLeaf(anchor)] : [];
			}),
		];
		expect(leaves.length).toBeGreaterThan(30);
		const sentences = JSON.stringify(leaves).split(/(?<=[.!?])\s+|"/);
		const claims = sentences.filter((sentence) => sentence.includes("under-bill"));
		expect(claims.length).toBeGreaterThan(0);
		for (const claim of claims) {
			expect(claim).toMatch(
				/once|historical|since fixed|fixed upstream|would|Pricing all|\bwere\b|\bwas\b/i,
			);
		}
	});

	it("keeps Claude reset mechanics and Copilot overage pricing current", () => {
		const claude = eligibleProviders().find((provider) => provider.id === "claude");
		const copilot = eligibleProviders().find((provider) => provider.id === "copilot");
		expect(claude).toBeDefined();
		expect(copilot).toBeDefined();
		const text = [
			JSON.stringify(limitLeaf(claude as Provider)),
			JSON.stringify(limitLeaf(copilot as Provider)),
			JSON.stringify(PLANS),
			JSON.stringify(GLOSSARY),
		].join(" ");
		expect(text).toContain("$0.04");
		expect(text).toContain("fixed day and time assigned");
		expect(text).not.toContain("$0.01");
		expect(text).not.toContain("7 days after");
	});
});
