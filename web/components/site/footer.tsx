import Image from "next/image";
import Link from "next/link";
import { SITE } from "@/lib/site";

/** Visible copy: Built with: YEN · Bitcoin Email · Terms (spaces are explicit JSX — not flex). */
export const FOOTER_CREDITS_VISIBLE = "Built with: YEN · Bitcoin Email · Terms";

// Sticker Bomb footer shared by every route: a yellow slab, JP's polaroid, and the canonical links.
export function Footer() {
	const year = new Date().getFullYear();
	return (
		<footer className="sb-footer">
			<div className="sb-shell grid gap-8 py-10 md:grid-cols-[minmax(0,1fr)_190px] md:items-center md:gap-14 md:py-14 lg:gap-16">
				<div className="max-w-[560px]">
					<p className="sb-display sb-footer-brand">{SITE.name}</p>
					<p className="sb-footer-body mt-4">
						{SITE.tagline} A free menu bar meter for Claude Code, Codex, Grok, Muse Spark, Cursor,
						and OpenCode Go — cost, official limits, local tokens, measured gateway usage, and light
						+ dark themes.
					</p>
					<p className="sb-footer-support mt-4">
						Ping{" "}
						<a
							href={SITE.supportSocialUrl}
							target="_blank"
							rel="noopener noreferrer"
							className="underline decoration-2 underline-offset-4"
						>
							@8bit
						</a>{" "}
						for support
					</p>
					<div className="sb-footer-legal mt-5 space-y-2">
						<p>
							{year} © {SITE.seoName}. Not affiliated with AI providers.
						</p>
						<p>
							Free and open source (MIT).{" "}
							<a
								href={SITE.repoUrl}
								target="_blank"
								rel="noopener noreferrer"
								className="underline underline-offset-4"
							>
								Contribute on GitHub
							</a>
						</p>
						<nav aria-label="Footer links" className="sb-footer-credits">
							Built with:{" "}
							<a
								href={SITE.yenUrl}
								target="_blank"
								rel="noopener noreferrer"
								className="underline underline-offset-4"
							>
								YEN
							</a>
							{" · "}
							<a
								href={SITE.btcEmailUrl}
								target="_blank"
								rel="noopener noreferrer"
								className="underline underline-offset-4"
							>
								Bitcoin Email
							</a>
							{" · "}
							<Link href="/terms" className="underline underline-offset-4">
								Terms
							</Link>
						</nav>
					</div>
				</div>

				<div className="w-full max-w-[220px] justify-self-center md:max-w-[190px] md:justify-self-end">
					<Image
						src={SITE.photo}
						alt="JP the tortoiseshell cat sitting on a pink bed"
						width={1170}
						height={1522}
						className="sb-footer-photo h-auto w-full md:aspect-[4/5] md:object-cover md:object-[center_42%]"
					/>
					<p className="sb-hand sb-footer-signoff mt-4 text-center">Hi, I'm JP.</p>
				</div>
			</div>
		</footer>
	);
}
