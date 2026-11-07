import { NextResponse } from "next/server";
import { API_NOINDEX_HEADER } from "@/lib/http/api-response";

// Same-origin sink for Content-Security-Policy violation reports (see `report-to`/`report-uri` in
// proxy.ts). The browser POSTs these automatically; we only log a compact, non-sensitive summary to
// the server logs (Vercel) so a CSP regression or injection attempt is observable, then answer 204.
// There is no store and no downstream call — this endpoint must stay cheap and side-effect-free.

const MAX_BODY_BYTES = 16_384; // A real CSP report is well under this; cap to avoid log-spam abuse.

const NO_CONTENT_HEADERS = {
	"Cache-Control": "no-store",
	"X-Robots-Tag": API_NOINDEX_HEADER,
} as const;

// Both report shapes carry the same interesting fields under different keys: the legacy
// `application/csp-report` body is `{ "csp-report": {...snake_case...} }`; the Reporting API
// (`application/reports+json`) sends an array of `{ type, body: {...kebab-or-snake...} }`.
type CspFields = {
	documentUri?: string;
	violatedDirective?: string;
	effectiveDirective?: string;
	blockedUri?: string;
};

function pick(source: Record<string, unknown>): CspFields {
	const get = (...keys: string[]) => {
		for (const key of keys) {
			const value = source[key];
			if (typeof value === "string" && value) return value;
		}
		return undefined;
	};
	return {
		documentUri: get("document-uri", "documentURL", "documentUri"),
		violatedDirective: get("violated-directive", "violatedDirective"),
		effectiveDirective: get("effective-directive", "effectiveDirective"),
		blockedUri: get("blocked-uri", "blockedURL", "blockedUri"),
	};
}

function extractReports(parsed: unknown): CspFields[] {
	if (Array.isArray(parsed)) {
		// Reporting API: [{ type: "csp-violation", body: {...} }, …]
		return parsed
			.filter(
				(entry): entry is { body: Record<string, unknown> } =>
					typeof entry === "object" && entry !== null && "body" in entry,
			)
			.map((entry) => pick(entry.body));
	}
	if (typeof parsed === "object" && parsed !== null && "csp-report" in parsed) {
		// Legacy report-uri: { "csp-report": {...} }
		const report = (parsed as { "csp-report": unknown })["csp-report"];
		if (typeof report === "object" && report !== null) {
			return [pick(report as Record<string, unknown>)];
		}
	}
	return [];
}

export async function POST(request: Request) {
	try {
		const contentLength = Number(request.headers.get("content-length") ?? "0");
		if (contentLength > MAX_BODY_BYTES) {
			return new NextResponse(null, { status: 204, headers: NO_CONTENT_HEADERS });
		}
		const raw = await request.text();
		if (raw.length > 0 && raw.length <= MAX_BODY_BYTES) {
			for (const report of extractReports(JSON.parse(raw))) {
				// biome-ignore lint/suspicious/noConsole: CSP violation summary for production security ops.
				console.warn("[csp-report]", {
					documentUri: report.documentUri,
					violatedDirective: report.violatedDirective ?? report.effectiveDirective,
					blockedUri: report.blockedUri,
				});
			}
		}
	} catch {
		// A malformed body is not worth a 4xx — the browser fired this, not a user; just swallow it.
	}
	return new NextResponse(null, { status: 204, headers: NO_CONTENT_HEADERS });
}
