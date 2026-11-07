/**
 * How-to / explainer guide manifest — curated to the set we can back with genuine, non-thin content
 * (real commands, file paths, real JP features; _docs/08-growth.md SEO guardrails). The flagship guides encode
 * JP's E-E-A-T edges: the historical ccusage #899 cache-tier bug case study, the ~30% new-tokenizer
 * inflation, and the 200K/272K context cliffs (_docs/08-growth.md SEO guardrails). Add a guide here only when its
 * body clears the gate.
 */

export interface GuideEntry {
	slug: string;
	title: string;
	category: "check" | "reduce" | "understand" | "compare-cost";
	/** True when the guide references what JP tracks today (Claude Code / Codex). */
	touchesLiveProvider: boolean;
	flagship?: boolean;
}

export const GUIDES: GuideEntry[] = [
	{
		slug: "check-claude-code-cost",
		title: "How to check your Claude Code cost",
		category: "check",
		touchesLiveProvider: true,
	},
	{
		slug: "see-codex-usage-limit",
		title: "How to check your Codex usage limit",
		category: "check",
		touchesLiveProvider: true,
	},
	{
		slug: "track-token-usage-on-macos",
		title: "How to track token usage on macOS",
		category: "check",
		touchesLiveProvider: true,
	},
	{
		slug: "reduce-claude-code-cost",
		title: "How to reduce your Claude Code cost",
		category: "reduce",
		touchesLiveProvider: true,
	},
	{
		slug: "enable-claude-live-limits",
		title: "How to enable Claude live limits in JP the Cat",
		category: "check",
		touchesLiveProvider: true,
	},
	{
		slug: "understand-the-5-hour-window",
		title: "Understanding the Claude 5-hour window",
		category: "understand",
		touchesLiveProvider: true,
	},
	{
		slug: "why-is-claude-code-so-expensive",
		title: "Why is Claude Code so expensive?",
		category: "understand",
		touchesLiveProvider: true,
	},
	{
		slug: "how-much-does-codex-cost",
		title: "How much does Codex cost?",
		category: "compare-cost",
		touchesLiveProvider: true,
	},
	{
		slug: "codex-plus-pro-rate-limits",
		title: "Codex Plus and Pro rate limits",
		category: "understand",
		touchesLiveProvider: true,
	},
	{
		slug: "real-vs-notional-cost",
		title: "Real cost vs notional list price",
		category: "understand",
		touchesLiveProvider: true,
	},
	{
		slug: "historical-ccusage-cache-cost-bug",
		title: "The historical ccusage cache-cost bug",
		category: "understand",
		touchesLiveProvider: true,
		flagship: true,
	},
	{
		slug: "new-tokenizer-30-percent-more-tokens",
		title: "The new tokenizer that adds ~30% more tokens",
		category: "understand",
		touchesLiveProvider: true,
		flagship: true,
	},
	{
		slug: "the-200k-272k-context-cliff",
		title: "The 200K / 272K context cliff",
		category: "understand",
		touchesLiveProvider: true,
		flagship: true,
	},
];

export const GUIDE_SLUGS = GUIDES.map((guide) => guide.slug);
