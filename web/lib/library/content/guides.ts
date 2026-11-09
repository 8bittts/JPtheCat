/**
 * Curated, non-thin content for each `/library/guides/[slug]`. Every body is grounded in real
 * commands, file paths, and shipped JP the Cat features — never padded (_docs/08-growth.md SEO guardrails).
 */

import { GUIDES, type GuideEntry } from "../guides-manifest";
import type { ContentSection, FaqItem, LeafContent, RelatedLink } from "./shared";

export function guideBySlug(slug: string): GuideEntry | undefined {
	return GUIDES.find((guide) => guide.slug === slug);
}

interface GuideBody {
	description: string;
	lede: string;
	sections: ContentSection[];
	faq: FaqItem[];
	related: RelatedLink[];
}

const GUIDE_CONTENT: Record<string, GuideBody> = {
	"check-claude-code-cost": {
		description:
			"Three ways to check what Claude Code costs on macOS — the /cost command, the ccusage CLI, and a live menu-bar readout.",
		lede: "Claude Code does not show a running dollar total by default. Here are the three honest ways to see it.",
		sections: [
			{
				heading: "1. The built-in /cost command",
				body: "Inside a Claude Code session, type `/cost` for a session summary, or `/usage` for your official 5-hour and weekly limit percentages. This covers the current session only — it does not aggregate across projects or days.",
			},
			{
				heading: "2. The ccusage CLI",
				body: "`npx ccusage@latest` reads the JSONL transcripts under `~/.claude/projects` and prints per-day and per-model cost. It is free and widely used; an older `calculate` mode once under-billed 1-hour cache writes, since fixed upstream (see the cache-cost guide).",
			},
			{
				heading: "3. A live menu-bar total (JP the Cat)",
				body: "JP the Cat keeps a running dollar figure in your menu bar, computed from the same local logs and priced to the cent — including the 5-minute vs 1-hour cache-write split. Nothing leaves your Mac: no API key, no account.",
			},
		],
		faq: [
			{
				question: "Where does Claude Code store the data cost is computed from?",
				answer:
					"In JSONL transcripts under `~/.claude/projects` — each request records input, output, and cache token counts.",
			},
			{
				question: "Is the cost real money or an estimate?",
				answer:
					"It is your real per-token cost at Anthropic's published rates. On a Max subscription it is what that usage would meter at API prices.",
			},
		],
		related: [
			{ href: "/library/pricing/claude-opus-4-8", label: "Claude Opus 4.8 pricing" },
			{ href: "/library/calculators/claude-code-monthly-cost", label: "Monthly cost calculator" },
			{ href: "/library/guides/reduce-claude-code-cost", label: "Reduce your cost" },
		],
	},
	"see-codex-usage-limit": {
		description:
			"Check your Codex 5-hour and weekly usage limits on Plus or Pro from official local rate-limit data — no login or guessed ceiling.",
		lede: "Codex records its own rate-limit percentages. Here is how to check your quota without guessing.",
		sections: [
			{
				heading: "The official source",
				body: "Codex writes a `rate_limits` block (with `used_percent` and `resets_at`) into its rollout logs under `~/.codex/sessions`. That is the authoritative number — the same one OpenAI enforces.",
			},
			{
				heading: "Reading it live",
				body: "JP the Cat reads that block automatically with zero setup and shows Codex's 5-hour and weekly used-percent, tagged `official`, next to a clearly-labelled notional cost. Because Codex is a subscription, any dollar figure is list-price, not metered spend.",
			},
		],
		faq: [
			{
				question: "Does JP the Cat need my OpenAI login to read Codex usage?",
				answer:
					"No. It reads the local rollout logs Codex already writes — no credentials, no network.",
			},
			{
				question: "Why is the Codex dollar figure called notional?",
				answer:
					"Codex is billed as a flat subscription, so a per-token dollar figure is what the usage would cost at API list prices, not what you actually paid.",
			},
		],
		related: [
			{ href: "/library/limits/codex", label: "Codex limits explained" },
			{ href: "/library/guides/codex-plus-pro-rate-limits", label: "Plus and Pro rate limits" },
			{ href: "/library/glossary/used-percent", label: "What is used percent?" },
			{ href: "/library/plans/chatgpt-pro-codex", label: "ChatGPT Pro (Codex) plan" },
		],
	},
	"track-token-usage-on-macos": {
		description:
			"How to track AI coding token usage on macOS across Claude Code, Codex, Grok, Muse Spark, and OpenCode, from the local logs on your Mac.",
		lede: "Token counts drive every dollar. Here is how to watch them on macOS without sending anything to a server.",
		sections: [
			{
				heading: "Where the tokens live",
				body: "Claude Code records `input_tokens`, `output_tokens`, `cache_read_input_tokens`, and `cache_creation_input_tokens` (split into 5-minute and 1-hour) in its JSONL transcripts. Codex records rate-limit percentages in its rollout logs. Both are already on your Mac.",
			},
			{
				heading: "A glanceable readout",
				body: "JP the Cat parses those files locally and keeps a live menu-bar figure, a macOS widget, and a dashboard with per-model and per-day breakdowns. It tracks Claude Code, Codex, and Grok from their session logs, and Muse Spark from OpenCode muse-spark rows on this Mac (not your full Meta account dashboard); 59 more providers are on the roadmap.",
			},
		],
		faq: [
			{
				question: "Does tracking token usage upload my code?",
				answer:
					"Not with JP the Cat — it only reads local usage logs. Prompts, code, and transcripts never leave your Mac.",
			},
		],
		related: [
			{ href: "/library/track/claude-code", label: "Track Claude Code" },
			{ href: "/library/track/codex", label: "Track Codex" },
			{ href: "/library/glossary/blended-cost-per-mtok", label: "Blended $/MTok" },
		],
	},
	"reduce-claude-code-cost": {
		description:
			"Practical ways to reduce Claude Code cost: prompt caching, tighter context, the right model, and watching cache writes.",
		lede: "Most Claude Code spend is context you pay to re-send. A few habits cut it sharply.",
		sections: [
			{
				heading: "Lean on the cache",
				body: "On most Claude models a cache read costs 0.1× the input rate (0.05× on Opus 5.5, 0.025× on Fable 5.2, Fable 5.1, and Mythos 5.1). Keeping a stable context prefix so it can be cached — instead of reshuffling it every turn — is the single biggest lever. Reused context is nearly free; re-sent context is full price.",
			},
			{
				heading: "Right-size the model",
				body: "Haiku is a fraction of Opus per token. For routine edits and searches, a smaller model often does the job at a tenth of the cost. Reserve the largest model for the hard reasoning.",
			},
			{
				heading: "Watch the cache-write duration",
				body: "A 1-hour cache write costs 2× input; a 5-minute write costs 1.25×. Long-lived caches you do not reuse are wasted 2× writes. JP the Cat shows the 5-minute vs 1-hour split so you can see where it is going.",
			},
		],
		faq: [
			{
				question: "What is the cheapest way to run Claude Code?",
				answer:
					"Cache aggressively, keep context tight, and use the smallest model that works — cheap cache reads dominate a well-tuned session.",
			},
		],
		related: [
			{ href: "/library/glossary/prompt-caching", label: "Prompt caching" },
			{ href: "/library/glossary/cache-read-vs-cache-write", label: "Cache read vs write" },
			{ href: "/library/pricing/claude-haiku-4-5", label: "Haiku 4.5 pricing" },
		],
	},
	"enable-claude-live-limits": {
		description:
			"How to turn on Claude's official 5-hour and weekly limit tracking in JP the Cat — an opt-in, non-clobbering statusline capture.",
		lede: "Claude Code does not persist its limit percentages, so JP shows them only after you opt in. Here is the exact flow.",
		sections: [
			{
				heading: "Why it is opt-in",
				body: "Unlike Codex, Claude Code does not write its rate-limit percentages to a file. The only source is the statusline stdin feed. JP never edits your config silently — you enable it explicitly.",
			},
			{
				heading: "The steps",
				body: "Open JP the Cat → Settings → Live data → Enable Claude live limits. JP shows an acknowledgment, then appends a small, clearly-marked capture block to your statusline script (it reuses your existing stdin buffer and never rewrites `~/.claude/settings.json`). Turn it off and the block is removed. Until you opt in, Claude simply shows no limit gauge — never a wrong estimate.",
			},
		],
		faq: [
			{
				question: "Will this change my Claude Code settings?",
				answer:
					"It appends a marked block to your statusline script only, and only when it finds a reusable stdin buffer. Disabling it removes the block.",
			},
			{
				question: "Can JP estimate Claude's limits instead?",
				answer:
					"No — a token estimate cannot reproduce Claude's real limit percentage. Without the opt-in capture, JP shows no Claude gauge rather than a wrong one.",
			},
		],
		related: [
			{ href: "/library/limits/claude-code", label: "Claude Code limits" },
			{ href: "/library/glossary/used-percent", label: "What is used percent?" },
		],
	},
	"understand-the-5-hour-window": {
		description:
			"What the Claude 5-hour rate-limit window is, when it starts, when it resets, and how it differs from the weekly cap.",
		lede: "The 5-hour window is the limit most people hit first. Here is exactly how it works.",
		sections: [
			{
				heading: "A rolling window",
				body: "The 5-hour window opens on your first message and caps how much you can do in the next five hours. It resets five hours after it opened — not on a fixed clock — and runs independently of the separate weekly cap.",
			},
			{
				heading: "Reading it honestly",
				body: "JP the Cat surfaces Codex's 5-hour used-percent automatically and Claude's via the opt-in statusline capture, both tagged `official` and never presented once the reset time has passed.",
			},
		],
		faq: [
			{
				question: "When does the 5-hour window reset?",
				answer:
					"Five hours after it opened (your first message of the window), independent of the weekly cap.",
			},
		],
		related: [
			{ href: "/library/glossary/five-hour-window", label: "5-hour window (glossary)" },
			{ href: "/library/glossary/weekly-window", label: "Weekly window" },
			{ href: "/library/limits/claude-code", label: "Claude Code limits" },
		],
	},
	"why-is-claude-code-so-expensive": {
		description:
			"Why Claude Code can feel expensive — big context, cache writes, plugin/MCP overhead — and how to see where it goes.",
		lede: "Claude Code cost is rarely the model being pricey. It is usually context you pay to move around.",
		sections: [
			{
				heading: "Context is the bill",
				body: "Every turn re-sends the working context. Without caching, a large project context is paid at full input price on each request. Plugins, MCP servers, and tool outputs all add tokens you may not see.",
			},
			{
				heading: "Cache writes add up",
				body: "The first time context is cached, you pay a write — 1.25× input for 5 minutes or 2× for an hour. Reused reads are then cheap (0.1× input on most Claude models, less on Opus 5.5, Fable 5.2, Fable 5.1, and Mythos 5.1), but writes you never reuse are pure overhead.",
			},
			{
				heading: "Measure it",
				body: "JP the Cat breaks the cost down per model and shows the 5-minute vs 1-hour cache-write composition, so 'expensive' turns into a specific, fixable number.",
			},
		],
		faq: [
			{
				question: "Is a bigger model always more expensive?",
				answer:
					"Per token, yes — but a well-cached session on a large model can cost less than an uncached one on a small model. Where the tokens go matters more than the model alone.",
			},
		],
		related: [
			{ href: "/library/guides/reduce-claude-code-cost", label: "Reduce your cost" },
			{ href: "/library/glossary/context-window", label: "Context window" },
			{ href: "/library/glossary/context-cliff", label: "The context cliff" },
		],
	},
	"codex-plus-pro-rate-limits": {
		description:
			"Yes, ChatGPT Plus has a Codex rate limit. How Plus and Pro 5-hour and weekly windows work, and how to read the official used-percent on a Mac.",
		lede: "ChatGPT Plus and Pro both meter Codex. Neither plan publishes a fixed request cap. The honest number is the official used-percent Codex already writes on your Mac.",
		sections: [
			{
				heading: "Does ChatGPT Plus have a Codex limit?",
				body: "Yes. Codex on Plus shares ChatGPT's agentic-usage pool. That pool has a 5-hour window and a weekly window. OpenAI does not publish a fixed request or token ceiling for Plus, so any page that quotes one is guessing. The number that is real is the `used_percent` Codex writes into its local rollout logs.",
			},
			{
				heading: "How Pro differs",
				body: "Pro uses the same two windows — 5-hour and weekly — on a larger pool. JP does not invent a Plus-vs-Pro request count. It reads the official used-percent for whichever plan is on this Mac and labels it `official`. Dollar figures stay notional list price, because Codex is a subscription.",
			},
			{
				heading: "How to read the official number",
				body: "Codex writes a `rate_limits` block (`used_percent`, `resets_at`) under `~/.codex/sessions`. That is the same number OpenAI enforces. JP the Cat reads it automatically with no login. If the file is missing, the honest UI is no gauge — not an estimate from tokens.",
			},
		],
		faq: [
			{
				question: "Is there a Codex limit on the Plus plan?",
				answer:
					"Yes. Plus meters Codex against a 5-hour and a weekly pool. There is no published request cap; read the official used-percent Codex already stores locally.",
			},
			{
				question: "What are Codex rate limits for Pro users?",
				answer:
					"The same two windows as Plus, on a larger pool. JP shows Pro's official used-percent from the local rollout logs. It will not print a guessed Pro ceiling.",
			},
			{
				question: "Does JP need my OpenAI login to show Plus or Pro limits?",
				answer: "No. It reads the local Codex rollout logs — no credentials, no network.",
			},
		],
		related: [
			{
				href: "/library/guides/see-codex-usage-limit",
				label: "How to check your Codex usage limit",
			},
			{ href: "/library/plans/chatgpt-plus-codex", label: "ChatGPT Plus (Codex)" },
			{ href: "/library/plans/chatgpt-pro-codex", label: "ChatGPT Pro (Codex)" },
			{ href: "/library/limits/codex", label: "Codex limits explained" },
		],
	},
	"how-much-does-codex-cost": {
		description:
			"How much Codex costs — the subscription price vs the notional API list price, and why the two are different.",
		lede: "Codex is billed as a flat subscription, so 'how much does it cost' has two honest answers.",
		sections: [
			{
				heading: "What you actually pay",
				body: "Codex comes with a ChatGPT plan — $20/mo on Plus, $200/mo on Pro — and your usage is metered against a rate-limit pool, not per token. That subscription price is your real cost.",
			},
			{
				heading: "The notional list price",
				body: "It can still be useful to know what your Codex usage would cost at OpenAI's API rates. JP the Cat computes that as a clearly-labelled notional figure — never presented as real spend, because on a subscription you did not pay per token.",
			},
		],
		faq: [
			{
				question: "Does Codex charge per token?",
				answer:
					"Not on a ChatGPT subscription — it meters usage against a pool. A per-token figure is notional list price, not a bill.",
			},
		],
		related: [
			{ href: "/library/calculators/codex-notional-cost", label: "Codex notional calculator" },
			{ href: "/library/plans/chatgpt-plus-codex", label: "ChatGPT Plus (Codex)" },
			{ href: "/library/guides/real-vs-notional-cost", label: "Real vs notional cost" },
		],
	},
	"real-vs-notional-cost": {
		description:
			"Real cost vs notional list price: when an AI coding dollar figure is money you spent, and when it is an estimate.",
		lede: "The most important honesty question in usage tracking: is this number real, or is it list price?",
		sections: [
			{
				heading: "Real cost",
				body: "For Claude Code, JP computes cost from the actual per-token counts in your local logs at Anthropic's rates. That is real, metered-equivalent spend, priced to the cent.",
			},
			{
				heading: "Notional list price",
				body: "For subscription-metered providers like Codex or the Gemini CLI, per-token math produces a notional figure — what the usage would cost at API list prices, not what you paid. JP labels every such number so you always know which is which.",
			},
		],
		faq: [
			{
				question: "Why not just show one number?",
				answer:
					"Because mixing real spend with list-price estimates is how other trackers mislead. JP keeps them labelled and separate.",
			},
		],
		related: [
			{ href: "/library/glossary/notional-vs-real-cost", label: "Notional vs real (glossary)" },
			{ href: "/library/glossary/list-price", label: "List price" },
		],
	},
	"historical-ccusage-cache-cost-bug": {
		description:
			"A historical ccusage bug once under-billed 1-hour cache writes by 37.5%. Here is the bug (#899), the fix, and the guardrail JP keeps.",
		lede: "A real cache-tier accounting bug, now fixed upstream, still makes a good case study for what a trustworthy cost parser has to guard against.",
		sections: [
			{
				heading: "The historical bug",
				body: "ccusage issue #899 documented that `calculate` mode once priced every `cache_creation` token at the single 5-minute rate (1.25× input). But Claude Code predominantly writes 1-hour caches, which cost 2× input, so those writes were billed at 62.5% of their true cost — a 37.5% under-bill. That upstream bug has since been fixed.",
			},
			{
				heading: "The guardrail",
				body: "The JSONL carries the split: `usage.cache_creation.ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens`. Price the 5-minute tokens at 1.25× and the 1-hour tokens at 2× separately. JP the Cat reads that split, preserves provenance, and keeps regression coverage so this class of bug does not recur here.",
			},
		],
		faq: [
			{
				question: "Does this mean ccusage is still wrong today?",
				answer:
					"No. The point of the guide is historical and technical: the upstream bug was real, the fix is known, and JP keeps the same area explicitly guarded with parser provenance and regression tests.",
			},
		],
		related: [
			{ href: "/library/glossary/ephemeral-5m-vs-1h-cache", label: "5-minute vs 1-hour cache" },
			{ href: "/library/compare/jp-the-cat-vs-ccusage", label: "JP the Cat vs ccusage" },
			{ href: "/library/pricing/claude-opus-4-8", label: "Opus 4.8 cache pricing" },
		],
	},
	"new-tokenizer-30-percent-more-tokens": {
		description:
			"Opus 4.7+, Fable 5, and Sonnet 5 use a new tokenizer that emits ~30% more tokens for the same text — raising cost at the same rate.",
		lede: "Same rate card, higher bill: the newer models count tokens differently.",
		sections: [
			{
				heading: "What changed",
				body: "Claude Opus 4.7 and later, Fable 5, and Sonnet 5 use a newer tokenizer that produces about 30% more tokens for the same characters. Sonnet 4.6 and earlier use the old tokenizer. Because you are billed per token, the same prompt can cost ~30% more even though the per-token price is unchanged.",
			},
			{
				heading: "Why estimates undercount",
				body: "Any cost estimate based on character or word counts with the old tokenizer will undercount these models. JP the Cat prices from the real token counts in your logs, so the inflation is already in the number.",
			},
		],
		faq: [
			{
				question: "Does the new tokenizer change the per-token price?",
				answer:
					"No — the rate is the same. It changes how many tokens the same text becomes, which is what you pay for.",
			},
		],
		related: [
			{ href: "/library/glossary/tokenizer", label: "Tokenizer (glossary)" },
			{ href: "/library/pricing/claude-opus-4-8", label: "Opus 4.8 pricing" },
			{ href: "/library/pricing/claude-fable-5", label: "Fable 5 pricing" },
		],
	},
	"the-200k-272k-context-cliff": {
		description:
			"Above 200K (Claude/Gemini) or 272K (OpenAI) tokens, the whole request is billed at a premium tier. Here is what it costs.",
		lede: "Cross the context threshold and the premium applies to the entire request — not just the overflow.",
		sections: [
			{
				heading: "Where the cliff is",
				body: "For Claude and Gemini the threshold is 200K tokens; for OpenAI it is 272K. Above it, input is roughly 2× and output roughly 1.5× — applied to the whole request, retroactively, not only the tokens past the line.",
			},
			{
				heading: "Why it surprises people",
				body: "A request that creeps over the threshold does not cost 'a little more for the extra tokens' — every token in it is repriced. JP the Cat carries the >200K tiers in its pricing table, so a large-context session is costed correctly.",
			},
		],
		faq: [
			{
				question: "Is only the overflow billed at the higher rate?",
				answer: "No — crossing the threshold reprices the entire request at the premium tier.",
			},
		],
		related: [
			{ href: "/library/glossary/context-cliff", label: "Context cliff (glossary)" },
			{ href: "/library/calculators/context-200k-surcharge", label: "200K surcharge calculator" },
			{ href: "/library/pricing/claude-sonnet-4-5", label: "Sonnet 4.5 (has a >200K tier)" },
		],
	},
};

export function guideLeaf(guide: GuideEntry): LeafContent {
	const body = GUIDE_CONTENT[guide.slug];
	if (!body) {
		throw new Error(`missing guide content for ${guide.slug}`);
	}
	return {
		title: guide.title,
		description: body.description,
		lede: body.lede,
		sections: body.sections,
		faq: body.faq,
		related: body.related,
	};
}
