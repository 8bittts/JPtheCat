import { GLOSSARY, type GlossaryTerm } from "../glossary-registry";
import type { LeafContent } from "./shared";

export function glossaryBySlug(slug: string): GlossaryTerm | undefined {
	return GLOSSARY.find((term) => term.slug === slug);
}

export function glossaryLeaf(term: GlossaryTerm): LeafContent {
	return {
		title: `${term.term} explained`,
		description: `${term.short} What it means for what you pay for AI coding agents.`,
		lede: term.short,
		sections: [
			{ heading: "Why it matters for cost", body: term.mechanic },
			{
				heading: "How JP the Cat surfaces it",
				body: "JP the Cat reads the real token counts behind this from the local logs on your Mac and prices them at the shipped rates — so it shows up in your actual cost, not an estimate.",
			},
		],
		faq: [
			{ question: `What is ${term.term.toLowerCase()}?`, answer: term.short },
			{ question: "How does it change what I pay?", answer: term.mechanic },
		],
		related: [{ href: term.related, label: "See it in context" }],
	};
}
