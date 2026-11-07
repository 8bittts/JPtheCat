import { type NextRequest, NextResponse } from "next/server";

// Deny every powerful feature the marketing site never uses. `browsing-topics=()`
// opts out of the Topics API (the successor to the deprecated FLoC `interest-cohort`);
// the hardware/payment features are listed so a future embedded/third-party frame can't
// silently gain them. Keep this value byte-identical to the vercel.json edge header.
export const DOCUMENT_PERMISSIONS_POLICY =
	"camera=(), microphone=(), geolocation=(), browsing-topics=(), interest-cohort=(), payment=(), usb=(), serial=(), bluetooth=(), hid=(), midi=()";

export const DOCUMENT_SECURITY_HEADERS = {
	"cross-origin-opener-policy": "same-origin",
	"cross-origin-resource-policy": "same-origin",
	"x-content-type-options": "nosniff",
	"referrer-policy": "strict-origin-when-cross-origin",
	"permissions-policy": DOCUMENT_PERMISSIONS_POLICY,
} as const;

// Same-origin sink for CSP violation reports. `report-to` names a Reporting API endpoint group
// declared by the `Reporting-Endpoints` response header (set in `proxy()`); `report-uri` is the legacy
// fallback for browsers that predate the Reporting API. Both point at the same in-app route.
export const CSP_REPORT_PATH = "/api/csp-report";
export const CSP_REPORT_GROUP = "csp-endpoint";
export const REPORTING_ENDPOINTS_HEADER = `${CSP_REPORT_GROUP}="${CSP_REPORT_PATH}"`;

export function buildContentSecurityPolicy(nonce: string) {
	return [
		"default-src 'self'",
		`script-src 'nonce-${nonce}' 'strict-dynamic'`,
		// 'unsafe-inline' is required for React 19 / Tailwind inline `style=` attributes
		// (nonces don't cover style attributes). It does NOT weaken the script policy,
		// which stays nonce + 'strict-dynamic' with no inline-script escape hatch.
		"style-src 'self' 'unsafe-inline'",
		"img-src 'self' data: blob:",
		// The JP hover sound is packaged media, so static audio/video assets must stay playable.
		"media-src 'self' blob: data:",
		"font-src 'self' data:",
		"connect-src 'self' https://api.jpthecat.com",
		"manifest-src 'self'",
		"frame-src 'none'",
		"object-src 'none'",
		"base-uri 'self'",
		"form-action 'self'",
		"frame-ancestors 'none'",
		"upgrade-insecure-requests",
		// Report violations to the same-origin sink. `report-to` for modern browsers (group declared by
		// the Reporting-Endpoints header), `report-uri` as the legacy fallback.
		`report-to ${CSP_REPORT_GROUP}`,
		`report-uri ${CSP_REPORT_PATH}`,
	].join("; ");
}

/**
 * Per-request nonce CSP. Next reads the nonce from the request's
 * Content-Security-Policy header and applies it to its own scripts; our one
 * hand-written script (the JSON-LD in app/page.tsx) reads `x-nonce` and applies
 * it too. Using a nonce forces dynamic rendering — acceptable for a small
 * marketing site, and the price of a strict, `unsafe-inline`-free script policy.
 *
 * `connect-src` includes `https://api.jpthecat.com` because the download CTA and future
 * calls resolve through that branded release/API host.
 */
export function proxy(request: NextRequest) {
	const nonce = btoa(crypto.randomUUID());
	const csp = buildContentSecurityPolicy(nonce);

	const requestHeaders = new Headers(request.headers);
	requestHeaders.set("x-nonce", nonce);
	requestHeaders.set("content-security-policy", csp);

	const response = NextResponse.next({ request: { headers: requestHeaders } });
	response.headers.set("content-security-policy", csp);
	// Declares the `csp-endpoint` group that the CSP `report-to` directive targets.
	response.headers.set("reporting-endpoints", REPORTING_ENDPOINTS_HEADER);
	for (const [key, value] of Object.entries(DOCUMENT_SECURITY_HEADERS)) {
		response.headers.set(key, value);
	}
	return response;
}

export const config = {
	matcher: [
		{
			// Run on documents only; skip static assets and prefetches (whose cached
			// nonce would never match a fresh request's nonce). `sha256`/`dmg` cover the
			// public /stable release artifacts, which must be served purely by the Vercel
			// edge headers (cross-origin CORP) — running them through this middleware would
			// stamp a document CORP:same-origin and a pointless per-request nonce on them.
			source:
				"/((?!_next/static|_next/image|favicon.ico|.*\\.(?:png|jpg|jpeg|gif|webp|svg|ico|mp4|webm|m4a|mp3|wav|ogg|aac|json|txt|xml|webmanifest|wasm|sha256|dmg)).*)",
			missing: [
				{ type: "header", key: "next-router-prefetch" },
				{ type: "header", key: "purpose", value: "prefetch" },
			],
		},
	],
};
