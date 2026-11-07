import { describe, expect, it } from "bun:test";
import { enrichDownloadNetworkIntel } from "@/lib/analytics/download-network-intel";
import { createDownloadNotificationEvent } from "@/lib/email/download-notification";

const RELEASE_URL = "https://api.jpthecat.com/storage/v1/object/public/releases/JPtheCat-0.058.dmg";

describe("download network intelligence", () => {
	it("fails closed to the original event when no client IP is available", async () => {
		const request = new Request("https://jpthecat.com/download?source=pricing");
		const event = createDownloadNotificationEvent({ releaseUrl: RELEASE_URL, request });

		expect(await enrichDownloadNetworkIntel(event)).toBe(event);
	});

	it("adds ASN and hosting/anonymizer flags from ipapi.is without lat/long", async () => {
		const request = new Request("https://jpthecat.com/download?source=pricing", {
			headers: { "x-forwarded-for": "203.0.113.7" },
		});
		const event = createDownloadNotificationEvent({ releaseUrl: RELEASE_URL, request });
		const fetchCalls: string[] = [];
		const fetchImpl = async (url: RequestInfo | URL) => {
			fetchCalls.push(String(url));
			return Response.json({
				asn: { asn: 24940, org: "Hetzner Online GmbH" },
				is_datacenter: true,
				is_proxy: false,
				is_tor: false,
				is_vpn: false,
				latitude: "50.475",
				longitude: "12.365",
			});
		};

		const enriched = await enrichDownloadNetworkIntel(event, fetchImpl as typeof fetch);

		expect(fetchCalls[0]).toContain("https://api.ipapi.is/?q=203.0.113.7");
		expect(enriched.network).toEqual({
			asn: "AS24940",
			isAnonymous: false,
			isHosting: true,
			org: "Hetzner Online GmbH",
		});
		expect(JSON.stringify(enriched)).not.toContain("50.475");
		expect(JSON.stringify(enriched)).not.toContain("12.365");
	});

	it("reads the keyless free-tier shape and leaves absent flags null, never false", async () => {
		// Live ipapi.is response without IPAPI_IS_KEY since 2026-09-01: `asn` is one string, `company`
		// is a name, and no `is_*` flag is present. A `false` here would read as "not hosting" and
		// silently re-open the datacenter hole the growth readers filter on.
		const request = new Request("https://jpthecat.com/download?source=pricing", {
			headers: { "x-forwarded-for": "203.0.113.7" },
		});
		const event = createDownloadNotificationEvent({ releaseUrl: RELEASE_URL, request });
		const fetchCalls: string[] = [];
		const fetchImpl = async (url: RequestInfo | URL) => {
			fetchCalls.push(String(url));
			return Response.json({
				asn: "AS12322 Free SAS",
				city: "Paris",
				company: "Free SAS",
				docs: "https://ipapi.is/free-tier.html?ref=api",
				ip: "203.0.113.7",
				is_bogon: false,
				lat: 48.85,
				lon: 2.35,
			});
		};

		const enriched = await enrichDownloadNetworkIntel(event, fetchImpl as typeof fetch);

		expect(fetchCalls[0]).toContain("q=203.0.113.7");
		expect(enriched.network).toEqual({
			asn: "AS12322",
			isAnonymous: null,
			isHosting: null,
			org: "Free SAS",
		});
		expect(JSON.stringify(enriched)).not.toContain("48.85");
	});
});
