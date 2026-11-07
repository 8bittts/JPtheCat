// Shared types + cross-source helpers for the growth-digest data loaders.

export type EnvSource = Record<string, string | undefined>;
export type Fetcher = typeof fetch;

export function yyyyMmDd(date: Date) {
	return date.toISOString().slice(0, 10);
}

function projectRef(source: EnvSource): string {
	const ref = source.SUPABASE_PROJECT_REF?.trim();
	if (ref) return ref;
	const url = source.NEXT_PUBLIC_SUPABASE_URL?.trim();
	if (!url) throw new Error("SUPABASE_PROJECT_REF or NEXT_PUBLIC_SUPABASE_URL required");
	const derived = new URL(url).hostname.split(".")[0];
	if (!derived) throw new Error(`Could not derive Supabase project ref from ${url}`);
	return derived;
}

export function buildGrowthPostgresConnectionString(source: EnvSource = process.env): string {
	const password = source.SUPABASE_DB_PASSWORD;
	if (!password) throw new Error("SUPABASE_DB_PASSWORD not set");
	const host = source.SUPABASE_POOLER_HOST ?? "aws-0-us-east-1.pooler.supabase.com";
	const user = `postgres.${projectRef(source)}`;
	return `postgresql://${user}:${encodeURIComponent(password)}@${host}:5432/postgres?sslmode=require`;
}
