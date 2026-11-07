/**
 * Interactive cost-calculator manifest. Scenario calculators + a few flagship model calculators
 * (NOT one per model — that would cannibalize the pricing pages, _docs/08-growth.md SEO guardrails). Each computes
 * from the real bundled pricing table; Codex/Gemini outputs carry the notional label.
 */

import type { ModelId } from "./pricing-data";

export interface CalculatorEntry {
	slug: string;
	title: string;
	kind: "scenario" | "model";
	/** For `kind: "model"`, the model id whose real rates drive the widget. */
	modelId?: ModelId;
	/** Output is a notional list-price estimate (subscription providers), not metered spend. */
	notional: boolean;
	blurb: string;
}

export const CALCULATORS: CalculatorEntry[] = [
	{
		slug: "tokens-to-dollars",
		title: "Tokens to dollars",
		kind: "scenario",
		notional: false,
		blurb:
			"Convert input, output, cache-read, and cache-write token counts into a dollar cost at any model's real rates.",
	},
	{
		slug: "claude-code-monthly-cost",
		title: "Claude Code monthly cost",
		kind: "scenario",
		notional: false,
		blurb: "Project a monthly Claude Code bill from a typical day of real per-token usage.",
	},
	{
		slug: "prompt-cache-savings",
		title: "Prompt cache savings",
		kind: "scenario",
		notional: false,
		blurb:
			"See how much each model's discounted cache-read rate saves versus re-sending context every turn.",
	},
	{
		slug: "context-200k-surcharge",
		title: "200K context surcharge",
		kind: "scenario",
		notional: false,
		blurb:
			"How the >200K (and OpenAI >272K) context cliff reprices one large request: base rates versus long-context rates.",
	},
	{
		slug: "codex-notional-cost",
		title: "Codex notional cost",
		kind: "scenario",
		notional: true,
		blurb:
			"What your Codex usage would cost at API list prices — a notional figure, not real spend.",
	},
	{
		slug: "claude-opus-4-8-cost",
		title: "Claude Opus 4.8 cost",
		kind: "model",
		modelId: "claude-opus-4-8",
		notional: false,
		blurb:
			"Estimate Opus 4.8 cost across the input, output, and cache tokens you enter, at API list rates.",
	},
	{
		slug: "claude-sonnet-4-6-cost",
		title: "Claude Sonnet 4.6 cost",
		kind: "model",
		modelId: "claude-sonnet-4-6",
		notional: false,
		blurb:
			"Estimate Sonnet 4.6 cost across the input, output, and cache tokens you enter, at API list rates.",
	},
	{
		slug: "gpt-5-3-codex-cost",
		title: "GPT-5.3-Codex cost",
		kind: "model",
		modelId: "gpt-5.3-codex",
		notional: true,
		blurb:
			"Notional API-list-price cost for GPT-5.3-Codex usage — labelled, not metered subscription spend.",
	},
	{
		slug: "gemini-3-pro-cost",
		title: "Gemini 3 Pro cost",
		kind: "model",
		modelId: "gemini-3-pro-preview",
		notional: true,
		blurb: "Notional API-list-price cost for Gemini 3 Pro across input, output, and cache tokens.",
	},
];

export const CALCULATOR_SLUGS = CALCULATORS.map((calc) => calc.slug);
