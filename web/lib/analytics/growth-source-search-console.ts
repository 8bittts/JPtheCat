import type { GrowthDigestSourceData } from "@/lib/analytics/growth-digest";
import { OWNER_VALUE } from "@/lib/email/owner-vocabulary";
import { type EnvSource, type Fetcher, yyyyMmDd } from "./growth-digest-common";

const DEFAULT_GSC_SITE_URL = "https://jpthecat.com/";

async function mintGoogleAccessToken(source: EnvSource, fetcher: Fetcher): Promise<string | null> {
	const refreshToken = source.GOOGLE_OAUTH_REFRESH_TOKEN;
	const clientId = source.GOOGLE_OAUTH_CLIENT_ID;
	const clientSecret = source.GOOGLE_OAUTH_CLIENT_SECRET;
	if (refreshToken && clientId && clientSecret) {
		const response = await fetcher("https://oauth2.googleapis.com/token", {
			body: new URLSearchParams({
				client_id: clientId,
				client_secret: clientSecret,
				grant_type: "refresh_token",
				refresh_token: refreshToken,
			}),
			headers: { "content-type": "application/x-www-form-urlencoded" },
			method: "POST",
		});
		const body = (await response.json()) as {
			access_token?: string;
			error?: string;
			error_description?: string;
		};
		if (!response.ok || !body.access_token) {
			throw new Error(
				`OAuth refresh failed: ${response.status} ${body.error}: ${body.error_description}`,
			);
		}
		return body.access_token;
	}
	return source.GOOGLE_OAUTH_ACCESS_TOKEN ?? null;
}

// Search Console orders rows by clicks only, so 0-click ties come back in arbitrary order; rank ties
// by impressions so "top" always means the most-seen.
function byClicksThenImpressions(
	left: { clicks: number; impressions: number },
	right: { clicks: number; impressions: number },
) {
	return (
		Number(right.clicks || 0) - Number(left.clicks || 0) ||
		Number(right.impressions || 0) - Number(left.impressions || 0)
	);
}

export async function loadSearchConsole(
	windowDays: number,
	now: Date,
	source: EnvSource,
	fetcher: Fetcher,
): Promise<GrowthDigestSourceData["searchConsole"]> {
	try {
		const token = await mintGoogleAccessToken(source, fetcher);
		if (!token) {
			return {
				clicks: null,
				impressions: null,
				position: null,
				status: "skipped",
				topCountries: [],
				topPages: [],
				topQueries: [],
			};
		}
		const siteUrl = source.GSC_SITE_URL?.trim() || DEFAULT_GSC_SITE_URL;
		const gscUrl = `https://searchconsole.googleapis.com/webmasters/v3/sites/${encodeURIComponent(siteUrl)}/searchAnalytics/query`;
		const range = {
			endDate: yyyyMmDd(now),
			startDate: yyyyMmDd(new Date(now.getTime() - windowDays * 86_400_000)),
		};
		const query = async (queryBody: Record<string, unknown>) => {
			const response = await fetcher(gscUrl, {
				body: JSON.stringify({ ...range, ...queryBody }),
				headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
				method: "POST",
			});
			const json = (await response.json()) as {
				error?: unknown;
				rows?: Array<{
					clicks: number;
					ctr: number;
					impressions: number;
					keys?: string[];
					position: number;
				}>;
			};
			if (!response.ok) {
				throw new Error(JSON.stringify(json.error ?? json));
			}
			return json.rows ?? [];
		};
		const [totalRows, queryRows, pageRows, countryRows] = await Promise.all([
			query({ rowLimit: 1 }),
			query({ dimensions: ["query"], rowLimit: 10 }),
			query({ dimensions: ["page"], rowLimit: 8 }),
			query({ dimensions: ["country"], rowLimit: 8 }),
		]);
		const total = totalRows[0] ?? null;
		const clicks = total ? Number(total.clicks || 0) : 0;
		const impressions = total ? Number(total.impressions || 0) : 0;
		const weightedPosition = total && impressions > 0 ? Number(total.position || 0) : null;
		return {
			clicks,
			impressions,
			position: weightedPosition,
			status: "ok",
			// The count shown is impressions, so rank by impressions (Search Console returns click order).
			topCountries: countryRows
				.map((row) => ({
					count: Number(row.impressions || 0),
					label: row.keys?.[0]?.toUpperCase() ?? OWNER_VALUE.unknown,
				}))
				.sort((left, right) => right.count - left.count)
				.slice(0, 5),
			topPages: [...pageRows]
				.sort(byClicksThenImpressions)
				.slice(0, 5)
				.map((row) => ({
					clicks: Number(row.clicks || 0),
					impressions: Number(row.impressions || 0),
					label: row.keys?.[0] ?? OWNER_VALUE.unknown,
					position: Number(row.position || 0),
				})),
			topQueries: [...queryRows]
				.sort(byClicksThenImpressions)
				.slice(0, 5)
				.map((row) => ({
					clicks: Number(row.clicks || 0),
					impressions: Number(row.impressions || 0),
					position: Number(row.position || 0),
					query: row.keys?.[0] ?? OWNER_VALUE.unknown,
				})),
		};
	} catch (error) {
		const message = error instanceof Error ? error.message : "Unknown Search Console error";
		return {
			clicks: null,
			impressions: null,
			message,
			position: null,
			status: "error",
			topCountries: [],
			topPages: [],
			topQueries: [],
		};
	}
}
