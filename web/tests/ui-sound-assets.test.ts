import { describe, expect, it } from "bun:test";
import { createHash } from "node:crypto";

// [CRITICAL] Drift + format guard for JP the Cat's shipped sound assets.
//
// AGENTS.md requires the interactive UI cues and the mascot meow to be BYTE-IDENTICAL
// between the native app Resources and the homepage `web/public` folder so the app and
// site share one voice, and to stay loudness-normalized + correct-format. Nothing else
// enforced this — a partial regen, a hand re-export, or a wrong-format (48k/stereo/
// truncated) re-encode passed every gate. `mac/scripts/generate-ui-sounds.py` writes both
// copies from one ffmpeg run, and the captured meow is copied to both trees by hand; this
// test is the regression guard that keeps them in lockstep.
//
// Tests run from `web/`, so the app copies are reached via `../mac/...` (same idiom as
// remote-pricing-endpoint-parity.test.ts). Kept hermetic (no ffprobe/ffmpeg spawn) so it
// runs anywhere `bun test` runs: byte-identity + a size-band canary that trips on any
// catastrophic format change (a 44.1k-mono cue re-encoded to 48k stereo roughly doubles).

const WEB = "public";
const APP = "../mac/Sources/JPtheCatApp/Resources";

// (app filename, web filename) — the meow is `jp-meow.m4a` in the app, `meow.m4a` on the web.
const PAIRS: ReadonlyArray<readonly [string, string]> = [
	["jp-meow.m4a", "meow.m4a"],
	["ui-toggle-on.m4a", "ui-toggle-on.m4a"],
	["ui-toggle-off.m4a", "ui-toggle-off.m4a"],
	["ui-click-top.m4a", "ui-click-top.m4a"],
	["ui-click-bottom.m4a", "ui-click-bottom.m4a"],
];

// Sane size bands (bytes). The four synthesized cues are tiny 44.1k-mono AAC clips; the
// captured meow is a ~1.9s 48k-stereo AAC. Bands are wide enough to survive an intentional
// re-normalize but tight enough to trip on a wrong-format re-encode.
const SIZE_BAND: Record<string, readonly [number, number]> = {
	"ui-toggle-on.m4a": [1500, 8000],
	"ui-toggle-off.m4a": [1500, 8000],
	"ui-click-top.m4a": [1200, 8000],
	"ui-click-bottom.m4a": [1200, 8000],
	"meow.m4a": [18000, 60000],
};

async function bytes(path: string): Promise<Uint8Array> {
	return new Uint8Array(await Bun.file(path).arrayBuffer());
}

function sha256(buf: Uint8Array): string {
	return createHash("sha256").update(buf).digest("hex");
}

describe("ui + mascot sound assets", () => {
	it("keeps every sound byte-identical between the app and the homepage", async () => {
		for (const [appName, webName] of PAIRS) {
			const appBytes = await bytes(`${APP}/${appName}`);
			const webBytes = await bytes(`${WEB}/${webName}`);
			expect(sha256(webBytes), `${webName} must match app ${appName}`).toBe(sha256(appBytes));
		}
	});

	it("keeps each sound within its expected size band (format canary)", async () => {
		for (const [, webName] of PAIRS) {
			const size = (await bytes(`${WEB}/${webName}`)).byteLength;
			const [lo, hi] = SIZE_BAND[webName];
			expect(size, `${webName} size ${size} out of band [${lo}, ${hi}]`).toBeGreaterThanOrEqual(lo);
			expect(size, `${webName} size ${size} out of band [${lo}, ${hi}]`).toBeLessThanOrEqual(hi);
		}
	});
});
