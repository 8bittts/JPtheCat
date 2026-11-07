import { GrowthDigestEmail, GrowthDigestPlainText } from "@/emails/growth-digest";
import {
	buildGrowthDigest,
	buildGrowthTrend,
	type GrowthDigest,
	type GrowthDigestFrequency,
	growthDigestBodyFingerprint,
	growthDigestIdempotencyKey,
} from "@/lib/analytics/growth-digest";
import { loadGrowthDigestSourceData } from "@/lib/analytics/growth-digest-data";
import { isRollupHour, rollupDateKey, rollupTrendDue } from "@/lib/analytics/rollup-schedule";
import { isCronRequestAuthorized } from "@/lib/email/cron-auth";
import { DEFAULT_DOWNLOAD_NOTIFICATION_FROM } from "@/lib/email/download-notification";
import { sendEmail } from "@/lib/email/send-helper";

export const runtime = "nodejs";
export const maxDuration = 300;

type GrowthDigestDeps = {
	buildDigest: typeof buildGrowthDigest;
	loadSourceData: typeof loadGrowthDigestSourceData;
	now: () => Date;
	sendEmailFn: typeof sendEmail;
};

const DEFAULT_DEPS: GrowthDigestDeps = {
	buildDigest: buildGrowthDigest,
	loadSourceData: loadGrowthDigestSourceData,
	now: () => new Date(),
	sendEmailFn: sendEmail,
};

/**
 * One owner report per day. The cron fires twice (03:00 and 04:00 UTC) and only the firing that is
 * 20:00 in Los Angeles sends; `?sample` skips the clock gate and prefixes the subject. Mondays add a
 * last-7-days trend and the 1st a last-30-days trend, so the old weekly/monthly digests live inside it.
 */
export type GrowthDigestRun = {
	dateKey: string;
	due: boolean;
	sample: boolean;
	sampleId?: string;
	trends: GrowthDigestFrequency[];
};

function growthDigestRecipient() {
	return process.env.GROWTH_DIGEST_TO?.trim() || process.env.DOWNLOAD_NOTIFICATION_TO?.trim();
}

function cleanSampleId(value: string | null, dateKey: string) {
	const cleaned = value
		?.trim()
		.replace(/[^A-Za-z0-9_-]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.slice(0, 64);
	return cleaned || dateKey;
}

function trendsFor(now: Date, sample: string | null): GrowthDigestFrequency[] {
	if (sample === "all") return ["weekly", "monthly"];
	const due = rollupTrendDue(now);
	return [
		...(due.weekly ? (["weekly"] as const) : []),
		...(due.monthly ? (["monthly"] as const) : []),
	];
}

export function resolveGrowthDigestRun(request: Request, now = new Date()): GrowthDigestRun {
	const dateKey = rollupDateKey(now);
	const url = new URL(request.url);
	const sample = url.searchParams.get("sample");
	if (sample !== null) {
		return {
			dateKey,
			due: true,
			sample: true,
			sampleId: cleanSampleId(url.searchParams.get("sample_id"), dateKey),
			trends: trendsFor(now, sample),
		};
	}
	return { dateKey, due: isRollupHour(now), sample: false, trends: trendsFor(now, null) };
}

export function growthDigestSendIdempotencyKey(run: GrowthDigestRun, rollup: GrowthDigest) {
	const bodyFingerprint = growthDigestBodyFingerprint(rollup);
	if (run.sample) {
		return `growth_digest_sample:daily:${run.dateKey}:${run.sampleId}:${bodyFingerprint}`;
	}
	return growthDigestIdempotencyKey("daily", run.dateKey, bodyFingerprint);
}

export function growthDigestSendSubject(subject: string, run: GrowthDigestRun) {
	return run.sample ? `[Sample] ${subject}` : subject;
}

async function buildRollup(run: GrowthDigestRun, now: Date, deps: GrowthDigestDeps) {
	const [daily, ...trendData] = await Promise.all([
		deps.loadSourceData({ frequency: "daily", now }),
		...run.trends.map((frequency) => deps.loadSourceData({ frequency, now })),
	]);
	const trends = run.trends.map((frequency, index) => {
		const data = trendData[index];
		if (!data) throw new Error(`TREND_DATA_MISSING:${frequency}`);
		return buildGrowthTrend(data, frequency);
	});
	return deps.buildDigest(daily, "daily", trends);
}

async function sendRollup(run: GrowthDigestRun, now: Date, deps: GrowthDigestDeps) {
	const to = growthDigestRecipient();
	if (!to) return { error: "RECIPIENT_NOT_CONFIGURED", sent: false };
	const rollup = await buildRollup(run, now, deps);
	const idempotencyKey = growthDigestSendIdempotencyKey(run, rollup);
	const sendResult = await deps.sendEmailFn({
		entityRefId: idempotencyKey,
		from: process.env.RESEND_FROM_EMAIL?.trim() || DEFAULT_DOWNLOAD_NOTIFICATION_FROM,
		idempotencyKey,
		react: GrowthDigestEmail({ rollup }),
		subject: growthDigestSendSubject(rollup.subject, run),
		text: GrowthDigestPlainText({ rollup }),
		to,
	});
	if (!sendResult) return { error: "RESEND_NOT_CONFIGURED", sent: false };
	if (sendResult.error) return { error: sendResult.error.message ?? "SEND_FAILED", sent: false };
	return { sent: true };
}

export async function runGrowthDigestRequest(
	request: Request,
	deps: GrowthDigestDeps = DEFAULT_DEPS,
) {
	if (!isCronRequestAuthorized(request)) {
		return Response.json({ error: "UNAUTHORIZED" }, { status: 401 });
	}

	const now = deps.now();
	const run = resolveGrowthDigestRun(request, now);
	if (!run.due) {
		return Response.json({ due: false, ok: true, sample: false, sent: 0 }, { status: 200 });
	}

	let result: { error?: string; sent: boolean };
	try {
		result = await sendRollup(run, now, deps);
	} catch (error) {
		result = {
			error: error instanceof Error ? error.message : "UNKNOWN_SEND_ERROR",
			sent: false,
		};
	}

	const responseBody = {
		dateKey: run.dateKey,
		due: true,
		ok: result.sent,
		...(result.error ? { error: result.error } : {}),
		sample: run.sample,
		...(run.sample ? { sampleId: run.sampleId } : {}),
		sent: result.sent ? 1 : 0,
		trends: run.trends,
	};
	if (!result.sent) {
		// biome-ignore lint/suspicious/noConsole: Aggregate cron failure summary for production ops verification.
		console.error("[daily-report] send failed", responseBody);
		return Response.json(responseBody, { status: 503 });
	}
	// biome-ignore lint/suspicious/noConsole: Aggregate cron send result for production ops verification.
	console.info("[daily-report] send complete", responseBody);
	return Response.json(responseBody, { status: 200 });
}

export async function GET(request: Request) {
	return runGrowthDigestRequest(request);
}
