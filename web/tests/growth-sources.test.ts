import { describe, expect, it } from "bun:test";
import { loadGitHubActivity } from "@/lib/analytics/growth-source-github";
import { loadSearchConsole } from "@/lib/analytics/growth-source-search-console";
import { loadVercelAnalytics } from "@/lib/analytics/growth-source-vercel";
import { OWNER_VALUE } from "@/lib/email/owner-vocabulary";

const NOW = new Date("2026-10-19T14:00:00.000Z");

function jsonResponse(body: unknown) {
	return new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } });
}

describe("growth digest sources", () => {
	it("ranks Search Console 0-click ties by impressions and countries by the impressions shown", async () => {
		const rows = (dimension: string | undefined) => {
			if (dimension === "query") {
				return [
					{ clicks: 0, impressions: 1, keys: ["seen once"], position: 9 },
					{ clicks: 1, impressions: 2, keys: ["clicked"], position: 3 },
					{ clicks: 0, impressions: 7, keys: ["seen most"], position: 5 },
				];
			}
			if (dimension === "country") {
				return [
					{ clicks: 1, impressions: 5, keys: ["chn"], position: 4 },
					{ clicks: 0, impressions: 33, keys: ["usa"], position: 11 },
				];
			}
			return [{ clicks: 3, impressions: 100, position: 10.7 }];
		};
		const fetcher = (async (_url: string | URL | Request, init?: RequestInit) => {
			const body = JSON.parse(String(init?.body ?? "{}")) as { dimensions?: string[] };
			return jsonResponse({ rows: rows(body.dimensions?.[0]) });
		}) as typeof fetch;

		const search = await loadSearchConsole(7, NOW, { GOOGLE_OAUTH_ACCESS_TOKEN: "test" }, fetcher);

		expect(search.status).toBe("ok");
		expect(search.topQueries.map((row) => row.query)).toEqual([
			"clicked",
			"seen most",
			"seen once",
		]);
		expect(search.topCountries).toEqual([
			{ count: 33, label: "USA" },
			{ count: 5, label: "CHN" },
		]);
	});

	it("names a blank Vercel referrer as direct traffic, never a dash", async () => {
		const fetcher = (async (url: string | URL | Request) => {
			const href = String(url);
			if (href.includes("referrerHostname")) {
				return jsonResponse({
					data: [
						{ pageviews: 43, referrerHostname: "" },
						{ pageviews: 6, referrerHostname: "t.co" },
					],
				});
			}
			return jsonResponse({ data: [] });
		}) as typeof fetch;

		const vercel = await loadVercelAnalytics(7, NOW, { VERCEL_TOKEN: "test" }, fetcher);

		expect(vercel.status).toBe("ok");
		expect(vercel.topReferrers).toEqual([
			{ count: 43, label: OWNER_VALUE.direct },
			{ count: 6, label: "t.co" },
		]);
	});

	it("counts a renamed event under both its snake_case and legacy Title Case names", async () => {
		const fetcher = (async (url: string | URL | Request) => {
			if (String(url).includes("events/aggregate")) {
				return jsonResponse({
					data: [
						{ count: 3, eventName: "download_cta_clicked" },
						{ count: 2, eventName: "Download CTA Clicked" },
					],
				});
			}
			return jsonResponse({ data: [] });
		}) as typeof fetch;

		const vercel = await loadVercelAnalytics(7, NOW, { VERCEL_TOKEN: "test" }, fetcher);

		expect(vercel.downloadCtaClicks).toBe(5);
	});

	it("counts repository link clicks from the repo_link_clicked event", async () => {
		const fetcher = (async (url: string | URL | Request) =>
			jsonResponse({
				data: String(url).includes("events/aggregate")
					? [{ count: 4, eventName: "repo_link_clicked" }]
					: [],
			})) as typeof fetch;

		const vercel = await loadVercelAnalytics(1, NOW, { VERCEL_TOKEN: "test" }, fetcher);

		expect(vercel.repoLinkClicks).toBe(4);
	});
});

const OWNER = { login: "8bittts", type: "User" };
const daysAgo = (days: number) => new Date(NOW.getTime() - days * 86_400_000).toISOString();

function githubItem(overrides: Record<string, unknown>) {
	return {
		comments: 0,
		created_at: daysAgo(10),
		html_url: `https://github.com/8bittts/JPtheCat/issues/${overrides.number}`,
		labels: [],
		reactions: { total_count: 0 },
		title: `Item ${overrides.number}`,
		user: { login: "alice", type: "User" },
		...overrides,
	};
}

const OPEN_ITEMS = [
	githubItem({ number: 1, title: "Owner todo", user: OWNER }),
	githubItem({ number: 2, title: "Bump deps", user: { login: "dependabot[bot]", type: "Bot" } }),
	githubItem({ number: 3, title: "Plain question" }),
	githubItem({ labels: [{ name: "bug" }], number: 4, title: "Crash on launch" }),
	githubItem({ number: 5, pull_request: { merged_at: null }, title: "Add a theme" }),
	githubItem({ draft: true, number: 6, pull_request: { merged_at: null }, title: "WIP" }),
	githubItem({ labels: ["security"], number: 7, title: "Token leak" }),
	githubItem({ comments: 4, created_at: daysAgo(1), number: 8, title: "Busy question" }),
];

const RECENT_ITEMS = [
	githubItem({ created_at: daysAgo(0.5), number: 8, user: { login: "bob", type: "User" } }),
	githubItem({
		created_at: daysAgo(0.2),
		number: 9,
		pull_request: { merged_at: null },
		user: { login: "carol", type: "User" },
	}),
	githubItem({
		created_at: daysAgo(5),
		number: 10,
		pull_request: { merged_at: daysAgo(0.1) },
		user: { login: "dave", type: "User" },
	}),
	githubItem({ created_at: daysAgo(0.3), number: 11, user: OWNER }),
];

function githubFetcher(seen: Array<{ url: string; headers: Record<string, string> }> = []) {
	return (async (url: string | URL | Request, init?: RequestInit) => {
		const href = String(url);
		seen.push({ headers: (init?.headers ?? {}) as Record<string, string>, url: href });
		if (href.endsWith("/repos/8bittts/JPtheCat")) {
			return jsonResponse({ forks_count: 2, owner: OWNER, stargazers_count: 12 });
		}
		if (href.includes("/contributors")) {
			return jsonResponse([
				OWNER,
				{ login: "dave", type: "User" },
				{ login: "renovate[bot]", type: "Bot" },
			]);
		}
		if (href.includes("state=open")) return jsonResponse(OPEN_ITEMS);
		return jsonResponse(RECENT_ITEMS);
	}) as typeof fetch;
}

describe("GitHub digest source", () => {
	it("ranks community items for triage and leaves out the owner and bots", async () => {
		const github = await loadGitHubActivity(1, NOW, {}, githubFetcher());

		expect(github.status).toBe("ok");
		// Security, then a ready pull request, then bugs, then questions by engagement, then drafts.
		expect(github.priorities.map((item) => item.number)).toEqual([7, 5, 4, 8, 3]);
		expect(github.priorities[0]).toMatchObject({
			author: "alice",
			kind: "issue",
			reason: "security label",
			url: "https://github.com/8bittts/JPtheCat/issues/7",
		});
		expect(github.priorities[1]?.kind).toBe("pull_request");
		expect(github.priorities[3]).toMatchObject({ ageDays: 1, engagement: 4 });
		expect(github.priorities.map((item) => item.number)).not.toContain(1);
		expect(github.priorities.map((item) => item.number)).not.toContain(2);
	});

	it("counts window activity, community contributors, and repository totals", async () => {
		const github = await loadGitHubActivity(1, NOW, {}, githubFetcher());

		expect(github).toMatchObject({
			codeContributors: 1,
			forks: 2,
			mergedPullRequests: 1,
			newIssues: 2,
			newPullRequests: 1,
			openIssues: 6,
			openPullRequests: 2,
			stars: 12,
			windowContributors: 3,
		});
	});

	it("reads the public API without a token and sends one only when configured", async () => {
		const anonymous: Array<{ url: string; headers: Record<string, string> }> = [];
		await loadGitHubActivity(1, NOW, {}, githubFetcher(anonymous));
		expect(anonymous).toHaveLength(4);
		expect(
			anonymous.every((call) =>
				call.url.startsWith("https://api.github.com/repos/8bittts/JPtheCat"),
			),
		).toBe(true);
		expect(anonymous.some((call) => "authorization" in call.headers)).toBe(false);
		expect(anonymous.find((call) => call.url.includes("state=all"))?.url).toContain(
			`since=${daysAgo(1)}`,
		);

		const authed: Array<{ url: string; headers: Record<string, string> }> = [];
		await loadGitHubActivity(1, NOW, { GITHUB_TOKEN: "test" }, githubFetcher(authed));
		expect(authed.every((call) => call.headers.authorization === "Bearer test")).toBe(true);
	});

	it("fails soft with a reason when GitHub refuses the request", async () => {
		const fetcher = (async (_url: string | URL | Request) =>
			new Response("rate limited", { status: 403 })) as typeof fetch;

		const github = await loadGitHubActivity(1, NOW, {}, fetcher);

		expect(github.status).toBe("error");
		expect(github.message).toContain("returned 403");
		expect(github.priorities).toEqual([]);
		expect(github.openIssues).toBeNull();
	});
});
