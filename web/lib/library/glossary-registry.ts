/**
 * Glossary terms gated on real backing: a definition PLUS a JP-specific numeric mechanic from the
 * pricing table AND an outbound link to a pricing/calculator/limits page (_docs/08-growth.md SEO guardrails).
 * Starts with the terms that clear the gate; more are added only as each earns backing.
 */

export interface GlossaryTerm {
	slug: string;
	term: string;
	short: string;
	/** The concrete numeric mechanic that makes this term matter for cost. */
	mechanic: string;
	/** Outbound `/library/...` target this term should link into. */
	related: string;
}

export const GLOSSARY: GlossaryTerm[] = [
	{
		slug: "prompt-caching",
		term: "Prompt caching",
		short:
			"Reusing a previously-sent context prefix instead of paying full input price for it again.",
		mechanic:
			"On most Claude models cache reads cost 0.1x the input rate (0.05x on Opus 5.5, 0.025x on Fable 5.1); the first write costs 1.25x (5-min) or 2x (1-hour).",
		related: "/library/calculators/prompt-cache-savings",
	},
	{
		slug: "cache-read-vs-cache-write",
		term: "Cache read vs cache write",
		short: "The difference between paying to store context (write) and paying to reuse it (read).",
		mechanic:
			"Write: 1.25x input (5-min) or 2x input (1-hour). Read: 0.1x input on most Claude models, 0.05x on Opus 5.5, 0.025x on Fable 5.1.",
		related: "/library/pricing/claude-opus-4-8",
	},
	{
		slug: "ephemeral-5m-vs-1h-cache",
		term: "Ephemeral 5-minute vs 1-hour cache",
		short:
			"Claude's two cache-write durations, billed at different rates — the split most trackers ignore.",
		mechanic:
			"5-minute write = 1.25x input; 1-hour write = 2x input. Pricing all writes at 1.25x under-bills 1-hour writes by 37.5%.",
		related: "/library/guides/historical-ccusage-cache-cost-bug",
	},
	{
		slug: "context-window",
		term: "Context window",
		short: "The maximum tokens a model can consider at once, including your whole conversation.",
		mechanic:
			"Crossing 200K (Claude/Gemini) or 272K (OpenAI) tokens moves the whole request to a premium tier.",
		related: "/library/glossary/context-cliff",
	},
	{
		slug: "context-cliff",
		term: "Context cliff",
		short:
			"The point where a request gets billed at a higher per-token tier for exceeding a context threshold.",
		mechanic:
			"Above 200K (Claude/Gemini) input is ~2x and output ~1.5x for the ENTIRE request, not just the overflow.",
		related: "/library/calculators/context-200k-surcharge",
	},
	{
		slug: "tokenizer",
		term: "Tokenizer",
		short: "How text is split into tokens — the unit you're billed on.",
		mechanic:
			"The newer Opus/Fable/Sonnet-5 tokenizer emits ~30% more tokens for the same text, raising cost at the same rate.",
		related: "/library/guides/new-tokenizer-30-percent-more-tokens",
	},
	{
		slug: "notional-vs-real-cost",
		term: "Notional vs real cost",
		short:
			"Whether a dollar figure is what you actually spent or what usage would cost at list prices.",
		mechanic:
			"Claude Code cost is computed from real per-token counts; Codex is a subscription, so its $ is notional list price.",
		related: "/library/guides/real-vs-notional-cost",
	},
	{
		slug: "list-price",
		term: "List price",
		short: "A provider's published per-token API rate, before any subscription or discount.",
		mechanic:
			"Batch API is 50% off; a cached batch can be ~5% of standard — so list price is an upper bound.",
		related: "/library/pricing",
	},
	{
		slug: "used-percent",
		term: "Used percent",
		short: "How much of a rate-limit window you've consumed, as reported by the provider itself.",
		mechanic:
			"JP reads Codex used_percent automatically and Claude's only via the opt-in statusline capture — never an estimate.",
		related: "/library/limits/codex",
	},
	{
		slug: "burn-rate",
		term: "Burn rate",
		short: "How fast you're spending tokens or dollars over a window.",
		mechanic:
			"Projected onto the 5-hour window, burn rate predicts whether you'll hit the cap before it resets.",
		related: "/library/guides/understand-the-5-hour-window",
	},
	{
		slug: "reasoning-tokens",
		term: "Reasoning tokens",
		short: "Hidden 'thinking' tokens a model generates before its visible answer.",
		mechanic:
			"They are billed as output tokens and are already inside the output count — never double-count them.",
		related: "/library/pricing/claude-opus-4-8",
	},
	{
		slug: "five-hour-window",
		term: "5-hour window",
		short:
			"A rolling usage window that starts on your first message and caps how much you can do in 5 hours.",
		mechanic: "It resets 5 hours after it opened, independent of the separate weekly cap.",
		related: "/library/limits/claude-code",
	},
	{
		slug: "weekly-window",
		term: "Weekly window",
		short: "A 7-day usage cap that resets at a fixed time regardless of the 5-hour window.",
		mechanic:
			"Resets at a fixed day and time assigned to the account; Max plans can add separate model-specific weekly allowances.",
		related: "/library/limits/claude-code",
	},
	{
		slug: "blended-cost-per-mtok",
		term: "Blended $/MTok",
		short:
			"A single effective per-million-token price across a mix of input, output, and cache tokens.",
		mechanic:
			"It weights each token type by its real rate, so heavy cache reuse lowers the blended figure well under output price.",
		related: "/library/calculators/tokens-to-dollars",
	},
];

export const GLOSSARY_SLUGS = GLOSSARY.map((term) => term.slug);
