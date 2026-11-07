import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const ARTIFACT_ROOTS = [".next/static", ".next/server/app"] as const;
const PUBLIC_VALUES = new Set(["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"]);
const SECRET_NAME =
	/(API_KEY|TOKEN|SECRET|SECRET_KEY|PASSWORD|SERVICE_ROLE_KEY|PRIVATE_KEY|CREDENTIAL|SALT)$/;
const PLATFORM_PUBLIC = /^(VERCEL_|NEXT_(?!PUBLIC_)|TURBO_|NX_|AWS_(?!SECRET|ACCESS)|__)/;
const PUBLIC_PLATFORM = /^(NEXT_PUBLIC_|REACT_APP_|VITE_|PUBLIC_|NUXT_PUBLIC_|GATSBY_)VERCEL_/;
const NEVER_SECRET = /^(NODE_ENV|CI|TZ|LANG|LC_[A-Z_]+|PATH|HOME|SHELL|PWD|TMPDIR|USER|TERM|_.*)$/;

type Finding = { variable: string; artifact: string; encoding: string };

function collectFiles(root: string): string[] {
	const files: string[] = [];
	const stack = [root];
	while (stack.length > 0) {
		const current = stack.pop();
		if (!current) continue;
		for (const entry of readdirSync(current)) {
			const path = join(current, entry);
			if (statSync(path).isDirectory()) stack.push(path);
			else files.push(path);
		}
	}
	return files;
}

function encodings(value: string): Array<{ encoding: string; needle: string }> {
	return [
		{ encoding: "raw", needle: value },
		{ encoding: "JSON", needle: JSON.stringify(value).slice(1, -1) },
		{
			encoding: "JavaScript unicode",
			needle: [...value]
				.map((character) =>
					/[A-Za-z0-9]/.test(character)
						? character
						: `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`,
				)
				.join(""),
		},
		{
			encoding: "HTML entity",
			needle: value.replace(/[^A-Za-z0-9]/g, (character) => `&#${character.charCodeAt(0)};`),
		},
	].filter(({ needle }) => needle.length > 0);
}

function scanEnvironment() {
	const secrets: Array<{ variable: string; value: string }> = [];
	for (const [variable, rawValue] of Object.entries(process.env)) {
		const value = rawValue?.trim();
		if (!value || PUBLIC_VALUES.has(variable) || NEVER_SECRET.test(variable)) continue;
		if (PUBLIC_PLATFORM.test(variable)) continue;
		if (PLATFORM_PUBLIC.test(variable) && variable !== "VERCEL_OIDC_TOKEN") continue;
		if (SECRET_NAME.test(variable) && value.length >= 6) secrets.push({ variable, value });
	}
	return secrets;
}

function main() {
	const cwd = process.cwd();
	const artifacts = ARTIFACT_ROOTS.flatMap((root) => {
		const absolute = resolve(cwd, root);
		return existsSync(absolute) ? collectFiles(absolute) : [];
	});
	const secrets = scanEnvironment();
	if (artifacts.length === 0)
		throw new Error("Secret scan failed: zero browser artifacts were found.");
	if (secrets.length === 0)
		throw new Error("Secret scan failed: zero credential values were available to scan.");

	const findings: Finding[] = [];
	for (const artifact of artifacts) {
		const contents = readFileSync(artifact, "utf8");
		for (const { variable, value } of secrets) {
			const match = encodings(value).find(({ needle }) => contents.includes(needle));
			if (match)
				findings.push({ variable, artifact: relative(cwd, artifact), encoding: match.encoding });
		}
	}

	console.log(
		`Secret scan: ${secrets.length} credential values across ${artifacts.length} browser artifacts.`,
	);
	if (findings.length > 0) {
		for (const finding of findings) {
			console.error(`${finding.variable} (${finding.encoding}) -> ${finding.artifact}`);
		}
		throw new Error(`${findings.length} secret value(s) reached browser output.`);
	}
	console.log("Secret scan passed: no server secret reached browser output.");
}

main();
