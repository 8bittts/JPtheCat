import Link from "next/link";
import { LibraryShell } from "@/components/library/library-shell";
import { LibraryLinkGrid } from "@/components/library/link-grid";
import { LibraryValueBenchmark } from "@/components/library/value-benchmark";
import { rootHubSections } from "@/lib/library/hub";
import { collectionJsonLd, libraryCrumbs } from "@/lib/library/json-ld";
import { libraryPageMetadata } from "@/lib/library/metadata";
import { MODEL_ID_ALIASES } from "@/lib/library/pricing-data";
import { liveProviderNames, roadmapProviderCount } from "@/lib/library/provider-registry";

/** Local model ids (e.g. Grok Build's `grok-4.7-build`) that bill at a published row. */
const LOCAL_ID_COUNT = Object.keys(MODEL_ID_ALIASES).length;

export const metadata = libraryPageMetadata({
	title: "AI coding cost & usage library",
	description:
		"Model pricing, usage limits, calculators, and honest guides for what Claude Code, Codex, Grok, Muse Spark, OpenCode, and more AI coding agents cost.",
	path: "/library",
});

export default function LibraryHome() {
	const crumbs = libraryCrumbs([]);
	return (
		<LibraryShell
			title="The AI coding cost & usage library"
			lede={`Straight answers on what your AI coding agents cost and how close you are to your limits — model pricing, calculators, rate-limit explainers, and honest comparisons. ${liveProviderNames()} are tracked today; ${roadmapProviderCount()} more providers are on the roadmap.`}
			crumbs={crumbs}
			jsonLd={collectionJsonLd(crumbs, "/library", "AI coding cost & usage library")}
			wide
		>
			<section className="sb-panel">
				<p className="sb-page-kicker mb-2">Pricing accuracy</p>
				<h2 className="sb-section-title">Local model IDs stay in the total</h2>
				<p className="sb-body sb-body--measure mt-3 opacity-90">
					Coding agents log some models under their own IDs — Grok Build writes grok-4.7-build for
					Grok 4.7. JP maps {LOCAL_ID_COUNT} local and legacy IDs to the published rate they bill
					at, so those sessions are counted instead of omitted as unpriced.
				</p>
				<p className="sb-body mt-3">
					<Link href="/library/pricing/family/xai" className="sb-text-link">
						See every Grok rate
					</Link>
				</p>
			</section>
			<LibraryValueBenchmark />
			<LibraryLinkGrid items={rootHubSections()} />
		</LibraryShell>
	);
}
