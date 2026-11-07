import Link from "next/link";

export interface RelatedLink {
	href: string;
	label: string;
}

export function RelatedRail({
	items,
	heading = "Related",
}: {
	items: RelatedLink[];
	heading?: string;
}) {
	if (items.length === 0) {
		return null;
	}
	return (
		<nav aria-label={heading} className="sb-related">
			<p className="sb-related__kicker">{heading}</p>
			<ul className="flex flex-wrap gap-2">
				{items.map((item) => {
					const external = item.href.startsWith("http://") || item.href.startsWith("https://");
					const className = "sb-pill transition-transform hover:translate-y-px";
					return (
						<li key={item.href}>
							{external ? (
								<a href={item.href} className={className} target="_blank" rel="noopener noreferrer">
									{item.label}
								</a>
							) : (
								<Link href={item.href} className={className}>
									{item.label}
								</Link>
							)}
						</li>
					);
				})}
			</ul>
		</nav>
	);
}
