import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";
import { ContactSupportCta } from "@/components/site/contact-support-cta";
import { Footer } from "@/components/site/footer";
import { Nav } from "@/components/site/nav";
import { MeowCat } from "@/components/sticker/meow-cat";
import { PAGE_SEO, pageMetadata } from "@/lib/seo";
import { SITE } from "@/lib/site";

// Page-specific OG/Twitter cards — without `pageMetadata`, /contact would inherit the root
// layout's HOME social cards (title/description/url). See lib/seo.ts.
export const metadata = pageMetadata(PAGE_SEO.contact);

const tilt = (deg: number, extra?: CSSProperties) =>
	({ "--r": `${deg}deg`, ...extra }) as CSSProperties;

const HELP_NOTES = [
	{
		kicker: "Numbers",
		title: "A number looks off",
		body: "Tell me which provider and window, and what your provider dashboard says. Never send private agent logs.",
		icon: "key",
		bg: "var(--sb-honey)",
	},
	{
		kicker: "Install",
		title: "Download or Mac setup",
		body: "Stuck opening the app, finding the menu-bar cat, or moving to another Mac? Include your macOS version.",
		icon: "spark",
		bg: "var(--sb-orange)",
	},
	{
		kicker: "Support",
		title: "Product help",
		body: "Questions about features, themes, the widget, or supported providers belong here too.",
		icon: "bell",
		bg: "var(--sb-pink)",
	},
] as const;

function ContactListeningCard() {
	return (
		<article
			className="sb-card mx-auto w-full max-w-[420px]"
			style={tilt(1.5, { background: "var(--sb-yellow)" })}
		>
			<span className="sb-tag" style={{ background: "var(--sb-white)" }}>
				Contact
			</span>
			<h2 className="sb-hand sb-hand--lg mt-3">JP is listening</h2>
			<p className="sb-hand sb-hand-accent mt-2">Tiny desk, sharp claws, actual help.</p>
			<p className="sb-body mt-3">
				Send a clear note and JP&apos;s human will follow up from {SITE.email}.
			</p>
			<div className="sb-row mt-4 !justify-start">
				<span className="sb-pill">Number checks</span>
				<span className="sb-pill">Mac setup</span>
			</div>
			<p className="sb-hand mt-5 text-right">— JP</p>
		</article>
	);
}

function ContactIcon({ name, className = "h-4 w-4" }: { name: string; className?: string }) {
	const path =
		name === "key" ? (
			<>
				<circle cx="7.5" cy="14.5" r="3.5" />
				<path d="M10.2 11.8 20 2m-3 3 3 3m-6 0 2 2" />
			</>
		) : name === "spark" ? (
			<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6.3 6.3l2.5 2.5M15.2 15.2l2.5 2.5M17.7 6.3l-2.5 2.5M8.8 15.2l-2.5 2.5" />
		) : (
			<>
				<path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6Z" />
				<path d="M10 20a2 2 0 0 0 4 0" />
			</>
		);
	return (
		<svg
			viewBox="0 0 24 24"
			className={className}
			fill="none"
			stroke="currentColor"
			strokeWidth="1.7"
			strokeLinecap="round"
			strokeLinejoin="round"
			aria-hidden="true"
		>
			{path}
		</svg>
	);
}

function HelpListItem({ children }: { children: ReactNode }) {
	return <li>{children}</li>;
}

export default function ContactPage() {
	return (
		<>
			<Nav />
			<main id="main-content">
				<section className="sb-hero sb-shell">
					<p className="sb-page-kicker">Contact JP · warm paws, useful answers</p>
					<h1 className="sb-h2 mt-4">
						Need a <span className="sb-accent">paw</span>?
					</h1>
					<p className="sb-sub">
						Stuck on setup, seeing a number you don&apos;t trust, or need a hand getting JP settled
						in your menu bar? Send the details and I&apos;ll sort it out.
					</p>

					<div className="relative mx-auto mt-6 max-w-[720px]">
						<MeowCat />
						<span
							className="sb-sticker"
							style={tilt(-8, {
								background: "var(--sb-honey)",
								left: "max(0px, calc(50% - 400px))",
								top: "8%",
							})}
						>
							<span className="sb-trim">warm paws</span>
						</span>
						<span
							className="sb-sticker"
							style={tilt(6, {
								background: "var(--sb-pink)",
								right: "max(0px, calc(50% - 400px))",
								top: "36%",
								"--d": "-1s",
							} as CSSProperties)}
						>
							<span className="sb-trim">useful answers</span>
						</span>
					</div>

					<div className="mt-8">
						<ContactListeningCard />
					</div>

					<div className="sb-cta-row">
						<ContactSupportCta />
						<Link href="/#faq" className="sb-link">
							Read the FAQ →
						</Link>
					</div>
				</section>

				<section className="sb-section sb-shell">
					<h2 className="sb-h2">
						Short note, enough clues, <span className="sb-accent">no secrets</span>.
					</h2>
					<p className="sb-lede">
						JP the Cat is privacy-minded: prompts, code, and transcripts belong on your Mac. Support
						works best with app details and a short description instead.
					</p>

					<div className="sb-board">
						{HELP_NOTES.map((note, i) => (
							<article
								key={note.kicker}
								className="sb-card"
								style={tilt([-2, 1.5, -1][i] ?? 0, { background: note.bg })}
							>
								<span className="sb-tag inline-flex items-center gap-1.5">
									<ContactIcon name={note.icon} className="h-[15px] w-[15px]" />
									{note.kicker}
								</span>
								<h3>{note.title}</h3>
								<p>{note.body}</p>
							</article>
						))}
					</div>

					<article className="sb-card mx-auto mt-10 max-w-[620px]" style={tilt(-0.5)}>
						<p className="sb-page-kicker">JP&apos;s checklist</p>
						<ul className="sb-body mt-3 space-y-2">
							<HelpListItem>
								Include the app version and macOS version for setup issues.
							</HelpListItem>
							<HelpListItem>
								Do not paste prompts, source code, transcripts, or OAuth tokens.
							</HelpListItem>
							<HelpListItem>
								For legal questions, the Terms and Privacy pages still list the direct support
								address.
							</HelpListItem>
						</ul>
					</article>

					<p className="sb-hand sb-cap">
						JP reads quickly, judges quietly, and answers through a human.
					</p>
				</section>
			</main>
			<Footer />
		</>
	);
}
