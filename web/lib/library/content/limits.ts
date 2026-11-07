import type { Provider } from "@/lib/site";
import { PLANS } from "../plans-registry";
import { liveProviderNames, providerSlug } from "../provider-registry";
import type { ContentSection, LeafContent } from "./shared";

/** Documented limit mechanics (`_docs/03-data.md`) — only providers with backed mechanics (_docs/08-growth.md SEO guardrails). */
const LIMIT_MECHANICS: Record<string, { lede: string; mechanics: ContentSection[] }> = {
	"claude-code": {
		lede: "Claude Code enforces two limits at once: a rolling 5-hour window and a weekly cap. Here is how each works and when it resets.",
		mechanics: [
			{
				heading: "The dual-layer windows",
				body: "The 5-hour window opens on your first message and resets five hours later. Separately, the weekly cap resets at a fixed day and time assigned to your account; Claude shows the next reset in Settings → Usage. Max plans can add distinct model-specific weekly allowances on top.",
			},
			{
				heading: "How JP reads it",
				body: "JP the Cat shows Claude's true 5-hour and weekly used-percent — but only after you opt in (Settings → Live data → Enable Claude live limits), because Claude Code does not persist these numbers. Without the opt-in, JP shows no Claude gauge rather than a wrong estimate.",
			},
		],
	},
	codex: {
		lede: "Codex meters usage against a 5-hour and a weekly rate-limit pool shared with your ChatGPT plan. JP reads the official percentages automatically.",
		mechanics: [
			{
				heading: "The agentic-usage pool",
				body: "Codex shares an agentic-usage pool on 5-hour and weekly windows. It writes the used-percent and reset time into its rollout logs, so the number JP shows is the one OpenAI enforces — no setup, no login.",
			},
			{
				heading: "Cost is notional",
				body: "Because Codex is a flat subscription, any dollar figure is notional list price — what the usage would cost at API rates, clearly labelled, never presented as metered spend.",
			},
		],
	},
	grok: {
		lede: "Grok brings Grok Build, Cursor, and Grok Bot into one view. Opt-in official plan usage shows the shared weekly pool and any reported billing-cycle pools, never percentages invented from local tokens.",
		mechanics: [
			{
				heading: "Weekly and billing-cycle pools",
				body: "The shared dashboard service reports a weekly included-usage pool when the plan has one, plus Cursor Models and Other Models billing-cycle pools when available. JP keeps each reported reset and shows each distinct pool once. Opt-in Grok Build hook capture supplies a weekly fallback, never an additional copy of the same pool.",
			},
			{
				heading: "How JP reads it",
				body: "Enable Grok plan usage in Live data to read official weekly and billing-cycle percentages from api2.cursor.sh with a saved Cursor or Grok Bot sign-in. One five-minute cadence covers both apps. The weekly API pool takes precedence; the optional Grok Build local hook is a fallback, never an extra weekly bar. A Cursor-only plan can show its billing-cycle meter without pretending it is weekly. Local priced activity is notional; unknown models show tokens, and percentages never enter dollar totals.",
			},
		],
	},
	opencodego: {
		lede: "OpenCode Go publishes a monthly dollar limit for each model it serves. A 5-hour window allows 20% of that limit and a week allows 50%. JP measures your local Go usage against those published caps — a measured reading, not an official percentage.",
		mechanics: [
			{
				heading: "Per-model dollar caps",
				body: "Each Go model has its own monthly dollar limit on opencode.ai/docs/go, and dated promotions can raise one for a while. The 5-hour and weekly windows are fixed fractions of that monthly limit, so the model nearest its own cap is the one that binds.",
			},
			{
				heading: "How JP reads it",
				body: "JP prices the Go-routed turns OpenCode logs in ~/.local/share/opencode/opencode.db at Go's published rates and shows 5-hour, weekly, and monthly usage against each model's cap, labelled measured. OpenCode stores no reset time or remaining quota on your Mac, so JP shows no countdown, and a model it cannot price adds nothing rather than a false 0%. Go dollars stay out of combined totals because the same turns also count under their model's row.",
			},
		],
	},
	copilot: {
		lede: "GitHub Copilot meters premium AI requests, with additional requests currently priced at $0.04 each on eligible paid plans. This page is reference only — Copilot stays estimate-only and out of dollar aggregates, with an optional token-based widget view.",
		mechanics: [
			{
				heading: "Premium-request metering",
				body: "Copilot plans include a monthly premium-request allotment; on eligible paid plans, additional premium requests are currently billed at $0.04 each. There is no rolling 5-hour window.",
			},
			{
				heading: "On the JP roadmap",
				body: "GitHub Copilot is a local-next provider in JP's catalog. JP can show local Copilot activity and an explicitly token-based widget view once you opt in, but it stays out of combined dollar totals and alerts.",
			},
		],
	},
};

function resetAnswer(provider: Provider): string {
	if (!provider.live) {
		return `${provider.name} uses a monthly pool rather than a rolling window; see the plan pages for specifics.`;
	}
	if (provider.id === "grok") {
		return "Grok shows each official pool’s reported reset: the weekly API boundary (or local hook fallback), and the billing-cycle end for monthly pools. A monthly-only plan is labelled billing-cycle, never weekly.";
	}
	if (provider.id === "opencodego") {
		return "OpenCode records no reset boundary on your Mac, so JP measures trailing 5-hour, 7-day, and 30-day windows and shows no countdown.";
	}
	return "The 5-hour window resets five hours after it opened; the weekly cap resets at the fixed day and time assigned to the account.";
}

function tracksLimitsAnswer(provider: Provider): string {
	if (provider.live) {
		if (provider.id === "grok") {
			return "Yes — Grok unifies Grok Build, Cursor, and Grok Bot. Enable Grok plan usage for official weekly and billing-cycle pools; opt-in local hook capture is the weekly fallback. No quota is derived from tokens.";
		}
		if (provider.id === "opencodego") {
			return "Yes — OpenCode Go is live today. JP shows measured 5-hour, weekly, and monthly usage against Go's published per-model caps, labelled measured rather than official.";
		}
		return `Yes — ${provider.name} is live today. Codex is automatic; Claude requires the opt-in statusline capture; Grok SuperGrok weekly requires the opt-in Grok hook capture.`;
	}
	if (provider.id === "copilot") {
		return "Not for limits — Copilot has no rate-limit gauge. JP can show local Copilot activity and a token-estimate widget once you opt in, but it stays out of combined dollar totals and alerts.";
	}
	return `Not yet. ${provider.name} is on the roadmap; JP tracks ${liveProviderNames()} today.`;
}

function limitsHonesty(provider: Provider): string {
	if (provider.id === "opencodego") {
		return "Measured, not official: JP compares local Go spend with Go's published caps. OpenCode reports no remaining quota, so JP never shows an official percentage or a reset countdown.";
	}
	if (provider.live) {
		return `JP the Cat shows ${provider.name}'s official used-percent — never a fabricated denominator or a token-based estimate.`;
	}
	if (provider.id === "copilot") {
		return "Reference only: Copilot's local activity and token-estimate widget are visible once you opt in, but Copilot is excluded from combined dollar totals and alerts.";
	}
	return `Reference only: JP the Cat does not track ${provider.name} yet.`;
}

export function limitLeaf(provider: Provider): LeafContent {
	const mechanics = LIMIT_MECHANICS[provider.id === "claude" ? "claude-code" : provider.id];
	const slug =
		provider.id === "claude"
			? "claude-code"
			: provider.id === "copilot"
				? "github-copilot"
				: provider.id;
	const planLinks = PLANS.flatMap((plan) =>
		plan.provider === slug
			? [{ href: `/library/plans/${plan.slug}`, label: plan.displayName }]
			: [],
	);

	return {
		title: `${provider.name} usage limits explained`,
		description: `How ${provider.name}'s usage limits and reset windows work — the mechanics, and how to read them honestly.`,
		lede: mechanics.lede,
		sections: mechanics.mechanics,
		faq: [
			{
				question: `When do ${provider.name} limits reset?`,
				answer: resetAnswer(provider),
			},
			{
				question: `Does JP the Cat track ${provider.name} limits?`,
				answer: tracksLimitsAnswer(provider),
			},
		],
		related: [
			...(provider.live
				? [
						{
							href: `/library/track/${providerSlug(provider)}`,
							label: `How JP tracks ${provider.name}`,
						},
					]
				: []),
			...planLinks,
			{ href: "/library/glossary/used-percent", label: "What is used percent?" },
		],
		honesty: {
			tone: "neutral",
			text: limitsHonesty(provider),
		},
	};
}
