import { sectionLinks } from "@/lib/library/hub";
import { collectionJsonLd, libraryCrumbs } from "@/lib/library/json-ld";
import { librarySection } from "@/lib/library/metadata";
import type { LibrarySectionSlug } from "@/lib/library/sections";
import { LibraryShell } from "./library-shell";
import { LibraryLinkGrid } from "./link-grid";

export async function SectionHub({ slug }: { slug: LibrarySectionSlug }) {
	const current = librarySection(slug);
	const path = `/library/${slug}` as const;
	const crumbs = libraryCrumbs([{ name: current.label, href: path }]);
	return (
		<LibraryShell
			title={current.title}
			lede={current.description}
			crumbs={crumbs}
			jsonLd={collectionJsonLd(crumbs, path, current.title)}
			wide
		>
			<LibraryLinkGrid items={sectionLinks(slug)} />
		</LibraryShell>
	);
}
