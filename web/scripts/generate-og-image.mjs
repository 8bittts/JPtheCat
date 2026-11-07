// Regenerates web/public/og.jpg — the shared social/OG card used across every page.
//
// Sticker Bomb marketing skin (web/app/sticker.css): cream dot-grid canvas, Bagel Fat One
// display, Space Grotesk body, ink outlines, orange accents. Wordmark MUST read "JP the Cat"
// (AGENTS.md). Run: bun scripts/generate-og-image.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, "..");
const repoRoot = resolve(webRoot, "..");
const logoPath = resolve(repoRoot, "brand/jp-cat-yellow-icon-2048.png");
const outPath = resolve(webRoot, "public/og.jpg");

const sbBg = "#fff6e6";
const sbDot = "#f0d9b8";
const sbInk = "#151010";
const sbOrangeInk = "#b8400a";
const sbYellow = "#ffd23f";
const sbHoney = "#ffba3b";
const sbPink = "#ff9ad5";

const logoDataUri = `data:image/png;base64,${readFileSync(logoPath).toString("base64")}`;

const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Bagel+Fat+One&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet" />
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 1200px; height: 630px; }
  body {
    background-color: ${sbBg};
    background-image: radial-gradient(${sbDot} 1.5px, transparent 1.5px);
    background-size: 22px 22px;
    color: ${sbInk};
    font-family: "Space Grotesk", ui-sans-serif, system-ui, sans-serif;
    display: flex;
    align-items: center;
    overflow: hidden;
  }
  .card {
    display: flex;
    align-items: center;
    gap: 56px;
    padding: 0 72px;
    width: 100%;
    position: relative;
  }
  .badge {
    width: 300px;
    height: 300px;
    flex: 0 0 auto;
    border: 3px solid ${sbInk};
    border-radius: 28px;
    overflow: hidden;
    box-shadow: 8px 8px 0 ${sbInk};
    transform: rotate(-3deg);
    background: ${sbYellow};
  }
  .badge img { width: 100%; height: 100%; display: block; }
  .copy { display: flex; flex-direction: column; max-width: 720px; }
  .wordmark {
    font-family: "Bagel Fat One", system-ui, sans-serif;
    font-weight: 400;
    font-size: 96px;
    line-height: 0.95;
    letter-spacing: 0;
    color: ${sbInk};
  }
  .tagline {
    font-family: "Space Grotesk", ui-sans-serif, sans-serif;
    font-weight: 600;
    font-size: 38px;
    line-height: 1.12;
    color: ${sbInk};
    margin-top: 20px;
  }
  .tagline em {
    font-style: normal;
    color: ${sbOrangeInk};
  }
  .sub {
    font-weight: 500;
    font-size: 24px;
    line-height: 1.35;
    color: ${sbInk};
    opacity: 0.72;
    margin-top: 18px;
  }
  .sticker {
    position: absolute;
    font-family: "Bagel Fat One", system-ui, sans-serif;
    font-size: 22px;
    padding: 8px 16px;
    border: 3px solid ${sbInk};
    box-shadow: 4px 4px 0 ${sbInk};
    transform: rotate(-8deg);
    white-space: nowrap;
  }
  .s1 { top: 48px; right: 64px; background: ${sbYellow}; }
  .s2 { bottom: 52px; left: 64px; background: ${sbPink}; transform: rotate(6deg); }
  .s3 { bottom: 64px; right: 120px; background: ${sbHoney}; transform: rotate(-4deg); font-size: 18px; }
</style>
</head>
<body>
  <div class="card">
    <div class="badge"><img src="${logoDataUri}" alt="" /></div>
    <div class="copy">
      <div class="wordmark">JP the Cat</div>
      <div class="tagline">Know your agent <em>costs!</em></div>
      <div class="sub">Free for Mac · Claude Code, Codex, Grok &amp; more in your menu bar.</div>
    </div>
    <span class="sticker s1">100% local</span>
    <span class="sticker s2">free now!!</span>
    <span class="sticker s3">every cent</span>
  </div>
</body>
</html>`;

const browser = await chromium.launch();
const page = await browser.newPage({
	viewport: { width: 1200, height: 630 },
	deviceScaleFactor: 2,
});
await page.setContent(html, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(400);
const png = await page.screenshot({ type: "png" });
await browser.close();

let out = png;
try {
	const sharp = (await import("sharp")).default;
	out = await sharp(png)
		.resize(1200, 630, { fit: "fill" })
		.jpeg({ quality: 92, chromaSubsampling: "4:4:4" })
		.toBuffer();
} catch {
	console.warn("sharp not available — writing PNG bytes into og.jpg (still valid image).");
}
writeFileSync(outPath, out);
console.log(`Wrote ${outPath} (${out.length} bytes)`);
