import { basename } from "node:path";
import { OWNER_NOTIFICATION_FROM } from "@/lib/email/owner-notification";

// The download event the `/download` route persists. Downloads used to email the owner one by one;
// they are now counted in the 8pm Pacific daily report, so this module only builds the event.

export const DEFAULT_DOWNLOAD_NOTIFICATION_FROM = OWNER_NOTIFICATION_FROM;
const UNKNOWN = "Unknown";
const MAX_HEADER_VALUE_LENGTH = 240;
// Downloads flow through the homepage CTAs (tagged "pricing" for continuity with older rows) or a
// /library CTA modal. "hero"/"nav" are no longer emitted.
const ALLOWED_DOWNLOAD_SOURCES = new Set(["direct", "pricing", "library", "production-test"]);

type DownloadGeoContext = {
	city: string;
	country: string;
	postalCode: string;
	region: string;
	timezone: string;
};

type DownloadNetworkContext = {
	asn: string;
	isAnonymous: boolean | null;
	isHosting: boolean | null;
	org: string;
};

export type DownloadNotificationEvent = {
	downloadedAtIso: string;
	geo: DownloadGeoContext;
	ipAddress: string;
	network: DownloadNetworkContext;
	releaseFilename: string;
	releaseHost: string;
	releaseUrl: string;
	releaseVersion: string;
	referrer: string;
	requestUrl: string;
	source: string;
	userAgent: string;
};

type CreateDownloadNotificationEventInput = {
	now?: Date;
	releaseUrl: string;
	request: Request;
};

function clampHeaderText(value: string, maxLength = MAX_HEADER_VALUE_LENGTH) {
	return value.length > maxLength ? `${value.slice(0, maxLength - 1)}...` : value;
}

function cleanHeaderValue(value: string | null) {
	const trimmed = value?.trim();
	if (!trimmed) {
		return UNKNOWN;
	}
	return clampHeaderText(trimmed);
}

function decodeVercelHeaderValue(value: string) {
	try {
		return decodeURIComponent(value.replace(/\+/g, "%20"));
	} catch {
		return value;
	}
}

function cleanVercelGeoHeader(value: string | null, maxLength = MAX_HEADER_VALUE_LENGTH) {
	const trimmed = value?.trim();
	if (!trimmed) {
		return UNKNOWN;
	}
	const decoded = decodeVercelHeaderValue(trimmed).trim();
	return decoded ? clampHeaderText(decoded, maxLength) : UNKNOWN;
}

function parseReleaseVersion(releaseFilename: string) {
	const match = /^JPtheCat-(.+)\.dmg$/i.exec(releaseFilename);
	return match?.[1] ?? "unknown";
}

function cleanDownloadSource(source: string | null) {
	const trimmed = source?.trim();
	if (!trimmed) {
		return "direct";
	}
	return ALLOWED_DOWNLOAD_SOURCES.has(trimmed) ? trimmed : "external";
}

function firstForwardedIp(forwardedFor: string | null): string {
	const first = forwardedFor?.split(",")[0]?.trim();
	return first ? clampHeaderText(first, 64) : UNKNOWN;
}

export function createDownloadNotificationEvent({
	now = new Date(),
	releaseUrl,
	request,
}: CreateDownloadNotificationEventInput): DownloadNotificationEvent {
	const parsedRelease = new URL(releaseUrl);
	const requestUrl = new URL(request.url);
	const releaseFilename = basename(parsedRelease.pathname);

	return {
		downloadedAtIso: now.toISOString(),
		releaseFilename,
		releaseHost: parsedRelease.hostname,
		releaseUrl: parsedRelease.toString(),
		releaseVersion: parseReleaseVersion(releaseFilename),
		ipAddress: firstForwardedIp(request.headers.get("x-forwarded-for")),
		referrer: cleanHeaderValue(request.headers.get("referer")),
		requestUrl: requestUrl.toString(),
		source: cleanDownloadSource(requestUrl.searchParams.get("source")),
		userAgent: cleanHeaderValue(request.headers.get("user-agent")),
		geo: {
			city: cleanVercelGeoHeader(request.headers.get("x-vercel-ip-city")),
			country: cleanVercelGeoHeader(request.headers.get("x-vercel-ip-country"), 8),
			postalCode: cleanVercelGeoHeader(request.headers.get("x-vercel-ip-postal-code"), 32),
			region: cleanVercelGeoHeader(request.headers.get("x-vercel-ip-country-region"), 64),
			timezone: cleanVercelGeoHeader(request.headers.get("x-vercel-ip-timezone"), 128),
		},
		network: {
			asn: UNKNOWN,
			isAnonymous: null,
			isHosting: null,
			org: UNKNOWN,
		},
	};
}
