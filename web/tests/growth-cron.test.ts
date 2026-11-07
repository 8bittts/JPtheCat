import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
	GET,
	growthDigestSendIdempotencyKey,
	growthDigestSendSubject,
	resolveGrowthDigestRun,
	runGrowthDigestRequest,
} from "@/app/api/cron/growth-digest/route";
import {
	buildGrowthDigest,
	type GrowthDigestSourceData,
	growthDigestBodyFingerprint,
} from "@/lib/analytics/growth-digest";

describe("growth digest cron", () => {
	it("fails closed without the cron bearer secret", async () => {
		const response = await GET(new Request("https://jpthecat.com/api/cron/growth-digest"));

		expect(response.status).toBe(401);
		expect(await response.json()).toEqual({ error: "UNAUTHORIZED" });
	});

	it("fires at 03:00 and 04:00 UTC so one of the two is always 20:00 in Los Angeles", () => {
		const config = JSON.parse(readFileSync(join(process.cwd(), "vercel.json"), "utf8")) as {
			crons?: Array<{ path: string; schedule: string }>;
		};

		expect(config.crons).toEqual([
			{ path: "/api/cron/growth-digest", schedule: "0 3 * * *" },
			{ path: "/api/cron/growth-digest", schedule: "0 4 * * *" },
		]);
	});

	it("sends only on the firing that is 8pm Pacific, in both PDT and PST", () => {
		const cron = (iso: string) =>
			resolveGrowthDigestRun(
				new Request("https://jpthecat.com/api/cron/growth-digest"),
				new Date(iso),
			);
		// Summer (PDT, UTC-7): 03:00 UTC is 20:00, 04:00 UTC is 21:00.
		expect(cron("2026-07-07T03:00:00.000Z")).toMatchObject({ dateKey: "2026-07-06", due: true });
		expect(cron("2026-07-07T04:00:00.000Z").due).toBe(false);
		// Winter (PST, UTC-8): 03:00 UTC is 19:00, 04:00 UTC is 20:00.
		expect(cron("2026-12-08T03:00:00.000Z").due).toBe(false);
		expect(cron("2026-12-08T04:00:00.000Z")).toMatchObject({ dateKey: "2026-12-07", due: true });
	});

	it("adds the 7-day trend on Pacific Mondays and the 30-day trend on the Pacific 1st", () => {
		const cron = (iso: string) =>
			resolveGrowthDigestRun(
				new Request("https://jpthecat.com/api/cron/growth-digest"),
				new Date(iso),
			).trends;
		expect(cron("2026-07-07T03:00:00.000Z")).toEqual(["weekly"]); // Mon 2026-07-06 PT
		expect(cron("2026-07-02T03:00:00.000Z")).toEqual(["monthly"]); // Wed 2026-07-01 PT
		expect(cron("2026-06-02T03:00:00.000Z")).toEqual(["weekly", "monthly"]); // Mon 2026-06-01 PT
		expect(cron("2026-07-08T03:00:00.000Z")).toEqual([]);
	});

	it("skips without sending outside the 8pm hour", async () => {
		const sends: unknown[] = [];
		const response = await withCronSecret(() =>
			runGrowthDigestRequest(authorized("https://jpthecat.com/api/cron/growth-digest"), {
				buildDigest: buildGrowthDigest,
				loadSourceData: async () => sourceFixture(),
				now: () => new Date("2026-07-07T04:00:00.000Z"),
				sendEmailFn: async (input) => {
					sends.push(input);
					return { data: { id: "x" }, error: null } as never;
				},
			}),
		);
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ due: false, ok: true, sample: false, sent: 0 });
		expect(sends).toEqual([]);
	});

	it("sends one daily report with its trend sections and a dated idempotency key", async () => {
		const sends: Array<{ idempotencyKey?: string; subject: string; text?: string; to?: string }> =
			[];
		const frequencies: string[] = [];
		const response = await withCronSecret(() =>
			runGrowthDigestRequest(authorized("https://jpthecat.com/api/cron/growth-digest"), {
				buildDigest: buildGrowthDigest,
				loadSourceData: async ({ frequency }) => {
					frequencies.push(frequency);
					return sourceFixture();
				},
				now: () => new Date("2026-07-07T03:00:00.000Z"),
				sendEmailFn: async (input) => {
					sends.push(input as never);
					return { data: { id: "x" }, error: null } as never;
				},
			}),
		);
		expect(response.status).toBe(200);
		expect(frequencies).toEqual(["daily", "weekly"]);
		expect(sends).toHaveLength(1);
		expect(sends[0]?.idempotencyKey?.startsWith("growth_digest:daily:2026-07-06:")).toBe(true);
		expect(sends[0]?.subject).toBe("JP the Cat daily report: 3 Mac downloads");
		expect(sends[0]?.text).toContain("TREND: LAST 7 DAYS");
		expect(sends[0]?.to).toBe(TEST_RECIPIENT);
	});

	it("fails closed without loading data when no recipient is configured", async () => {
		const loads: string[] = [];
		const sends: unknown[] = [];
		const response = await withCronSecret(
			() =>
				runGrowthDigestRequest(authorized("https://jpthecat.com/api/cron/growth-digest"), {
					buildDigest: buildGrowthDigest,
					loadSourceData: async ({ frequency }) => {
						loads.push(frequency);
						return sourceFixture();
					},
					now: () => new Date("2026-07-07T03:00:00.000Z"),
					sendEmailFn: async (input) => {
						sends.push(input);
						return { data: { id: "x" }, error: null } as never;
					},
				}),
			{ recipient: null },
		);

		expect(response.status).toBe(503);
		expect((await response.json()).error).toBe("RECIPIENT_NOT_CONFIGURED");
		expect(loads).toEqual([]);
		expect(sends).toEqual([]);
	});

	it("samples skip the clock gate and never reuse the real idempotency key", () => {
		const run = resolveGrowthDigestRun(
			new Request("https://jpthecat.com/api/cron/growth-digest?sample=all&sample_id=prod-preview"),
			new Date("2026-07-04T14:00:00.000Z"),
		);

		expect(run).toEqual({
			dateKey: "2026-07-04",
			due: true,
			sample: true,
			sampleId: "prod-preview",
			trends: ["weekly", "monthly"],
		});
		const rollup = buildGrowthDigest(sourceFixture(), "daily");
		expect(growthDigestSendIdempotencyKey(run, rollup)).toBe(
			`growth_digest_sample:daily:2026-07-04:prod-preview:${growthDigestBodyFingerprint(rollup)}`,
		);
		expect(growthDigestSendSubject("JP the Cat daily report", run)).toBe(
			"[Sample] JP the Cat daily report",
		);
	});

	it("rekeys when the report body moves, so Resend cannot reject a same-day re-run", () => {
		// Production 503 on 2026-09-21T14:00Z: the key was frequency+date only, so a
		// same-day re-run reused it while the rollup had moved, and Resend refused the send.
		const run = resolveGrowthDigestRun(
			new Request("https://jpthecat.com/api/cron/growth-digest"),
			new Date("2026-07-07T03:00:00.000Z"),
		);
		const base = sourceFixture();
		const first = buildGrowthDigest(base, "daily");
		const rebuiltIdentical = buildGrowthDigest(sourceFixture(), "daily");
		const bodyMoved = buildGrowthDigest(
			{ ...base, headline: { ...base.headline, humanDownloads: base.headline.humanDownloads + 1 } },
			"daily",
		);

		expect(growthDigestSendIdempotencyKey(run, first)).toBe(
			growthDigestSendIdempotencyKey(run, rebuiltIdentical),
		);
		expect(growthDigestSendIdempotencyKey(run, first)).not.toBe(
			growthDigestSendIdempotencyKey(run, bodyMoved),
		);
	});

	it("fails closed when the send is skipped or errors softly", async () => {
		const response = await withCronSecret(() =>
			runGrowthDigestRequest(
				authorized("https://jpthecat.com/api/cron/growth-digest?sample&sample_id=soft-fail"),
				{
					buildDigest: buildGrowthDigest,
					loadSourceData: async () => sourceFixture(),
					now: () => new Date("2026-07-08T14:00:00.000Z"),
					sendEmailFn: async () => null,
				},
			),
		);

		expect(response.status).toBe(503);
		expect(await response.json()).toEqual({
			dateKey: "2026-07-08",
			due: true,
			error: "RESEND_NOT_CONFIGURED",
			ok: false,
			sample: true,
			sampleId: "soft-fail",
			sent: 0,
			trends: [],
		});
	});
});

function authorized(url: string) {
	return new Request(url, { headers: { authorization: "Bearer test-secret" } });
}

const TEST_RECIPIENT = "owner@example.test";
const RECIPIENT_ENV = ["GROWTH_DIGEST_TO", "DOWNLOAD_NOTIFICATION_TO"] as const;

async function withCronSecret<T>(
	run: () => Promise<T>,
	{ recipient = TEST_RECIPIENT }: { recipient?: string | null } = {},
): Promise<T> {
	const previous = Object.fromEntries(
		["CRON_SECRET", ...RECIPIENT_ENV].map((name) => [name, process.env[name]]),
	);
	process.env.CRON_SECRET = "test-secret";
	for (const name of RECIPIENT_ENV) delete process.env[name];
	if (recipient) process.env.GROWTH_DIGEST_TO = recipient;
	try {
		return await run();
	} finally {
		for (const [name, value] of Object.entries(previous)) {
			if (value === undefined) delete process.env[name];
			else process.env[name] = value;
		}
	}
}

function sourceFixture(): GrowthDigestSourceData {
	return {
		generatedAt: "2026-07-06T14:00:00.000Z",
		windowDays: 1,
		headline: {
			allHits: 13,
			botUaHits: 9,
			humanDownloads: 4,
			macHumanDownloads: 3,
			networkFlaggable: 4,
			networkFlagged: 4,
			uniqueHumanIps: 1,
		},
		macRolling: { current: 3, deltaPct: null, prior: 0 },
		rolling: { current: 4, deltaPct: null, prior: 0 },
		bySource: [{ count: 3, label: "pricing" }],
		byVersion: [{ count: 4, label: "0.062" }],
		byLocation: [{ count: 4, label: "San Francisco, CA, US" }],
		botUserAgents: [{ count: 6, label: "bingbot/2.0" }],
		vercel: {
			downloadCtaClicks: 7,
			libraryDownloadCtaClicks: 2,
			pageViews: 44,
			status: "ok",
			topCountries: [{ count: 30, label: "US" }],
			topPages: [{ count: 18, label: "/" }],
			topReferrers: [{ count: 5, label: "news.ycombinator.com" }],
			visitors: 20,
			repoLinkClicks: 3,
		},
		github: {
			codeContributors: 0,
			forks: 0,
			mergedPullRequests: 0,
			newIssues: 0,
			newPullRequests: 0,
			openIssues: 0,
			openPullRequests: 0,
			priorities: [],
			stars: 0,
			status: "ok",
			windowContributors: 0,
		},
		searchConsole: {
			clicks: 0,
			impressions: 0,
			position: null,
			status: "ok",
			topCountries: [{ count: 0, label: "usa" }],
			topPages: [{ clicks: 0, impressions: 0, label: "https://jpthecat.com/", position: 12.1 }],
			topQueries: [],
		},
	};
}
