import { readFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { after, type NextRequest, NextResponse } from "next/server";
import { enrichDownloadNetworkIntel } from "@/lib/analytics/download-network-intel";
import {
	buildDownloadRecord,
	type DownloadRecord,
	recordDownload,
} from "@/lib/analytics/downloads-store";
import {
	createDownloadNotificationEvent,
	type DownloadNotificationEvent,
} from "@/lib/email/download-notification";

// Validate → 302: the DMG is hosted on Supabase Storage (a public `releases` bucket), so the private
// repo's source stays private while the download is fully public. version.json ships in the deploy
// bundle and is rewritten by the release pipeline; `/download` gives marketing a clean, stable URL.

const NOINDEX_HEADER = "noindex, nofollow, noarchive, nosnippet, noimageindex";
const TRUSTED_RELEASE_HOSTNAMES = new Set([
	"api.jpthecat.com",
	// Legacy project host remains accepted so an emergency rollback manifest can still work.
	"duqpnrpzadrxqdbspjft.supabase.co",
]);
// Supabase public objects live under /storage/v1/object/public/<bucket>/<file>.
const RELEASE_PATH_PREFIX = "/storage/v1/object/public/releases/";

function downloadNotFoundResponse() {
	return new NextResponse("Download not available", {
		status: 404,
		headers: {
			"Cache-Control": "no-store",
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}

function downloadPrefetchResponse() {
	return new NextResponse(null, {
		status: 204,
		headers: {
			"Cache-Control": "no-store",
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}

const SHA256_PATTERN = /^[a-f0-9]{64}$/i;
const RELEASE_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const RELEASE_DMG_PATTERN = /^JPtheCat-\d+(?:\.\d+)*\.dmg$/;

function isPrefetchRequest(request: Request) {
	const purpose = request.headers.get("purpose")?.toLowerCase();
	const secPurpose = request.headers.get("sec-purpose")?.toLowerCase();
	return (
		request.headers.has("next-router-prefetch") ||
		purpose?.includes("prefetch") === true ||
		secPurpose?.includes("prefetch") === true
	);
}

export function resolveDownloadRedirectTarget(raw: unknown): string | null {
	if (typeof raw !== "object" || raw === null) {
		return null;
	}
	const manifest = raw as { url?: unknown; sha256?: unknown; releaseDate?: unknown };
	if (typeof manifest.url !== "string") {
		return null;
	}
	if (
		typeof manifest.sha256 !== "string" ||
		!SHA256_PATTERN.test(manifest.sha256.trim()) ||
		typeof manifest.releaseDate !== "string" ||
		!RELEASE_DATE_PATTERN.test(manifest.releaseDate.trim())
	) {
		return null;
	}

	const trimmed = manifest.url.trim();
	if (!trimmed) {
		return null;
	}

	try {
		const parsed = new URL(trimmed);
		if (parsed.protocol !== "https:") {
			return null;
		}
		if (
			!TRUSTED_RELEASE_HOSTNAMES.has(parsed.hostname) ||
			parsed.pathname.length <= RELEASE_PATH_PREFIX.length ||
			!parsed.pathname.startsWith(RELEASE_PATH_PREFIX) ||
			!parsed.pathname.toLowerCase().endsWith(".dmg")
		) {
			return null;
		}
		if (!RELEASE_DMG_PATTERN.test(basename(parsed.pathname))) {
			return null;
		}
		if (parsed.username || parsed.password || parsed.search || parsed.hash) {
			return null;
		}
		return parsed.toString();
	} catch {
		return null;
	}
}

type DownloadSideEffectDeps = {
	enrichDownloadNetworkIntel: typeof enrichDownloadNetworkIntel;
	recordDownload: typeof recordDownload;
};

// Downloads no longer email the owner one by one: the persisted row is the record, and the 8pm
// Pacific daily report (app/api/cron/growth-digest) counts and ranks them.
export async function runDownloadSideEffects(
	event: DownloadNotificationEvent,
	downloadRecordOrRequest: DownloadRecord | Request,
	deps: DownloadSideEffectDeps = { enrichDownloadNetworkIntel, recordDownload },
) {
	const enrichedEvent = await deps.enrichDownloadNetworkIntel(event);
	const downloadRecord =
		downloadRecordOrRequest instanceof Request
			? buildDownloadRecord(enrichedEvent, downloadRecordOrRequest)
			: downloadRecordOrRequest;
	await deps.recordDownload(downloadRecord);
}

// Read the version manifest once per instance, not per request.
const RELEASE_REDIRECT_URL: string | null = await (async () => {
	try {
		const versionPath = join(process.cwd(), "public", "stable", "version.json");
		const versionData = await readFile(versionPath, "utf-8");
		const versionJson = JSON.parse(versionData);
		return resolveDownloadRedirectTarget(versionJson);
	} catch (error) {
		const errorMessage = error instanceof Error ? error.message : "Unknown error";
		// biome-ignore lint/suspicious/noConsole: Boot-time diagnostic for missing/malformed version.json
		console.error("Error loading download manifest:", errorMessage);
		return null;
	}
})();

/**
 * Download route: /download → 302 to the latest verified DMG on Supabase Storage.
 */
export async function GET(request: NextRequest) {
	if (isPrefetchRequest(request)) {
		return downloadPrefetchResponse();
	}
	if (!RELEASE_REDIRECT_URL) {
		return downloadNotFoundResponse();
	}

	const event = createDownloadNotificationEvent({
		releaseUrl: RELEASE_REDIRECT_URL,
		request,
	});
	after(async () => {
		await runDownloadSideEffects(event, request);
	});

	return NextResponse.redirect(RELEASE_REDIRECT_URL, {
		status: 302,
		headers: {
			"Cache-Control": "no-store",
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}
