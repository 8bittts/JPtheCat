import { describe, expect, it } from "bun:test";
import { readdir } from "node:fs/promises";
import { join } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { CtaBlock } from "@/components/library/cta-block";
import { StickerHome } from "@/components/sticker/home";
import { NAV, PROVIDER_COUNTS, PROVIDERS, SITE } from "@/lib/site";

async function collectTsxFiles(directory: string): Promise<string[]> {
	const entries = await readdir(directory, { withFileTypes: true });
	const nested = await Promise.all(
		entries.map((entry) => {
			const path = join(directory, entry.name);
			if (entry.isDirectory()) {
				return collectTsxFiles(path);
			}
			return entry.isFile() && path.endsWith(".tsx") ? [path] : [];
		}),
	);
	return nested.flat();
}

// The homepage demo card is one 1:1 mirror of the native app spread over five modules: the dashboard
// face + card root (`menubar-demo.tsx`), the settings face (`menubar-demo-settings.tsx`), the chrome
// and card footer both faces share (`menubar-demo-chrome.tsx`), the modal dialogs
// (`demo-dialogs.tsx`), and the data/format/audio helpers. Guards that assert a control is ABSENT
// must scan every one of them, or a control simply moved into a sibling module would pass a guard
// that stopped looking at the right file. Keep this list complete when adding a module.
const DEMO_MODULES = [
	"components/site/menubar-demo.tsx",
	"components/site/menubar-demo-settings.tsx",
	"components/site/menubar-demo-chrome.tsx",
	"components/site/demo-dialogs.tsx",
	"components/site/menubar-demo-audio.ts",
	"components/site/menubar-demo-format.ts",
] as const;

async function readDemoModules(): Promise<string[]> {
	return Promise.all(DEMO_MODULES.map((path) => Bun.file(path).text()));
}

describe("public launch copy", () => {
	it("marks only implemented providers as live", () => {
		expect(PROVIDERS.filter((provider) => provider.live).map((provider) => provider.name)).toEqual([
			"Claude Code",
			"Codex",
			"Grok",
			"Muse Spark",
			"OpenCode Zen",
			"OpenCode Go",
		]);
	});

	it("publishes the comprehensive provider catalog without overclaiming launch support", () => {
		expect(PROVIDER_COUNTS.total).toBe(64);
		expect(PROVIDER_COUNTS.live).toBe(6);
		expect(PROVIDER_COUNTS.codexBarBaseline).toBe(51);
		expect(PROVIDER_COUNTS.ccusageLocalSources).toBe(15);
		expect(PROVIDER_COUNTS.codingAgentUsageTracker).toBe(15);
		expect(PROVIDER_COUNTS.openIslandAgents).toBe(9);
		expect(PROVIDER_COUNTS.apiRoadmap).toBe(38);

		for (const name of [
			"Claude Code",
			"Codex",
			"Gemini",
			"GitHub Copilot",
			"OpenCode Zen",
			"OpenCode Go",
			"Amp",
			"Droid (Factory)",
			"Codebuff",
			"Hermes Agent",
			"pi-agent",
			"Goose",
			"OpenClaw",
			"Qwen",
			"Qoder",
			"CodeBuddy",
			"OpenRouter",
			"LiteLLM",
			"Aider",
			"Antigravity",
		]) {
			expect(PROVIDERS.map((provider) => provider.name)).toContain(name);
		}
	});

	it("does not present future providers as launch-ready in metadata", () => {
		expect(SITE.description).toContain("Claude Code");
		expect(SITE.description).toContain("Cursor tokens");
		expect(SITE.description).not.toContain("live across");
		// Honesty gate: the catalog must be framed as roadmap, and "live" must attach to
		// Claude Code — never to the catalog of not-yet-supported providers.
		expect(SITE.description).not.toContain("65-provider");
		expect(SITE.description).toContain("measured gateway usage");
	});

	it("keeps the public footer contact, social, and JP photo canonical", () => {
		expect(SITE.email).toBe("support@jpthecat.com");
		expect(SITE.contactHref).toBe("/contact");
		expect(SITE.twitter).toBe("@8bit");
		expect(SITE.photo).toBe("/jp-the-cat.jpeg");
		expect(SITE.domain).toBe("JPtheCat.com");
	});

	it("routes non-legal support email links through the contact page", async () => {
		const siteEmailMailtoTemplate = /mailto:\$\{SITE\.email\}/;
		const sources = await Promise.all(
			["components/site/footer.tsx", ...DEMO_MODULES].map(
				async (file) => [file, await Bun.file(file).text()] as const,
			),
		);

		for (const [, source] of sources) {
			expect(source).not.toMatch(siteEmailMailtoTemplate);
			expect(source).not.toContain("mailto:support@jpthecat.com");
		}

		// /contact routes support through the real, submittable "Get Support" modal instead of a bare
		// mailto link — see components/site/contact-support-cta.tsx.
		expect(await Bun.file("app/contact/page.tsx").text()).toMatch(/<ContactSupportCta\b/);
		expect(await Bun.file("components/site/contact-support-cta.tsx").text()).toContain(
			"/api/support-report",
		);

		expect(sources.find(([file]) => file.endsWith("footer.tsx"))?.[1]).toContain(
			"SITE.supportSocialUrl",
		);
		// Settings → General → Support report opens the redacted support modal (menubar-demo-settings.tsx).
		expect(sources.find(([file]) => file.endsWith("menubar-demo-settings.tsx"))?.[1]).toContain(
			"Support report",
		);
		expect(await Bun.file("app/terms/page.tsx").text()).toMatch(siteEmailMailtoTemplate);
		expect(await Bun.file("lib/legal/combined-legal.ts").text()).toContain("Vercel Web Analytics");
	});

	it("keeps global navigation valid from legal routes", () => {
		expect(NAV.map((item) => item.href)).toEqual(["/#how", "/#widget", "/#honest", "/#faq"]);
		// JP is a free download: the header never links to a pricing section.
		expect(NAV.map((item) => item.href)).not.toContain("/#pricing");
	});

	it("keeps the global header aligned and silent", async () => {
		const nav = await Bun.file("components/site/nav.tsx").text();

		expect(nav).toContain("home-shell");
		expect(nav).not.toContain("PurrOnHover");
		expect(nav).not.toContain("nav-logo");
	});

	it("keeps mobile navigation as a hamburger toggle, matching yenchat", async () => {
		const nav = await Bun.file("components/site/nav.tsx").text();

		expect(nav).toContain("md:sticky");
		expect(nav).toContain('aria-label="Primary navigation"');
		expect(nav).toContain('aria-label="Toggle navigation menu"');
		expect(nav).toContain("aria-expanded={open}");
		expect(nav).toContain('aria-controls="mobile-site-nav"');
		expect(nav).toContain('id="mobile-site-nav"');
		expect(nav).not.toContain('className="sticky top-0');
		expect(nav).not.toContain("<details");
		expect(nav).not.toContain("<summary");
	});

	it("keeps the homepage demo footer help action on the canonical website URL", async () => {
		// The card footer is shared by BOTH faces and lives in menubar-demo-chrome.tsx.
		const modules = await readDemoModules();
		const chrome = await Bun.file("components/site/menubar-demo-chrome.tsx").text();

		expect(chrome).toContain('aria-label="Open JP the Cat website"');
		expect(chrome).toContain("href={SITE.url}");
		expect(chrome).toContain('target="_blank"');
		for (const source of modules) {
			expect(source).not.toContain('href="/"');
		}
	});

	it("keeps the homepage demo JP badge wired to the social share dialog", async () => {
		// The JP badge lives in the shared CardFooter (menubar-demo-chrome.tsx), rendered by both faces.
		const demo = await Bun.file("components/site/menubar-demo-chrome.tsx").text();
		// SharePopup lives in demo-dialogs.tsx.
		const dialogs = await Bun.file("components/site/demo-dialogs.tsx").text();
		// Share copy + destinations live in lib/share.ts.
		const share = await Bun.file("lib/share.ts").text();
		// The copy-link clipboard logic lives in lib/share-copy.ts.
		const shareCopy = await Bun.file("lib/share-copy.ts").text();

		// The badge trigger button stays in the demo card and opens the dialog.
		expect(demo).toContain('aria-label="Tell others about JP"');
		// The dialog markup lives in demo-dialogs.tsx.
		expect(dialogs).toContain('aria-label="Close share dialog"');
		expect(dialogs).toContain("Tell others about JP");
		// The clipboard write lives in the useCopyLink hook.
		expect(dialogs).toContain("useCopyLink");
		expect(shareCopy).toContain("navigator.clipboard.writeText(SHARE_URL)");
		expect(dialogs).toContain("Share the cute and useful token cat!");
		expect(dialogs).toContain("SHARE_DESTINATIONS");

		// Destination copy + URLs live in the shared module — including the X handle sourced from
		// SITE.twitter (never a hardcoded "@8bit" literal, which had drifted between the two surfaces).
		expect(share).toContain("X / Twitter");
		expect(share).toContain("SHARE_TEXT_X");
		expect(share).toContain("SITE.twitter");
		expect(share).not.toContain('"@8bit"');
		expect(share).toContain("https://twitter.com/intent/tweet");
		expect(share).toContain("https://www.facebook.com/sharer/sharer.php");
		expect(share).toContain("https://www.linkedin.com/shareArticle");
		expect(share).toContain("https://www.reddit.com/submit");
	});

	it("shows the interactive demo before the four-jobs explainer on the homepage", async () => {
		const home = await Bun.file("components/sticker/home.tsx").text();
		const demoAt = home.indexOf('id="demo"');
		const howAt = home.indexOf('id="how"');
		expect(demoAt).toBeGreaterThan(-1);
		expect(howAt).toBeGreaterThan(-1);
		expect(demoAt).toBeLessThan(howAt);
	});

	it("keeps the theme showcase count copy canonical", async () => {
		// The theme showcase now lives in the Sticker Bomb homepage.
		const showcase = await Bun.file("components/sticker/home.tsx").text();
		expect(showcase).toContain("24 themes. 1 cat.");
		expect(showcase).toContain("twenty-one terminal-inspired dark packs");
		expect(showcase).not.toContain("one cat.");
	});

	// [Regression guard] Both the dashboard AND settings faces' footers gained an Advanced Analytics
	// icon and an update-notification dot natively across several commits, but the web demo's matching
	// CardFooter calls silently fell behind (SettingsFace never got onOpenAdvancedAnalytics at all;
	// DashboardFace never got the UpdateDotButton accessory) until an explicit parity audit caught it.
	// Pin the fix so both faces stay in lockstep going forward.
	it("keeps both demo faces' footers in parity with the native app (Advanced Analytics + update dot)", async () => {
		// The two faces live in separate modules (DashboardFace in menubar-demo.tsx, SettingsFace in
		// menubar-demo-settings.tsx) and share ONE CardFooter from menubar-demo-chrome.tsx — read each
		// face's own call site so a face that drops an icon still fails here.
		const demo = await Bun.file("components/site/menubar-demo.tsx").text();
		const settings = await Bun.file("components/site/menubar-demo-settings.tsx").text();

		// DashboardFace's CardFooter call — slice a fixed window rather than searching for the closing
		// "/>" (the nested `<UpdateDotButton />` has its own, which would truncate the slice early).
		const dashboardFooterStart = demo.indexOf('leadingText="Updated just now"');
		const dashboardFooter = demo.slice(dashboardFooterStart, dashboardFooterStart + 200);
		expect(dashboardFooter).toContain("onOpenAdvancedAnalytics={onOpenAdvancedAnalytics}");
		expect(dashboardFooter).toContain("accessory={<UpdateDotButton />}");

		// SettingsFace's CardFooter call.
		const settingsFooterStart = settings.indexOf('leadingText="Settings"');
		const settingsFooter = settings.slice(settingsFooterStart, settingsFooterStart + 200);
		expect(settingsFooter).toContain("onOpenAdvancedAnalytics={onOpenAdvancedAnalytics}");
		expect(settingsFooter).toContain("accessory={<UpdateDotButton />}");

		// SettingsFace must actually receive (not just forward a stray reference to) the prop, and the
		// card must still hand it down.
		expect(settings).toContain("onOpenAdvancedAnalytics: () => void;");
		expect(demo).toContain("onOpenAdvancedAnalytics={() => setAdvancedAnalyticsOpen(true)}");
	});

	it("mirrors the expanded native Advanced Analytics window instead of the retired export tray", async () => {
		const demo = await Bun.file("components/site/advanced-analytics-demo.tsx").text();

		expect(demo).toContain("w-[min(96vw,960px)]");
		expect(demo).toContain("grid-cols-[minmax(0,1fr)_252px]");
		expect(demo).toContain("max-h-[calc(100dvh-96px)]");
		expect(demo).toContain("bg-card px-3.5");
		expect(demo).not.toContain("h-[min(90vh,1000px)]");
		expect(demo).not.toContain("pl-16");
		expect(demo).toContain("Daily trend · last {days} days");
		expect(demo).toContain("Token mix · last {days} days");
		expect(demo).toContain('values={["Calendar", "Rhythm", "Model × Day"] as const}');
		expect(demo).toContain('values={["Events", "Tokens", "$"] as const}');
		expect(demo).toContain("ProviderSidebar");
		expect(demo).toContain("MODEL_ROWS");
		expect(demo).toContain(
			"MEASURE_OFFSET: Record<Measure, number> = { Events: 3, Tokens: 6, $: 9 }",
		);
		expect(demo).toContain('action.value === "Tokens"');
		expect(demo).toContain("peakCallout");
		expect(demo).toContain("px-[22px] py-4");
		expect(demo).toContain("dialog.showModal()");
		expect(demo).toContain("onClose={onClose}");
		expect(demo).toContain("<option value={7}>last 7 days</option>");
		expect(demo).toContain("value={days}");
		expect(demo).toContain("TABLE_HEADERS.map");
		expect(demo).toContain('dispatch({ type: "sort", key })');
		expect(demo).toContain(
			'title="CSV, JSON, and Markdown export are available in the JP the Cat app"',
		);
		expect(demo).not.toContain("\n\t\t\topen\n");
		expect(demo).toContain("Codex, Grok & Muse Spark $ = notional list price");
		expect(demo).toContain("Cursor shows tokens (estimate, excluded");
		expect(demo).toContain("from $ totals).");
		expect(demo).not.toContain("Choose which providers to include, then export a CSV");
	});

	it("keeps compact homepage demo controls at WCAG 2.2 target-size minimums", async () => {
		// Scans EVERY demo module: the controls are spread across the dashboard face, the settings
		// face, and the shared chrome, and an undersized control must fail wherever it is declared.
		const modules = await readDemoModules();
		const all = modules.join("\n");

		expect(all).toContain("inline-flex min-h-6"); // TimeframePicker
		expect(all).toContain("grid h-6 w-6 shrink-0"); // CardFooter icons + UpdateDotButton
		expect(all).toContain("relative h-6 w-10 shrink-0"); // Switch
		expect(all).toContain("grid h-[26px] w-[26px] shrink-0"); // JPFaceActionRow's JP button
		for (const source of modules) {
			expect(source).not.toContain("grid h-[18px] w-[18px] shrink-0");
			expect(source).not.toContain("relative h-[18px] w-[30px]");
			expect(source).not.toContain(
				"grid h-[22px] w-[22px] shrink-0 place-items-center overflow-hidden",
			);
		}
	});

	it("keeps the homepage demo chrome on the native 32pt row", async () => {
		const modules = await readDemoModules();
		const all = modules.join("\n");

		// Exactly two 32pt chrome rows across the whole card: the shared `ChromeBar` the dashboard
		// face renders, plus the settings face's own inline bar (it carries a different control set).
		expect(all.match(/flex h-8 items-center gap-2 bg-card pr-3\.5 pl-4/g)).toHaveLength(2);
		expect(all).toContain("ml-auto flex items-center gap-1");
		// The update dot sits in the shared footer, left of the JP mark, sized like Refresh/Quit/Help.
		expect(all).toContain("grid h-6 w-6 shrink-0 place-items-center rounded-full");
		for (const source of modules) {
			expect(source).not.toContain("h-[38px]");
			expect(source).not.toContain("pl-[18px]");
			expect(source).not.toContain("ml-0.5 grid h-[17px] w-[17px]");
		}
	});

	it("keeps homepage demo sparklines on the native per-provider scale", async () => {
		const demo = await Bun.file("components/site/menubar-demo.tsx").text();
		const series = await Bun.file("components/site/menubar-demo-series.ts").text();

		expect(series).toContain("SPARKLINE_HEADROOM_FRACTION = 0.15");
		expect(series).toContain("function sparklineFractions");
		expect(series).toContain("Math.max(hi - lo, hi * SPARKLINE_HEADROOM_FRACTION, 0.000001)");
		expect(series).toContain("return values.map((v) => (v - lo) / denom)");
		expect(demo).toContain("function RowSparkline");
		expect(demo).toContain("series={sparklineFractions(windowSeries(AGG.series, days))}");
		expect(demo).toContain("{...selectorPresentation(PROVIDERS[k], days)}");
		// The retired absolute-scale meter must not reappear in ANY demo module, not just the
		// dashboard face that owns the sparklines today.
		for (const source of await readDemoModules()) {
			expect(source).not.toContain("function PulseMeter");
			expect(source).not.toContain("PULSE_POINTS");
			expect(source).not.toContain("demo-pulse-ride");
			expect(source).not.toContain("scaleMax");
			expect(source).not.toContain("v / scaleMax");
		}
	});

	it("keeps Privacy & data out of settings source-of-truth docs", async () => {
		// Every demo module, not just menubar-demo.tsx — the settings face lives in a sibling file, and
		// a "Privacy & data" row added there must still fail this guard.
		const modules = await readDemoModules();
		const todos = await Bun.file("../_docs/todos.md").text();
		const settingsCopyTests = await Bun.file(
			"../mac/Tests/JPtheCatAppTests/SettingsCopyTests.swift",
		).text();

		expect(settingsCopyTests).toContain("testSettingsFaceHasNoPrivacyRow");
		for (const source of modules) {
			expect(source).not.toContain("Privacy & data");
		}
		expect(todos).not.toContain("Privacy & data");
		expect(todos).not.toContain("Privacy link");
		expect(todos).not.toContain("Homepage demo mirrors all three");
	});

	it("keeps Claude live limits on the standardized homepage toggle row", async () => {
		const demo = await Bun.file("components/site/menubar-demo-settings.tsx").text();
		// The "Live data" section is its own component (LiveDataSection) — search its function body,
		// not an inline <Section title="Live data"> block in SettingsFace.
		const liveDataStart = demo.indexOf("function LiveDataSection");
		expect(liveDataStart).toBeGreaterThan(-1);
		const liveDataEnd = demo.indexOf("\nfunction ", liveDataStart + 1);
		const liveDataSource = demo.slice(liveDataStart, liveDataEnd);

		expect(liveDataSource).toContain("<ToggleRow");
		expect(liveDataSource).toContain(
			'title={grokLimits ? "Grok live limits · on" : "Enable Grok live limits"}',
		);
		expect(liveDataSource).toContain("on={grokLimits}");
		expect(liveDataSource).toContain(
			'title={claudeLimits ? "Claude live limits · on" : "Enable Claude live limits"}',
		);
		expect(liveDataSource).toContain("on={claudeLimits}");
		expect(liveDataSource).toContain(
			'title={cursorHook ? "Cursor CLI live data · on" : "Enable Cursor CLI live data"}',
		);
		expect(liveDataSource).toContain("on={cursorHook}");
		expect(liveDataSource).not.toContain("<SettingsRow");
		expect(liveDataSource).not.toContain('name="chevron"');
	});

	it("freezes homepage looping motion for reduced-motion users", async () => {
		const css = await Bun.file("app/globals.css").text();

		expect(css).toContain("@media (prefers-reduced-motion: reduce)");
		expect(css).toContain("animation: none !important");
		expect(css).not.toContain("animation-duration: 0.01ms !important");
		expect(css).not.toContain("animation-iteration-count: 1 !important");
	});

	it("keeps reduced-motion mascot users on the poster without loading video sources", async () => {
		const mascot = await Bun.file("components/site/mascot-video.tsx").text();
		const wrapper = await Bun.file("components/site/cat-animation.tsx").text();

		expect(mascot).toContain('window.matchMedia("(prefers-reduced-motion: reduce)")');
		expect(mascot).toContain('shouldReduceMotion.addEventListener("change", syncMotionPreference)');
		expect(mascot).toContain("const stopAndUnload = () =>");
		expect(mascot).toContain('video.removeAttribute("src")');
		expect(mascot).toContain('preload="none"');
		expect(mascot).toContain("video.src = selectedSource()");
		expect(mascot).not.toContain("<source src=");
		expect(wrapper).toContain("motion-reduce:block");
	});

	it("keeps legal WebGL scenes off for reduced-motion visitors", async () => {
		const stage = await Bun.file("components/legal/scene-stage.tsx").text();
		const engine = await Bun.file("components/legal/engine.ts").text();

		expect(stage).toContain('window.matchMedia("(prefers-reduced-motion: reduce)").matches');
		expect(stage).toContain("return; // CSS already reveals the poster; never start a loop");
		expect(stage).toContain("motion-reduce:opacity-100");
		expect(stage).toContain("IntersectionObserver");
		// The loop is renderer-driven (`setAnimationLoop`), so the pause path must CLEAR it —
		// pinning both halves keeps a hidden tab or an off-screen scene from rendering forever.
		expect(engine).toContain("renderer.setAnimationLoop(tick)");
		expect(engine).toContain("document.hidden");
		expect(engine).toContain("renderer.setAnimationLoop(null)");
		expect(engine).not.toContain("requestAnimationFrame(tick)");
	});

	// [Regression guard] `boot()` is async, so the IntersectionObserver can fire "off-screen" while
	// `engine` is still null — at which point `engine?.stop()` is a silent no-op and the freshly
	// created engine starts a rAF loop that renders a 2048x2048 shadow map every frame, forever, for a
	// scene the visitor already scrolled past. The fix records visibility in a plain `visible` flag and
	// gates `created.start()` on it. This CANNOT be caught behaviourally here: the Bun suite renders
	// with `renderToStaticMarkup`, which never runs `useEffect`, so a source pin is the only guard.
	// Pin the whole gate expression, not just the identifier — deleting the condition while leaving
	// `visible` declared must fail.
	it("keeps the legal WebGL engine from starting a rAF loop for an off-screen scene", async () => {
		const stage = await Bun.file("components/legal/scene-stage.tsx").text();

		// The flag itself, recorded on EVERY observer entry (not only intersecting ones).
		expect(stage).toContain("let visible = false;");
		expect(stage).toContain("visible = entry.isIntersecting;");
		// The gate. If this assertion fails, do NOT relax it — re-read the comment above `let visible`
		// in scene-stage.tsx; an ungated `created.start()` reintroduces the runaway shadow-map loop.
		expect(stage).toContain("if (visible && !disposed) {\n\t\t\t\tcreated.start();");
		// ...and that gated call is the ONLY place boot starts the loop, so an ungated second start
		// cannot be slipped in beside it.
		expect(stage.match(/created\.start\(\)/g)).toHaveLength(1);
	});

	// [Regression guard] `advanced-analytics-demo` is ~1k lines and is unreachable until a visitor
	// clicks the demo card's chart button, so a STATIC import parks the whole tray in the homepage
	// first-load JS for every visitor. It is loaded through `next/dynamic` with `ssr: false` instead.
	// Reverting to a static import is invisible to every other gate — the rendered markup is identical
	// and `renderToStaticMarkup` never runs the effect that mounts it — so this source pin is the only
	// thing standing between an edit and a silent homepage payload regression.
	it("keeps the advanced-analytics tray out of the homepage first-load bundle", async () => {
		const dialogs = await Bun.file("components/site/demo-dialogs.tsx").text();

		expect(dialogs).toContain('import dynamic from "next/dynamic"');
		expect(dialogs).toContain(
			'dynamic(\n\t() => import("./advanced-analytics-demo").then((m) => m.AdvancedAnalyticsDemo),\n\t{ ssr: false },\n)',
		);
		// A static `import { ... } from "./advanced-analytics-demo"` (any form) defeats the whole point.
		expect(dialogs).not.toMatch(/^import[^\n]*from\s+"\.\/advanced-analytics-demo"/m);
	});

	it("keeps the interactive homepage demo controls geometrically stable", async () => {
		const demo = await Bun.file("components/site/menubar-demo.tsx").text();
		const root = demo.slice(
			demo.indexOf("export function MenubarDemo"),
			demo.indexOf("// ── Dashboard face"),
		);

		expect(root).toContain("data-menubar-demo");
		expect(root).toContain("animate-float-shadow");
		expect(root).not.toMatch(/max-w-\[384px\][^"]*animate-float(?!-shadow)/);
	});

	it("starts the homepage demo at the native card chrome without a duplicate title strip", async () => {
		const demo = await Bun.file("components/site/menubar-demo.tsx").text();
		const root = demo.slice(
			demo.indexOf("export function MenubarDemo"),
			demo.indexOf("// ── Dashboard face"),
		);

		expect(root).toContain("data-demo-card");
		expect(root).not.toContain("<BrandMark");
		expect(root).not.toContain(">Settings<");
		expect(root).not.toContain('className="tnum');
	});

	it("keeps the public download CTA routed to the stable download endpoint", () => {
		expect(SITE.downloadCtaLabel).toBe("Download Meow");
		expect(SITE.downloadCtaHref).toBe("/download");
	});

	it("keeps every download-modal analytics event wired", async () => {
		const downloadCta = await Bun.file("components/site/download-cta.tsx").text();
		expect(downloadCta).toContain('"download_cta_clicked"');
		expect(downloadCta).toContain('"download_modal_opened"');
		expect(downloadCta).not.toContain("/api/newsletter");
		expect(downloadCta).toContain("trackProductEvent(clickEvent");
		expect(downloadCta).toContain("trackProductEvent(modalOpenEvent");
		// The download itself starts on the trigger click (not gated behind the modal submit).
		expect(downloadCta).toContain("startDownload();");
	});

	it("gives pSEO /library downloads a distinct analytics capture channel", () => {
		const libraryHtml = renderToStaticMarkup(CtaBlock({ heading: "Get JP" }));
		expect(libraryHtml).toContain('data-analytics-source="library"');
		expect(libraryHtml).toContain('data-analytics-channel="library"');
		expect(libraryHtml).toContain('data-analytics-event="library_download_cta_clicked"');
		// The homepage download CTAs stay on the home channel.
		const homeHtml = renderToStaticMarkup(StickerHome());
		expect(homeHtml).toContain('data-analytics-channel="home"');
		expect(homeHtml).toContain('data-analytics-event="download_cta_clicked"');
	});

	it("keeps app and component download links routed through the analytics CTA wrapper", async () => {
		const files = (await Promise.all(["app", "components"].map(collectTsxFiles))).flat();
		// Any /download link — bare OR with a ?source=… query — must go through DownloadCta so every
		// download surface shows the same download-started note sitewide.
		const directDownloadLinkPattern =
			/href=(?:\{SITE\.downloadCtaHref\}|["']\/download(?:\?[^"']*)?["'])/;

		for (const file of files) {
			if (file === "components/site/download-cta.tsx") {
				continue;
			}
			const source = await Bun.file(file).text();
			if (!directDownloadLinkPattern.test(source)) {
				continue;
			}

			expect(source, `${file} must use DownloadCta for public download links`).toContain(
				"<DownloadCta",
			);
		}
	});

	it("keeps the Homebrew cask display name human-readable in both published copies", async () => {
		for (const path of ["../Casks/jpthecat.rb", "public/stable/jpthecat.rb"]) {
			const cask = await Bun.file(path).text();
			expect(cask).toContain('name "JP the Cat"');
			expect(cask).not.toContain('name "JPtheCat"');
		}
	});

	// Both published copies must keep the versioned DMG template and the Sparkle livecheck — a cask
	// pinned to a literal version stops auto-updating silently, and a broken appcast URL makes
	// `brew upgrade` a no-op. Covers the web mirror too, which the retired Swift guard never read.
	it("keeps the release URL template and Sparkle livecheck in both published cask copies", async () => {
		for (const path of ["../Casks/jpthecat.rb", "public/stable/jpthecat.rb"]) {
			const cask = await Bun.file(path).text();
			expect(cask).toContain(
				'url "https://api.jpthecat.com/storage/v1/object/public/releases/JPtheCat-#{version}.dmg"',
			);
			expect(cask).toContain('url "https://jpthecat.com/stable/appcast.xml"');
			expect(cask).toContain("strategy :sparkle, &:short_version");
		}
	});

	it("allows the branded release host in the CSP connect policy", async () => {
		const proxy = await Bun.file("proxy.ts").text();

		expect(proxy).toContain("connect-src 'self' https://api.jpthecat.com");
	});

	it("installs Vercel Analytics and Speed Insights globally", async () => {
		const layout = await Bun.file("app/layout.tsx").text();
		const legal = await Bun.file("lib/legal/combined-legal.ts").text();
		const normalizedPrivacy = legal.replace(/\s+/g, " ");
		const llms = await Bun.file("public/llms.txt").text();

		expect(layout).toContain('from "@vercel/analytics/next"');
		expect(layout).toContain('from "@vercel/speed-insights/next"');
		expect(layout).toContain("<Analytics />");
		expect(layout).toContain("<SpeedInsights />");
		expect(normalizedPrivacy).toContain("Vercel Web Analytics and Speed Insights");
		expect(normalizedPrivacy).toContain("CTA click events");
		expect(normalizedPrivacy).toContain(
			"Successful non-bot downloads may send an owner notification",
		);
		expect(normalizedPrivacy).toContain("coarse Vercel edge location context");
		expect(normalizedPrivacy).toContain("postal code");
		expect(normalizedPrivacy).toContain("never latitude/longitude");
		expect(normalizedPrivacy).toContain("network/ASN and hosting/anonymizer signals");
		expect(normalizedPrivacy).toContain("ipapi.is");
		expect(normalizedPrivacy).toContain("Resend or email provider");
		// JP is free: the policy no longer describes license, trial, or Stripe data flows.
		expect(normalizedPrivacy).toContain("makes no license, trial, or purchase calls");
		expect(normalizedPrivacy).not.toMatch(/Stripe|Checkout Session/);
		expect(normalizedPrivacy).toContain(
			"does not include prompts, code, transcripts, token history",
		);
		expect(llms).toContain("Vercel Web Analytics and Speed Insights");
		expect(llms).toContain("CTA click");
		expect(llms).toContain("no postal code");
		expect(llms).toContain("never lat/long");
		expect(llms).toContain("ipapi.is ASN/network");
		expect(llms).toContain("Owner/admin notices may be sent");
		expect(llms).toContain("Pricing posture: free.");
		expect(llms).not.toMatch(/\$12\.99|Stripe|Checkout Session|refund window/);
		expect(llms).toContain("prompts, code, transcripts, and token history stay on your Mac");
	});

	it("keeps newsletter signup and Resend broadcasts out of the site", async () => {
		const legal = (await Bun.file("lib/legal/combined-legal.ts").text()).replace(/\s+/g, " ");
		const llms = await Bun.file("public/llms.txt").text();
		expect(legal).not.toMatch(/broadcast|Resend segment|newsletter (email|signup|prompt)/i);
		expect(llms).not.toMatch(/newsletter|broadcast|Resend segment/i);
	});

	it("footer credits visible string matches the shipped copy contract", async () => {
		const { FOOTER_CREDITS_VISIBLE } = await import("@/components/site/footer");
		expect(FOOTER_CREDITS_VISIBLE).toBe("Built with: YEN · Bitcoin Email · Terms");
	});

	it("keeps the founder social link and YEN credit opening outside the current page", async () => {
		const footer = await Bun.file("components/site/footer.tsx").text();

		expect(footer).toContain("sb-shell");
		expect(footer).not.toContain("max-w-[1320px]");
		expect(footer).toContain("h-auto w-full");
		expect(footer).not.toContain("aspect-[5/3]");
		expect(footer).toContain('target="_blank"');
		expect(footer).toContain('rel="noopener noreferrer"');
		expect(footer).toContain("Hi, I'm JP.");
		expect(footer).toContain("Ping");
		expect(footer).toContain("for support");
		expect(footer).toContain("SITE.supportSocialUrl");
		expect(footer).toContain("Bitcoin Email");
		expect(footer).toContain("SITE.btcEmailUrl");
		expect(footer).toContain(
			"{SITE.tagline} A free menu bar meter for Claude Code, Codex, Grok, Muse Spark, Cursor",
		);
		expect(footer.replace(/\s+/g, " ")).toContain(
			"and OpenCode Go — cost, official limits, local tokens, measured gateway usage, and light",
		);
		expect(footer).not.toContain("providers added constantly");
		expect(footer).toContain("new Date().getFullYear()");
		expect(footer).toContain("{SITE.seoName}. Not affiliated with AI providers.");
		expect(footer).not.toContain("Not affiliated with any listed AI provider.");
		expect(footer).not.toContain("Made with care and one very opinionated cat.");
		expect(footer).toContain('aria-label="Footer links"');
		expect(footer).toContain('className="sb-footer-credits"');
		expect(footer).toContain('Built with:{" "}');
		expect(footer).toContain('{" · "}');
		expect(footer).not.toContain('aria-label="Footer links" className="flex');
		expect(footer.replace(/\s+/g, " ")).toContain("Bitcoin Email");
		expect(footer).not.toMatch(/<\/nav>[\s\S]*<p>\s*Built with/);
		expect(footer).not.toContain("Contact");
		expect(footer).not.toContain("href={SITE.contactHref}");
		expect(footer).not.toContain("SITE.email");
		expect(footer).toContain("href={SITE.yenUrl}");
		expect(footer).toContain('href="/terms"');
		expect(footer).toContain("FOOTER_CREDITS_VISIBLE");
		expect(footer).not.toContain('/privacy"');
		// Release notes were removed; the footer never links to them.
		expect(footer).not.toContain('href: "/release"');
		expect(footer).not.toContain('{ label: "Provider catalog", href: "/#faq" }');
		expect(footer).not.toContain("Product</h3>");
		expect(footer).not.toContain('{ label: "Claude Code", href: "/#how" }');
		expect(footer).not.toContain('{ label: "Codex", href: "/#how" }');
	});

	it("keeps the provider marquee slow enough to read", async () => {
		const css = await Bun.file("app/globals.css").text();

		expect(css).toContain("--marquee-duration: 180s");
		expect(css).toContain("animation: marquee var(--marquee-duration) linear infinite");
		expect(css).toContain("@media (max-width: 640px)");
		expect(css).toContain("--marquee-duration: 88s");
		expect(css).not.toContain("animation-duration: 0.001ms !important");
	});

	it("keeps the mascot animation autoplay retry and packaged meow hover hooks wired", async () => {
		const mascotVideo = await Bun.file("components/site/mascot-video.tsx").text();
		const purr = await Bun.file("components/site/purr-on-hover.tsx").text();

		expect(mascotVideo).toContain("video.play()");
		expect(mascotVideo).toContain("data-mascot-video");
		expect(purr).toContain('const MEOW_AUDIO_SRC = "/meow.m4a"');
		expect(purr).toContain("new Audio(MEOW_AUDIO_SRC)");
		expect(purr).toContain('trigger.addEventListener("pointerenter", play)');
		expect(purr).toContain('trigger.addEventListener("mouseenter", play)');
		expect(purr).toContain('trigger.addEventListener("pointerdown", play)');
		expect(purr).toContain('const force = event?.type === "pointerdown"');
		expect(await Bun.file("public/meow.m4a").exists()).toBe(true);
		expect(await Bun.file("public/meow-1.mp3").exists()).toBe(true);
		expect(await Bun.file("public/meow-2.mp3").exists()).toBe(true);
	});

	it("routes WebKit to the HEVC-with-alpha MP4 so Safari never shows a yellow square", async () => {
		// Modern Safari plays the VP9/WebM source but ignores its alpha, painting the
		// mascot's transparent corners as an opaque honey square. It must be steered to
		// the hvc1 MP4 (the only format WebKit alphas). See docs/02-design-system.md.
		const mascotVideo = await Bun.file("components/site/mascot-video.tsx").text();

		expect(mascotVideo).toContain("GestureEvent");
		expect(mascotVideo).toContain('codecs="hvc1"');
		expect(mascotVideo).toContain("? mp4 : webm");
		expect(mascotVideo).toContain("video.src = selectedSource()");
		// No autoPlay attribute — the effect drives playback after selecting one
		// engine-specific source, so Safari never paints a WebM (yellow) frame.
		expect(mascotVideo).not.toContain("autoPlay");
		// Both transparent sources must ship for the per-engine selection to work.
		expect(await Bun.file("public/jp-paw-lick-purr.webm").exists()).toBe(true);
		expect(await Bun.file("public/jp-paw-lick-purr.mp4").exists()).toBe(true);
	});

	it("keeps scroll-reveal content visible before browser observers run", async () => {
		const css = await Bun.file("app/globals.css").text();
		const revealBlock = css.match(/\.reveal \{[^}]+\}/)?.[0] ?? "";

		expect(revealBlock).toContain("opacity: 1");
		expect(revealBlock).toContain("transform: none");
		expect(revealBlock).not.toContain("opacity: 0");
	});

	it("scopes Muse Spark to OpenCode on this Mac across public marketing copy", async () => {
		// How-it-works copy now lives in the Sticker Bomb homepage.
		const howItWorks = await Bun.file("components/sticker/home.tsx").text();
		for (const source of [howItWorks]) {
			expect(source.toLowerCase()).toContain("opencode");
			expect(source.toLowerCase()).toContain("meta account");
		}
		expect(await Bun.file("components/site/menubar-demo-series.ts").text()).toContain(
			"Meta account totals",
		);
		expect(howItWorks).not.toMatch(/Muse Spark already keep on your Mac — no account, no API key/);
	});

	it("keeps llms.txt aligned with current launch coverage", async () => {
		const llms = await Bun.file("public/llms.txt").text();

		expect(llms).toContain(
			"Claude Code, Codex, Grok, Muse Spark, OpenCode Zen, and OpenCode Go are live",
		);
		expect(llms.toLowerCase()).toContain("opencode");
		expect(llms.toLowerCase()).toContain("meta account dashboard");
		expect(llms).toContain(`${PROVIDER_COUNTS.total}-provider catalog`);
		expect(llms).toContain("any other listed AI provider");
		expect(llms).not.toContain("across Claude Code, Codex, Gemini");
		expect(llms).not.toContain("Claude Pro/Max and Codex");
		expect(llms).not.toContain("Keeps usage history past the 30-day log cleanup");
		expect(llms).not.toContain("Anthropic, OpenAI, or Google");
	});

	it("keeps SEO metadata aligned with the current provider catalog", async () => {
		const layout = await Bun.file("app/layout.tsx").text();

		expect(SITE.description).toContain("Cursor tokens");
		expect(layout).not.toContain("\tkeywords:");
	});

	it("keeps marquee icons self-hosted and gives every provider a visible mark", () => {
		const providersWithRemoteIcons = PROVIDERS.filter((provider) =>
			provider.icon?.startsWith("http"),
		);
		const providersWithoutVisibleMark = PROVIDERS.filter(
			(provider) => !provider.icon && !provider.glyph,
		);

		expect(providersWithRemoteIcons).toEqual([]);
		expect(providersWithoutVisibleMark).toEqual([]);
		expect(PROVIDERS.filter((provider) => provider.icon).length).toBeGreaterThanOrEqual(61);
		expect(
			PROVIDERS.filter((provider) => provider.sources.includes("codexbar") && !provider.icon).map(
				(provider) => provider.name,
			),
		).toEqual([]);
		expect(
			PROVIDERS.filter((provider) =>
				["Hermes Agent", "pi-agent", "Goose", "OpenClaw", "Qwen", "Qoder", "CodeBuddy"].includes(
					provider.name,
				),
			).map((provider) => provider.icon),
		).not.toContain(undefined);
		expect(PROVIDERS.filter((provider) => !provider.icon).map((provider) => provider.name)).toEqual(
			["Aider"],
		);
	});

	it("keeps declared provider icon files present", async () => {
		for (const provider of PROVIDERS) {
			if (!provider.icon) {
				continue;
			}

			const icon = Bun.file(`public${provider.icon}`);
			expect(await icon.exists()).toBe(true);
		}
	});
});
