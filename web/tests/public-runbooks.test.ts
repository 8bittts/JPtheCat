import { describe, expect, it } from "bun:test";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const RUNBOOK_ROOTS = ["../.claude/commands", "../.agents/skills"];
const MIN_RUNBOOK_FILES = 3;
const PRIVATE_SHAPES = [
	{ label: "absolute home path", pattern: /\/Users\/[a-z]/ },
	{ label: "email address", pattern: /[\w.+-]+@[\w-]+\.[a-z]{2,}/i },
];

async function listFiles(dir: string): Promise<string[]> {
	const entries = await readdir(dir, { withFileTypes: true });
	const nested = await Promise.all(
		entries.map((entry) => {
			const path = join(dir, entry.name);
			return entry.isDirectory() ? listFiles(path) : [path];
		}),
	);
	return nested.flat();
}

describe("public agent runbooks", () => {
	it("never carry operator home paths or email addresses", async () => {
		const files = (await Promise.all(RUNBOOK_ROOTS.map(listFiles))).flat();
		expect(files.length).toBeGreaterThanOrEqual(MIN_RUNBOOK_FILES);
		const hits: string[] = [];
		for (const file of files) {
			const text = await readFile(file, "utf8");
			for (const { label, pattern } of PRIVATE_SHAPES) {
				if (pattern.test(text)) hits.push(`${file}: ${label}`);
			}
		}
		expect(hits).toEqual([]);
	});

	it("keep the customer-data archive gitignored", async () => {
		const gitignore = await readFile("../.gitignore", "utf8");
		expect(gitignore.split("\n")).toContain("_docs/legacy-backup/");
	});
});
