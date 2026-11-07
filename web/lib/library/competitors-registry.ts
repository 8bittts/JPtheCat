/**
 * Factual attribute registry for the AI-usage-tracker competitive set (verified from the market
 * scan in `_docs/08-growth.md`). Feeds the compare + alternatives families. Attributes are neutral
 * facts only — no disparagement (_docs/08-growth.md SEO guardrails). JP appears as one honest row, never "the best".
 */

export interface CompetitorEntry {
	slug: string;
	name: string;
	url: string;
	price: string;
	theme: "light" | "dark" | "n/a";
	oss: boolean;
	gui: string;
	dataType: string;
	providerCoverage: string;
	notes: string;
	/** Whether this tool anchors its own `/library/alternatives/[slug]` page. */
	alternativesAnchor: boolean;
}

export const COMPETITORS: CompetitorEntry[] = [
	{
		slug: "ccusage",
		name: "ccusage",
		url: "https://github.com/ryoppippi/ccusage",
		price: "Free (open source)",
		theme: "n/a",
		oss: true,
		gui: "CLI",
		dataType: "real $ cost",
		providerCoverage: "Claude Code (Codex via plugins)",
		notes:
			"The dominant free CLI. Historically priced all cache-creation at the single 5-minute rate (issue #899, since fixed), under-billing 1-hour cache writes by 37.5%.",
		alternativesAnchor: true,
	},
	{
		slug: "codexbar",
		name: "CodexBar",
		url: "https://codexbar.app/",
		price: "Free",
		theme: "dark",
		oss: true,
		gui: "menu bar",
		dataType: "quota %",
		providerCoverage: "56 providers",
		notes: "Free menu-bar quota meter; tracks rate-limit windows, not computed dollar cost.",
		alternativesAnchor: true,
	},
	{
		slug: "sessionwatcher",
		name: "SessionWatcher",
		url: "https://sessionwatcher.com/",
		price: "$6.99+ one-time",
		theme: "dark",
		oss: false,
		gui: "menu bar",
		dataType: "quota % + cost",
		providerCoverage: "~6 providers",
		notes:
			"The deepest paid rival; dark-themed, with a programmatic guides library for ~6 providers.",
		alternativesAnchor: true,
	},
	{
		slug: "tokens-4-breakfast",
		name: "Tokens 4 Breakfast",
		url: "https://www.tokens4breakfast.app/",
		price: "Free / Pro $7.99 one-time",
		theme: "light",
		oss: false,
		gui: "menu bar",
		dataType: "cost",
		providerCoverage: "8 providers",
		notes:
			"Closest light-themed analogue; folds subscription and API into one bill without a real-vs-notional split.",
		alternativesAnchor: true,
	},
	{
		slug: "codeburn",
		name: "CodeBurn",
		url: "https://github.com/",
		price: "Free (open source)",
		theme: "dark",
		oss: true,
		gui: "menu bar",
		dataType: "cost",
		providerCoverage: "Claude Code",
		notes: "Free open-source burn-rate meter for Claude Code.",
		alternativesAnchor: true,
	},
	{
		slug: "claude-code-usage-monitor",
		name: "Claude-Code-Usage-Monitor",
		url: "https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor",
		price: "Free (open source)",
		theme: "n/a",
		oss: true,
		gui: "terminal",
		dataType: "quota % + tokens",
		providerCoverage: "Claude Code",
		notes:
			"Popular Python terminal monitor with a history warehouse that survives the 30-day cleanup.",
		alternativesAnchor: true,
	},
	{
		slug: "tokentracker",
		name: "TokenTracker",
		url: "https://github.com/",
		price: "Free (open source)",
		theme: "n/a",
		oss: true,
		gui: "CLI",
		dataType: "tokens + cost",
		providerCoverage: "Claude Code",
		notes: "Lightweight open-source token/cost CLI.",
		alternativesAnchor: true,
	},
	{
		slug: "vibe-island",
		name: "Vibe Island",
		url: "https://vibeisland.app/",
		price: "$19.99 one-time",
		theme: "dark",
		oss: false,
		gui: "notch",
		dataType: "agent control (quota secondary)",
		providerCoverage: "multiple agents",
		notes: "An agent control surface; quota is a secondary feature and there is no cost dashboard.",
		alternativesAnchor: true,
	},
	{
		slug: "open-island",
		name: "Open Island",
		url: "https://github.com/Octane0411/open-vibe-island",
		price: "Free (GPL v3)",
		theme: "dark",
		oss: true,
		gui: "notch",
		dataType: "quota %",
		providerCoverage: "10 agents",
		notes: "Open-source notch control surface; shows quota percentages, no per-token dollar cost.",
		alternativesAnchor: false,
	},
	{
		slug: "vibe-notch",
		name: "Vibe Notch",
		url: "https://vibenotch.app/",
		price: "Free",
		theme: "dark",
		oss: true,
		gui: "notch",
		dataType: "session status + tokens",
		providerCoverage: "Claude Code only",
		notes: "Apache-licensed Dynamic-Island-style monitor for Claude Code sessions.",
		alternativesAnchor: false,
	},
];

/** JP's own honest row for comparison/alternative tables — accurate live/roadmap counts. */
export const JP_COMPETITOR_ROW: CompetitorEntry = {
	slug: "jp-the-cat",
	name: "JP the Cat",
	url: "https://jpthecat.com",
	price: "Free (open source)",
	theme: "light",
	oss: true,
	gui: "menu bar",
	dataType: "real $ (Claude) + official % / notional $ (Codex, Grok)",
	providerCoverage: "Claude Code + Codex + Grok + Muse Spark live, 59 more on roadmap",
	notes:
		"Light-themed, honest-provenance meter with tested cache-tier billing, clear data provenance, and explicit labels for notional Codex and Grok list-price figures.",
	alternativesAnchor: false,
};

export const ALTERNATIVES_ANCHORS = COMPETITORS.flatMap((tool) =>
	tool.alternativesAnchor ? [tool.slug] : [],
);
