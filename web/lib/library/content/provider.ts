/**
 * Content generator for `/library/track/[provider]`. BRANCHES on live vs roadmap so it can never
 * over-claim (_docs/08-growth.md SEO guardrails): live pages sell JP; roadmap pages state the exact
 * status word + "not tracked yet" and never say JP tracks that provider today.
 */

import type { Provider } from "@/lib/site";
import { liveProviderNames } from "../provider-registry";
import type { FaqItem, LeafContent, RelatedLink } from "./shared";

export function providerTrackTitle(provider: Provider): string {
	return provider.live
		? `Track ${provider.name} usage & cost on macOS`
		: `${provider.name} usage tracking on macOS — roadmap`;
}

export function providerTrackDescription(provider: Provider): string {
	if (provider.live) {
		return `JP the Cat tracks ${provider.name} on your Mac today — local cost and usage, computed on-device.`;
	}
	return `Is ${provider.name} usage trackable on macOS? Where it sits on the JP the Cat roadmap (${provider.statusLabel}) and how to check usage today.`;
}

export function providerTrackLead(provider: Provider): string {
	if (provider.live) {
		return `JP the Cat tracks ${provider.name} on your Mac today — ${LIVE_DETAIL[provider.id] ?? "usage and cost read from local logs"}.`;
	}
	return `JP the Cat does not track ${provider.name} yet — it is on the roadmap (${provider.statusLabel}).`;
}

/** What each live page may claim. OpenCode gateways carry no official quota: Zen has none, and Go's
 * windows are measured against published caps. */
const LIVE_DETAIL: Record<string, string> = {
	claude: "real dollar cost, computed locally from your Claude Code session logs",
	codex: "official 5-hour and weekly usage plus a clearly-labelled notional cost",
	grok: "one Grok view for Grok Build, optional Cursor stop-hook activity, and opt-in official Grok / Cursor / Grok Bot plan pools",
	muse_spark:
		"clearly-labelled notional list-price cost from OpenCode Muse Spark and Muse Wonder turns on this Mac — not your full Meta account dashboard",
	opencode:
		"clearly-labelled notional list-price cost for turns OpenCode routed through Zen on this Mac, kept out of combined totals",
	opencodego:
		"clearly-labelled notional list-price cost for turns OpenCode routed through Go on this Mac, plus measured usage against Go's published per-model caps",
};

export function providerTrackBody(provider: Provider): string {
	if (provider.live) {
		if (provider.id === "grok")
			return "Grok combines local Grok Build logs with explicitly enabled Cursor CLI stop-hook activity as notional list-price cost. Unpriced models show tokens, not fabricated spend. The hook captures Cursor CLI turns and does not import Claude Code session logs. Optional official plan usage sends only a saved sign-in token to api2.cursor.sh; prompts, code, and transcripts stay on-device.";
		if (provider.id === "opencode" || provider.id === "opencodego") {
			const gateway = provider.id === "opencode" ? "Zen" : "Go";
			return `JP reads the assistant turns OpenCode recorded as routed through ${gateway} in ~/.local/share/opencode/opencode.db and prices them at the published ${gateway} rates. The same turns also count under their model's own row, so ${provider.name} dollars are shown but never added to the combined total. Free-tier models stay unpriced and show as tokens.${provider.id === "opencodego" ? " Go publishes no remaining quota on your Mac, so its 5-hour, weekly, and monthly bars are labelled measured and carry no reset countdown." : ""}`;
		}
		if (provider.id === "muse_spark") {
			return `${provider.name} is live when OpenCode on this Mac has logged Muse Spark or Muse Wonder assistant turns in ~/.local/share/opencode/opencode.db. JP prices those turns at Meta Model API list rates. Usage through other clients (Cursor Composer, direct API calls, other machines) appears on Meta's account dashboard but not here unless OpenCode logged it locally.`;
		}
		return `${provider.name} is one of the agents JP the Cat tracks today. Everything is read from local logs on your Mac — no account, no upload.`;
	}
	const catalogs = provider.sources.length === 1 ? "catalog" : "catalogs";
	return `${provider.name} appears in ${provider.sources.length} usage-tracker ${catalogs} JP maps. When a local usage source or connector ships, ${provider.name} moves from ${provider.statusLabel} to live. Until then JP the Cat does not report ${provider.name} usage — it only tracks ${liveProviderNames()}.`;
}

export function providerTrackFaq(provider: Provider): FaqItem[] {
	if (provider.live) {
		const localOnly =
			provider.id !== "grok"
				? `Yes — ${provider.name} is live today and read locally from your Mac.`
				: `Yes — ${provider.name} unifies local Grok Build and optional Cursor usage. Official plan pools require the Grok plan usage opt-in; only the saved Cursor or Grok Bot sign-in token goes to api2.cursor.sh.`;
		return [
			{
				question: `Does JP the Cat track ${provider.name}?`,
				answer: localOnly,
			},
		];
	}
	return [
		{
			question: `Does JP the Cat track ${provider.name} yet?`,
			answer: `Not yet. ${provider.name} is on the roadmap (${provider.statusLabel}); JP the Cat tracks ${liveProviderNames()} today.`,
		},
	];
}

function providerRelated(provider: Provider): RelatedLink[] {
	if (provider.id === "claude") {
		return [
			{ href: "/library/limits/claude-code", label: "Claude Code limits" },
			{ href: "/library/pricing/claude-opus-5-5", label: "Claude Opus 5.5 pricing" },
			{ href: "/library/guides/check-claude-code-cost", label: "Check your Claude Code cost" },
		];
	}
	if (provider.id === "codex") {
		return [
			{ href: "/library/limits/codex", label: "Codex limits" },
			{ href: "/library/plans/chatgpt-pro-codex", label: "ChatGPT Pro (Codex)" },
			{ href: "/library/guides/see-codex-usage-limit", label: "See your Codex usage limit" },
		];
	}
	if (provider.id === "muse_spark") {
		return [
			{ href: "/library/pricing/family/meta", label: "Meta (Muse) pricing" },
			{ href: "/library/calculators/tokens-to-dollars", label: "Tokens-to-dollars calculator" },
			{ href: "/library/guides/track-token-usage-on-macos", label: "Track usage on macOS" },
		];
	}
	if (provider.id === "grok") {
		return [
			{ href: "/library/pricing/grok-4-7", label: "Grok 4.7 pricing" },
			{ href: "/library/pricing/family/xai", label: "xAI (Grok) model pricing" },
			{ href: "https://docs.x.ai/developers/pricing", label: "Official xAI pricing" },
			{ href: "/library/guides/track-token-usage-on-macos", label: "Track usage on macOS" },
		];
	}
	if (provider.id === "opencode" || provider.id === "opencodego") {
		return [
			...(provider.id === "opencodego"
				? [{ href: "/library/limits/opencodego", label: "OpenCode Go limits" }]
				: []),
			{ href: "/library/pricing/family/opencode", label: "OpenCode Zen / Go model pricing" },
			{ href: "/library/pricing/family/deepseek", label: "DeepSeek pricing via OpenCode" },
		];
	}
	return [
		{ href: "/library/track", label: "All providers by status" },
		{ href: "/library/guides/track-token-usage-on-macos", label: "Track usage on macOS" },
	];
}

export function providerLeaf(provider: Provider): LeafContent {
	return {
		title: providerTrackTitle(provider),
		description: providerTrackDescription(provider),
		lede: providerTrackLead(provider),
		sections: [
			{
				heading: provider.live ? "How JP the Cat tracks it" : "Where it stands",
				body: providerTrackBody(provider),
			},
		],
		faq: providerTrackFaq(provider),
		related: providerRelated(provider),
		honesty: {
			tone: "neutral",
			text: provider.live
				? provider.id === "muse_spark"
					? "OpenCode sessions on this Mac only — Meta account dashboard totals can be higher when Muse Spark runs outside OpenCode."
					: provider.id === "grok"
						? "Local activity stays on your Mac. Optional plan usage sends only a saved sign-in token to api2.cursor.sh; no prompts, code, or transcripts."
						: "Everything is read from local logs on your Mac — no account, no upload."
				: `Roadmap status: ${provider.statusLabel}. JP the Cat tracks ${liveProviderNames()} today.`,
		},
	};
}
