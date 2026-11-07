import { SEO_DESCRIPTION_MAX_LENGTH } from "@/lib/seo";
import { COMPETITORS, type CompetitorEntry, JP_COMPETITOR_ROW } from "../competitors-registry";
import { fitSentences, type LeafContent } from "./shared";

export function alternativeAnchor(slug: string): CompetitorEntry | undefined {
	return COMPETITORS.find((tool) => tool.slug === slug && tool.alternativesAnchor);
}

/** JP first (the reason for the page), then every other tracker except the anchor. */
export function alternativesFor(anchorSlug: string): CompetitorEntry[] {
	const others = COMPETITORS.filter((tool) => tool.slug !== anchorSlug);
	return [JP_COMPETITOR_ROW, ...others];
}

function alternativesTitle(anchor: CompetitorEntry): string {
	if (anchor.slug === "ccusage") {
		return "ccusage alternatives: CLI vs Mac menu bar";
	}
	if (anchor.slug === "codexbar") {
		return "CodexBar alternatives: quota % vs real dollars";
	}
	return `${anchor.name} alternatives for macOS`;
}

function alternativesDescription(anchor: CompetitorEntry): string {
	if (anchor.slug === "ccusage") {
		return fitSentences(
			SEO_DESCRIPTION_MAX_LENGTH,
			"CodexBar, SessionWatcher, and JP the Cat versus the free ccusage CLI.",
			"Price, what each shows (tokens vs real $), and who they fit on a Mac.",
		);
	}
	if (anchor.slug === "codexbar") {
		return fitSentences(
			SEO_DESCRIPTION_MAX_LENGTH,
			"ccusage, SessionWatcher, and JP the Cat versus CodexBar's free quota-window menu bar.",
			"Price, tokens vs real dollars, and who they fit on a Mac.",
		);
	}
	return fitSentences(
		SEO_DESCRIPTION_MAX_LENGTH,
		`${alternativesFor(anchor.slug).length} ${anchor.name} alternatives compared on price, provider coverage, and whether each shows tokens or real dollar cost.`,
		`${anchor.name}: ${anchor.price}, shows ${anchor.dataType}.`,
	);
}

export function alternativesLeaf(anchor: CompetitorEntry): LeafContent {
	return {
		title: alternativesTitle(anchor),
		// "Honest alternatives … including free and paid options" described the page's existence, not
		// its contents. Lead with the count (the thing that makes a list result worth opening) and the
		// axis people actually choose on — tokens vs real dollars — plus what the anchor tool itself
		// shows, so the snippet is specific to THIS page rather than interchangeable across the set.
		// SERP exceptions: ccusage ranks ~7 on `ccusage alternatives` with 0 clicks; CodexBar ranks
		// ~7 on `codexbar alternatives` at 1.7% CTR (60 impressions / 1 click in 30d). Name the
		// actual options instead of repeating the generic count line.
		description: alternativesDescription(anchor),
		lede: `Looking for an alternative to ${anchor.name}? Here are the honest options for tracking AI coding cost and usage on a Mac.`,
		sections: [
			{
				heading: `Why look past ${anchor.name}?`,
				body: `${anchor.notes} Depending on what you need — a live menu-bar dollar figure, honest real-vs-notional labels, kept history, or a light theme — a different tool may fit better.`,
			},
			{
				heading: "Where JP the Cat fits",
				body: "JP the Cat is the light-themed, honest-provenance option: it computes real Claude Code dollars correctly (including the cache-write split most tools miss), labels notional Codex figures, and keeps everything local. It is free to download, with no account, trial, or license key.",
			},
		],
		faq: [
			{
				question: `Is there a free alternative to ${anchor.name}?`,
				answer:
					"Yes — several (ccusage, CodexBar, CodeBurn) are free and open source. JP the Cat is free too (closed source) and leads on light design, honest provenance, and correct cache-cost accounting.",
			},
		],
		related: [
			{ href: "/library/compare/jp-the-cat-vs-ccusage", label: "JP the Cat vs ccusage" },
			{ href: "/library/track/claude-code", label: "Track Claude Code" },
		],
	};
}
