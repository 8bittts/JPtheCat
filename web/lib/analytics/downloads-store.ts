// Durable download spine: persist one bot-classified row per /download redirect
// into Supabase Postgres so `/growth` has real MoM / rolling history.
//
// Ephemeral Supabase Storage access logs (the true byte-fetch signal) only live
// ~24h, so the redirect event is captured here as the durable, queryable record.
// Writes go through PostgREST with the public anon key against an INSERT-only,
// RLS-guarded `downloads` table — no Supabase SDK dependency, no read access, no
// service-role secret in the web runtime. Reads happen out-of-band in
// `web/scripts/growth-metrics.ts` over the direct Postgres connection (which bypasses
// RLS), never through this key.
//
// Fire-and-forget: called inside the route's `after()` alongside the Resend
// notice. A telemetry write must NEVER affect the user's download, so every
// failure is swallowed with a log line.

import { isBotUserAgent, isMacUserAgent } from "@/lib/analytics/download-bot";
import type { DownloadNotificationEvent } from "@/lib/email/download-notification";

const DOWNLOADS_TABLE = "downloads";
const MAX_TEXT_LENGTH = 512;

export type DownloadRecord = {
	version: string;
	source: string;
	referer: string;
	ip: string | null;
	city: string | null;
	country: string | null;
	networkAsn: string | null;
	networkIsAnonymous: boolean | null;
	networkIsHosting: boolean | null;
	networkOrg: string | null;
	postalCode: string | null;
	region: string | null;
	timezone: string | null;
	userAgent: string;
	isBot: boolean;
	isMac: boolean;
};

function firstForwardedIp(forwardedFor: string | null): string | null {
	const first = forwardedFor?.split(",")[0]?.trim();
	return first ? first.slice(0, MAX_TEXT_LENGTH) : null;
}

function clampText(value: string): string {
	return value.length > MAX_TEXT_LENGTH ? value.slice(0, MAX_TEXT_LENGTH) : value;
}

function nullableGeoValue(value: string, maxLength = MAX_TEXT_LENGTH): string | null {
	return value === "Unknown" ? null : clampText(value).slice(0, maxLength);
}

/**
 * Build the durable download row from the notification event plus the Vercel edge
 * geo/IP headers. Kept pure and exported so tests can assert the payload — including
 * the bot classification — without a network round-trip.
 */
export function buildDownloadRecord(
	event: DownloadNotificationEvent,
	request: Request,
): DownloadRecord {
	return {
		version: clampText(event.releaseVersion),
		source: clampText(event.source),
		referer: clampText(event.referrer),
		ip: firstForwardedIp(request.headers.get("x-forwarded-for")),
		city: nullableGeoValue(event.geo.city),
		country: nullableGeoValue(event.geo.country, 8),
		// Not stored: city, region and country are all the daily report uses, so a postcode is not
		// needed for operations and is dropped for privacy. The column stays for older rows.
		postalCode: null,
		region: nullableGeoValue(event.geo.region, 64),
		timezone: nullableGeoValue(event.geo.timezone, 128),
		networkAsn: nullableGeoValue(event.network.asn, 32),
		networkOrg: nullableGeoValue(event.network.org, 240),
		networkIsHosting: event.network.isHosting,
		networkIsAnonymous: event.network.isAnonymous,
		userAgent: clampText(event.userAgent),
		isBot: isBotUserAgent(event.userAgent),
		isMac: isMacUserAgent(event.userAgent),
	};
}

function resolveSupabaseRest(): { url: string; key: string } | null {
	const base = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
	const key = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
	if (!base || !key) {
		return null;
	}
	return { url: `${base.replace(/\/$/, "")}/rest/v1/${DOWNLOADS_TABLE}`, key };
}

/**
 * Persist a download event. Never throws — telemetry must not break the download.
 */
export async function recordDownload(record: DownloadRecord): Promise<void> {
	const rest = resolveSupabaseRest();
	if (!rest) {
		// biome-ignore lint/suspicious/noConsole: Misconfiguration diagnostic; download still proceeds.
		console.warn("Skipping download persistence: Supabase URL/key not configured.");
		return;
	}
	try {
		const response = await fetch(rest.url, {
			method: "POST",
			headers: {
				"Content-Type": "application/json",
				apikey: rest.key,
				Prefer: "return=minimal",
			},
			body: JSON.stringify({
				version: record.version,
				source: record.source,
				referer: record.referer,
				ip: record.ip,
				city: record.city,
				country: record.country,
				postal_code: record.postalCode,
				region: record.region,
				timezone: record.timezone,
				network_asn: record.networkAsn,
				network_org: record.networkOrg,
				network_is_hosting: record.networkIsHosting,
				network_is_anonymous: record.networkIsAnonymous,
				ua: record.userAgent,
				is_bot: record.isBot,
				is_mac: record.isMac,
			}),
		});
		if (!response.ok) {
			const detail = await response.text().catch(() => "");
			// biome-ignore lint/suspicious/noConsole: Persistence failure needs logs; download still proceeds.
			console.error(`Download persistence failed: ${response.status} ${detail}`.trim());
		}
	} catch (error) {
		const message = error instanceof Error ? error.message : "Unknown persistence error";
		// biome-ignore lint/suspicious/noConsole: Persistence failure needs logs; download still proceeds.
		console.error(`Download persistence error: ${message}`);
	}
}
