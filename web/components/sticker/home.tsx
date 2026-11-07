import Image from "next/image";
import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";
import { DownloadCta } from "@/components/site/download-cta";
import { MenubarDemo } from "@/components/site/menubar-demo";
import { HOMEBREW_INSTALL_COMMANDS } from "@/lib/homebrew";
import { HOMEPAGE_PROVIDERS } from "@/lib/homepage-providers";
import { SITE } from "@/lib/site";
import { MeowCat } from "./meow-cat";

const tilt = (deg: number, extra?: CSSProperties) =>
	({ "--r": `${deg}deg`, ...extra }) as CSSProperties;

const STEPS = [
	{
		k: "Track",
		t: "Local truth, zero setup",
		d: "Claude Code, Codex, and Grok Build already keep usage logs on your Mac — no account, no API key. Muse Spark and OpenCode Go read OpenCode's local database here; Muse Spark counts sessions on this Mac, not your full Meta account dashboard. Follow along in the menu bar, the macOS widget, or her dashboard.",
		bg: "var(--sb-orange)",
	},
	{
		k: "Cost",
		t: "Priced to the cent",
		d: "Real dollars with real per-model rates — the 5min vs 1hr cache split most tools flatten, streaming chunks de-duplicated. Pick a 7, 14, 30, or 90-day window and JP does the math.",
		bg: "var(--sb-pink)",
	},
	{
		k: "Limit",
		t: "Real limits, from the source",
		d: "Your 5hr and weekly usage comes straight from official feeds — Codex automatically, Claude when live limits are on. Every number is stamped official. JP never guesses.",
		bg: "var(--sb-yellow)",
	},
	{
		k: "Alert",
		t: "One meow. Never a nag.",
		d: "A single meow and a native macOS banner the moment a provider crosses 80% — once per window, then quiet. Tune it or turn it off in Settings.",
		bg: "var(--sb-honey)",
	},
];

const PROMISES = [
	{
		h: "Never leaves your Mac",
		b: "Your prompts, code, transcripts, token history, and API keys stay on machine — always and forever.",
		bg: "var(--sb-pink)",
	},
	{
		h: "Least-privilege access",
		b: "No Full Disk Access. Ever. JP reads only the provider logs already on device and never breaks your privacy.",
		bg: "var(--sb-yellow)",
	},
	{
		h: "Signed & notarized",
		b: "Developer ID signed and notarized by Apple, so Gatekeeper opens her with one friendly “are you sure?” — never the scary block.",
		bg: "var(--sb-orange)",
	},
];

const WIDGET_SIZES = [
	{ n: "Small", d: "Today's total, notional tag, and live spend." },
	{ n: "Medium", d: "Small + per-provider breakdown with gauges." },
	{ n: "Large", d: "Medium + last 30 days total and more." },
];

const WIDGET_STEPS = [
	"Download it. Meow.",
	"Right-click the desktop or open Notification Center.",
	`Search for “${SITE.name}”.`,
	"Choose a size and drag it into place.",
];

const THEMES = [
	{ file: "theme-1.webp", name: "Sunlit Ledger" },
	{ file: "theme-2.webp", name: "Retro Terminal" },
	{ file: "theme-3.webp", name: "Tokyo Night" },
	{ file: "theme-4.webp", name: "GitHub Dark" },
];

const FAQ: { id: string; q: string; a: ReactNode }[] = [
	{
		id: "free",
		q: "Is it really free?",
		a: "Yes. Download it, keep it, use every feature. No account to create, no card, no trial clock.",
	},
	{
		id: "inside",
		q: "What's inside JP the Cat?",
		a: "Real Claude Code dollars, cache-aware and deduplicated; Codex's official 5-hour and weekly limits, automatic; Grok Build as notional list-price dollars from local sessions; Claude's official limits once you opt in; an optional Cursor CLI row; a per-model provider drawer; a native macOS widget in three sizes; 24 themes; a 7/14/30/90-day window; and an 80% usage alert with JP's meow.",
	},
	{
		id: "free-tools",
		q: "How is this different from other usage tools?",
		a: "Most CLIs and menu-bar tools show token counts and rough percentages — and several misprice cache tokens. JP starts with accurate Claude Code dollars, Codex's official limits, and honest notional Grok cost, then adds a widget, themes, and an 80% meow. Cursor stays estimate-only and never sneaks into the headline total.",
	},
	{
		id: "notch-apps",
		q: "Isn't this just another notch app?",
		a: `Different job. Those are agent control panels — approve prompts, jump to terminals. ${SITE.name} is a cost-and-limits meter: what am I spending, and how much of the current window is used?`,
	},
	{
		id: "accuracy",
		q: "How accurate is the cost?",
		a: (
			<>
				Claude Code is priced from the same{" "}
				<Link href="/library/pricing" prefetch={false} className="font-bold underline">
					per-model rates
				</Link>{" "}
				as your invoice, including the 5-minute vs 1-hour cache-write split. Codex's 5-hour and
				weekly numbers come straight from its own rollout log, marked official. Grok uses official
				xAI API list prices as notional cost — never claimed as subscription spend. Cursor is
				token-estimate only. Anywhere a number is inferred, JP stamps it est.
			</>
		),
	},
	{
		id: "requirements",
		q: "What do I need to run it?",
		a: "macOS 14 (Sonoma) or newer on an Apple Silicon Mac, plus Claude Code, Codex, and/or Grok Build. Any combination makes her happy. Cursor CLI is optional.",
	},
	{
		id: "install",
		q: "Is it safe to install?",
		a: "Yes. She is signed with a Developer ID and notarized by Apple. She runs unsandboxed for exactly one reason — to read home-root tool logs (~/.claude, ~/.codex, ~/.grok, and OpenCode's local data) — so there's no Full Disk Access and no Accessibility prompt.",
	},
	{
		id: "updates",
		q: "How do I get updates?",
		a: "JP updates herself in place with one click, using Sparkle. A dot in Settings turns amber when a new build is ready; click it and she installs it while keeping your settings.",
	},
	{
		id: "offline",
		q: "Does it work offline?",
		a: "Yes. JP reads the on-disk logs your tools already write, so cost and usage math stays local and keeps working offline.",
	},
	{
		id: "uninstall",
		q: "How do I uninstall it?",
		a: `Drag ${SITE.name} to the Trash. If you turned on Claude live limits, switch that off first (Settings → Live data). Her own files live in ~/Library/Application Support/JPtheCat — delete that folder to clear every trace.`,
	},
	{
		id: "jp",
		q: "Who is JP the Cat, exactly?",
		a: "A highly opinionated tortoiseshell with impeccable taste and zero patience for wasted tokens. Lovable, a little bossy, and extremely picky about who she works with.",
	},
];

function Download({ children, small }: { children: ReactNode; small?: boolean }) {
	return (
		<DownloadCta
			href={SITE.downloadCtaHref}
			source="pricing"
			prefetch={false}
			className={small ? "sb-btn sb-btn--small" : "sb-btn"}
		>
			<span className="sb-trim">{children}</span>
		</DownloadCta>
	);
}

function ProviderPill({ provider }: { provider: (typeof HOMEPAGE_PROVIDERS)[number] }) {
	return (
		<span className="sb-pill">
			{/* The self-hosted marks are white template glyphs (made for dark menu bars), so they are
			    painted through a mask in ink instead of being shown as a white-on-white <img>. */}
			{provider.icon ? (
				<span
					className="sb-pill__icon"
					aria-hidden="true"
					style={{ "--sb-icon": `url(${provider.icon})` } as CSSProperties}
				/>
			) : (
				<span className="sb-pill__mono" aria-hidden="true">
					{provider.name.charAt(0)}
				</span>
			)}
			{provider.name}
		</span>
	);
}

export function StickerHome() {
	const words = ["Know", "your", "agent", "costs!"];
	const marquee = [0, 1, 2].flatMap((copy) =>
		HOMEPAGE_PROVIDERS.map((provider) => ({ provider, key: `${copy}-${provider.id}` })),
	);
	return (
		<>
			<section id="top" className="sb-hero sb-shell">
				<h1 className="sb-h1">
					{words.map((w) => (
						<span key={w}>{w}&nbsp;</span>
					))}
				</h1>
				<div style={{ position: "relative" }}>
					<MeowCat />
					<span
						className="sb-sticker"
						style={tilt(-10, {
							background: "var(--sb-yellow)",
							left: "max(0px, calc(50% - 420px))",
							top: "14%",
						})}
					>
						<span className="sb-trim">every cent</span>
					</span>
					<span
						className="sb-sticker"
						style={tilt(8, {
							background: "var(--sb-honey)",
							right: "max(0px, calc(50% - 430px))",
							top: "42%",
							"--d": "-1s",
						} as CSSProperties)}
					>
						<span className="sb-trim">100% local</span>
					</span>
					<span
						className="sb-sticker"
						style={tilt(6, {
							background: "var(--sb-pink)",
							left: "max(0px, calc(50% - 380px))",
							bottom: "6%",
							"--d": "-2s",
						} as CSSProperties)}
					>
						<span className="sb-trim">free now!!</span>
					</span>
				</div>
				<p className="sb-sub">
					Your AI agents&apos; tokens, cost, and limits — right in the menu bar.
				</p>
				<div className="sb-cta-row">
					<Download>Download free ↓</Download>
					<a href="#how" className="sb-link">
						how it works →
					</a>
				</div>
				<p className="sb-fine">Free · Offline · No account · {SITE.minMacOS}+</p>
			</section>

			<div className="sb-marquee">
				<div className="sb-marquee__track">
					{marquee.map(({ provider, key }) => (
						<ProviderPill key={key} provider={provider} />
					))}
				</div>
			</div>

			<section id="demo" className="sb-section sb-shell">
				<h2 className="sb-h2">Go on, poke her.</h2>
				<p className="sb-lede">
					This is the real menu bar dashboard, running right here with demo numbers. Switch
					providers, change the window, flip to Settings.
				</p>
				<div className="sb-demo">
					<div className="sb-demo__inner">
						<MenubarDemo />
					</div>
				</div>
			</section>

			<section id="how" className="sb-section sb-shell">
				<h2 className="sb-h2">
					Four small jobs,
					<br />
					done purrfectly.
				</h2>
				<div className="sb-board">
					{STEPS.map((s, i) => (
						<article
							className="sb-card"
							key={s.k}
							style={tilt([-2, 1.5, -1, 2][i] ?? 0, { background: s.bg })}
						>
							<span className="sb-hand">
								#{i + 1} {s.k}
							</span>
							<h3>{s.t}</h3>
							<p>{s.d}</p>
						</article>
					))}
				</div>
			</section>

			<section id="analytics" className="sb-section sb-shell">
				<h2 className="sb-h2">
					Look at all
					<br />
					those numbers.
				</h2>
				<div className="sb-frame">
					<Image
						src="/jpthecat-analytics-big.png"
						alt={`${SITE.name} Advanced Analytics: a spend hero, stat tiles, provider trends, heatmaps, and a per-model table — every figure stamped official or est.`}
						width={4040}
						height={1936}
						quality={90}
						sizes="(max-width: 1248px) 100vw, 1152px"
					/>
				</div>
				<p className="sb-hand sb-cap">
					Advanced Analytics — every number labelled official or est.
				</p>
			</section>

			<section id="widget" className="sb-section sb-shell">
				<h2 className="sb-h2">On your desktop, too.</h2>
				<div className="sb-widgets">
					<div className="grid gap-6">
						<article className="sb-card" style={tilt(1)}>
							<h3>Pick a size</h3>
							<dl className="sb-sizes">
								{WIDGET_SIZES.map((w) => (
									<div key={w.n}>
										<dt>{w.n}</dt>
										<dd>{w.d}</dd>
									</div>
								))}
							</dl>
						</article>
						<article className="sb-card" style={tilt(-1, { background: "var(--sb-yellow)" })}>
							<h3>Add it in seconds</h3>
							<ol className="sb-steps">
								{WIDGET_STEPS.map((step) => (
									<li key={step}>{step}</li>
								))}
							</ol>
						</article>
					</div>
					<div className="grid gap-5">
						<Image
							src="/widget/widget-large-light.webp"
							alt={`${SITE.name} Large macOS widget in Sunlit light mode with provider rows and usage gauges.`}
							width={1092}
							height={1146}
							sizes="(max-width: 900px) 100vw, 540px"
						/>
						<div className="grid grid-cols-[2fr_1fr] gap-5">
							<Image
								src="/widget/widget-medium-dark.webp"
								alt={`${SITE.name} Medium widget in Midnight dark mode.`}
								width={1092}
								height={510}
								sizes="(max-width: 900px) 66vw, 360px"
							/>
							<Image
								src="/widget/widget-small-light.webp"
								alt={`${SITE.name} Small widget with today's total.`}
								width={510}
								height={510}
								sizes="(max-width: 900px) 33vw, 180px"
							/>
						</div>
					</div>
				</div>
			</section>

			<section id="themes" className="sb-section sb-shell">
				<h2 className="sb-h2">24 themes. 1 cat.</h2>
				<p className="sb-lede">From Sunlit light to twenty-one terminal-inspired dark packs.</p>
				<div className="sb-themes">
					{THEMES.map((t, i) => (
						<figure key={t.file} style={tilt([-2, 1.5, -1, 2][i] ?? 0)}>
							<Image
								src={`/${t.file}`}
								alt={`${SITE.name} dashboard in the ${t.name} theme`}
								width={808}
								height={960}
								sizes="(max-width: 900px) 50vw, 280px"
							/>
							<figcaption className="sb-hand">{t.name}</figcaption>
						</figure>
					))}
				</div>
			</section>

			<section id="honest" className="sb-section sb-shell">
				<h2 className="sb-h2">She keeps secrets.</h2>
				<p className="sb-lede">
					Every plan figure comes straight from the provider&apos;s own counter, stamped{" "}
					<span
						className="sb-tag"
						style={{ background: "var(--sb-orange)", color: "var(--sb-white)" }}
					>
						official
					</span>
					. Anything JP works out on top is stamped{" "}
					<span className="sb-tag" style={{ background: "var(--sb-yellow)" }}>
						est.
					</span>{" "}
					and never dressed up as measured.
				</p>
				<div className="sb-board">
					{PROMISES.map((p, i) => (
						<article
							className="sb-card"
							key={p.h}
							style={tilt([-1.5, 1, -1][i] ?? 0, { background: p.bg })}
						>
							<h3>{p.h}</h3>
							<p>{p.b}</p>
						</article>
					))}
				</div>
			</section>

			<section id="download" className="sb-section sb-shell">
				{/* Old inbound links point at /#pricing; keep the anchor so they land on the free card. */}
				<span id="pricing" aria-hidden="true" />
				<div className="sb-free">
					<span className="sb-hand sb-hand--xl">the price is…</span>
					<span className="sb-free__price">$0</span>
					<p className="sb-lede-strong">
						No trial. No license key. No account. Just a very picky cat and very accurate numbers.
					</p>
					<div className="sb-cta-row">
						<Download>Get JP free ↓</Download>
					</div>
					<p className="sb-fine">{SITE.minMacOS}+ · Apple Silicon · or install with Homebrew:</p>
					<code className="sb-code">{HOMEBREW_INSTALL_COMMANDS.join("\n")}</code>
				</div>
			</section>

			<section id="faq" className="sb-section sb-shell">
				<h2 className="sb-h2">Questions?</h2>
				<div className="sb-faq">
					{FAQ.map((f) => (
						<details key={f.id} id={`faq-${f.id}`}>
							<summary>{f.q}</summary>
							<div>{f.a}</div>
						</details>
					))}
				</div>
				<div className="sb-cta-row" style={{ marginTop: 48 }}>
					<Download>Download free ↓</Download>
					<a href={SITE.contactHref} className="sb-link">
						still stuck? write to JP →
					</a>
				</div>
			</section>
		</>
	);
}
