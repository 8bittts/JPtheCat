import { describe, expect, it } from "bun:test";
import { GET, POST } from "@/app/api/support-report/route";

describe("retired support-report endpoint", () => {
	it("answers 410 so shipped apps never mistake a report for sent", async () => {
		for (const handler of [POST, GET]) {
			const response = handler();
			expect(response.status).toBe(410);
			expect(response.headers.get("Cache-Control")).toBe("no-store");
			expect(await response.json()).toEqual({
				error: "SUPPORT_REPORT_RETIRED",
				contact: "support@jpthecat.com",
			});
		}
	});

	it("stores nothing and sends no email", async () => {
		const source = await Bun.file(
			new URL("../app/api/support-report/route.ts", import.meta.url),
		).text();
		expect(source).not.toMatch(/fetch\(|sendEmail|resend|after\(/i);
	});
});
