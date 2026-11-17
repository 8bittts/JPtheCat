import { describe, expect, it } from "bun:test";
import { GET, resolveDownloadRedirectTarget } from "@/app/download/route";

const RELEASE_URL =
	"https://github.com/8bittts/JPtheCat/releases/download/v0.001/JPtheCat-0.001.dmg";

describe("download manifest guardrails", () => {
	// Every other case in this block feeds a hand-written object, so a shape break in the manifest we
	// actually ship 404s /download for every visitor with the whole suite green. This is the one case
	// that validates the real file the route resolves its redirect target from at module load.
	it("accepts the manifest actually shipped in public/stable", async () => {
		const manifest = await Bun.file("public/stable/version.json").json();
		expect(resolveDownloadRedirectTarget(manifest)).toBeTruthy();
	});

	it("accepts a complete GitHub release manifest", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: RELEASE_URL,
				sha256: "a".repeat(64),
				releaseDate: "2026-07-01",
			}),
		).toBe(RELEASE_URL);
	});

	it("rejects the retired Supabase release hosts", () => {
		for (const url of [
			"https://api.jpthecat.com/storage/v1/object/public/releases/JPtheCat-0.001.dmg",
			"https://duqpnrpzadrxqdbspjft.supabase.co/storage/v1/object/public/releases/JPtheCat-0.001.dmg",
		]) {
			expect(
				resolveDownloadRedirectTarget({ url, sha256: "a".repeat(64), releaseDate: "2026-07-01" }),
			).toBeNull();
		}
	});

	it("rejects another repository's release assets", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: "https://github.com/someone/JPtheCat/releases/download/v0.001/JPtheCat-0.001.dmg",
				sha256: "a".repeat(64),
				releaseDate: "2026-07-01",
			}),
		).toBeNull();
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

	it("rejects release DMGs that are not JPtheCat release artifacts", () => {
		expect(
			resolveDownloadRedirectTarget({
				url: "https://github.com/8bittts/JPtheCat/releases/download/v0.001/OtherApp-0.001.dmg",
				sha256: "a".repeat(64),
				releaseDate: "2026-07-01",
			}),
		).toBeNull();
	});

	it("the download route records nothing and sends no email", async () => {
		const source = await Bun.file(new URL("../app/download/route.ts", import.meta.url)).text();
		expect(source).not.toContain("after(");
		expect(source).not.toContain("recordDownload");
		expect(source).not.toContain("sendOwnerNotification");
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
