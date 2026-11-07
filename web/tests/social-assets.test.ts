import { describe, expect, it } from "bun:test";
import sharp from "sharp";
import { SITE } from "@/lib/site";

const OG_WIDTH = 1200;
const OG_HEIGHT = 630;

describe("social / SEO image assets", () => {
	it("ships og.jpg at the canonical Open Graph dimensions", async () => {
		expect(SITE.ogImage).toBe("/og.jpg");
		const path = `public${SITE.ogImage}`;
		const file = Bun.file(path);
		expect(await file.exists()).toBe(true);
		const meta = await sharp(Buffer.from(await file.arrayBuffer())).metadata();
		expect(meta.width).toBe(OG_WIDTH);
		expect(meta.height).toBe(OG_HEIGHT);
	});

	it("keeps PWA icons present and square", async () => {
		for (const [path, size] of [
			["public/icon-192.png", 192],
			["public/icon-512.png", 512],
			["public/icon-maskable-512.png", 512],
			["app/icon.png", 512],
			["app/apple-icon.png", 180],
		] as const) {
			const file = Bun.file(path);
			expect(await file.exists()).toBe(true);
			const meta = await sharp(Buffer.from(await file.arrayBuffer())).metadata();
			expect(meta.width).toBe(size);
			expect(meta.height).toBe(size);
		}
	});

	it("wires root layout metadata to SITE.ogImage with explicit OG size", async () => {
		const layout = await Bun.file("app/layout.tsx").text();
		expect(layout).toContain("url: SITE.ogImage");
		expect(layout).toContain(`width: ${OG_WIDTH}`);
		expect(layout).toContain(`height: ${OG_HEIGHT}`);
		expect(layout).toContain("images: [SITE.ogImage]");
	});

	it("documents Sticker Bomb regeneration scripts for og + web icons", async () => {
		const ogScript = await Bun.file("scripts/generate-og-image.mjs").text();
		const iconScript = await Bun.file("scripts/generate-web-icons.mjs").text();
		expect(ogScript).toContain("#fff6e6");
		expect(ogScript).toContain("Bagel Fat One");
		expect(iconScript).toContain("#fff6e6");
	});

	it("uses Sticker Bomb paper hex for manifest theme colors", () => {
		expect(SITE.paperHex).toBe("#fff6e6");
	});
});
