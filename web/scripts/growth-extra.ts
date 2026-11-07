#!/usr/bin/env bun
// Extra /growth legs that the two headline readers do not print: four-layer /download
// filter counts (so a restated human_downloads figure can be explained) and Vercel Web
// Analytics (analytics-pull.ts owns Search Console only).
//
// Read-only. Prints aggregates only — no IPs, UAs, tokens, or secrets.
//
// Usage: bun scripts/growth-extra.ts [days] [--json]
//
// Credentials: web/.env.local then web/.env, same as growth-metrics.ts. Vercel token
// comes from VERCEL_TOKEN / VERCEL_API_TOKEN, or the logged-in Vercel CLI auth.json
// so a local /growth run can pull Web Analytics without copying a token into env.

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { SQL } from "bun";
import { loadVercelAnalytics } from "../lib/analytics/growth-source-vercel";

const ENV_FILES = [".env.local", ".env"];
const JSON_MODE = process.argv.includes("--json");
const DAYS = (() => {
	const n = Number(process.argv.find((a) => /^\d+$/.test(a)) ?? "30");
	return Number.isFinite(n) && n > 0 ? n : 30;
})();

const out: Record<string, unknown> = {};

function unquote(value: string): string {
	if (value.startsWith('"') && value.endsWith('"')) return value.slice(1, -1);
	if (value.startsWith("'") && value.endsWith("'")) return value.slice(1, -1);
	return value;
}

function applyEnvLine(line: string): void {
	const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
	if (!m) return;
	const [, k, rawV] = m;
	if (process.env[k]) return;
	process.env[k] = unquote(rawV.trim());
}

function loadEnv() {
	for (const file of ENV_FILES) {
		if (!existsSync(file)) continue;
		for (const line of readFileSync(file, "utf8").split("\n")) {
			applyEnvLine(line);
		}
	}
}

function projectRef(): string {
	const ref = process.env.SUPABASE_PROJECT_REF?.trim();
	if (ref) return ref;
	const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
	if (!url) throw new Error("SUPABASE_PROJECT_REF or NEXT_PUBLIC_SUPABASE_URL required");
	const derived = new URL(url).hostname.split(".")[0];
	if (!derived) throw new Error(`Could not derive project ref from ${url}`);
	return derived;
}

function buildConnectionString(): string {
	const password = process.env.SUPABASE_DB_PASSWORD;
	if (!password) throw new Error("SUPABASE_DB_PASSWORD not set");
	const host = process.env.SUPABASE_POOLER_HOST ?? "aws-0-us-east-1.pooler.supabase.com";
	const user = `postgres.${projectRef()}`;
	return `postgresql://${user}:${encodeURIComponent(password)}@${host}:5432/postgres?sslmode=require`;
}

function vercelTokenFromCli(): string | null {
	const authPath = join(homedir(), "Library/Application Support/com.vercel.cli/auth.json");
	if (!existsSync(authPath)) return null;
	try {
		const data = JSON.parse(readFileSync(authPath, "utf8")) as { token?: unknown };
		return typeof data.token === "string" && data.token.trim() ? data.token.trim() : null;
	} catch {
		return null;
	}
}

function resolveVercelToken(): { token: string | null; source: "env" | "cli" | "missing" } {
	const env = process.env.VERCEL_TOKEN?.trim() || process.env.VERCEL_API_TOKEN?.trim();
	if (env) return { source: "env", token: env };
	const cli = vercelTokenFromCli();
	if (cli) return { source: "cli", token: cli };
	return { source: "missing", token: null };
}

async function filterLayers(sql: SQL) {
	const [layers] = await sql`
		with base as (
			select *
			from downloads
			where source not in ('smoke-test', 'production-test')
				and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
		),
		burst_ips as (
			select distinct a.ip
			from base a
			join base b
				on a.ip = b.ip
				and a.source <> b.source
				and abs(extract(epoch from a.created_at - b.created_at)) <= 8
			where a.ip is not null
		),
		monitor_ips as (
			select ip
			from base
			where ip is not null
			group by ip
			having count(distinct created_at::date) >= 4
		)
		select
			(select count(*)::int from base) as all_clean_source,
			(select count(*)::int from base
				where created_at >= now() - ${`${DAYS} days`}::interval) as all_window,
			(select count(*)::int from base where is_bot = true) as ua_bot_all,
			(select count(*)::int from base
				where is_bot = true
					and created_at >= now() - ${`${DAYS} days`}::interval) as ua_bot_window,
			(select count(*)::int from base where is_bot = false) as pass_ua_all,
			(select count(*)::int from base
				where is_bot = false
					and (coalesce(network_is_hosting, false) = true
						or coalesce(network_is_anonymous, false) = true)) as hosting_or_anon_nonbot_all,
			(select count(*)::int from base
				where is_bot = false
					and (coalesce(network_is_hosting, false) = true
						or coalesce(network_is_anonymous, false) = true)
					and created_at >= now() - ${`${DAYS} days`}::interval) as hosting_or_anon_nonbot_window,
			(select count(*)::int from monitor_ips) as monitor_ip_count,
			(select count(*)::int from base
				where is_bot = false
					and ip in (select ip from monitor_ips)) as monitor_nonbot_rows,
			(select count(*)::int from base
				where is_bot = false
					and ip in (select ip from monitor_ips)
					and created_at >= now() - ${`${DAYS} days`}::interval) as monitor_nonbot_rows_window,
			(select count(*)::int from base
				where is_bot = false and exclusion is not null) as stamped_exclusion_all,
			(select count(*)::int from base
				where is_bot = false and is_mac = true
					and created_at >= now() - ${`${DAYS} days`}::interval) as mac_ua_nonbot_window,
			(select count(*)::int from base
				where is_bot = false and network_is_hosting is not null
					and created_at >= now() - ${`${DAYS} days`}::interval) as network_flagged_nonbot_window,
			(select count(*)::int from burst_ips) as burst_ip_count,
			(select count(*)::int from base
				where is_bot = false
					and ip in (select ip from burst_ips)
					and ip not in (select ip from monitor_ips)) as burst_only_nonbot_rows,
			(select count(*)::int from base where ip is null) as redacted_ip_rows,
			(select count(*)::int from base
				where ip is null
					and created_at >= now() - ${`${DAYS} days`}::interval) as redacted_ip_rows_window
	`;

	const monthly = await sql`
		with base as (
			select *
			from downloads
			where source not in ('smoke-test', 'production-test')
				and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
		)
		select
			to_char(date_trunc('month', created_at), 'YYYY-MM') as month,
			count(*)::int as all_hits,
			count(*) filter (where is_bot = true)::int as ua_bots,
			count(*) filter (where is_bot = false)::int as nonbot,
			count(*) filter (
				where is_bot = false and coalesce(network_is_hosting, false) = true
			)::int as nonbot_hosting,
			count(*) filter (where is_bot = false and ip is null)::int as nonbot_redacted_ip,
			count(*) filter (where is_bot = false and is_mac = true)::int as nonbot_mac,
			count(*) filter (
				where is_bot = false and network_is_hosting is not null
			)::int as nonbot_network_flagged
		from base
		group by 1
		order by 1
	`;

	out.filter_layers = layers;
	out.monthly_raw_layers = monthly;
	if (JSON_MODE) return;
	console.log(`=== Filter layers (last ${DAYS}d window + all-time) ===`);
	console.log(JSON.stringify(layers, null, 2));
	console.log("\n=== Monthly raw layers ===");
	console.log(JSON.stringify(monthly, null, 2));
}

async function vercelAnalytics() {
	const resolved = resolveVercelToken();
	out.vercel_token_source = resolved.source;
	if (!resolved.token) {
		out.vercel = { status: "skipped", reason: "no VERCEL_TOKEN and no CLI auth" };
		if (!JSON_MODE) {
			console.log("\n=== Vercel Web Analytics ===\n(skipped: no VERCEL_TOKEN and no CLI auth)");
		}
		return;
	}
	process.env.VERCEL_TOKEN = resolved.token;
	const data = await loadVercelAnalytics(DAYS, new Date(), process.env, fetch);
	out.vercel = data;
	if (JSON_MODE) return;
	console.log(`\n=== Vercel Web Analytics (${DAYS}d, token=${resolved.source}) ===`);
	console.log(JSON.stringify(data, null, 2));
}

async function main() {
	loadEnv();
	const sql = new SQL(buildConnectionString());
	try {
		await filterLayers(sql);
		await vercelAnalytics();
		if (JSON_MODE) console.log(JSON.stringify(out, null, 2));
	} finally {
		await sql.close();
	}
}

await main();
