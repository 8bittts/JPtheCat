import { describe, expect, it } from "bun:test";
import { formatEmailTimestamp } from "@/emails/format-timestamp";
import { shortenUserAgent } from "@/lib/analytics/growth-source-downloads";

describe("owner digest copy", () => {
	it("stamps owner mail in Pacific time with the PST/PDT label", () => {
		expect(formatEmailTimestamp("2026-11-06T04:00:00.000Z")).toBe("Nov 5 · 8:00pm PST");
		expect(formatEmailTimestamp("2026-07-04T03:00:00.000Z")).toBe("Jul 3 · 8:00pm PDT");
	});

	it("never cuts a bot user agent mid-token", () => {
		const ua =
			"Mozilla/5.0 (compatible; SERankingBacklinksBot/1.0; +https://seranking.com/backlinks-crawler)";
		const label = shortenUserAgent(ua);
		expect(label.endsWith("…")).toBe(true);
		expect(label).not.toContain("seranking.c…");
		expect(label.length).toBeLessThanOrEqual(73);
		expect(shortenUserAgent("curl/8.7.1")).toBe("curl/8.7.1");
	});
});
