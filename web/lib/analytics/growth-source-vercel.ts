import type { GrowthCountRow, GrowthDigestSourceData } from "@/lib/analytics/growth-digest";
import { OWNER_VALUE } from "@/lib/email/owner-vocabulary";
import { type EnvSource, type Fetcher, yyyyMmDd } from "./growth-digest-common";
import { LEGACY_PRODUCT_EVENT_NAMES, type ProductEventName } from "./product-analytics";

const DEFAULT_VERCEL_PROJECT_ID = "prj_r95zGdIKvmv8ZwnWqpT8tMjteZSb";
const DEFAULT_VERCEL_TEAM_SLUG = "8lee";

type VercelAggregateRow = Record<string, unknown>;

function numericField(row: Record<string, unknown>, keys: string[]): number {
	for (const key of keys) {
		const value = Number(row[key]);
		if (Number.isFinite(value)) return value;
	}
	return 0;
}

function vercelProjectUrl(path: string, source: EnvSource): URL {
	const url = new URL(`https://api.vercel.com/v1/query/web-analytics/${path}`);
	url.searchParams.set("projectId", source.VERCEL_PROJECT_ID?.trim() || DEFAULT_VERCEL_PROJECT_ID);
	url.searchParams.set("slug", source.VERCEL_TEAM_SLUG?.trim() || DEFAULT_VERCEL_TEAM_SLUG);
	if (source.VERCEL_TEAM_ID?.trim()) {
		url.searchParams.set("teamId", source.VERCEL_TEAM_ID.trim());
		url.searchParams.delete("slug");
	}
	return url;
}

function setVercelWindow(url: URL, windowDays: number, now: Date) {
	url.searchParams.set("since", yyyyMmDd(new Date(now.getTime() - windowDays * 86_400_000)));
	url.searchParams.set("until", yyyyMmDd(now));
}

async function vercelJson(
	path: string,
	token: string,
	source: EnvSource,
	fetcher: Fetcher,
	configure: (url: URL) => void,
) {
	const url = vercelProjectUrl(path, source);
	configure(url);
	const response = await fetcher(url, {
		headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
	});
	const body = (await response.json()) as {
		data?: unknown;
		error?: unknown;
	};
	if (!response.ok) {
		throw new Error(JSON.stringify(body.error ?? body));
	}
	return body.data;
}

function labelFor(row: VercelAggregateRow, keys: string[], fallback: string): string {
	for (const key of keys) {
		const value = row[key];
		if (typeof value === "string" && value.trim()) return value;
	}
	return fallback;
}

function vercelRows(
	data: unknown,
	labelKeys: string[],
	countKeys: string[],
	fallback: string = OWNER_VALUE.unknown,
): GrowthCountRow[] {
	const rows = Array.isArray(data) ? data : [];
	const result: GrowthCountRow[] = [];
	for (const row of rows) {
		const record = row as VercelAggregateRow;
		const count = numericField(record, countKeys);
		if (count <= 0) continue;
		const label = labelFor(record, labelKeys, fallback);
		if (label === "Others") continue;
		result.push({
			count,
			label,
		});
	}
	return result.sort((left, right) => right.count - left.count).slice(0, 5);
}

export async function loadVercelAnalytics(
	windowDays: number,
	now: Date,
	source: EnvSource,
	fetcher: Fetcher,
): Promise<GrowthDigestSourceData["vercel"]> {
	const token = source.VERCEL_TOKEN?.trim() || source.VERCEL_API_TOKEN?.trim();
	if (!token) {
		return {
			downloadCtaClicks: null,
			libraryDownloadCtaClicks: null,
			pageViews: null,
			repoLinkClicks: null,
			status: "skipped",
			topCountries: [],
			topPages: [],
			topReferrers: [],
			visitors: null,
		};
	}

	try {
		const [eventData, visitCountData, topPagesData, topReferrersData, topCountriesData] =
			await Promise.all([
				vercelJson("events/aggregate", token, source, fetcher, (url) => {
					setVercelWindow(url, windowDays, now);
					url.searchParams.set("by", "eventName");
					url.searchParams.set("limit", "50");
				}),
				vercelJson("visits/count", token, source, fetcher, (url) => {
					setVercelWindow(url, windowDays, now);
				}),
				vercelJson("visits/aggregate", token, source, fetcher, (url) => {
					setVercelWindow(url, windowDays, now);
					url.searchParams.set("by", "requestPath");
					url.searchParams.set("limit", "8");
				}),
				vercelJson("visits/aggregate", token, source, fetcher, (url) => {
					setVercelWindow(url, windowDays, now);
					url.searchParams.set("by", "referrerHostname");
					url.searchParams.set("limit", "8");
				}),
				vercelJson("visits/aggregate", token, source, fetcher, (url) => {
					setVercelWindow(url, windowDays, now);
					url.searchParams.set("by", "country");
					url.searchParams.set("limit", "8");
				}),
			]);

		const rows = Array.isArray(eventData) ? eventData : [];
		const countFor = (name: ProductEventName) =>
			rows
				.filter((row) => {
					const eventName = String(row.eventName ?? "");
					return eventName === name || eventName === LEGACY_PRODUCT_EVENT_NAMES[name];
				})
				.reduce((sum, row) => sum + numericField(row, ["count", "events", "value", "total"]), 0);
		const visitCount = (visitCountData ?? {}) as Record<string, unknown>;

		return {
			downloadCtaClicks: countFor("download_cta_clicked"),
			libraryDownloadCtaClicks: countFor("library_download_cta_clicked"),
			pageViews: numericField(visitCount, ["pageviews", "pageViews", "count", "total"]),
			repoLinkClicks: countFor("repo_link_clicked"),
			status: "ok",
			topCountries: vercelRows(topCountriesData, ["country"], ["pageviews", "pageViews", "count"]),
			topPages: vercelRows(
				topPagesData,
				["requestPath", "route"],
				["pageviews", "pageViews", "count"],
			),
			// A blank referrer hostname is direct traffic, not a missing value.
			topReferrers: vercelRows(
				topReferrersData,
				["referrerHostname"],
				["pageviews", "pageViews", "count"],
				OWNER_VALUE.direct,
			),
			visitors: numericField(visitCount, ["visitors", "uniqueVisitors", "devices"]),
		};
	} catch (error) {
		const message = error instanceof Error ? error.message : "Unknown Vercel Analytics error";
		return {
			downloadCtaClicks: null,
			libraryDownloadCtaClicks: null,
			message,
			pageViews: null,
			repoLinkClicks: null,
			status: "error",
			topCountries: [],
			topPages: [],
			topReferrers: [],
			visitors: null,
		};
	}
}
