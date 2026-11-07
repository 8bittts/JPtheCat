/**
 * Content generator for `/library/pricing/[model]`. Composed entirely from the model's real bundled
 * rates. Subscription-metered vendors (OpenAI/Codex, Gemini, xAI/Grok) get an "API list price"
 * framing + an above-the-fold notional note; Claude gets a "real cost, computed locally" note
 * (_docs/08-growth.md SEO guardrails). xAI rates source: https://docs.x.ai/developers/pricing.
 */

import { presentationModelId } from "@/lib/model-identity";
import { SEO_TITLE_MAX_LENGTH } from "@/lib/seo";
import type { ModelId } from "../pricing-data";
import { pricingCaveat } from "../pricing-provenance";
import {
	isSubscriptionNotional,
	MODEL_DISPLAY_NAME,
	modelEnrichments,
	modelVendor,
	type PricingVendor,
	perMillion,
	pricing,
	usInferenceMultiplier,
	VENDOR_LABEL,
} from "../pricing-registry";
import { type FaqItem, type LeafContent, usdPerMTok } from "./shared";

export function pricingTitle(id: ModelId): string {
	const name = MODEL_DISPLAY_NAME[id];
	if (isSubscriptionNotional(id)) return `${name} API list price — cost per token`;
	const title = `${name} pricing — cost per million tokens`;
	// A long accounting-row name (`Claude Opus 5.5 · Fast mode`) must still fit the SEO title cap.
	return title.length <= SEO_TITLE_MAX_LENGTH ? title : `${name} pricing — cost per token`;
}

export function pricingDescription(id: ModelId): string {
	const name = MODEL_DISPLAY_NAME[id];
	const p = pricing(id);
	const basis = pricingCaveat(id)
		? "historical unverified list price"
		: isSubscriptionNotional(id)
			? "API list price"
			: "pricing";
	return `${name} ${basis}: ${usdPerMTok(perMillion(p.input_cost_per_token))} per million input tokens, ${usdPerMTok(perMillion(p.output_cost_per_token))} output, plus cache and context tiers.`;
}

export function pricingLead(id: ModelId): string {
	const name = MODEL_DISPLAY_NAME[id];
	const p = pricing(id);
	const caveat = pricingCaveat(id);
	const tierNote =
		p.input_cost_per_token_above_200k_tokens !== undefined
			? ` Requests with ${contextThresholdLabel(id)} in the prompt, including cache reads and writes, use the premium rates for the whole request.`
			: "";
	const base = `${caveat ? `${caveat} ` : ""}${name} costs ${usdPerMTok(perMillion(p.input_cost_per_token))} per million input tokens and ${usdPerMTok(perMillion(p.output_cost_per_token))} per million output tokens (USD).${tierNote}`;
	const enrichments = modelEnrichments(id);
	if (enrichments.includes("fast-mode")) {
		const tokenizer = enrichments.includes("new-tokenizer")
			? " It uses the newer tokenizer, which emits ~30% more tokens for the same text."
			: "";
		return `${base} This is the fast-mode rate, Anthropic's research-preview option for faster output. It applies across the full context window, prompt-caching multipliers stack on top, and JP the Cat applies it only to turns Claude Code logs as fast.${tokenizer}`;
	}
	if (enrichments.includes("limited-availability")) {
		return `${base} Anthropic offers it only to approved Project Glasswing customers. It also uses the newer tokenizer, which emits ~30% more tokens for the same text.`;
	}
	if (enrichments.includes("new-tokenizer")) {
		return `${base} It uses the newer tokenizer, which emits ~30% more tokens for the same text.`;
	}
	if (enrichments.includes("grok-notional")) {
		return `${base} Official rates are published at docs.x.ai/developers/pricing. On Grok Build (SuperGrok / X Premium+) this is a notional list-price figure, not subscription spend.`;
	}
	if (enrichments.includes("opencode-notional")) {
		return `${base} Rates follow the published OpenCode Zen or Go table for this model and gateway (opencode.ai/docs/zen and opencode.ai/docs/go). On OpenCode Zen or Go this is a notional list-price figure for turns logged on this Mac, not a metered vendor bill; free-tier ids stay unpriced and show as tokens.`;
	}
	if (enrichments.includes("muse-spark-notional")) {
		return `${base} On Meta's Muse models via OpenCode on this Mac (the Muse Spark row) this is a notional list-price figure (published Meta API rates), not Meta account dashboard billing and not a different plan's metered spend.`;
	}
	return base;
}

/** The subscription each notional vendor's list price is measured against. */
const SUBSCRIPTION_LABEL: Record<PricingVendor, string> = {
	claude: "",
	openai: "Codex",
	gemini: "Gemini CLI",
	xai: "Grok Build / SuperGrok",
	meta: "Muse Spark / Meta Model API",
	deepseek: "OpenCode Zen / Go",
	opencode: "OpenCode Zen / Go",
};

/** Above-the-fold provenance note — carries the notional/list-price marker for subscription vendors. */
export function pricingHonestyNote(id: ModelId): string {
	const vendor = modelVendor(id);
	const caveat = pricingCaveat(id);
	if (caveat)
		return `${caveat} These notional figures are retained for historical accounting, not a current price quote.`;
	if (isSubscriptionNotional(id)) {
		const sub = SUBSCRIPTION_LABEL[vendor];
		return `These are ${VENDOR_LABEL[vendor]} API list prices in USD. On ${sub} usage this is a notional list price — what usage would cost at API rates, not metered spend.`;
	}
	return "Claude Code computes your real per-token cost from local session logs at these rates — no estimate, no upload.";
}

export function pricingFaq(id: ModelId): FaqItem[] {
	const name = MODEL_DISPLAY_NAME[id];
	const p = pricing(id);
	const items: FaqItem[] = [
		{
			question: `How much does ${name} cost per million tokens?`,
			answer: `${usdPerMTok(perMillion(p.input_cost_per_token))} input and ${usdPerMTok(perMillion(p.output_cost_per_token))} output per million tokens (USD list price).`,
		},
	];
	if (modelEnrichments(id).includes("fast-mode")) {
		const standard = MODEL_DISPLAY_NAME[presentationModelId(id) as ModelId];
		items.push({
			question: `When does ${name} pricing apply?`,
			answer: `Only to turns that ran in fast mode, which Claude Code logs as usage.speed "fast". Standard-speed turns bill at the ${standard} rate.`,
		});
	}
	const usInference = usInferenceMultiplier(id);
	if (usInference !== undefined) {
		items.push({
			question: `Does US-only inference change ${name} pricing?`,
			answer: `Yes. A request pinned to US-only inference bills every token category at ${usInference}x these rates. JP the Cat applies it to turns Claude Code logs with inference_geo "us".`,
		});
	}
	if (modelEnrichments(id).includes("limited-availability")) {
		items.push({
			question: `Is ${name} generally available?`,
			answer: "No — Anthropic offers it only to approved Project Glasswing customers.",
		});
	}
	if (p.cache_read_input_token_cost !== undefined) {
		const cachePerM = perMillion(p.cache_read_input_token_cost);
		const inputPerM = perMillion(p.input_cost_per_token);
		const ratio = inputPerM > 0 ? cachePerM / inputPerM : 0;
		const ratioNote =
			ratio > 0.08 && ratio < 0.12
				? " — about a tenth of the input rate"
				: ratio > 0
					? ` — about ${(ratio * 100).toFixed(0)}% of the input rate`
					: "";
		items.push({
			question: `What is the cache-read price for ${name}?`,
			answer: `${usdPerMTok(cachePerM)} per million cached-read tokens${ratioNote}.`,
		});
	}
	if (
		p.cache_creation_input_token_cost !== undefined &&
		p.cache_creation_input_token_cost_above_1hr !== undefined
	) {
		items.push({
			question: `How is cache writing priced for ${name}?`,
			answer: cacheWriteDescription(
				p.cache_creation_input_token_cost,
				p.cache_creation_input_token_cost_above_1hr,
			),
		});
	}
	if (p.input_cost_per_token_above_200k_tokens !== undefined) {
		items.push({
			question: `Does ${name} have a context pricing tier?`,
			answer: `Yes — at ${contextThresholdLabel(id)} input rises to ${usdPerMTok(perMillion(p.input_cost_per_token_above_200k_tokens))} per million for the entire request.`,
		});
	}
	return items;
}

function cacheWriteDescription(short: number, long: number): string {
	const rate = usdPerMTok(perMillion(short));
	return short === long
		? `Cache writes cost ${rate} per million tokens.`
		: `Cache writes cost ${rate} for 5 minutes or ${usdPerMTok(perMillion(long))} for 1 hour, per million tokens.`;
}

function contextThresholdLabel(id: ModelId): string {
	const p = pricing(id);
	return `${p.context_tier_inclusive ? "≥" : ">"}${(p.context_tier_threshold ?? 200_000) / 1000}K tokens`;
}

export function pricingLeaf(id: ModelId): LeafContent {
	const p = pricing(id);
	const bits: string[] = [];
	if (p.cache_read_input_token_cost !== undefined) {
		const cachePerM = perMillion(p.cache_read_input_token_cost);
		const inputPerM = perMillion(p.input_cost_per_token);
		const ratio = inputPerM > 0 ? cachePerM / inputPerM : 0;
		const ratioNote =
			ratio > 0.08 && ratio < 0.12
				? " — about a tenth of input"
				: ratio > 0
					? ` — about ${(ratio * 100).toFixed(0)}% of input`
					: "";
		bits.push(`Cache reads cost ${usdPerMTok(cachePerM)} per million tokens${ratioNote}.`);
	}
	if (
		p.cache_creation_input_token_cost !== undefined &&
		p.cache_creation_input_token_cost_above_1hr !== undefined
	) {
		bits.push(
			cacheWriteDescription(
				p.cache_creation_input_token_cost,
				p.cache_creation_input_token_cost_above_1hr,
			),
		);
	}
	if (p.input_cost_per_token_above_200k_tokens !== undefined) {
		bits.push(`The ${contextThresholdLabel(id)} context tier reprices the whole request.`);
	}
	const econ =
		bits.length > 0
			? bits.join(" ")
			: `${MODEL_DISPLAY_NAME[id]} has input and output rates in the bundled table; no separate cache or context rate is recorded.`;
	const vendor = modelVendor(id);

	return {
		title: pricingTitle(id),
		description: pricingDescription(id),
		lede: pricingLead(id),
		sections: [{ heading: "Cache & context economics", body: econ }],
		faq: pricingFaq(id),
		related: [
			{ href: `/library/pricing/family/${vendor}`, label: `${VENDOR_LABEL[vendor]} models` },
			{ href: "/library/calculators/tokens-to-dollars", label: "Cost calculator" },
			...(vendor === "xai"
				? [
						{
							href: "https://docs.x.ai/developers/pricing",
							label: "Official xAI pricing",
						},
					]
				: [{ href: "/library/glossary/cache-read-vs-cache-write", label: "Cache read vs write" }]),
		],
		honesty: {
			tone: isSubscriptionNotional(id) ? "notional" : "neutral",
			text: pricingHonestyNote(id),
		},
	};
}
