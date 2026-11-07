import { PLANS, type PlanEntry } from "../plans-registry";
import { liveProviderNames, providerBySlug } from "../provider-registry";
import type { ContentSection, LeafContent } from "./shared";

export function planBySlug(slug: string): PlanEntry | undefined {
	return PLANS.find((plan) => plan.slug === slug);
}

export function planLeaf(plan: PlanEntry): LeafContent {
	const provider = providerBySlug(plan.provider);
	const providerName = provider?.name ?? plan.provider;
	const live = provider?.live ?? false;

	const sections: ContentSection[] = [
		{
			heading: "What you get",
			body: `${plan.displayName} costs $${plan.priceUsdMonthly}/month (${plan.multiplier}). ${plan.windowMechanics}`,
		},
		{
			heading: "How much usage is that?",
			body: `${plan.messageEstimate} These figures are unofficial and model-dependent — run \`/usage\` or \`/status\` for your live numbers.`,
		},
	];
	if (plan.promo) {
		sections.push({
			heading: "Time-boxed promotion",
			body: `${plan.promo.note} Verified as of ${plan.lastVerified}; treat it as expiring around ${plan.promo.expires}.`,
		});
	}

	const serp =
		plan.slug === "chatgpt-plus-codex"
			? {
					title: "Does ChatGPT Plus have a Codex limit?",
					description:
						"Yes. Plus shares a 5-hour and weekly Codex pool. How the windows work, and how to read the official used-percent — no guessed ceiling.",
				}
			: plan.slug === "chatgpt-pro-codex"
				? {
						title: "ChatGPT Pro Codex rate limits",
						description:
							"How Pro's Codex 5-hour and weekly rate-limit windows work. Official used-percent from local logs, not a published request cap.",
					}
				: {
						title: `${plan.displayName} — limits & price`,
						description: `${plan.displayName}: $${plan.priceUsdMonthly}/mo, ${plan.multiplier}. Windows, mechanics, and an honest usage estimate.`,
					};

	return {
		title: serp.title,
		description: serp.description,
		lede: `What ${plan.displayName} costs, what its limits mean, and how much real headroom it gives you.`,
		sections,
		faq: [
			{
				question: `How much does ${plan.displayName} cost?`,
				answer: `$${plan.priceUsdMonthly} per month.`,
			},
			{
				question: "Are the usage counts official?",
				answer:
					"No — they are rough, unofficial, and depend on the model and message length. Check /usage or /status for live numbers.",
			},
		],
		related: [
			{ href: `/library/limits/${plan.provider}`, label: `${providerName} limits` },
			{ href: "/library/glossary/five-hour-window", label: "5-hour window" },
		],
		honesty: {
			tone: "neutral",
			text: live
				? `JP the Cat shows your real ${providerName} usage against this plan from local logs — official percentages, not estimates.`
				: `JP the Cat does not track ${providerName} yet, so this page is reference only. ${liveProviderNames()} are tracked today.`,
		},
	};
}
