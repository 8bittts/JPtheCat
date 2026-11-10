import { consumeRateLimit } from "@/lib/analytics/rate-limit";
import { notifySupportReport } from "@/lib/email/support-report";
import { cleanString, EMAIL_PATTERN, jsonResponse } from "@/lib/http/api-response";

const SUPPORT_REPORT_THROTTLE_WINDOW_SECONDS = 60;
const MIN_REPORT_LENGTH = 80;
const MAX_REPORT_LENGTH = 20_000;
const MAX_MESSAGE_LENGTH = 4_000;
const MAX_APP_VERSION_LENGTH = 80;

type Payload = {
	contact_email?: unknown;
	message?: unknown;
	report?: unknown;
	app_version?: unknown;
};

function clientIp(request: Request): string | null {
	const first = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
	return first || null;
}

function cleanEmail(value: unknown): string | null {
	const email = cleanString(value, 254)?.toLowerCase() ?? null;
	return email && EMAIL_PATTERN.test(email) ? email : null;
}

export async function POST(request: Request) {
	const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
	if (
		!contentType
			.split(";")
			.map((part) => part.trim())
			.includes("application/json")
	) {
		return jsonResponse({ error: "UNSUPPORTED_MEDIA_TYPE" }, { status: 415 });
	}

	const { allowed } = await consumeRateLimit(
		"support-report",
		clientIp(request),
		SUPPORT_REPORT_THROTTLE_WINDOW_SECONDS,
	);
	if (!allowed) {
		return jsonResponse({ error: "RATE_LIMITED" }, { status: 429 });
	}

	let payload: Payload;
	try {
		payload = (await request.json()) as Payload;
	} catch {
		return jsonResponse({ error: "INVALID_JSON" }, { status: 400 });
	}

	const report = cleanString(payload.report, MAX_REPORT_LENGTH);
	const providedEmail = cleanString(payload.contact_email, 254);
	const contactEmail = cleanEmail(payload.contact_email);
	if (
		!report ||
		report.length < MIN_REPORT_LENGTH ||
		!report.startsWith("JP the Cat support report") ||
		(providedEmail && !contactEmail)
	) {
		return jsonResponse({ error: "INVALID_INPUT" }, { status: 400 });
	}

	await notifySupportReport({
		appVersion: cleanString(payload.app_version, MAX_APP_VERSION_LENGTH),
		contactEmail,
		message: cleanString(payload.message, MAX_MESSAGE_LENGTH),
		receivedAtIso: new Date().toISOString(),
		report,
	});
	return jsonResponse({ ok: true });
}
