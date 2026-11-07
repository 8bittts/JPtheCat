import {
	isModelPricingEligible,
	isSubscriptionNotional,
	MODEL_SLUG,
	modelsForVendor,
	type PricingVendor,
	VENDOR_LABEL,
	VENDORS,
} from "../pricing-registry";
import type { LeafContent } from "./shared";

export function vendorBySlug(slug: string): PricingVendor | undefined {
	return VENDORS.find((vendor) => vendor === slug);
}

function subscriptionNote(vendor: PricingVendor): string {
	switch (vendor) {
		case "openai":
			return "On a Codex / ChatGPT subscription, these list prices are notional — what usage would cost at API rates, not metered spend.";
		case "gemini":
			return "On a Gemini CLI / Code Assist subscription, these list prices are notional — what usage would cost at API rates, not metered spend.";
		case "xai":
			return "On Grok Build under SuperGrok or X Premium+, these list prices are notional — what usage would cost at xAI API rates (https://docs.x.ai/developers/pricing), not subscription spend.";
		case "meta":
			return "On Muse Spark via the Meta Model API (including OpenCode sessions), these list prices are notional — what usage would cost at published Meta API rates, not a different billing plan.";
		case "deepseek":
			return "On OpenCode Zen (pay-as-you-go) or OpenCode Go ($10/month), these are the gateway's published list prices (opencode.ai/docs/zen and opencode.ai/docs/go) — a notional figure for what the turns would cost at those rates, not a metered bill from DeepSeek.";
		case "opencode":
			return "OpenCode Zen serves its own house models free; OpenCode Go ($10/month) meters glm-*, kimi-*, qwen-*, minimax-*, mimo-, longcat- and hy- models at published per-token rates. JP mirrors those Go list prices as notional figures.";
		case "claude":
			return "Claude Code computes real per-token cost from your local logs at these rates.";
	}
}

export function vendorLeaf(vendor: PricingVendor): LeafContent {
	const models = modelsForVendor(vendor);
	const notional = isSubscriptionNotional(models[0]);
	const label = VENDOR_LABEL[vendor];

	const sections = [
		{
			heading: "How to read this table",
			body:
				vendor === "xai"
					? "Prices are USD per million tokens. Rows marked OpenCode use that gateway’s table; other rows use xAI API list rates (docs.x.ai/developers/pricing). Cached-input rates are model-specific on xAI — not a flat 0.1× of input — and appear in the table when the vendor publishes them."
					: "Prices are USD per million tokens from the bundled table. Historical rates that could not be verified are labelled beside the model. Cache reads usually cost less than full input (often about a tenth for Claude/OpenAI/Gemini); context thresholds vary by model and gateway; a recorded context tier reprices the whole request.",
		},
		{
			heading: vendor === "claude" ? "Tokenizer note" : "Subscription note",
			body:
				vendor === "claude"
					? "Opus 4.7+, Fable 5+, Sonnet 5+, and Haiku 5.5 use a newer tokenizer that emits ~30% more tokens for the same text, so the same prompt costs more even at an unchanged rate. Sonnet 4.6 and Haiku 4.5 use the old tokenizer."
					: subscriptionNote(vendor),
		},
	];

	const cheapestAnswer =
		vendor === "xai"
			? "Among models JP prices, Grok Build 0.1 is the lowest per-token code tier; Grok 4.3 / 4.20 are mid; Grok 4.7 / 4.6 are the frontier rate. The table distinguishes direct and gateway rates."
			: "The flash / mini / haiku tiers are the lowest per-token; the pro / opus tiers cost more but reason harder. The table shows the exact rates.";

	return {
		title: `${label} model pricing`,
		description: `${label} models compared: per-million-token input, output, and cache rates at API list prices.`,
		lede: `Every ${label} model JP prices, side by side — input, output, and cache rates per million tokens.`,
		sections,
		faq: [
			{
				question: `Which ${label} model is cheapest?`,
				answer: cheapestAnswer,
			},
			...(vendor === "xai"
				? [
						{
							question: "Where do these xAI rates come from?",
							answer:
								"Official xAI developer pricing at https://docs.x.ai/developers/pricing, plus each model's cached-input line on its model page. JP mirrors those list rates for notional Grok Build cost.",
						},
					]
				: []),
		],
		// Only link models whose pricing page actually exists — the route is eligibility-gated
		// (`isModelPricingEligible`), so an ineligible model's link would 404. Use the canonical
		// `MODEL_SLUG` map, not an inline slug transform, so these can't drift from the real routes.
		related: models
			.filter(isModelPricingEligible)
			.slice(0, 4)
			.map((id) => ({
				href: `/library/pricing/${MODEL_SLUG[id]}`,
				label: `${id} pricing`,
			})),
		honesty: notional
			? {
					tone: "notional",
					text: `${label} usage on a subscription is metered as a flat plan, so these per-token figures are list price, not spend.`,
				}
			: {
					tone: "neutral",
					text: "Claude Code computes real per-token cost from your local logs at these rates.",
				},
	};
}
