import type { FaqItem } from "@/lib/library/content/shared";

// On-page FAQ only — no FAQPage JSON-LD (Google restricted FAQ rich results; _docs/08-growth.md SEO guardrails).
export function FaqList({
	items,
	heading = "Common questions",
}: {
	items: FaqItem[];
	heading?: string;
}) {
	if (items.length === 0) {
		return null;
	}
	return (
		<section className="sb-faq-block" aria-labelledby="faq-heading">
			<h2 id="faq-heading" className="sb-section-title">
				{heading}
			</h2>
			<dl className="sb-faq-grid">
				{items.map((item) => (
					<div key={item.question} className="sb-faq-item">
						<dt>{item.question}</dt>
						<dd>{item.answer}</dd>
					</div>
				))}
			</dl>
		</section>
	);
}
