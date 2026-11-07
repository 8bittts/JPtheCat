/**
 * Pure, framework-free helpers shared by the `/library` content generators. Every generated string
 * is composed from an entity's OWN data (never a name-swapped template) so each page carries
 * genuinely-varying substance (_docs/08-growth.md SEO guardrails).
 */

export interface FaqItem {
	question: string;
	answer: string;
}

export interface ContentSection {
	heading: string;
	/** Paragraphs separated by a blank line; rendered as <p> each. */
	body: string;
}

export interface RelatedLink {
	href: string;
	label: string;
}

/** Uniform contract every leaf generator returns, so routes stay thin. */
export interface LeafContent {
	title: string;
	description: string;
	lede: string;
	sections: ContentSection[];
	faq: FaqItem[];
	related: RelatedLink[];
	honesty?: { tone: "neutral" | "notional"; text: string };
}

/** Truncate at a word boundary (no ellipsis) as a safety net; generators should stay under caps. */
export function clampLength(text: string, max: number): string {
	if (text.length <= max) {
		return text;
	}
	const cut = text.slice(0, max);
	const lastSpace = cut.lastIndexOf(" ");
	return (lastSpace > max * 0.6 ? cut.slice(0, lastSpace) : cut).trimEnd();
}

/**
 * Join sentences into a SERP description, dropping trailing sentences that would not fit whole.
 *
 * `libraryPageMetadata` clamps descriptions to 160 chars, and a clamp lands mid-sentence — which
 * reads worse in a result than a shorter, complete line. Callers pass the most valuable sentence
 * first and optional context after, so the snippet degrades by losing whole sentences instead of
 * being cut off. Always returns at least the first sentence (clamped) so it can never be empty.
 *
 * A sentence that does not fit is SKIPPED, not treated as a stop: every caller passes independent
 * facts, so a long middle sentence must not strand the short one after it and leave half the
 * available snippet empty. Do not pass sentences that only read correctly in sequence.
 */
export function fitSentences(max: number, ...sentences: string[]): string {
	const [head, ...rest] = sentences.filter((s) => s.trim().length > 0);
	if (!head) return "";
	let out = clampLength(head, max);
	for (const next of rest) {
		const candidate = `${out} ${next}`;
		if (candidate.length > max) continue;
		out = candidate;
	}
	return out;
}

/** Format a USD amount, locale-grouped to the cent (mirrors the app's MoneyFormatter: $1,123.37). */
export function formatUsd(amount: number): string {
	const rounded = Math.round(amount * 100) / 100;
	return `$${rounded.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** Format a per-million-token dollar rate for prose. */
export function usdPerMTok(perMillion: number): string {
	return `$${perMillion.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 6 })}`;
}
