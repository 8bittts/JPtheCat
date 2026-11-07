import { CALCULATORS, type CalculatorEntry } from "../calculators-manifest";
import type { ModelId } from "../pricing-data";
import {
	isSubscriptionNotional,
	MODEL_DISPLAY_NAME,
	MODEL_SLUG,
	modelsForVendor,
	pricing,
} from "../pricing-registry";
import type { LeafContent, RelatedLink } from "./shared";

export interface CalcModel {
	id: ModelId;
	label: string;
	input: number;
	output: number;
	cacheRead: number;
	/** 5-minute cache-write rate; falls back to 1.25x input exactly like the app's CostCalculator. */
	cacheWrite: number;
	/** Whole-request context surcharge, when the model publishes one. */
	tier?: CalcContextTier;
	/** Subscription-vendor list price (Codex/Gemini/Grok/Muse Spark), not metered spend. */
	notional: boolean;
}

interface CalcContextTier {
	/** Largest prompt (input + cache read + cache write) still billed at base rates. */
	lastBaseTokens: number;
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
}

/** Calculators whose inputs describe ONE request, so the context surcharge applies to their totals. */
export type CalculatorMode = "session" | "request";

export function calculatorMode(calc: CalculatorEntry): CalculatorMode {
	return calc.slug === "context-200k-surcharge" ? "request" : "session";
}

export function calculatorBySlug(slug: string): CalculatorEntry | undefined {
	return CALCULATORS.find((calc) => calc.slug === slug);
}

/** Mirrors `PricingTable.lastBaseContextTokenCount` + `CostCalculator.cost(model:usage:forceTier:)`. */
function calcTier(id: ModelId): CalcContextTier | undefined {
	const p = pricing(id);
	const input = p.input_cost_per_token_above_200k_tokens;
	if (input === undefined) return undefined;
	const threshold = p.context_tier_threshold ?? 200_000;
	return {
		lastBaseTokens: threshold - (p.context_tier_inclusive ? 1 : 0),
		input,
		output: p.output_cost_per_token_above_200k_tokens ?? p.output_cost_per_token,
		cacheRead:
			p.cache_read_input_token_cost_above_200k_tokens ??
			p.cache_read_input_token_cost ??
			input * 0.1,
		cacheWrite:
			p.cache_creation_input_token_cost_above_200k_tokens ??
			p.cache_creation_input_token_cost ??
			input * 1.25,
	};
}

function calcModel(id: ModelId): CalcModel {
	const p = pricing(id);
	return {
		id,
		label: MODEL_DISPLAY_NAME[id],
		input: p.input_cost_per_token,
		output: p.output_cost_per_token,
		cacheRead: p.cache_read_input_token_cost ?? p.input_cost_per_token * 0.1,
		cacheWrite: p.cache_creation_input_token_cost ?? p.input_cost_per_token * 1.25,
		tier: calcTier(id),
		notional: isSubscriptionNotional(id),
	};
}

/** Current flagship per live vendor, newest first. Older models keep their own pricing pages. */
const SCENARIO_MODELS: ModelId[] = [
	"claude-fable-5-1",
	"claude-opus-5-5",
	"claude-sonnet-5-5",
	"claude-haiku-5-5",
	"gpt-6-astra",
	"gpt-6.1-sol",
	"gpt-5.6-sol",
	"grok-4.7",
	"muse-spark-1.3",
	"gemini-3-pro-preview",
];

const CLAUDE_CODE_MODELS: ModelId[] = [
	"claude-fable-5-1",
	"claude-opus-5-5",
	"claude-sonnet-5-5",
	"claude-haiku-5-5",
];

/** Models with a published context surcharge, so the surcharge calculator never shows a flat row. */
const SURCHARGE_MODELS: ModelId[] = [
	"claude-haiku-5-5",
	"gpt-6-astra",
	"gpt-6.1-sol",
	"gpt-5.6-sol",
	"gpt-5.5",
	"grok-4.7",
	"claude-sonnet-4-5",
	"gemini-3-pro-preview",
];

/** Which model rates power the widget for a given calculator. */
export function calculatorModels(calc: CalculatorEntry): CalcModel[] {
	if (calc.kind === "model" && calc.modelId) {
		return [calcModel(calc.modelId)];
	}
	if (calc.slug === "codex-notional-cost") {
		// Codex emits GPT-6, GPT-5.6, GPT-5.5 and GPT-5.4 ids as well as *-codex ids, so every direct
		// OpenAI row is a model Codex can bill. Gateway (-zen) rows belong to the opencode vendor.
		return modelsForVendor("openai").map(calcModel);
	}
	if (calc.slug === "claude-code-monthly-cost") return CLAUDE_CODE_MODELS.map(calcModel);
	if (calc.slug === "context-200k-surcharge") return SURCHARGE_MODELS.map(calcModel);
	return SCENARIO_MODELS.map(calcModel);
}

export function calculatorLeaf(calc: CalculatorEntry): LeafContent {
	const related: RelatedLink[] = [
		{ href: "/library/glossary/blended-cost-per-mtok", label: "Blended $/MTok" },
		{ href: "/library/pricing", label: "All model pricing" },
	];
	if (calc.kind === "model" && calc.modelId) {
		related.unshift({
			href: `/library/pricing/${MODEL_SLUG[calc.modelId]}`,
			label: `${MODEL_DISPLAY_NAME[calc.modelId]} pricing`,
		});
	}

	return {
		title: `${calc.title} calculator`,
		description: `${calc.blurb} Estimated from JP the Cat's bundled model pricing.`,
		lede: calc.blurb,
		sections: [
			{
				heading: "How the estimate works",
				body:
					calculatorMode(calc) === "request"
						? "Enter the token mix of ONE request. When input, cache reads, and cache writes together cross the model's published threshold (200K for Grok, Gemini, and Claude Sonnet 4.5; 272K for OpenAI), the WHOLE request is billed at the long-context rates — the same rule JP the Cat applies to each real turn. Totals summed across many turns never trip the surcharge on their own."
						: "The calculator prices the token counts you enter — input, output, cache reads, and 5-minute cache writes — at each model's own published rates from JP the Cat's bundled pricing table. Cache-read discounts differ by model: 0.1× input for most, 0.05× on Claude Opus 5.5, and 0.025× on Claude Fable 5.1. Session totals are priced at base rates because the long-context surcharge is decided per request; use the 200K context surcharge calculator for one large turn. 1-hour cache writes cost more and are not modeled here.",
			},
		],
		faq: [
			{
				question: "Is this calculator accurate?",
				answer:
					"It uses the same published per-token rates JP prices real usage at, so it is close — but it cannot know your exact cache reuse, which is the biggest swing factor.",
			},
		],
		related,
		honesty: calc.notional
			? {
					tone: "notional",
					text: "This estimates API list price. On a Codex or Gemini subscription that is a notional figure — what usage would cost at API rates, not metered spend.",
				}
			: calc.slug === "tokens-to-dollars"
				? {
						tone: "neutral",
						text: "Claude selections use real API list rates. Every other selection is a notional list-price estimate — what usage would cost at API rates, not metered subscription spend.",
					}
				: undefined,
	};
}
