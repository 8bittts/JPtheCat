import type { CSSProperties } from "react";
import type { CompetitorEntry } from "@/lib/library/competitors-registry";

export function AlternativesList({ tools }: { tools: CompetitorEntry[] }) {
	return (
		<ul className="sb-board mt-8 list-none p-0">
			{tools.map((tool, index) => (
				<li key={tool.slug}>
					<article
						className="sb-card h-full"
						style={
							{
								"--r": `${([-1, 1, -0.5][index % 3] ?? 0) * 1}deg`,
								background: tool.slug === "jp-the-cat" ? "var(--sb-yellow)" : "var(--sb-white)",
							} as CSSProperties
						}
					>
						<div className="flex items-baseline justify-between gap-2">
							<h3 className="sb-link-grid__title">{tool.name}</h3>
							<span className="sb-small opacity-75">{tool.price}</span>
						</div>
						<p className="sb-small mt-1.5 opacity-80">
							{tool.dataType} · {tool.gui} · {tool.oss ? "open source" : "paid"}
						</p>
						<p className="sb-body mt-2">{tool.notes}</p>
					</article>
				</li>
			))}
		</ul>
	);
}
