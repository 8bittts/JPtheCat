import { afterEach, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	copyFileSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	realpathSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const repo = resolve(import.meta.dir, "..");
const config = JSON.parse(readFileSync(join(repo, "vercel.json"), "utf8"));
const temporary: string[] = [];

afterEach(() => {
	for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture(version: unknown = `bun@${process.versions.bun}`, exitCode = 0) {
	const root = realpathSync(mkdtempSync(join(tmpdir(), "bun-runtime-test-")));
	temporary.push(root);
	mkdirSync(join(root, "scripts"));
	mkdirSync(join(root, "bin"));
	copyFileSync(join(repo, "scripts/run-pinned-bun.cjs"), join(root, "scripts/run-pinned-bun.cjs"));
	writeFileSync(
		join(root, "package.json"),
		JSON.stringify({
			packageManager: version,
			scripts: { build: `exit ${exitCode}`, "build:turbo": `exit ${exitCode}` },
		}),
	);
	const stub = join(root, "bin/bunx");
	writeFileSync(stub, `#!/bin/sh\nprintf '%s\\n' "$@"\nexit ${exitCode}\n`);
	chmodSync(stub, 0o755);
	return { root, env: { ...process.env, PATH: `${join(root, "bin")}:${process.env.PATH}` } };
}

function command(f: ReturnType<typeof fixture>, cmd: string) {
	return spawnSync("/bin/sh", ["-c", cmd], { cwd: f.root, env: f.env, encoding: "utf8" });
}

describe("pinned Bun deployment", () => {
	test("Vercel install and build resolve the declared version without a registry call", () => {
		for (const version of ["bun@1.4.2", "bun@1.4.3"]) {
			const f = fixture(version);
			for (const [key, phase] of [
				["installCommand", "install"],
				["buildCommand", "build"],
			]) {
				const result = command(f, config[key]);
				expect(result.status).toBe(0);
				expect(result.stdout.trim().split("\n").slice(0, 3)).toEqual([
					version,
					join(f.root, "scripts/run-pinned-bun.cjs"),
					phase,
				]);
			}
		}
	}, 30_000);

	test("missing and malformed declarations fail before bootstrap", () => {
		for (const version of [undefined, "", "bun@latest", "npm@1.4.2", "bun@1.4.2; echo bad"]) {
			const f = fixture(version);
			if (version === undefined) writeFileSync(join(f.root, "package.json"), "{}");
			const result = command(f, config.installCommand);
			expect(result.status).toBe(1);
			expect(result.stderr).toContain("packageManager must declare an exact Bun version");
			expect(result.stdout).toBe("");
		}
		const f = fixture();
		rmSync(join(f.root, "package.json"));
		expect(command(f, config.installCommand).status).toBe(1);
	}, 30_000);

	test("a bootstrap failure propagates", () => {
		const f = fixture(`bun@${process.versions.bun}`, 23);
		expect(command(f, config.installCommand).status).toBe(23);
	}, 30_000);

	test("a mismatched executing Bun fails before the build", () => {
		const f = fixture("bun@0.0.0");
		const result = spawnSync(process.execPath, ["scripts/run-pinned-bun.cjs", "build"], {
			cwd: f.root,
			env: f.env,
			encoding: "utf8",
		});
		expect(result.status).toBe(1);
		expect(result.stderr).toContain("required 0.0.0");
	}, 30_000);

	test("the verified runtime reaches nested Bun calls and emits a receipt", () => {
		const f = fixture();
		writeFileSync(
			join(f.root, "package.json"),
			JSON.stringify({
				packageManager: `bun@${process.versions.bun}`,
				scripts: { build: "bun --version" },
			}),
		);
		const badBun = join(f.root, "bin/bun");
		writeFileSync(badBun, "#!/bin/sh\nexit 97\n");
		chmodSync(badBun, 0o755);
		const result = spawnSync(process.execPath, ["scripts/run-pinned-bun.cjs", "build"], {
			cwd: f.root,
			env: f.env,
			encoding: "utf8",
		});
		expect(result.status).toBe(0);
		expect(result.stdout).toContain(
			`[bun-runtime] PASS build: required=${process.versions.bun} running=${process.versions.bun}`,
		);
		expect(result.stdout.trim().split("\n").at(-1)).toBe(process.versions.bun);
	}, 30_000);

	test("a failed build cannot become a successful wrapper exit", () => {
		const f = fixture(`bun@${process.versions.bun}`, 23);
		const result = spawnSync(process.execPath, ["scripts/run-pinned-bun.cjs", "build"], {
			cwd: f.root,
			env: f.env,
			encoding: "utf8",
		});
		expect(result.status).toBe(23);
	}, 30_000);
});
