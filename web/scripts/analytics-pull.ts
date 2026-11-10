#!/usr/bin/env bun
// Pull Search Console snapshots for the JP the Cat /growth review — the keyword-growth
// signal behind the /library pSEO bet. Read-only.
//
// JP the Cat ships NO GA4 leg: website traffic telemetry is Vercel Web Analytics +
// Speed Insights (mounted in web/app/layout.tsx). The automated owner digest pulls Vercel
// visits/events through the Web Analytics API; this script owns the Search Console leg.
// Vercel custom events are NOT bot-filtered (GSC plus the download spine are the trustier
// acquisition signals). The download-funnel spine lives in scripts/growth-metrics.ts.
//
// Adapted from DeathNote's 95-google-analytics-pull.ts (OAuth refresh + GSC query).
//
// Usage: bun scripts/analytics-pull.ts [days]   (days defaults to 30; run 30 and 90 to
//   diff keyword movement — rising/cooling/position-wins.)
//
// Credentials (web/.env.local then .env): GOOGLE_OAUTH_REFRESH_TOKEN +
// GOOGLE_OAUTH_CLIENT_ID + GOOGLE_OAUTH_CLIENT_SECRET (headless refresh; preferred), or
// GOOGLE_OAUTH_ACCESS_TOKEN (static ~1h token). GSC_SITE_URL defaults to
// https://jpthecat.com/ and must be a verified Search Console property. Without any
// credential the script prints a dormant-leg notice and exits 0 (never throws).

import { loadReaderEnv, trailingDaysArgument } from "../lib/analytics/reader-cli";

const DEFAULT_SITE_URL = "https://jpthecat.com/";

const DAYS = trailingDaysArgument();

// Mint a fresh access token from a stored refresh token (headless), falling back to a
// static access token. Returns null when no credential is configured (dormant leg).
async function mintAccessToken(): Promise<string | null> {
	const refreshToken = process.env.GOOGLE_OAUTH_REFRESH_TOKEN;
	const clientId = process.env.GOOGLE_OAUTH_CLIENT_ID;
	const clientSecret = process.env.GOOGLE_OAUTH_CLIENT_SECRET;
	if (refreshToken && clientId && clientSecret) {
		const res = await fetch("https://oauth2.googleapis.com/token", {
			method: "POST",
			headers: { "content-type": "application/x-www-form-urlencoded" },
			body: new URLSearchParams({
				grant_type: "refresh_token",
				refresh_token: refreshToken,
				client_id: clientId,
				client_secret: clientSecret,
			}),
		});
		const body = (await res.json()) as {
			access_token?: string;
			error?: string;
			error_description?: string;
		};
		if (!res.ok || !body.access_token) {
			throw new Error(
				`OAuth refresh failed: ${res.status} ${body.error}: ${body.error_description}`,
			);
		}
		return body.access_token;
	}
	return process.env.GOOGLE_OAUTH_ACCESS_TOKEN ?? null;
}

function fmtDate(d: Date): string {
	return d.toISOString().slice(0, 10);
}

interface GscRow {
	keys?: string[];
	clicks: number;
	impressions: number;
	ctr: number;
	position: number;
}
interface GscResult {
	rows?: GscRow[];
}

async function gscQuery(token: string, siteUrl: string, body: unknown): Promise<GscResult> {
	const res = await fetch(
		`https://searchconsole.googleapis.com/webmasters/v3/sites/${encodeURIComponent(siteUrl)}/searchAnalytics/query`,
		{
			method: "POST",
			headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
			body: JSON.stringify(body),
		},
	);
	const json = (await res.json()) as GscResult & { error?: unknown };
	if (!res.ok) throw new Error(`GSC ${res.status}: ${JSON.stringify(json.error ?? json)}`);
	return json;
}

function printGscTable(title: string, report: GscResult, dimensions: string[]): void {
	console.log(`\n=== ${title} ===`);
	if (!report.rows?.length) {
		console.log("(no rows)");
		return;
	}
	console.log([...dimensions, "clicks", "impressions", "ctr", "position"].join("\t"));
	for (const row of report.rows) {
		const keys = row.keys ?? [];
		console.log(
			[
				...keys,
				row.clicks,
				row.impressions,
				`${(row.ctr * 100).toFixed(1)}%`,
				row.position.toFixed(1),
			].join("\t"),
		);
	}
}

async function main() {
	loadReaderEnv();
	const token = await mintAccessToken();
	if (!token) {
		console.log(
			"=== Search Console leg is dormant ===\n" +
				"No Google OAuth credentials configured. To enable keyword growth:\n" +
				"  1. Verify https://jpthecat.com/ as a Search Console property for the owner Google account.\n" +
				"  2. Reuse the shared Google OAuth client already used for the operator account and store\n" +
				"     GOOGLE_OAUTH_CLIENT_ID / _SECRET / _REFRESH_TOKEN in web/.env.local\n" +
				"     (see _docs/08-growth.md → Readers).\n" +
				"Traffic in the meantime: Vercel Web Analytics API/dashboard (custom events; NOT bot-filtered).",
		);
		return;
	}

	const siteUrl = process.env.GSC_SITE_URL?.trim() || DEFAULT_SITE_URL;
	const end = new Date();
	const start = new Date(end.getTime() - DAYS * 86400000);
	const range = { startDate: fmtDate(start), endDate: fmtDate(end) };
	const gsc = (body: unknown) => gscQuery(token, siteUrl, body);

	console.log(`Search Console — ${siteUrl} — ${range.startDate}..${range.endDate} (${DAYS}d)`);

	printGscTable("Top queries", await gsc({ ...range, dimensions: ["query"], rowLimit: 50 }), [
		"query",
	]);
	printGscTable("Top pages", await gsc({ ...range, dimensions: ["page"], rowLimit: 30 }), ["page"]);
	printGscTable(
		"Monthly trend (by date — roll up to month)",
		await gsc({ ...range, dimensions: ["date"], rowLimit: 500 }),
		["date"],
	);
	printGscTable("Top countries", await gsc({ ...range, dimensions: ["country"], rowLimit: 15 }), [
		"country",
	]);
}

await main();
