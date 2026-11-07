import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { ADMIN_EMAIL_ISSUES_LABEL } from "@/emails/admin-email-content";
import { EMAIL_FOOTER_DOMAIN_DISPLAY } from "@/emails/email-footer";
import { GrowthDigestEmail, GrowthDigestPlainText } from "@/emails/growth-digest";
import { buildGrowthDigest, type GrowthDigestSourceData } from "@/lib/analytics/growth-digest";

describe("growth digest", () => {
	it("builds an owner growth digest around human downloads, not raw hits", () => {
		const rollup = buildGrowthDigest(sourceFixture(), "weekly");

		expect(rollup.title).toBe("Weekly JP the Cat report");
		expect(rollup.subject).toBe("JP the Cat weekly report: 3 Mac downloads");
		expect(rollup.preview).toBe("Weekly report: 3 Mac downloads, +50% vs prior window.");
		expect(rollup.metricCards.map((metric) => metric.label)).toEqual([
			"Mac downloads",
			"Human downloads",
			"Unique human IPs",
			"Bot UA hits",
		]);
		expect(rollup.metricCards[0]?.value).toBe("3");
		expect(rollup.metricCards[0]?.detail).toBe("macOS browsers only · +50% vs prior 2");
		expect(rollup.metricCards[1]?.value).toBe("4");
		expect(rollup.metricCards[1]?.detail).toContain("all platforms · 13 raw hits");
		expect(new Set(rollup.metricCards.map((metric) => metric.group))).toEqual(
			new Set(["downloads"]),
		);
		expect(rollup.issues).toEqual([]);
		expect(rollup.opportunities.join(" ")).toContain("Bot pressure");
	});

	it("collects failed legs as issues and counts them in the subject", () => {
		const source = sourceFixture();
		const rollup = buildGrowthDigest(
			{
				...source,
				searchConsole: { ...source.searchConsole, message: "credentials expired", status: "error" },
				vercel: { ...source.vercel, status: "skipped" },
			},
			"weekly",
		);

		// A skipped leg is a choice, not a fault; only failures surface.
		expect(rollup.issues).toEqual(["Search Console failed: credentials expired."]);
		expect(rollup.subject).toBe("JP the Cat weekly report: 3 Mac downloads · 1 issue");

		const html = renderToStaticMarkup(<GrowthDigestEmail rollup={rollup} />);
		expect(html.indexOf(ADMIN_EMAIL_ISSUES_LABEL)).toBeGreaterThan(-1);
		expect(html.indexOf(ADMIN_EMAIL_ISSUES_LABEL)).toBeLessThan(html.indexOf("<h1"));
		// A leg that did not run shows its state in Health and drops its own section.
		expect(html).toContain("Search Console: </strong>failed (credentials expired)");
		expect(html).not.toContain("Search (Search Console)");
		expect(html).not.toContain("Traffic (Vercel Web Analytics)");
	});

	it("leads with open-source triage after Health and counts it in the subject", () => {
		const source = sourceFixture();
		const rollup = buildGrowthDigest(
			{
				...source,
				github: {
					...source.github,
					codeContributors: 2,
					newIssues: 1,
					newPullRequests: 1,
					priorities: [
						{
							ageDays: 3,
							author: "alice",
							engagement: 1,
							kind: "pull_request",
							number: 12,
							reason: "pull request awaiting review",
							title: "Add a theme",
							url: "https://github.com/8bittts/JPtheCat/pull/12",
						},
					],
					windowContributors: 1,
				},
			},
			"daily",
		);

		expect(rollup.subject).toBe(
			"JP the Cat daily report: 3 Mac downloads · 1 open-source item to triage",
		);
		const html = renderToStaticMarkup(<GrowthDigestEmail rollup={rollup} />);
		const text = GrowthDigestPlainText({ rollup });
		expect(html.indexOf("Health")).toBeLessThan(html.indexOf("Open source (GitHub)"));
		expect(html.indexOf("Open source (GitHub)")).toBeLessThan(html.indexOf("Downloads"));
		expect(html).toContain('href="https://github.com/8bittts/JPtheCat/pull/12"');
		expect(text).toContain(
			"Triage first:\n  1. PR #12: Add a theme — https://github.com/8bittts/JPtheCat/pull/12 (pull request awaiting review · by alice · 3 days old · 1 comment or reaction)",
		);
		expect(text).toContain("New in window: 1 issue · 1 pull request · 0 merged");
		expect(text).toContain("Community contributors: 1 in window · 2 with merged code");
		expect(text).toContain("Repo link clicks: 3");
		expect(text).toContain("GitHub: connected");
	});

	it("reports a failed GitHub leg as an issue and drops its section", () => {
		const source = sourceFixture();
		const rollup = buildGrowthDigest(
			{
				...source,
				github: { ...source.github, message: "GitHub / returned 403", status: "error" },
			},
			"daily",
		);

		expect(rollup.issues).toEqual(["GitHub failed: GitHub / returned 403."]);
		const html = renderToStaticMarkup(<GrowthDigestEmail rollup={rollup} />);
		expect(html).not.toContain("Open source (GitHub)");
	});

	it("lists ranked rows as numbered items with units, and links pages", () => {
		const html = renderToStaticMarkup(
			<GrowthDigestEmail rollup={buildGrowthDigest(sourceFixture(), "weekly")} />,
		);
		const text = GrowthDigestPlainText({ rollup: buildGrowthDigest(sourceFixture(), "weekly") });

		// One level under the label as 1. 2. 3., never a "·"-joined sentence.
		expect(html).toContain("Top pages: </strong><ol");
		expect(html).toContain("list-style-type:decimal");
		expect(html).toContain('href="https://jpthecat.com/"');
		expect(html).toContain(">/</a> (18 views)");
		expect(html).not.toContain("pricing: 3 ·");
		expect(text).toContain("Top pages:\n  1. https://jpthecat.com/ (18 views)");
		expect(text).toContain("By source:\n  1. pricing (3 downloads)");
		expect(text).toContain("By version:\n  1. v0.062 (4 downloads)");
		expect(text).toContain("Top referrers:\n  1. news.ycombinator.com (5 views)");
		// Search Console pages link to the live URL and spell out their units.
		expect(text).toContain("  1. https://jpthecat.com/ (0 clicks · 0 impressions · position 12.1)");
		// An empty ranked list says what happened instead of vanishing.
		expect(text).toContain("Top queries: none in this window");
	});

	it("renders the digest on the admin shell, health first", () => {
		const html = renderToStaticMarkup(
			<GrowthDigestEmail rollup={buildGrowthDigest(sourceFixture(), "weekly")} />,
		);

		expect(html).toContain("Weekly JP the Cat report");
		const order = [
			">Health<",
			">Downloads<",
			">Traffic (Vercel Web Analytics)<",
			">Search (Search Console)<",
			">Signals<",
		].map((label) => html.indexOf(label));
		expect(order.every((index) => index > -1)).toBe(true);
		expect([...order].sort((a, b) => a - b)).toEqual(order);
		expect(html).toContain("Mac downloads: </strong>3 (macOS browsers only · +50% vs prior 2)");
		expect(html).toContain(
			"Human downloads: </strong>4 (all platforms · 13 raw hits · none in prior window)",
		);
		expect(html).toContain("Page views / visitors");
		// JP is free: the owner digest carries no sales, license, trial, or Stripe sections.
		expect(html).not.toMatch(
			/Paid licenses|Trial starts|License mix|Stripe|Pricing scroll|Buy CTA/,
		);
		expect(html).toContain(`>${EMAIL_FOOTER_DOMAIN_DISPLAY}</a>`);
		expect(html).not.toContain(ADMIN_EMAIL_ISSUES_LABEL);
		expect(html).not.toContain("jp-signature");
		expect(html).not.toContain("Paw-printed");
		expect(html.toLowerCase()).not.toContain("#fdcd2d");
	});

	it("provides a curated plain-text fallback for the owner digest", () => {
		const text = GrowthDigestPlainText({ rollup: buildGrowthDigest(sourceFixture(), "weekly") });

		expect(text.startsWith("Weekly JP the Cat report\n")).toBe(true);
		expect(text).toContain("HEALTH\nVercel Web Analytics: connected");
		expect(text).toContain(
			"DOWNLOADS\nMac downloads: 3 (macOS browsers only · +50% vs prior 2)\nHuman downloads: 4 (all platforms · 13 raw hits · none in prior window)",
		);
		expect(text).toContain("Download CTA clicks: 7");
		expect(text).toContain("SEARCH (SEARCH CONSOLE)");
		expect(text).toContain("SIGNALS\n- Bot pressure is high");
		expect(text).not.toContain("NEEDS ATTENTION");
		expect(text).toContain(EMAIL_FOOTER_DOMAIN_DISPLAY);
		expect(text).not.toContain(" · jpthecat.com");
	});

	it("leads with a Needs-attention issue when the datacenter filter was blind for any row", () => {
		// ipapi.is dropped the hosting flags from its keyless tier on 2026-09-01; the digest kept
		// reporting an inflated figure for seven weeks because nothing surfaced the gap.
		const data = sourceFixture();
		data.headline.networkFlagged = 1;
		const rollup = buildGrowthDigest(data, "weekly");

		expect(rollup.issues).toEqual([
			"Datacenter filter blind: 3 of 4 non-bot downloads got no hosting flag from ipapi.is (set IPAPI_IS_KEY).",
		]);
		expect(rollup.subject).toBe("JP the Cat weekly report: 3 Mac downloads · 1 issue");
	});
});

function sourceFixture(): GrowthDigestSourceData {
	return {
		generatedAt: "2026-07-03T14:00:00.000Z",
		windowDays: 7,
		headline: {
			allHits: 13,
			botUaHits: 9,
			humanDownloads: 4,
			macHumanDownloads: 3,
			networkFlaggable: 4,
			networkFlagged: 4,
			uniqueHumanIps: 1,
		},
		macRolling: { current: 3, deltaPct: 50, prior: 2 },
		rolling: { current: 4, deltaPct: null, prior: 0 },
		bySource: [{ count: 3, label: "pricing" }],
		byVersion: [{ count: 4, label: "0.062" }],
		byLocation: [{ count: 4, label: "San Francisco, CA, US" }],
		botUserAgents: [{ count: 6, label: "bingbot/2.0" }],
		vercel: {
			downloadCtaClicks: 7,
			libraryDownloadCtaClicks: 2,
			pageViews: 44,
			status: "ok",
			topCountries: [{ count: 30, label: "US" }],
			topPages: [{ count: 18, label: "/" }],
			topReferrers: [{ count: 5, label: "news.ycombinator.com" }],
			visitors: 20,
			repoLinkClicks: 3,
		},
		github: {
			codeContributors: 0,
			forks: 0,
			mergedPullRequests: 0,
			newIssues: 0,
			newPullRequests: 0,
			openIssues: 0,
			openPullRequests: 0,
			priorities: [],
			stars: 0,
			status: "ok",
			windowContributors: 0,
		},
		searchConsole: {
			clicks: 0,
			impressions: 0,
			position: null,
			status: "ok",
			topCountries: [{ count: 0, label: "usa" }],
			topPages: [{ clicks: 0, impressions: 0, label: "https://jpthecat.com/", position: 12.1 }],
			topQueries: [],
		},
	};
}
