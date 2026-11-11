/**
 * Subscription plan/limit data (`_docs/03-data.md` mechanics). ONLY the four documented provider families
 * (Claude, ChatGPT+Codex, Cursor, Copilot) — no fabricated tiers (_docs/08-growth.md SEO guardrails). Message counts
 * are unofficial estimates; every entry carries `lastVerified` and time-boxed promos carry an
 * expiry so a page can't silently go stale-wrong (_docs/08-growth.md SEO guardrails).
 */

export interface PlanEntry {
	slug: string;
	/** Provider slug this plan belongs to (matches provider-registry slugs). */
	provider: string;
	displayName: string;
	priceUsdMonthly: number;
	multiplier: string;
	windowMechanics: string;
	/** Unofficial, model-dependent — always labeled as such in copy. */
	messageEstimate: string;
	lastVerified: string;
	promo?: { note: string; expires: string };
}

export const PLANS: PlanEntry[] = [
	{
		slug: "claude-pro",
		provider: "claude-code",
		displayName: "Claude Pro",
		priceUsdMonthly: 20,
		multiplier: "1x baseline",
		windowMechanics:
			"A 5-hour rolling window (starts on your first message) plus a weekly cap that resets at a fixed day and time assigned to the account.",
		messageEstimate: "Rough, unofficial: on the order of ~40-80 Sonnet messages per 5-hour window.",
		lastVerified: "2026-07",
	},
	{
		slug: "claude-max-5x",
		provider: "claude-code",
		displayName: "Claude Max 5x",
		priceUsdMonthly: 100,
		multiplier: "5x Pro",
		windowMechanics:
			"Same dual-layer 5-hour + weekly windows as Pro, with roughly 5x the headroom and a separate Opus weekly cap.",
		messageEstimate: "Rough, unofficial: ~5x the Pro ceiling; model- and length-dependent.",
		lastVerified: "2026-07",
	},
	{
		slug: "claude-max-20x",
		provider: "claude-code",
		displayName: "Claude Max 20x",
		priceUsdMonthly: 200,
		multiplier: "20x Pro",
		windowMechanics:
			"The dual-layer 5-hour + weekly windows with roughly 20x the Pro headroom and the largest Opus weekly allowance.",
		messageEstimate:
			"Rough, unofficial: ~20x the Pro ceiling; heavy Opus use still hits the weekly cap.",
		lastVerified: "2026-07",
		promo: {
			note: "A temporary +50% weekly allowance promotion was running for Max tiers.",
			expires: "2026-07-13",
		},
	},
	{
		slug: "chatgpt-plus-codex",
		provider: "codex",
		displayName: "ChatGPT Plus (Codex)",
		priceUsdMonthly: 20,
		multiplier: "entry Codex pool",
		windowMechanics:
			"Codex shares the ChatGPT agentic-usage pool with a 5-hour and a weekly rate-limit window; JP reads the official used-percent from Codex's rollout logs.",
		messageEstimate:
			"Rough, unofficial: entry-level agentic pool; enough for light daily Codex use.",
		lastVerified: "2026-07",
	},
	{
		slug: "chatgpt-pro-codex",
		provider: "codex",
		displayName: "ChatGPT Pro (Codex)",
		priceUsdMonthly: 200,
		multiplier: "largest Codex pool",
		windowMechanics:
			"The largest agentic-usage pool for Codex, on the same 5-hour + weekly windows JP surfaces as official used-percent.",
		messageEstimate:
			"Rough, unofficial: the highest Codex headroom OpenAI offers on a personal plan.",
		lastVerified: "2026-07",
	},
	{
		slug: "cursor-pro",
		provider: "grok",
		displayName: "Cursor Pro",
		priceUsdMonthly: 20,
		multiplier: "monthly credit pool",
		windowMechanics:
			"Cursor meters a monthly request/credit pool rather than a rolling window. JP shows opt-in official monthly pools in the unified Grok view, alongside a weekly pool when reported. Opt-in local Cursor CLI activity uses notional list-price cost for priced models and tokens for entirely unpriced models; official plan percentages never enter dollar totals.",
		messageEstimate:
			"Rough, unofficial: a fixed monthly credit allotment; overage is pay-as-you-go.",
		lastVerified: "2026-07",
	},
	{
		slug: "cursor-ultra",
		provider: "grok",
		displayName: "Cursor Ultra",
		priceUsdMonthly: 200,
		multiplier: "largest credit pool",
		windowMechanics:
			"The largest Cursor monthly credit pool. JP shows opt-in official monthly pools in the unified Grok view, alongside a weekly pool when reported. Opt-in local Cursor CLI activity uses notional list-price cost for priced models and tokens for entirely unpriced models; official plan percentages never enter dollar totals.",
		messageEstimate: "Rough, unofficial: ~10x the Pro credit pool.",
		lastVerified: "2026-07",
	},
	{
		slug: "github-copilot-pro",
		provider: "github-copilot",
		displayName: "GitHub Copilot Pro",
		priceUsdMonthly: 10,
		multiplier: "premium-request pool",
		windowMechanics:
			"Copilot meters premium AI requests; additional requests are currently $0.04 each on eligible paid plans. Reference only — not counted in JP's totals yet.",
		messageEstimate:
			"Rough, unofficial: an included premium-request allotment plus metered overage.",
		lastVerified: "2026-07",
	},
	{
		slug: "github-copilot-pro-plus",
		provider: "github-copilot",
		displayName: "GitHub Copilot Pro+",
		priceUsdMonthly: 39,
		multiplier: "larger premium pool",
		windowMechanics:
			"A larger premium-request pool than Pro. Reference only — not counted in JP's totals yet.",
		messageEstimate: "Rough, unofficial: several times the Pro premium-request allotment.",
		lastVerified: "2026-07",
	},
];

export const PLAN_SLUGS = PLANS.map((plan) => plan.slug);
