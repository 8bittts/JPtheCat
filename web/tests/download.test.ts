import { describe, expect, it } from "bun:test";
import { GET, resolveDownloadRedirectTarget, runDownloadSideEffects } from "@/app/download/route";
import { buildDownloadRecord } from "@/lib/analytics/downloads-store";
import { createDownloadNotificationEvent } from "@/lib/email/download-notification";

const RELEASE_URL = "https://api.jpthecat.com/storage/v1/object/public/releases/JPtheCat-0.001.dmg";
const LEGACY_RELEASE_URL =
	"https://duqpnrpzadrxqdbspjft.supabase.co/storage/v1/object/public/releases/JPtheCat-0.001.dmg";
const HUMAN_USER_AGENT =
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15";
const BOT_USER_AGENT = "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)";

function downloadEventForUserAgent(userAgent: string) {
	const request = new Request("https://jpthecat.com/download?source=pricing", {
		headers: {
			"user-agent": userAgent,
			"x-forwarded-for": "40.77.167.159",
		},
	});
	const event = createDownloadNotificationEvent({ releaseUrl: RELEASE_URL, request });
	return { event, record: buildDownloadRecord(event, request) };
}

describe("download manifest guardrails", () => {
	// Every other case in this block feeds a hand-written object, so a shape break in the manifest we
	// actually ship 404s /download for every visitor with the whole suite green. This is the one case
	// that validates the real file the route resolves its redirect target from at module load.
	it("accepts the manifest actually shipped in public/stable", async () => {
		const manifest = await Bun.file("public/stable/version.json").json();
		expect(resolveDownloadRedirectTarget(manifest)).toBeTruthy();
	});

	it("accepts a complete Supabase release manifest", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: RELEASE_URL,
				sha256: "a".repeat(64),
				releaseDate: "2026-07-01",
			}),
		).toBe(RELEASE_URL);
	});

	it("keeps the Supabase project host as a rollback fallback", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: LEGACY_RELEASE_URL,
				sha256: "a".repeat(64),
				releaseDate: "2026-07-01",
			}),
		).toBe(LEGACY_RELEASE_URL);
	});

	it("fails closed for placeholder manifests", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: RELEASE_URL,
				sha256: "",
				releaseDate: "",
			}),
		).toBeNull();
	});

	it("rejects non-release or non-DMG URLs", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: "https://example.com/JPtheCat-0.001.dmg",
				sha256: "a".repeat(64),
				releaseDate: "2026-07-01",
			}),
		).toBeNull();
	});

	it("rejects trusted-bucket DMGs that are not JPtheCat release artifacts", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: "https://api.jpthecat.com/storage/v1/object/public/releases/OtherApp-0.001.dmg",
				sha256: "a".repeat(64),
				releaseDate: "2026-07-01",
			}),
		).toBeNull();
	});

	it("records bot and human downloads alike and never emails the owner per download", async () => {
		for (const userAgent of [BOT_USER_AGENT, HUMAN_USER_AGENT]) {
			const { event, record } = downloadEventForUserAgent(userAgent);
			const records: unknown[] = [];

			await runDownloadSideEffects(event, record, {
				enrichDownloadNetworkIntel: async (emailEvent) => emailEvent,
				recordDownload: async (downloadRecord) => {
					records.push(downloadRecord);
				},
			});

			expect(records).toEqual([record]);
		}
	});

	it("the download route no longer imports any owner email sender", async () => {
		const source = await Bun.file(new URL("../app/download/route.ts", import.meta.url)).text();
		expect(source).not.toContain("notifyDownload");
		expect(source).not.toContain("sendOwnerNotification");
		expect(source).toContain("recordDownload");
	});

	it("enriches the request before recording the row", async () => {
		const request = new Request("https://jpthecat.com/download?source=pricing", {
			headers: {
				"user-agent": HUMAN_USER_AGENT,
				"x-forwarded-for": "203.0.113.7",
				"x-vercel-ip-city": "Falkenstein",
				"x-vercel-ip-country": "DE",
				"x-vercel-ip-country-region": "SN",
				"x-vercel-ip-postal-code": "08223",
				"x-vercel-ip-timezone": "Europe/Berlin",
			},
		});
		const event = createDownloadNotificationEvent({ releaseUrl: RELEASE_URL, request });
		const records: unknown[] = [];

		await runDownloadSideEffects(event, request, {
			enrichDownloadNetworkIntel: async (emailEvent) => ({
				...emailEvent,
				network: {
					asn: "AS24940",
					isAnonymous: false,
					isHosting: true,
					org: "Hetzner Online GmbH",
				},
			}),
			recordDownload: async (downloadRecord) => {
				records.push(downloadRecord);
			},
		});

		expect(records).toEqual([
			expect.objectContaining({
				networkAsn: "AS24940",
				networkIsAnonymous: false,
				networkIsHosting: true,
				networkOrg: "Hetzner Online GmbH",
				postalCode: null,
			}),
		]);
	});

	it("does not treat router or browser prefetches as real downloads", async () => {
		const prefetchHeaders: Array<Record<string, string>> = [
			{ "next-router-prefetch": "1" },
			{ purpose: "prefetch" },
			{ "sec-purpose": "prefetch" },
			{ "sec-purpose": "prefetch;prerender" },
		];
		for (const headers of prefetchHeaders) {
			const response = await GET(
				new Request("https://jpthecat.com/download?source=hero", { headers }) as never,
			);

			expect(response.status).toBe(204);
			expect(response.headers.get("Location")).toBeNull();
			expect(response.headers.get("Cache-Control")).toBe("no-store");
			expect(response.headers.get("X-Robots-Tag")).toContain("noindex");
		}
	});
});
