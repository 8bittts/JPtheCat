/**
 * Library view over the canonical provider catalog (`@/lib/site` PROVIDERS stays the source of
 * truth). Adds URL-safe slugs, a track-page eligibility gate, and honest live/roadmap branching.
 *
 * [CRITICAL] `status` (honesty) and track-eligibility (thin gate) are SEPARATE inputs (_docs/08-growth.md SEO guardrails): the gate decides IF a page exists; `status` decides WHAT it may claim. Only the `live`
 * catalog entries (`liveProviderIds`) may be called tracked — no roadmap page may claim JP tracks it today.
 */

import { PROVIDERS, type Provider } from "@/lib/site";

/** Friendly slug overrides; every other provider slug is its catalog id. */
const PROVIDER_SLUG_OVERRIDES: Record<string, string> = {
	claude: "claude-code",
	copilot: "github-copilot",
	muse_spark: "muse-spark",
	grok_bot: "grok-bot",
	factory: "droid",
	zai: "z-ai",
	vertexai: "vertex-ai",
	jetbrains: "jetbrains-ai",
	kimik2: "kimi-k2",
};

export const PROVIDER_SLUG: Record<string, string> = Object.fromEntries(
	PROVIDERS.map((provider) => [provider.id, PROVIDER_SLUG_OVERRIDES[provider.id] ?? provider.id]),
);

export const PROVIDER_SLUG_TO_ID: Record<string, string> = Object.fromEntries(
	PROVIDERS.map((provider) => [PROVIDER_SLUG[provider.id], provider.id]),
);

export function providerBySlug(slug: string): Provider | undefined {
	const id = PROVIDER_SLUG_TO_ID[slug];
	return id ? PROVIDERS.find((provider) => provider.id === id) : undefined;
}

export function providerSlug(provider: Provider): string {
	return PROVIDER_SLUG[provider.id];
}

/**
 * Track-page thin gate: live, or a roadmap provider that shows up in >=2 real tracker catalogs
 * (genuine multi-source informational demand). Single-source api-roadmap stubs stay below the gate
 * until a parser or second signal lands (_docs/08-growth.md SEO guardrails).
 */
function isProviderTrackEligible(provider: Provider): boolean {
	return provider.live || provider.sources.length >= 2;
}

export function eligibleProviders(): Provider[] {
	return PROVIDERS.filter(isProviderTrackEligible);
}

export function eligibleProviderSlugs(): string[] {
	return eligibleProviders().map(providerSlug);
}

/** Only provider pages with shipped, provider-specific product substance belong in search. */
export function indexableProviderSlugs(): string[] {
	return eligibleProviders().flatMap((provider) => (provider.live ? [providerSlug(provider)] : []));
}

/** The live providers — the only ones a page may say JP "tracks today". */
export function liveProviderIds(): string[] {
	return PROVIDERS.flatMap((provider) => (provider.live ? [provider.id] : []));
}

/** The live set as prose, derived from the catalog so copy never lists a stale subset. */
export function liveProviderNames(): string {
	const names = PROVIDERS.flatMap((provider) => (provider.live ? [provider.name] : []));
	if (names.length < 3) return names.join(" and ");
	return `${names.slice(0, -1).join(", ")}, and ${names.at(-1)}`;
}

/** How many catalog providers are roadmap entries rather than live. */
export function roadmapProviderCount(): number {
	return PROVIDERS.filter((provider) => !provider.live).length;
}

/** A real data-point count for transparency/tests (sources + live weight). Not the gate itself. */
export function providerLibraryDataScore(provider: Provider): number {
	return provider.sources.length + (provider.live ? 2 : 0);
}
