import { LibraryShell } from "@/components/library/library-shell";
import { StatusMatrix } from "@/components/library/status-matrix";
import { collectionJsonLd, libraryCrumbs } from "@/lib/library/json-ld";
import { libraryPageMetadata } from "@/lib/library/metadata";

export const metadata = libraryPageMetadata({
	title: "Track AI coding agent usage on macOS",
	description:
		"Which AI coding agents JP the Cat tracks today, from Claude Code and Codex to OpenCode Zen and Go, and where every other provider sits on the roadmap.",
	path: "/library/track",
});

export default function TrackHub() {
	const crumbs = libraryCrumbs([{ name: "Track usage", href: "/library/track" }]);
	return (
		<LibraryShell
			title="Track AI coding agent usage & cost"
			lede="JP the Cat tracks Claude Code, Codex, and Grok from local session logs, and Muse Spark, OpenCode Zen, and OpenCode Go from OpenCode on this Mac (not your full Meta account dashboard). Here is every provider in the catalog by support status — the live ones link through to a page; the rest are roadmap, never presented as supported."
			crumbs={crumbs}
			jsonLd={collectionJsonLd(crumbs, "/library/track", "Track AI coding agent usage")}
			wide
		>
			<StatusMatrix />
		</LibraryShell>
	);
}
