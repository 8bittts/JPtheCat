/**
 * The `/library` section hubs. `/library` (root) links down to each; each section grids its own
 * eligible leaf cards. The sitemap points crawlers at these; nav/footer never mention `/library`
 * (_docs/08-growth.md SEO guardrails). Static metadata only — child counts are computed in `eligibility.ts`
 * to avoid a circular import.
 */

export type LibrarySectionSlug =
	| "track"
	| "pricing"
	| "calculators"
	| "limits"
	| "plans"
	| "compare"
	| "alternatives"
	| "guides"
	| "glossary";

export interface LibrarySection {
	slug: LibrarySectionSlug;
	label: string;
	title: string;
	description: string;
}

export const LIBRARY_SECTIONS: LibrarySection[] = [
	{
		slug: "track",
		label: "Track usage",
		title: "Track AI coding agent usage & cost on macOS",
		description:
			"Which coding agents JP the Cat tracks today, from Claude Code and Codex to OpenCode Zen and Go, and where every other provider sits on the roadmap.",
	},
	{
		slug: "pricing",
		label: "Model pricing",
		title: "AI model pricing — cost per million tokens",
		description:
			"Per-token API list prices for Claude, OpenAI/Codex, Gemini, and xAI/Grok models JP prices, including cache and context tiers where published.",
	},
	{
		slug: "calculators",
		label: "Calculators",
		title: "AI token cost calculators",
		description:
			"Estimate token spend, cache savings, and monthly cost from real bundled pricing — with notional-vs-real labels.",
	},
	{
		slug: "limits",
		label: "Usage limits",
		title: "AI coding agent usage limits explained",
		description:
			"How the 5-hour and weekly rate-limit windows work for the providers JP tracks, and when they reset.",
	},
	{
		slug: "plans",
		label: "Plans",
		title: "AI coding subscription plans & limits",
		description:
			"What each Claude, ChatGPT/Codex, Cursor, and Copilot tier actually gets you — price, multiplier, and window mechanics.",
	},
	{
		slug: "compare",
		label: "Comparisons",
		title: "AI usage trackers & models compared",
		description: "Head-to-head comparisons of usage trackers and of model cost per million tokens.",
	},
	{
		slug: "alternatives",
		label: "Alternatives",
		title: "AI usage tracker alternatives for macOS",
		description:
			"Honest alternatives to the popular AI coding cost and usage trackers, including free and open-source options.",
	},
	{
		slug: "guides",
		label: "Guides",
		title: "How to track & reduce AI coding cost",
		description:
			"Step-by-step guides for checking, reducing, and understanding what your coding agents cost.",
	},
	{
		slug: "glossary",
		label: "Glossary",
		title: "AI coding cost glossary",
		description:
			"Plain definitions of the tokens, caching, and rate-limit terms that drive what you pay.",
	},
];
