import { NextResponse } from "next/server";
import { API_NOINDEX_HEADER } from "@/lib/http/api-response";

// Retired endpoint. App versions up to 1.160 POST support reports here and treat any 2xx as sent,
// and Next answers a POST to a missing route with a 200 not-found page, so this route must exist to
// return a real failure: those apps then show their "email support@JPtheCat.com directly" hint.
// It stores nothing and sends no email.
function gone() {
	return NextResponse.json(
		{ error: "SUPPORT_REPORT_RETIRED", contact: "support@jpthecat.com" },
		{ status: 410, headers: { "Cache-Control": "no-store", "X-Robots-Tag": API_NOINDEX_HEADER } },
	);
}

export const GET = gone;
export const POST = gone;
