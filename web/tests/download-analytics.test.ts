import { describe, expect, it } from "bun:test";
import { isBotUserAgent, isMacUserAgent } from "@/lib/analytics/download-bot";
import { buildDownloadRecord } from "@/lib/analytics/downloads-store";
import { createDownloadNotificationEvent } from "@/lib/email/download-notification";

const RELEASE_URL = "https://api.jpthecat.com/storage/v1/object/public/releases/JPtheCat-0.062.dmg";

function makeRequest(
	source: string,
	{
		city,
		country,
		ip,
		postalCode,
		region,
		timezone,
		ua,
	}: {
		ua?: string;
		ip?: string;
		country?: string;
		city?: string;
		region?: string;
		postalCode?: string;
		timezone?: string;
	} = {},
) {
	const headers = new Headers();
	if (ua) headers.set("user-agent", ua);
	if (ip) headers.set("x-forwarded-for", ip);
	if (country) headers.set("x-vercel-ip-country", country);
	if (city) headers.set("x-vercel-ip-city", city);
	if (region) headers.set("x-vercel-ip-country-region", region);
	if (postalCode) headers.set("x-vercel-ip-postal-code", postalCode);
	if (timezone) headers.set("x-vercel-ip-timezone", timezone);
	return new Request(`https://jpthecat.com/download?source=${source}`, { headers });
}

describe("download bot classifier", () => {
	it("flags known crawlers and generic HTTP clients", () => {
		expect(isBotUserAgent("Mozilla/5.0 (compatible; Dataprovider.com)")).toBe(true);
		expect(isBotUserAgent("curl/8.7.1")).toBe(true);
		expect(isBotUserAgent("python-requests/2.31.0")).toBe(true);
		expect(isBotUserAgent("Googlebot/2.1")).toBe(true);
	});

	it("treats an empty or missing user-agent as a bot", () => {
		expect(isBotUserAgent("")).toBe(true);
		expect(isBotUserAgent(null)).toBe(true);
		expect(isBotUserAgent(undefined)).toBe(true);
	});

	it("passes a real macOS Safari user-agent as human", () => {
		const safari =
			"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15";
		expect(isBotUserAgent(safari)).toBe(false);
	});

	it("flags the self-named scanners and the owner smoke UA that passed the list in Oct 2026", () => {
		expect(isBotUserAgent("GrowthScan/0.1 (+contact in repo)")).toBe(true);
		expect(isBotUserAgent("msh-pdfmin/1")).toBe(true);
		expect(isBotUserAgent("NumeosScoutObservatory/1.1.1 (+public-readonly-card)")).toBe(true);
		expect(isBotUserAgent("Mozilla/5.0 (Macintosh) update-projs-smoke")).toBe(true);
	});

	it("classifies the frozen macOS token as the only platform that can open the DMG", () => {
		expect(
			isMacUserAgent(
				"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
			),
		).toBe(true);
		expect(
			isMacUserAgent(
				"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
			),
		).toBe(false);
		expect(isMacUserAgent("Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36")).toBe(
			false,
		);
		expect(isMacUserAgent("")).toBe(false);
		expect(isMacUserAgent(null)).toBe(false);
	});
});

describe("download record builder", () => {
	it("captures source, version, geo, IP and bot flag", () => {
		const request = makeRequest("pricing", {
			ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15",
			ip: "203.0.113.7, 10.0.0.1",
			city: "San%20Francisco",
			country: "US",
			postalCode: "94107",
			region: "CA",
			timezone: "America/Los_Angeles",
		});
		const event = {
			...createDownloadNotificationEvent({ releaseUrl: RELEASE_URL, request }),
			network: {
				asn: "AS7922",
				isAnonymous: false,
				isHosting: false,
				org: "Comcast Cable Communications, LLC",
			},
		};
		const record = buildDownloadRecord(event, request);

		expect(event.geo).toEqual({
			city: "San Francisco",
			country: "US",
			postalCode: "94107",
			region: "CA",
			timezone: "America/Los_Angeles",
		});
		expect(event.network).toEqual({
			asn: "AS7922",
			isAnonymous: false,
			isHosting: false,
			org: "Comcast Cable Communications, LLC",
		});
		expect(record.version).toBe("0.062");
		expect(record.source).toBe("pricing");
		expect(record.ip).toBe("203.0.113.7");
		expect(record.city).toBe("San Francisco");
		expect(record.country).toBe("US");
		expect(record.postalCode).toBeNull();
		expect(record.region).toBe("CA");
		expect(record.timezone).toBe("America/Los_Angeles");
		expect(record.networkAsn).toBe("AS7922");
		expect(record.networkIsAnonymous).toBe(false);
		expect(record.networkIsHosting).toBe(false);
		expect(record.isMac).toBe(true);
		expect(record.networkOrg).toBe("Comcast Cable Communications, LLC");
		expect(record.isBot).toBe(false);
	});

	it("marks a crawler download as a bot", () => {
		const request = makeRequest("pricing", { ua: "Mozilla/5.0 (compatible; Dataprovider.com)" });
		const event = createDownloadNotificationEvent({ releaseUrl: RELEASE_URL, request });
		expect(buildDownloadRecord(event, request).isBot).toBe(true);
	});
});
