import type { Metadata } from "next";
import Link from "next/link";
import { LegalDocument } from "@/components/legal/legal-document";
import { SceneStage } from "@/components/legal/scene-stage";
import { Footer } from "@/components/site/footer";
import { Nav } from "@/components/site/nav";
import { StickerPageHero } from "@/components/sticker/page-hero";
import {
	COMBINED_LEGAL_TOC,
	POLICY_SECTIONS,
	TERMS_CLAUSES,
	THIRD_PARTIES,
} from "@/lib/legal/combined-legal";
import { PAGE_SEO, pageMetadata } from "@/lib/seo";
import { SITE } from "@/lib/site";

export const metadata: Metadata = pageMetadata(PAGE_SEO.terms);

export default function TermsAndPrivacy() {
	return (
		<>
			<Nav />
			<main id="main-content" className="overflow-hidden">
				<SceneStage variant="terms" />

				<section className="sb-inner sb-section sb-shell">
					<StickerPageHero
						kicker="Legal"
						title="Privacy and Terms of Service"
						lede="How JP the Cat handles your data, what the free app promises, and the plain-language rules for using the website and downloads."
						meta={
							<>
								Last updated November 5, 2026. Questions? Use the contact page or ping @8bit on X.
							</>
						}
					/>

					<LegalDocument
						contentId="legal-content"
						items={COMBINED_LEGAL_TOC}
						navigationLabel="Legal sections"
					>
						<section id="privacy-policy" className="scroll-mt-24">
							<h2 className="sb-page-title--doc">Privacy policy</h2>
							<p className="sb-page-lede mt-3">
								JP the Cat is built around a simple privacy boundary: app usage math happens on your
								Mac, while the website, downloads, updates, and support use the limited services
								described below.
							</p>
						</section>

						{POLICY_SECTIONS.map((section) => (
							<article key={section.id} id={section.id} className="scroll-mt-24">
								<h2 className="sb-section-title">{section.title}</h2>
								<p className="sb-body sb-body--measure mt-3">{section.body}</p>
							</article>
						))}

						<section id="third-party-processors" className="scroll-mt-24">
							<h2 className="sb-section-title">Who may process what.</h2>
							<p className="sb-body sb-body--measure mt-3">
								These services may touch the website, release path, updates, or support. They are
								not a path for app usage history.
							</p>
							<div className="mt-8 space-y-8">
								{THIRD_PARTIES.map(([name, purpose]) => (
									<article key={name}>
										<h3 className="sb-section-title sb-section-title--sm">{name}</h3>
										<p className="sb-body sb-body--measure mt-2">{purpose}</p>
									</article>
								))}
							</div>
						</section>

						<p id="privacy-contact" className="sb-body sb-body--measure scroll-mt-24">
							Questions about privacy? Use the{" "}
							<Link href={SITE.contactHref} className="sb-text-link">
								contact page
							</Link>{" "}
							or email{" "}
							<a className="sb-text-link" href={`mailto:${SITE.email}`}>
								{SITE.email}
							</a>
							.
						</p>

						<section id="terms-of-service" className="scroll-mt-24 pt-6">
							<h2 className="sb-page-title--doc">Terms of service</h2>
							<p className="sb-page-lede mt-3">
								These terms cover free use, earlier purchases, provider responsibility, fair use,
								updates, warranty, and liability. JP is a local meter, not your official provider
								bill.
							</p>
						</section>

						{TERMS_CLAUSES.map((clause) => (
							<article key={clause.id} id={clause.id} className="scroll-mt-24">
								<h2 className="sb-section-title">{clause.title}</h2>
								<p className="sb-body sb-body--measure mt-3">{clause.body}</p>
							</article>
						))}

						<p className="sb-body sb-body--measure">
							Need help? Visit{" "}
							<Link href={SITE.contactHref} className="sb-text-link">
								contact
							</Link>{" "}
							or email{" "}
							<a className="sb-text-link" href={`mailto:${SITE.email}`}>
								{SITE.email}
							</a>
							.
						</p>
					</LegalDocument>
				</section>
			</main>
			<Footer />
		</>
	);
}
