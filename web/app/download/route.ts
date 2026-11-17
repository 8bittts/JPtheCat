import { readFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { type NextRequest, NextResponse } from "next/server";

// Validate → 302: the DMG is a GitHub Release asset on the public repository. version.json ships in
// the deploy bundle and is rewritten by the release pipeline; `/download` gives marketing a clean,
// stable URL and records nothing.

const NOINDEX_HEADER = "noindex, nofollow, noarchive, nosnippet, noimageindex";
const TRUSTED_RELEASE_HOSTNAME = "github.com";
// GitHub Release assets live under /<owner>/<repo>/releases/download/<tag>/<file>.
const RELEASE_PATH_PREFIX = "/8bittts/JPtheCat/releases/download/";

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
			parsed.hostname !== TRUSTED_RELEASE_HOSTNAME ||
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
 * Download route: /download → 302 to the latest verified DMG on GitHub Releases.
 */
export async function GET(request: NextRequest) {
	if (isPrefetchRequest(request)) {
		return downloadPrefetchResponse();
	}
	if (!RELEASE_REDIRECT_URL) {
		return downloadNotFoundResponse();
	}

	return NextResponse.redirect(RELEASE_REDIRECT_URL, {
		status: 302,
		headers: {
			"Cache-Control": "no-store",
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}
