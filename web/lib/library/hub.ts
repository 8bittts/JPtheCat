/**
 * Link builders for the root hub and each section hub. Centralizes the leaf-card labels/meta so
 * every hub route stays a few lines. All labels come from the registries (real data).
 */

import { CALCULATORS } from "./calculators-manifest";
import { COMPETITORS } from "./competitors-registry";
import { comparePairTitle } from "./content/compare";
import { usdPerMTok } from "./content/shared";
import {
	COMPARE_PAIRS,
	eligibleSlugsForSection,
	LIMIT_PROVIDER_SLUGS,
	VENDOR_FAMILY_SLUGS,
} from "./eligibility";
import { GLOSSARY } from "./glossary-registry";
import { GUIDES } from "./guides-manifest";
import { PLANS } from "./plans-registry";
import {
	MODEL_DISPLAY_NAME,
	MODEL_SLUG_TO_ID,
	perMillion,
	pricing,
	VENDOR_LABEL,
	VENDORS,
} from "./pricing-registry";
import { providerBySlug } from "./provider-registry";
import { LIBRARY_SECTIONS, type LibrarySectionSlug } from "./sections";

export interface HubLink {
	href: string;
	title: string;
	meta?: string;
}

export function rootHubSections(): HubLink[] {
	return LIBRARY_SECTIONS.map((section) => {
		const count =
			section.slug === "pricing"
				? eligibleSlugsForSection("pricing").length + VENDOR_FAMILY_SLUGS.length
				: eligibleSlugsForSection(section.slug).length;
		return {
			href: `/library/${section.slug}`,
			title: section.label,
			meta: `${count} ${count === 1 ? "page" : "pages"}`,
		};
	});
}

export function sectionLinks(section: LibrarySectionSlug): HubLink[] {
	switch (section) {
		case "pricing": {
			const families = VENDORS.map((vendor) => ({
				href: `/library/pricing/family/${vendor}`,
				title: `${VENDOR_LABEL[vendor]} — all models`,
				meta: "vendor table",
			}));
			const models = eligibleSlugsForSection("pricing").map((slug) => {
				const id = MODEL_SLUG_TO_ID[slug];
				const p = pricing(id);
				return {
					href: `/library/pricing/${slug}`,
					title: MODEL_DISPLAY_NAME[id],
					meta: `${usdPerMTok(perMillion(p.input_cost_per_token))} in · ${usdPerMTok(perMillion(p.output_cost_per_token))} out / 1M`,
				};
			});
			return [...families, ...models];
		}
		case "track":
			return eligibleSlugsForSection("track").map((slug) => {
				const provider = providerBySlug(slug);
				return {
					href: `/library/track/${slug}`,
					title: provider?.name ?? slug,
					meta: provider?.live
						? "live · tracked today"
						: `roadmap · ${provider?.statusLabel ?? ""}`,
				};
			});
		case "limits":
			return LIMIT_PROVIDER_SLUGS.map((slug) => {
				const provider = providerBySlug(slug);
				return {
					href: `/library/limits/${slug}`,
					title: `${provider?.name ?? slug} limits`,
					meta: provider?.live ? "live" : "reference",
				};
			});
		case "plans":
			return PLANS.map((plan) => ({
				href: `/library/plans/${plan.slug}`,
				title: plan.displayName,
				meta: `$${plan.priceUsdMonthly}/mo`,
			}));
		case "calculators":
			return CALCULATORS.map((calc) => ({
				href: `/library/calculators/${calc.slug}`,
				title: calc.title,
				meta: calc.notional ? "notional" : "calculator",
			}));
		case "compare":
			return COMPARE_PAIRS.map((pair) => ({
				href: `/library/compare/${pair.slug}`,
				title: comparePairTitle(pair),
				meta: pair.kind === "tool" ? "trackers" : "models",
			}));
		case "alternatives":
			return eligibleSlugsForSection("alternatives").map((slug) => {
				const tool = COMPETITORS.find((entry) => entry.slug === slug);
				return {
					href: `/library/alternatives/${slug}`,
					title: `${tool?.name ?? slug} alternatives`,
					meta: tool?.price,
				};
			});
		case "guides":
			return GUIDES.map((guide) => ({ href: `/library/guides/${guide.slug}`, title: guide.title }));
		case "glossary":
			return GLOSSARY.map((term) => ({
				href: `/library/glossary/${term.slug}`,
				title: term.term,
				meta: term.short.length > 72 ? `${term.short.slice(0, 69)}…` : term.short,
			}));
	}
}
