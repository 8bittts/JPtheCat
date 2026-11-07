import { headers } from "next/headers";
import type { ReactNode } from "react";
import { Footer } from "@/components/site/footer";
import { Nav } from "@/components/site/nav";
import { StickerPageHero } from "@/components/sticker/page-hero";
import { jsonLdString } from "@/lib/library/json-ld";
import { type Crumb, LibraryBreadcrumb } from "./breadcrumb";

interface LibraryShellProps {
	title: string;
	lede: string;
	crumbs: Crumb[];
	jsonLd: Record<string, unknown>;
	children: ReactNode;
	eyebrow?: string;
	wide?: boolean;
}

/**
 * Shared page frame for every `/library` route: Nav + a reading-width main with breadcrumb, hero,
 * and nonce'd JSON-LD, + Footer. `/library` is crawlable via the sitemap but never linked from this
 * chrome (_docs/08-growth.md SEO guardrails). Async so it can read the per-request CSP nonce.
 */
export async function LibraryShell({
	title,
	lede,
	crumbs,
	jsonLd,
	children,
	eyebrow,
	wide,
}: LibraryShellProps) {
	const nonce = (await headers()).get("x-nonce") ?? undefined;
	return (
		<>
			<script nonce={nonce} type="application/ld+json" suppressHydrationWarning>
				{jsonLdString(jsonLd)}
			</script>
			<Nav />
			<main
				id="main-content"
				className={`sb-inner sb-shell sb-section ${wide ? "max-w-[var(--measure-well)]" : "reading-shell mx-auto w-full"}`}
			>
				<LibraryBreadcrumb crumbs={crumbs} />
				<div className="mt-6">
					<StickerPageHero kicker={eyebrow} title={title} lede={lede} />
				</div>
				{children}
			</main>
			<Footer />
		</>
	);
}
