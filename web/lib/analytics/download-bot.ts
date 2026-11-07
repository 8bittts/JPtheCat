// Bot classification for the /download growth spine.
//
// A raw /download hit is NOT an install: crawlers and scrapers pull the DMG, so
// bot filtering is load-bearing.
//
// This module is the write-time, per-request classifier: it flags the obvious
// non-human user agents. The *burst* pattern (one IP walking every CTA link in a
// few seconds) can only be seen across rows, so it is reconciled at read time in
// `web/scripts/growth-metrics.ts` — keep the two halves in sync.

// Substrings that unambiguously mark an automated client. Matched case-insensitively
// against the raw user-agent. Deliberately conservative: a false "human" is cheaper
// than silently discarding a real install, and the read-time burst pass is the backstop.
const BOT_UA_SUBSTRINGS: readonly string[] = [
	// Named crawlers / aggregators seen hitting the release bucket.
	"dataprovider.com",
	"bot",
	"spider",
	"crawler",
	"crawl",
	"slurp",
	"scraper",
	// Generic HTTP clients / libraries — never a real Mac user double-clicking a DMG.
	"curl",
	"wget",
	"python-requests",
	"python-urllib",
	"go-http-client",
	"node-fetch",
	"axios",
	"okhttp",
	"java/",
	"libwww",
	"httpclient",
	"headless",
	// Monitors / preview fetchers / link expanders.
	"monitor",
	"uptime",
	"pingdom",
	"phantomjs",
	"facebookexternalhit",
	"embedly",
	"preview",
	"whatsapp",
	"telegrambot",
	"discordbot",
	// Self-named scanners that passed every marker above in Oct 2026 (`GrowthScan/0.1`,
	// `msh-pdfmin/1`, `NumeosScoutObservatory/1.1.1`) and the operator's own `update-projs-smoke` UA.
	"growthscan",
	"scan/",
	"pdfmin",
	"observatory",
	"smoke",
];

// Every modern macOS browser (Safari, Chrome, Firefox, Arc, …) freezes the platform token at
// `Macintosh; Intel Mac OS X 10_15_7`, so the prefix is a stable "this client can run the DMG" test
// with no false negatives for real users. A Windows, Android, or Linux browser pulling a macOS DMG
// is a crawler or a curious visitor, never an install, which is why `/growth` leads with Mac rows.
const MAC_UA_PREFIX = "mozilla/5.0 (macintosh";

/**
 * Best-effort per-request bot classification from the user-agent string.
 *
 * Returns true for an empty/unknown UA (a real browser always sends one) and for
 * any UA matching a known automated-client marker. This is intentionally the
 * write-time filter only; see the module note about read-time burst detection.
 */
export function isBotUserAgent(userAgent: string | null | undefined): boolean {
	const ua = userAgent?.trim().toLowerCase();
	if (!ua) {
		return true;
	}
	return BOT_UA_SUBSTRINGS.some((needle) => ua.includes(needle));
}

/**
 * True when the user agent is a macOS browser, the only client that can open the DMG it pulled.
 * Persisted at write time as `downloads.is_mac` so the platform survives the 30-day UA redaction.
 */
export function isMacUserAgent(userAgent: string | null | undefined): boolean {
	const ua = userAgent?.trim().toLowerCase();
	return Boolean(ua?.startsWith(MAC_UA_PREFIX));
}
