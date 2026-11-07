// Regenerates PWA / favicon PNGs from brand/jp-eyes.png (Linux-safe; mirrors generate-brand-icons.swift web outputs).
// Sticker Bomb maskable uses full-bleed --sb-bg cream (#fff6e6), not Sunlit paper.
//
// Run: bun scripts/generate-web-icons.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, "..");
const repoRoot = resolve(webRoot, "..");
const sourcePath = resolve(repoRoot, "brand/jp-eyes.png");

const sbBg = { r: 255, g: 246, b: 230, alpha: 1 };
const transparent = { r: 0, g: 0, b: 0, alpha: 0 };

async function makeIcon(
	size,
	{ background = transparent, insetScale = 1, cornerRadiusRatio = 0.22 },
) {
	const face = Math.round(size * insetScale);
	const offset = Math.round((size - face) / 2);
	const facePng = await sharp(readFileSync(sourcePath))
		.resize(face, face, { fit: "contain", background: transparent })
		.png()
		.toBuffer();

	let pipeline = sharp({
		create: { width: size, height: size, channels: 4, background },
	}).composite([{ input: facePng, left: offset, top: offset }]);

	if (cornerRadiusRatio > 0) {
		const radius = Math.round(size * cornerRadiusRatio);
		const mask = Buffer.from(
			`<svg width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${radius}" ry="${radius}" fill="white"/></svg>`,
		);
		pipeline = sharp(await pipeline.png().toBuffer()).composite([
			{ input: mask, blend: "dest-in" },
		]);
	}

	return pipeline.png().toBuffer();
}

async function write(relativePath, buffer) {
	const out = resolve(webRoot, relativePath);
	writeFileSync(out, buffer);
	console.log(`Wrote ${relativePath} (${buffer.length} bytes)`);
}

const icon512 = await makeIcon(512, { cornerRadiusRatio: 0.22 });
const icon192 = await sharp(icon512).resize(192, 192).png().toBuffer();
const maskable = await makeIcon(512, {
	background: sbBg,
	insetScale: 0.78,
	cornerRadiusRatio: 0,
});
const apple = await makeIcon(180, {
	background: sbBg,
	insetScale: 0.92,
	cornerRadiusRatio: 0.22,
});

await write("public/icon-512.png", icon512);
await write("public/icon-192.png", icon192);
await write("app/icon.png", icon512);
await write("public/icon-maskable-512.png", maskable);
await write("app/apple-icon.png", apple);
