import { expect, test } from "bun:test";
import { providerLeaf } from "@/lib/library/content/provider";
import { PROVIDERS } from "@/lib/site";
import config from "../next.config";

test("native/library catalog has one Grok service while legacy routes redirect permanently", async () => {
	expect(
		PROVIDERS.filter((p) => ["grok", "grok_bot", "cursor"].includes(p.id)).map((p) => p.id),
	).toEqual(["grok"]);
	const redirects = await config.redirects?.();
	for (const legacy of ["cursor", "grok-bot"]) {
		for (const [prefix, destination] of [
			["", "/library/track/grok"],
			["/track", "/library/track/grok"],
			["/limits", "/library/limits/grok"],
		]) {
			expect(redirects?.find((r) => r.source === `/library${prefix}/${legacy}`)).toEqual({
				source: `/library${prefix}/${legacy}`,
				destination,
				permanent: true,
			});
		}
	}
});

test("Grok library content discloses local notional accounting and optional credential-only API use", () => {
	const grok = PROVIDERS.find((p) => p.id === "grok");
	if (!grok) throw new Error("Missing Grok");
	const content = JSON.stringify(providerLeaf(grok));
	for (const word of ["Cursor", "Grok Bot", "notional", "api2.cursor.sh", "opt-in"])
		expect(content).toContain(word);
	expect(content).not.toContain("separate provider");
});
