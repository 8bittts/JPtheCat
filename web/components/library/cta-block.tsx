import { DownloadCta } from "@/components/site/download-cta";
import { HomebrewInstallCallout } from "@/components/site/homebrew-install-callout";
import { SITE } from "@/lib/site";

export function CtaBlock({ heading, sub }: { heading: string; sub?: string }) {
	return (
		<section className="sb-cta-band" aria-labelledby="library-download-cta">
			<h2 id="library-download-cta" className="sb-section-title">
				{heading}
			</h2>
			{sub ? <p className="sb-body mx-auto mt-2 max-w-[52ch]">{sub}</p> : null}
			<DownloadCta
				href={SITE.downloadCtaHref}
				source="library"
				className="sb-btn sb-btn--small mt-5"
			>
				<span className="sb-trim">{SITE.downloadCtaLabel}</span>
			</DownloadCta>
			<div className="mx-auto mt-4 max-w-[430px]">
				<HomebrewInstallCallout />
			</div>
		</section>
	);
}
