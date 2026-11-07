import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PROVIDERS } from "@/lib/site";

// `web/lib/site.ts` PROVIDERS mirrors the native `ProviderCatalog` in
// `mac/Sources/JPtheCatCore/Providers/ProviderCatalog.swift`. Nothing tied the two together, and
// they drifted ("Nemotron 3" vs "NVIDIA Nemotron", glyph "BP" vs "Bp"). This test re-parses the
// Swift catalog and asserts every descriptor's id, name, glyph, support tier, and icon slug match
// the web entry 1:1, so a provider added or renamed on one side fails loudly on the other.

type ParsedDescriptor = {
	id: string;
	name: string;
	glyph: string;
	support: string;
	iconSlug: string | undefined;
};

// `ProviderID` cases whose Swift name differs from the raw value the web catalog keys on.
const SWIFT_CASE_TO_RAW: Record<string, string> = {
	museSpark: "muse_spark",
	bigPickle: "big_pickle",
	piAgent: "pi",
	grokBot: "grok_bot",
};

const SUPPORT_TO_STATUS: Record<string, string> = {
	live: "live",
	localRoadmap: "local-roadmap",
	connectRoadmap: "connect-roadmap",
	apiRoadmap: "api-roadmap",
	candidateRoadmap: "candidate-roadmap",
};

function parseProviderCatalogSwift(): ParsedDescriptor[] {
	const src = readFileSync(
		join(import.meta.dir, "../../mac/Sources/JPtheCatCore/Providers/ProviderCatalog.swift"),
		"utf8",
	);
	const out: ParsedDescriptor[] = [];
	for (const m of src.matchAll(/ProviderDescriptor\(([\s\S]*?)\),?\n/g)) {
		const body = m[1];
		const id = body.match(/id:\s*\.(\w+)/)?.[1];
		const name = body.match(/name:\s*"([^"]+)"/)?.[1];
		const glyph = body.match(/glyph:\s*"([^"]+)"/)?.[1];
		const support = body.match(/support:\s*\.(\w+)/)?.[1];
		const iconSlug = body.match(/iconSlug:\s*"([^"]+)"/)?.[1];
		if (!id || !name || !glyph || !support) continue;
		out.push({ id: SWIFT_CASE_TO_RAW[id] ?? id, name, glyph, support, iconSlug });
	}
	return out;
}

type WebProvider = (typeof PROVIDERS)[number];

/** Every field on which one native descriptor disagrees with its web twin. */
function driftFor(d: ParsedDescriptor, w: WebProvider): string[] {
	const drift: string[] = [];
	if (w.name !== d.name) drift.push(`${d.id}: name web="${w.name}" mac="${d.name}"`);
	if (w.glyph !== d.glyph) drift.push(`${d.id}: glyph web="${w.glyph}" mac="${d.glyph}"`);
	const status = SUPPORT_TO_STATUS[d.support];
	if (w.status !== status) drift.push(`${d.id}: status web="${w.status}" mac="${status}"`);
	// `Provider.icon` is derived from the definition's slug (`/provider-icons/<slug>.svg`). The web
	// may reuse a mark for an entry the app has none for (e.g. `openai` -> `codex`), so the slug is
	// compared only where the native catalog defines one.
	const webSlug = w.icon?.match(/\/provider-icons\/(.+)\.svg$/)?.[1];
	if (d.iconSlug !== undefined && webSlug !== d.iconSlug) {
		drift.push(`${d.id}: iconSlug web="${webSlug}" mac="${d.iconSlug}"`);
	}
	return drift;
}

describe("provider catalog parity (mac ProviderCatalog ↔ web PROVIDERS)", () => {
	const swift = parseProviderCatalogSwift();

	it("parses every native descriptor", () => {
		expect(swift.length).toBeGreaterThan(60);
		expect(swift.length).toBe(PROVIDERS.length);
	});

	// Row ORDER is a per-surface display choice and is deliberately not pinned.
	it("keeps id, name, glyph, support tier, and native icon slug identical on both sides", () => {
		const web = new Map(PROVIDERS.map((p) => [p.id, p]));
		const drift = swift.flatMap((d) => {
			const w = web.get(d.id);
			return w ? driftFor(d, w) : [`${d.id}: missing from web PROVIDERS`];
		});
		expect(drift).toEqual([]);
	});

	it("covers exactly the same id set on both sides", () => {
		expect(PROVIDERS.map((p) => p.id).sort()).toEqual(swift.map((d) => d.id).sort());
	});
});
