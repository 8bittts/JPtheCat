import Link from "next/link";

export interface LibraryLink {
	href: string;
	title: string;
	meta?: string;
}

export function LibraryLinkGrid({ items }: { items: LibraryLink[] }) {
	return (
		<ul className="sb-link-grid">
			{items.map((item) => (
				<li key={item.href}>
					<Link href={item.href}>
						<span className="sb-link-grid__title">{item.title}</span>
						{item.meta ? <span className="sb-link-grid__meta">{item.meta}</span> : null}
					</Link>
				</li>
			))}
		</ul>
	);
}
