// Shared plumbing for the read-only growth readers in `scripts/`: the env-file loader, the
// Supabase pooler connection string, and the `[days]` argument. One copy, so the readers cannot
// disagree on which credentials they read or which trailing window they report.

import { existsSync, readFileSync } from "node:fs";

type Env = Record<string, string | undefined>;

const ENV_FILES = [".env.local", ".env"];
const DEFAULT_POOLER_HOST = "aws-0-us-east-1.pooler.supabase.com";
const DEFAULT_DAYS = 30;

function unquote(value: string): string {
	if (value.startsWith('"') && value.endsWith('"')) return value.slice(1, -1);
	if (value.startsWith("'") && value.endsWith("'")) return value.slice(1, -1);
	return value;
}

/** Applies `KEY=value` lines to `env`. A key that is already set wins, so the shell overrides a file. */
export function applyEnvText(text: string, env: Env = process.env): void {
	for (const line of text.split("\n")) {
		const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
		if (!match) continue;
		const [, key, rawValue] = match;
		if (!env[key]) env[key] = unquote(rawValue.trim());
	}
}

/** Loads `.env.local` then `.env` from the working directory; the first file to set a key wins. */
export function loadReaderEnv(): void {
	for (const file of ENV_FILES) {
		if (existsSync(file)) applyEnvText(readFileSync(file, "utf8"));
	}
}

function projectRef(env: Env): string {
	const ref = env.SUPABASE_PROJECT_REF?.trim();
	if (ref) return ref;
	const url = env.NEXT_PUBLIC_SUPABASE_URL;
	if (!url) throw new Error("SUPABASE_PROJECT_REF or NEXT_PUBLIC_SUPABASE_URL required");
	const derived = new URL(url).hostname.split(".")[0];
	if (!derived) throw new Error(`Could not derive project ref from ${url}`);
	return derived;
}

/** The read-only pooler connection string. Throws when the password or the project ref is missing. */
export function supabasePoolerUrl(env: Env = process.env): string {
	const password = env.SUPABASE_DB_PASSWORD;
	if (!password) throw new Error("SUPABASE_DB_PASSWORD not set");
	const host = env.SUPABASE_POOLER_HOST ?? DEFAULT_POOLER_HOST;
	const user = `postgres.${projectRef(env)}`;
	return `postgresql://${user}:${encodeURIComponent(password)}@${host}:5432/postgres?sslmode=require`;
}

/** The first all-digit argument as a positive day count; 30 when it is absent or zero. */
export function trailingDaysArgument(argv: readonly string[] = process.argv): number {
	const days = Number(argv.find((argument) => /^\d+$/.test(argument)) ?? DEFAULT_DAYS);
	return Number.isFinite(days) && days > 0 ? days : DEFAULT_DAYS;
}
