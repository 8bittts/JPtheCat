import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { ComparisonTable } from "@/components/library/comparison-table";
import { LeafBody } from "@/components/library/leaf-body";
import { PricingTable } from "@/components/library/pricing-table";
import { VendorModelsTable } from "@/components/library/vendor-models-table";
import { alternativeAnchor, alternativesLeaf } from "@/lib/library/content/alternatives";
import { compareBySlug, compareLeaf, compareTable } from "@/lib/library/content/compare";
import { guideBySlug, guideLeaf } from "@/lib/library/content/guides";
import { planBySlug, planLeaf } from "@/lib/library/content/plans";
import { pricingFaq, pricingLeaf, pricingTitle } from "@/lib/library/content/pricing";
import { providerLeaf } from "@/lib/library/content/provider";
import { vendorLeaf } from "@/lib/library/content/vendor";
import type { ModelId } from "@/lib/library/pricing-data";
import { PROVIDERS } from "@/lib/site";

// Renders the actual leaf output (the async routes can't be unit-rendered, but these are the sync
// pieces they compose) to prove the honesty markers reach the DOM.
describe("library rendering", () => {
	it("renders Sonnet 5.5 cache rates and GPT-6.1 Sol notional context pricing", () => {
		const sonnet = renderToStaticMarkup(
			<LeafBody content={pricingLeaf("claude-sonnet-5-5")}>
				<PricingTable id="claude-sonnet-5-5" />
			</LeafBody>,
		);
		for (const text of ["Claude Sonnet 5.5", "$2.00", "$10.00", "$2.50", "$4.00", "$0.10"])
			expect(sonnet).toContain(text);
		expect(sonnet).toContain(
			"Cache reads cost $0.10 per million tokens — about 5% of input. Cache writes cost $2.50",
		);
		const sol = renderToStaticMarkup(
			<LeafBody content={pricingLeaf("gpt-6.1-sol")}>
				<PricingTable id="gpt-6.1-sol" />
			</LeafBody>,
		);
		for (const text of ["GPT-6.1 Sol", "Notional list price", "$0.10", "$4.00", "$15.00", "272"])
			expect(sol).toContain(text);
	});
	it("renders both Haiku 5.5 prompt-length tiers and exact cache rates", () => {
		const html = renderToStaticMarkup(
			<LeafBody content={pricingLeaf("claude-haiku-5-5")}>
				<PricingTable id="claude-haiku-5-5" />
			</LeafBody>,
		);
		for (const text of [
			"Claude Haiku 5.5",
			"$0.10",
			"$0.50",
			"$0.125",
			"$0.20",
			"$0.01",
			"$0.625",
			"$1.00",
			"$0.05",
			"$2.50",
			"100",
		])
			expect(html).toContain(text);
		expect(pricingLeaf("claude-haiku-5-5").lede).toContain("including cache reads and writes");
		expect(pricingLeaf("claude-haiku-5-5").lede).toContain(">100K");
		expect(
			pricingFaq("claude-haiku-5-5").some(
				(item) => item.answer.includes("&gt;100K") || item.answer.includes(">100K"),
			),
		).toBe(true);
	});
	it("renders Zen Sonnet's distinct cache rate in its family table without a thin route", () => {
		const html = renderToStaticMarkup(
			<LeafBody content={vendorLeaf("opencode")}>
				<VendorModelsTable vendor="opencode" />
			</LeafBody>,
		);
		const row = html.split("</tr>").find((part) => part.includes("Claude Sonnet 5.5 · Zen"));
		expect(row).toBeDefined();
		expect(row).toContain("$0.20");
		expect(row).not.toContain("/library/pricing/claude-sonnet-5-5-zen");
		expect(html).toContain("list price, not spend");
		expect(
			pricingFaq("claude-sonnet-5-5-zen").some((item) =>
				item.question.startsWith("Does US-only inference"),
			),
		).toBe(false);
	});
	it("renders the Opus 5.5 fast-mode page at its own rate and names when it applies", () => {
		const fast = renderToStaticMarkup(
			<LeafBody content={pricingLeaf("claude-opus-5-5-fast-mode")}>
				<PricingTable id="claude-opus-5-5-fast-mode" />
			</LeafBody>,
		);
		for (const text of [
			"Claude Opus 5.5 · Fast mode",
			"$8.00",
			"$40.00",
			"$10.00",
			"$16.00",
			"$0.40",
		])
			expect(fast).toContain(text);
		expect(pricingLeaf("claude-opus-5-5-fast-mode").lede).toContain(
			"applies it only to turns Claude Code logs as fast",
		);
		expect(fast).toContain("Standard-speed turns bill at the Claude Opus 5.5 rate.");
		expect(pricingTitle("claude-opus-5-5-fast-mode")).toBe(
			"Claude Opus 5.5 · Fast mode pricing — cost per token",
		);
		expect(pricingTitle("claude-opus-5-5")).toBe(
			"Claude Opus 5.5 pricing — cost per million tokens",
		);
	});
	it("states the US-only inference premium only on Claude 4.6 and later pages", () => {
		const question = (id: ModelId) =>
			pricingFaq(id).find((item) => item.question.startsWith("Does US-only inference"));
		expect(question("claude-sonnet-5-5")?.answer).toContain("at 1.1x these rates");
		expect(question("claude-opus-5-5-fast-mode")?.answer).toContain("at 1.1x these rates");
		expect(question("claude-opus-4-6")).toBeDefined();
		for (const id of [
			"claude-opus-4-5",
			"claude-sonnet-4-5",
			"claude-haiku-4-5",
			"gpt-6.1-sol",
		] as const)
			expect(question(id)).toBeUndefined();
	});
	it("preserves published fractional-cent rates in the real pricing table", () => {
		const luna = renderToStaticMarkup(<PricingTable id="gpt-6-luna" />);
		const mimo = renderToStaticMarkup(<PricingTable id="mimo-v2.6-pro" />);
		expect(luna).toContain("$0.125");
		expect(mimo).toContain("$0.003625");
	});
	it("renders a subscription-notional pricing leaf with the notional marker", () => {
		const html = renderToStaticMarkup(
			<LeafBody content={pricingLeaf("gpt-5.3-codex")}>
				<PricingTable id="gpt-5.3-codex" />
			</LeafBody>,
		);
		expect(html).toContain("Notional list price");
		expect(html).toContain("$");
	});

	it("renders a Claude pricing leaf as real, non-notional cost", () => {
		const html = renderToStaticMarkup(
			<LeafBody content={pricingLeaf("claude-opus-4-8")}>
				<PricingTable id="claude-opus-4-8" />
			</LeafBody>,
		);
		expect(html).toContain("real per-token cost");
		expect(html.toLowerCase()).not.toContain("notional");
	});

	it("renders Mythos pricing with its limited-availability qualification", () => {
		const html = renderToStaticMarkup(
			<LeafBody content={pricingLeaf("claude-mythos-5")}>
				<PricingTable id="claude-mythos-5" />
			</LeafBody>,
		);
		expect(html).toContain("Claude Mythos 5");
		expect(html).toContain("$10.00");
		expect(html).toContain("$50.00");
		expect(html).toContain("Project Glasswing");
		expect(html.toLowerCase()).not.toContain("notional");
	});

	it("renders a roadmap provider leaf without over-claiming support", () => {
		const gemini = PROVIDERS.find((provider) => provider.id === "gemini");
		if (!gemini) {
			throw new Error("expected gemini in the catalog");
		}
		const html = renderToStaticMarkup(<LeafBody content={providerLeaf(gemini)} />);
		expect(html).toContain("does not report Gemini usage");
		expect(html).toContain("Roadmap status: local next");
		expect(html).not.toMatch(/tracks Gemini[^.]*\b(today|now|live)\b/i);
	});

	it("renders a comparison table with both tools", () => {
		const pair = compareBySlug("jp-the-cat-vs-ccusage");
		if (!pair) {
			throw new Error("expected compare pair");
		}
		const html = renderToStaticMarkup(<ComparisonTable {...compareTable(pair)} />);
		expect(html).toContain("JP the Cat");
		expect(html).toContain("ccusage");
	});

	it("uses query-aligned metadata for Search Console opportunity pages", () => {
		const guide = guideBySlug("see-codex-usage-limit");
		if (!guide) {
			throw new Error("expected Codex usage-limit guide");
		}
		const codexGuide = guideLeaf(guide);
		expect(codexGuide.title).toBe("How to check your Codex usage limit");
		expect(codexGuide.description).toContain("5-hour and weekly usage limits");

		const toolPair = compareBySlug("jp-the-cat-vs-tokens-4-breakfast");
		const modelPair = compareBySlug("gpt-5-3-codex-vs-claude-opus-4-8");
		if (!toolPair || !modelPair) {
			throw new Error("expected Search Console opportunity pairs");
		}
		expect(compareLeaf(toolPair).title).toBe("Tokens 4 Breakfast vs JP the Cat for Mac");
		expect(compareLeaf(toolPair).description).toContain("real Claude dollars");
		expect(compareLeaf(modelPair).title).toBe("GPT-5.3-Codex vs Claude Opus 4.8 — API pricing");

		const ccusage = alternativeAnchor("ccusage");
		if (!ccusage) {
			throw new Error("expected ccusage alternatives anchor");
		}
		expect(alternativesLeaf(ccusage).title).toBe("ccusage alternatives: CLI vs Mac menu bar");
		expect(alternativesLeaf(ccusage).description).toContain("CodexBar");

		const codexbar = alternativeAnchor("codexbar");
		if (!codexbar) {
			throw new Error("expected CodexBar alternatives anchor");
		}
		expect(alternativesLeaf(codexbar).title).toBe("CodexBar alternatives: quota % vs real dollars");
		expect(alternativesLeaf(codexbar).description).toContain("SessionWatcher");

		const plusLimits = guideBySlug("codex-plus-pro-rate-limits");
		if (!plusLimits) {
			throw new Error("expected Codex Plus/Pro rate-limit guide");
		}
		expect(guideLeaf(plusLimits).title).toBe("Codex Plus and Pro rate limits");
		expect(guideLeaf(plusLimits).description).toContain("ChatGPT Plus has a Codex rate limit");
		expect(guideLeaf(plusLimits).description.toLowerCase()).not.toContain("requests per");

		const plusPlan = planBySlug("chatgpt-plus-codex");
		const proPlan = planBySlug("chatgpt-pro-codex");
		if (!plusPlan || !proPlan) {
			throw new Error("expected ChatGPT Plus/Pro Codex plans");
		}
		expect(planLeaf(plusPlan).title).toBe("Does ChatGPT Plus have a Codex limit?");
		expect(planLeaf(proPlan).title).toBe("ChatGPT Pro Codex rate limits");
	});
});
