import { SEO_DESCRIPTION_MAX_LENGTH } from "@/lib/seo";
import { COMPETITORS, type CompetitorEntry, JP_COMPETITOR_ROW } from "../competitors-registry";
import { COMPARE_PAIRS, type ComparePair } from "../eligibility";
import { MODEL_DISPLAY_NAME, MODEL_SLUG_TO_ID, perMillion, pricing } from "../pricing-registry";
import { fitSentences, type LeafContent, usdPerMTok } from "./shared";

export interface CompareTable {
	headers: string[];
	rows: { label: string; values: string[] }[];
}

export function compareBySlug(slug: string): ComparePair | undefined {
	return COMPARE_PAIRS.find((pair) => pair.slug === slug);
}

function toolBySlug(slug: string): CompetitorEntry {
	if (slug === JP_COMPETITOR_ROW.slug) {
		return JP_COMPETITOR_ROW;
	}
	const tool = COMPETITORS.find((entry) => entry.slug === slug);
	if (!tool) {
		throw new Error(`unknown compare tool ${slug}`);
	}
	return tool;
}

function modelName(slug: string): string {
	const id = MODEL_SLUG_TO_ID[slug];
	return id ? MODEL_DISPLAY_NAME[id] : slug;
}

export function comparePairTitle(pair: ComparePair): string {
	return pair.kind === "tool"
		? `${toolBySlug(pair.a).name} vs ${toolBySlug(pair.b).name}`
		: `${modelName(pair.a)} vs ${modelName(pair.b)}`;
}

/** Tool comparisons add JP as an honest third column when neither side is JP itself. */
function compareTools(pair: ComparePair): { tools: CompetitorEntry[]; table: CompareTable } {
	const a = toolBySlug(pair.a);
	const b = toolBySlug(pair.b);
	const includesJp = pair.a === JP_COMPETITOR_ROW.slug || pair.b === JP_COMPETITOR_ROW.slug;
	const tools = includesJp ? [a, b] : [a, b, JP_COMPETITOR_ROW];
	const table: CompareTable = {
		headers: tools.map((tool) => tool.name),
		rows: [
			{ label: "Price", values: tools.map((tool) => tool.price) },
			{ label: "Theme", values: tools.map((tool) => tool.theme) },
			{ label: "Open source", values: tools.map((tool) => (tool.oss ? "Yes" : "No")) },
			{ label: "Form factor", values: tools.map((tool) => tool.gui) },
			{ label: "Shows", values: tools.map((tool) => tool.dataType) },
			{ label: "Providers", values: tools.map((tool) => tool.providerCoverage) },
		],
	};
	return { tools, table };
}

/**
 * JP's registry `dataType` ("real $ (Claude) + official % / notional $ (Codex, Grok)") is written for
 * a table cell, and at 104 chars it crowds the competitor's own facts out of a 160-char SERP
 * description. This is the same claim in snippet length — it keeps the notional label, which is the
 * part that must never be dropped, and drops only the parenthetical provider spellings.
 */
const JP_SNIPPET_SHOWS = "real Claude $ plus labelled notional figures";

function toolSnippetFact(tool: CompetitorEntry): string {
	const shows = tool.slug === JP_COMPETITOR_ROW.slug ? JP_SNIPPET_SHOWS : tool.dataType;
	return `${tool.name}: ${tool.price}, shows ${shows}.`;
}

/**
 * `"Sonnet 4.6 is $3/$15 per 1M tokens; Opus 4.8 is $5/$25."` — the input/output pair for each
 * model, for the SERP description. Returns undefined when either side lacks bundled input+output
 * pricing so the caller can fall back rather than render a half-empty comparison.
 * Deliberately says "API list price" in the caller's sentence: these are list rates, not what a
 * subscription user is actually billed.
 */
function modelHeadlineRates(aSlug: string, bSlug: string): string | undefined {
	const aId = MODEL_SLUG_TO_ID[aSlug];
	const bId = MODEL_SLUG_TO_ID[bSlug];
	if (!aId || !bId) return undefined;
	const a = pricing(aId);
	const b = pricing(bId);
	const pairFor = (p: typeof a): string | undefined =>
		p.input_cost_per_token === undefined || p.output_cost_per_token === undefined
			? undefined
			: `${usdPerMTok(perMillion(p.input_cost_per_token))}/${usdPerMTok(perMillion(p.output_cost_per_token))}`;
	const aRate = pairFor(a);
	const bRate = pairFor(b);
	if (!aRate || !bRate) return undefined;
	return fitSentences(
		SEO_DESCRIPTION_MAX_LENGTH,
		`${MODEL_DISPLAY_NAME[aId]} is ${aRate} per 1M tokens in/out at API list price; ${MODEL_DISPLAY_NAME[bId]} is ${bRate}.`,
		"Cache read and 1h cache write rates compared too.",
	);
}

function compareModels(pair: ComparePair): CompareTable {
	const aId = MODEL_SLUG_TO_ID[pair.a];
	const bId = MODEL_SLUG_TO_ID[pair.b];
	const a = pricing(aId);
	const b = pricing(bId);
	const row = (label: string, av: number | undefined, bv: number | undefined) => ({
		label,
		values: [
			av === undefined ? "—" : usdPerMTok(perMillion(av)),
			bv === undefined ? "—" : usdPerMTok(perMillion(bv)),
		],
	});
	return {
		headers: [MODEL_DISPLAY_NAME[aId], MODEL_DISPLAY_NAME[bId]],
		rows: [
			row("Input / 1M", a.input_cost_per_token, b.input_cost_per_token),
			row("Output / 1M", a.output_cost_per_token, b.output_cost_per_token),
			row("Cache read / 1M", a.cache_read_input_token_cost, b.cache_read_input_token_cost),
			row(
				"Cache write 1h / 1M",
				a.cache_creation_input_token_cost_above_1hr,
				b.cache_creation_input_token_cost_above_1hr,
			),
		],
	};
}

export function compareTable(pair: ComparePair): CompareTable {
	return pair.kind === "tool" ? compareTools(pair).table : compareModels(pair);
}

export function compareLeaf(pair: ComparePair): LeafContent {
	const title = comparePairTitle(pair);
	if (pair.kind === "tool") {
		const a = toolBySlug(pair.a);
		const b = toolBySlug(pair.b);
		const searchTitle =
			pair.slug === "jp-the-cat-vs-tokens-4-breakfast"
				? "Tokens 4 Breakfast vs JP the Cat for Mac"
				: a.slug === JP_COMPETITOR_ROW.slug
					? `${b.name} vs ${a.name} — price & features`
					: `${title} — price & features`;
		const searchDescription =
			pair.slug === "jp-the-cat-vs-tokens-4-breakfast"
				? fitSentences(
						SEO_DESCRIPTION_MAX_LENGTH,
						"Tokens 4 Breakfast folds subscription and API into one bill.",
						"JP the Cat, free, splits real Claude dollars from Codex list price.",
					)
				: fitSentences(
						SEO_DESCRIPTION_MAX_LENGTH,
						...(a.slug === JP_COMPETITOR_ROW.slug
							? [toolSnippetFact(b), toolSnippetFact(a)]
							: [toolSnippetFact(a), toolSnippetFact(b)]),
						"Side by side on macOS provider coverage, themes, and history.",
					);
		return {
			title: searchTitle,
			// Name the two facts a chooser actually decides on — what it costs and what it shows —
			// instead of listing the table's column headings. `price` and `dataType` come straight from
			// the competitor registry, so this stays true as those entries are corrected.
			//
			// The OTHER tool goes first, matching `searchTitle`: these pages rank on the competitor's
			// name, and JP's own price/dataType strings are long enough that leading with them pushed
			// the competitor's fact past the 160-char cut on exactly the query the page is ranking for.
			// Tokens 4 Breakfast is a SERP exception: it ranks ~6 on the brand query at 1.8% CTR
			// (111 impressions / 2 clicks in 30d). Drop the jargon title ("real vs notional $") and
			// keep the honesty split in the description in plain language.
			description: searchDescription,
			lede: `How ${a.name} and ${b.name} compare as AI coding usage trackers — the honest facts, side by side.`,
			sections: [
				{ heading: a.name, body: `${a.notes} Price: ${a.price}. Shows: ${a.dataType}.` },
				{ heading: b.name, body: `${b.notes} Price: ${b.price}. Shows: ${b.dataType}.` },
			],
			faq: [
				{
					question: `Is ${a.name} or ${b.name} better?`,
					answer: `They serve different needs — ${a.name} shows ${a.dataType}, ${b.name} shows ${b.dataType}. The table lays out the facts so you can choose.`,
				},
			],
			related: [
				{
					href: `/library/alternatives/${a.slug === JP_COMPETITOR_ROW.slug ? b.slug : a.slug}`,
					label: "More alternatives",
				},
			],
		};
	}
	const aName = modelName(pair.a);
	const bName = modelName(pair.b);
	return {
		title: `${title} — API pricing`,
		// Lead the SERP snippet with the actual rates rather than a list of the columns the page
		// contains. A pricing-comparison searcher is scanning for the number; a description that only
		// promises "compare API pricing" gives them no reason to open the result — the /library pages
		// were ranking 6-7 and converting under 3%. Falls back to the generic line when either model
		// has no bundled pricing, so an unpriced pair never renders a half-empty claim.
		description:
			modelHeadlineRates(pair.a, pair.b) ??
			`${aName} vs ${bName}: compare API pricing per million tokens for input, output, cache reads, and one-hour cache writes.`,
		lede: `${aName} and ${bName}, compared on real per-million-token pricing.`,
		sections: [
			{
				heading: "Reading the comparison",
				body: "All figures are USD per million tokens at API list prices. Cache-read economics often matter more than the headline input/output rates for a well-cached coding session.",
			},
		],
		faq: [
			{
				question: `Which is cheaper, ${aName} or ${bName}?`,
				answer:
					"It depends on your input/output mix and how much you cache. The table shows each rate so you can weigh your own workload.",
			},
		],
		related: [
			{ href: `/library/pricing/${pair.a}`, label: `${aName} pricing` },
			{ href: `/library/pricing/${pair.b}`, label: `${bName} pricing` },
		],
	};
}
