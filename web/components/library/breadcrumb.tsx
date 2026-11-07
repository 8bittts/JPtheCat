import Link from "next/link";

export interface Crumb {
	name: string;
	href: string;
}

export function LibraryBreadcrumb({ crumbs }: { crumbs: Crumb[] }) {
	return (
		<nav aria-label="Breadcrumb" className="sb-crumb">
			<ol className="flex flex-wrap items-center gap-1.5">
				{crumbs.map((crumb, index) => (
					<li key={crumb.href} className="flex items-center gap-1.5">
						{index > 0 ? (
							<span aria-hidden="true" className="opacity-50">
								/
							</span>
						) : null}
						{index < crumbs.length - 1 ? (
							<Link href={crumb.href}>{crumb.name}</Link>
						) : (
							<span aria-current="page" className="font-semibold opacity-100">
								{crumb.name}
							</span>
						)}
					</li>
				))}
			</ol>
		</nav>
	);
}
