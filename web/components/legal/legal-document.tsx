import type { ReactNode } from "react";

type LegalDocumentItem = {
	id: string;
	title: string;
};

type LegalDocumentProps = {
	children: ReactNode;
	contentId: string;
	items: readonly LegalDocumentItem[];
	navigationLabel: string;
	/** Vertical rhythm between top-level content blocks. Legal pages use the default `space-y-10`;
	 *  the release page passes `space-y-12` for its longer per-day cards. */
	contentClassName?: string;
};

export function LegalDocument({
	children,
	contentId,
	items,
	navigationLabel,
	contentClassName = "space-y-10",
}: LegalDocumentProps) {
	return (
		<>
			<a href={`#${contentId}`} className="sb-skip-link">
				Skip to {navigationLabel.toLowerCase()}
			</a>

			<div className="mt-12 grid items-start gap-8 lg:grid-cols-[300px_1fr]">
				<aside className="lg:sticky lg:top-12">
					<div className="sb-legal-rail">
						<p className="sb-legal-rail__label">On this page</p>
						<nav aria-label={navigationLabel} className="sb-legal-nav mt-4">
							<ul className="space-y-1">
								{items.map((item, index) => (
									<li key={item.id}>
										<a href={`#${item.id}`}>
											<span>{String(index + 1).padStart(2, "0")}</span>
											<span>{item.title}</span>
										</a>
									</li>
								))}
							</ul>
						</nav>
					</div>
				</aside>

				<div id={contentId} className={contentClassName}>
					{children}
				</div>
			</div>
		</>
	);
}
