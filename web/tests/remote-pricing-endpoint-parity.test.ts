import { describe, expect, it } from "bun:test";

// [CRITICAL] Drift guard: `web/public/stable/pricing-v1.json` is the remote pricing table the Mac app
// conditionally GETs (served at https://jpthecat.com/stable/pricing-v1.json, beside the Sparkle appcast).
// `RemotePricingStore` merges it OVER the bundled defaults, so any drift here would silently reprice
// real usage. It must stay a verbatim mirror of the shipped bundled table — regenerate by copying
// `mac/Sources/JPtheCatCore/Resources/pricing-default.json`, never by hand-editing this file.
describe("remote pricing endpoint parity", () => {
	it("is byte-identical to the shipped mac pricing-default.json", async () => {
		const macText = await Bun.file(
			"../mac/Sources/JPtheCatCore/Resources/pricing-default.json",
		).text();
		const endpointText = await Bun.file("public/stable/pricing-v1.json").text();
		expect(endpointText).toBe(macText);
	});

	it("decodes to the {models:{…}} shape RemotePricingStore expects", async () => {
		const parsed = JSON.parse(await Bun.file("public/stable/pricing-v1.json").text()) as {
			models?: Record<string, unknown>;
			pricing_revision?: number;
		};
		expect(parsed.models).toBeDefined();
		expect(parsed.pricing_revision).toBe(2);
		expect(Object.keys(parsed.models ?? {}).length).toBeGreaterThan(0);
	});
});

// Old apps cannot negotiate context thresholds; their feed stays byte-identical to v1.125.
// This digest was also checked against the production response before deployment.
it("preserves the feed consumed by installed legacy apps", async () => {
	const legacy = await Bun.file("public/stable/pricing.json").arrayBuffer();
	expect(new Bun.CryptoHasher("sha256").update(legacy).digest("hex")).toBe(
		"2ee20713d7a73c62473dbdebb5e2e650a6977c820adce06cd82bfbe7eaa31f54",
	);
});
