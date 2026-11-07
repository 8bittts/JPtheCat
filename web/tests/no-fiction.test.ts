import { describe, expect, it } from "bun:test";
import { readdir, readFile } from "node:fs/promises";
import { extname, join } from "node:path";

const WEB_SOURCE_ROOTS = ["app", "components", "lib"];
const REPO_SOURCE_ROOTS = ["../mac/Sources"];
const WEB_PUBLIC_TEXT_FILES = ["public/llms.txt"];
const AGENT_DOCS = [
	"../AGENTS.md",
	"../mac/AGENTS.md",
	"AGENTS.md",
	"../supabase/AGENTS.md",
	"../README.md",
];
// Every top-level owner doc, derived rather than listed, so a renamed or added doc stays covered.
const OWNER_DOC_DIR = "../_docs";
const MIN_OWNER_DOCS = 10;
const TEXT_EXTENSIONS = new Set([".ts", ".tsx", ".md", ".txt", ".swift"]);

const STALE_LIVE_CHECKOUT_RULES = [
	{ label: "early-access public pricing mode", pattern: /\bearly[- ]access\b/i },
	{
		label: "free early-access checkout copy",
		pattern: /\bfree while (?:JP is )?in early access\b/i,
	},
	{ label: "future-tense licensing copy", pattern: /\bwhen licensing (?:lands|ships)\b/i },
	{ label: "future-tense checkout copy", pattern: /\bwhen paid checkout is enabled\b/i },
	{ label: "planned price copy", pattern: /\bplanned \$12\.99\b/i },
	{
		label: "planned paid-release copy",
		pattern: /\b(?:planned paid release|paid release is planned)\b/i,
	},
	{
		label: "planned license API copy",
		pattern: /\b(?:planned license API|license API planned)\b/i,
	},
	{ label: "unbuilt license API action", pattern: /\bstand up the license API\b/i },
	{
		label: "non-live checkout copy",
		pattern: /\bcheckout will be handled by a payment processor\b/i,
	},
	{ label: "pre-live offer gate", pattern: /\bno offers? until\b/i },
	{
		label: "pre-license app network copy",
		pattern: /\bA salted license check when you buy\b/i,
	},
	{
		label: "purchase-only app network copy",
		pattern: /\bonly required network call is a salted license check when you purchase\b/i,
	},
	{
		label: "license-only launch network copy",
		pattern: /\bnothing but a salted device hash on license check\b/i,
	},
	{ label: "unshipped Phase 3 licensing copy", pattern: /\blicensing unshipped\b/i },
	{ label: "fixed Stripe profile blocker copy", pattern: /\bbuyer profile fix\b/i },
	{ label: "unrecruited Product Hunt hunter copy", pattern: /\bHunter lined up\b/i },
	{
		label: "old early-bird price copy",
		pattern: /(?:early-bird price|current-price[^\n]+→)\s*[^\n]*\$6\.99\b/i,
	},
	{ label: "old conversion-test price copy", pattern: /\bA\/B to \$7\.99\b/i },
	{
		label: "pre-revenue growth owner copy",
		pattern: /\bpre-(?:revenue|monetization) macOS app\b/i,
	},
	{
		label: "old pre-revenue price posture",
		pattern: /\bpre-revenue\s+\$9\.99\s+(?:Mac\s+)?app\b/i,
	},
	{
		label: "old README phase 2 active state",
		pattern: /\|\s*2\s*\|\s*Active\s+—/i,
	},
	{
		label: "old README phase 3 partial state",
		pattern: /\|\s*3\s*\|\s*Partial\s+—/i,
	},
	{ label: "unconfigured Stripe account copy", pattern: /\bnothing is set up for JP yet\b/i },
	{ label: "pre-revenue report requirement", pattern: /\breports must stay pre-revenue\b/i },
];

function displayPath(path: string): string {
	return path.startsWith("../") ? path.slice(3) : `web/${path}`;
}

async function collectTextFiles(directory: string): Promise<string[]> {
	const entries = await readdir(directory, { withFileTypes: true });
	const files = await Promise.all(
		entries.map((entry) => {
			const path = join(directory, entry.name);
			if (entry.isDirectory()) {
				return collectTextFiles(path);
			}
			return entry.isFile() && TEXT_EXTENSIONS.has(extname(path)) ? [path] : [];
		}),
	);
	return files.flat();
}

async function ownerDocs(): Promise<string[]> {
	const entries = await readdir(OWNER_DOC_DIR, { withFileTypes: true });
	return entries
		.filter((entry) => entry.isFile() && extname(entry.name) === ".md")
		.map((entry) => join(OWNER_DOC_DIR, entry.name));
}

async function fictionGuardFiles(): Promise<string[]> {
	const sourceFiles = (await Promise.all(WEB_SOURCE_ROOTS.map(collectTextFiles))).flat();
	const repoSourceFiles = (await Promise.all(REPO_SOURCE_ROOTS.map(collectTextFiles))).flat();
	return [
		...sourceFiles,
		...repoSourceFiles,
		...WEB_PUBLIC_TEXT_FILES,
		...AGENT_DOCS,
		...(await ownerDocs()),
	];
}

describe("no-fiction guard", () => {
	it("scans every owner doc", async () => {
		const docs = await ownerDocs();
		expect(docs.length).toBeGreaterThanOrEqual(MIN_OWNER_DOCS);
		expect(docs).toContain(join(OWNER_DOC_DIR, "todos.md"));
	});

	it("keeps live checkout truth from regressing to stale launch fiction", async () => {
		const matches: string[] = [];

		for (const file of await fictionGuardFiles()) {
			const source = await readFile(file, "utf8");
			for (const rule of STALE_LIVE_CHECKOUT_RULES) {
				if (rule.pattern.test(source)) {
					matches.push(`${displayPath(file)}: ${rule.label}`);
				}
			}
		}

		expect(matches).toEqual([]);
	});

	it("does not revive separate Cursor or Grok Bot provider rows in active public catalogs", async () => {
		const native = await readFile(
			"../mac/Sources/JPtheCatCore/Providers/ProviderCatalog.swift",
			"utf8",
		);
		const web = await readFile("lib/site.ts", "utf8");
		expect(native).not.toMatch(/id:\s*\.(?:cursor|grokBot)\s*,/);
		expect(web).not.toMatch(/id:\s*"(?:cursor|grok_bot)"\s*,/);
	});

	it("documents the guard anywhere future agents check source-of-truth rules", async () => {
		const requiredDocs = ["../AGENTS.md"];

		for (const file of requiredDocs) {
			const source = await readFile(file, "utf8");
			expect(source, displayPath(file)).toContain("web/tests/no-fiction.test.ts");
		}
	});
});
