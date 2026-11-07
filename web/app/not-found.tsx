import type { Metadata } from "next";
import Link from "next/link";
import { Footer } from "@/components/site/footer";
import { Nav } from "@/components/site/nav";
import { MeowCat } from "@/components/sticker/meow-cat";
import { SITE } from "@/lib/site";

export const metadata: Metadata = {
	title: { absolute: `404 — ${SITE.name}` },
	description: "That JP the Cat page was not found.",
	alternates: {},
	robots: { index: false, follow: false },
	openGraph: {
		title: `404 — ${SITE.name}`,
		description: "That JP the Cat page was not found.",
		url: SITE.url,
		siteName: SITE.name,
		type: "website",
		locale: "en_US",
		images: [{ url: SITE.ogImage, width: 1200, height: 630, alt: `404 — ${SITE.name}` }],
	},
	twitter: {
		card: "summary_large_image",
		title: `404 — ${SITE.name}`,
		description: "That JP the Cat page was not found.",
		site: SITE.twitter,
		creator: SITE.twitter,
		images: [SITE.ogImage],
	},
};

/**
 * Global 404 — the render target for every `notFound()` across the library routes
 * and any unmatched URL. The CTA pair routes home, never /download.
 */
export default function NotFound() {
	return (
		<>
			<Nav />
			<main id="main-content">
				<section className="sb-hero sb-shell">
					<p className="sb-page-kicker">404 · Page not found</p>
					<div aria-hidden className="sb-404 tnum">
						4<span>0</span>4
					</div>
					<h1 className="sb-page-title mt-4">
						This page <span className="sb-accent">wandered</span> off.
					</h1>
					<p className="sb-page-lede">
						Very unlike me — I count everything, and this one never made the ledger. Let&apos;s get
						you back to a page that actually adds up.
					</p>
					<div className="relative mx-auto mt-6 max-w-[520px]">
						<MeowCat />
					</div>
					<div className="sb-cta-row">
						<Link href="/" className="sb-btn sb-btn--small">
							<span className="sb-trim">Take me home</span>
						</Link>
						<Link href="/#how" className="sb-link">
							See how JP works →
						</Link>
					</div>
					<p className="sb-fine">
						Getting lost here cost you exactly <span className="tnum">$0.00</span> — I checked.
					</p>
				</section>
			</main>
			<Footer />
		</>
	);
}
