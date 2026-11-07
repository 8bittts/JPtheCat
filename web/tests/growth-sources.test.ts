import { describe, expect, it } from "bun:test";
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
});
