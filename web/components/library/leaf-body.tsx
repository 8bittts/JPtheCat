import type { ReactNode } from "react";
import type { LeafContent } from "@/lib/library/content/shared";
import { CtaBlock } from "./cta-block";
import { FaqList } from "./faq-list";
import { HonestyNote } from "./honesty-note";
import { RelatedRail } from "./related-rail";

/**
 * Uniform leaf renderer: an optional family-specific lead passed as `children` (pricing table,
 * calculator, comparison), the provenance note, prose sections, FAQ, an optional CTA, and the
 * related rail. Keeps every leaf route to a few lines.
 */
export function LeafBody({
	content,
	cta,
	children,
}: {
	content: LeafContent;
	cta?: { heading: string; sub?: string };
	children?: ReactNode;
}) {
	return (
		<>
			{children}
			{content.honesty ? (
				<HonestyNote tone={content.honesty.tone}>{content.honesty.text}</HonestyNote>
			) : null}
			{content.sections.length > 0 ? (
				<div className="mt-10 flex flex-col gap-8">
					{content.sections.map((section) => (
						<section key={section.heading}>
							<h2 className="sb-section-title">{section.heading}</h2>
							{section.body.split("\n\n").map((paragraph) => (
								<p key={paragraph} className="sb-body sb-body--measure mt-3 first:mt-0">
									{paragraph}
								</p>
							))}
						</section>
					))}
				</div>
			) : null}
			<FaqList items={content.faq} />
			{cta ? <CtaBlock heading={cta.heading} sub={cta.sub} /> : null}
			<RelatedRail items={content.related} />
		</>
	);
}
