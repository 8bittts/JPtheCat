#!/usr/bin/env bun
// Pull JP the Cat growth metrics straight from Postgres for the /growth review.
// Read-only aggregates only — never mutates.
//
// JP the Cat is a free macOS app with intentionally narrow server telemetry. There is NO product
// usage schema; app usage stays local. The durable growth spine is the acquisition funnel —
// bot-classified `/download` rows. This script owns that spine. The
// traffic + Search Console keyword leg lives in scripts/analytics-pull.ts.
//
// The download signal is heavily bot-polluted (a single overnight sample was almost
// entirely Dataprovider.com + curl + a ChromeOS scraper pulling a macOS .dmg), so
// EVERY human figure below excludes is_bot rows AND collapses the "one client walks
// hero+nav+pricing within seconds" burst pattern that a UA check alone can't catch.
// The headline is `mac_human_downloads`: a Windows or Android browser pulling the DMG
// is a crawler, not an install (86% of "human" rows were, in Oct 2026).
//
// Usage: bun scripts/growth-metrics.ts [days] [--json]
//   days    trailing window for rolling comparisons (default 30).
//   --json  emit a single JSON document instead of the tables.
//
// Credentials read from .env.local then .env: SUPABASE_PROJECT_REF (or
// NEXT_PUBLIC_SUPABASE_URL) for the ref, SUPABASE_DB_PASSWORD for the pooler
// password. Pooler host defaults to aws-0-us-east-1; override SUPABASE_POOLER_HOST.

import { existsSync, readFileSync } from "node:fs";
import { SQL } from "bun";
import { humanDownloadsCte } from "../lib/analytics/growth-download-sql";

const ENV_FILES = [".env.local", ".env"];

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

const JSON_MODE = process.argv.includes("--json");
const DAYS = (() => {
	const n = Number(process.argv.find((a) => /^\d+$/.test(a)) ?? "30");
	return Number.isFinite(n) && n > 0 ? n : 30;
})();

type Row = Record<string, unknown>;
const out: Record<string, unknown> = {};

function fmt(v: unknown): string {
	if (v === null || v === undefined) return "—";
	if (typeof v === "number") return Number.isInteger(v) ? String(v) : v.toFixed(2);
	return String(v);
}

function emit(title: string, rows: Row[], key: string) {
	out[key] = rows;
	if (JSON_MODE) return;
	console.log(`\n=== ${title} ===`);
	if (!rows.length) {
		console.log("(no rows)");
		return;
	}
	const cols = Object.keys(rows[0]);
	console.log(cols.join("\t"));
	for (const r of rows) console.log(cols.map((c) => fmt(r[c])).join("\t"));
}

// The "real human download" burst window + CTE now live in the shared `growth-download-sql` module so
// this CLI and the growth-digest data loader can't drift (they had). See that module for the full rule.

function humanCte(sql: SQL) {
	return humanDownloadsCte(sql);
}

async function main() {
	loadEnv();
	const sql = new SQL(buildConnectionString());

	try {
		// Headline: total vs human vs Mac-human vs bot in the window, plus datacenter-filter coverage.
		// `mac_human_downloads` is the number to lead with; `human_downloads` is every platform and is
		// only kept for continuity with reports before 2026-10. `network_flagged / network_flaggable`
		// says how many non-bot rows the hosting rule could actually judge — a gap means the rule was
		// blind for those rows (the ipapi.is free tier dropped the flags on 2026-09-01).
		emit(
			`Headline (last ${DAYS}d)`,
			await sql`
				${humanCte(sql)}
				select
					(select count(*)::int from downloads
						where created_at >= now() - ${`${DAYS} days`}::interval
							and source not in ('smoke-test', 'production-test')
							and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as all_hits,
					(select count(*)::int from mac_human
						where created_at >= now() - ${`${DAYS} days`}::interval) as mac_human_downloads,
					(select count(*)::int from human
						where created_at >= now() - ${`${DAYS} days`}::interval) as human_downloads,
					(select count(*)::int from downloads
						where is_bot = false and network_is_hosting is not null
							and created_at >= now() - ${`${DAYS} days`}::interval
							and source not in ('smoke-test', 'production-test')
							and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as network_flagged,
					(select count(*)::int from downloads
						where is_bot = false
							and created_at >= now() - ${`${DAYS} days`}::interval
							and source not in ('smoke-test', 'production-test')
							and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as network_flaggable,
					(select count(*)::int from downloads
						where is_bot = true and created_at >= now() - ${`${DAYS} days`}::interval
							and source not in ('smoke-test', 'production-test')
							and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as bot_ua_hits,
					(select count(distinct ip)::int from human
						where created_at >= now() - ${`${DAYS} days`}::interval and ip is not null) as unique_human_ips
			`,
			"headline",
		);

		// Rolling window vs prior window with delta_pct — Mac-human (the headline) and all-platform human.
		emit(
			`Downloads — rolling ${DAYS}d vs prior ${DAYS}d`,
			await sql`
				${humanCte(sql)}
				select population, current, prior,
					round(100.0 * (current - prior) / nullif(prior, 0), 1) as delta_pct
				from (
					select 'mac_human' as population,
						count(*) filter (where created_at >= now() - ${`${DAYS} days`}::interval)::int as current,
						count(*) filter (where created_at >= now() - ${`${DAYS * 2} days`}::interval
							and created_at < now() - ${`${DAYS} days`}::interval)::int as prior
					from mac_human
					union all
					select 'human' as population,
						count(*) filter (where created_at >= now() - ${`${DAYS} days`}::interval)::int as current,
						count(*) filter (where created_at >= now() - ${`${DAYS * 2} days`}::interval
							and created_at < now() - ${`${DAYS} days`}::interval)::int as prior
					from human
				) t
			`,
			"rolling",
		);

		// Monthly trend — last 6 months; current month is partial, annotate in the report. `platform_unknown`
		// is human rows whose UA was redacted before `is_mac` existed (before 2026-09-21): they can never
		// be classified, so a month made of them has no honest Mac figure.
		emit(
			"Downloads by month (last 6, current is partial)",
			await sql`
				${humanCte(sql)}
				select to_char(date_trunc('month', created_at), 'YYYY-MM') as month,
					count(*) filter (where is_mac = true)::int as mac_human_downloads,
					count(*)::int as human_downloads,
					count(*) filter (where is_mac is null)::int as platform_unknown
				from human
				where created_at >= date_trunc('month', now()) - interval '5 months'
				group by 1 order by 1
			`,
			"by_month",
		);

		// By CTA source (Mac human, window).
		emit(
			`Mac human downloads by source (last ${DAYS}d)`,
			await sql`
				${humanCte(sql)}
				select coalesce(source, '—') as source, count(*)::int as mac_human_downloads
				from mac_human where created_at >= now() - ${`${DAYS} days`}::interval
				group by 1 order by 2 desc
			`,
			"by_source",
		);

		// By release version (Mac human, window).
		emit(
			`Mac human downloads by version (last ${DAYS}d)`,
			await sql`
				${humanCte(sql)}
				select coalesce(version, '—') as version, count(*)::int as mac_human_downloads
				from mac_human where created_at >= now() - ${`${DAYS} days`}::interval
				group by 1 order by 2 desc
			`,
			"by_version",
		);

		// Top Mac-human geographies (window).
		emit(
			`Mac human downloads by country (last ${DAYS}d, top 12)`,
			await sql`
				${humanCte(sql)}
				select coalesce(country, '—') as country, count(*)::int as mac_human_downloads
				from mac_human where created_at >= now() - ${`${DAYS} days`}::interval
				group by 1 order by 2 desc limit 12
			`,
			"by_country",
		);

		// Platform of every non-bot row that passed the read-time rules: the wrong-platform pulls are
		// crawlers with browser UAs, and their size is the inflation the Mac headline removes.
		emit(
			`Human downloads by platform (last ${DAYS}d)`,
			await sql`
				${humanCte(sql)}
				select case
						when is_mac = true then 'mac'
						when is_mac is null then 'unknown (UA redacted)'
						when ua like '%Windows%' then 'windows'
						when ua like '%Android%' or ua like '%iPhone%' or ua like '%iPad%' then 'mobile'
						when ua not like 'Mozilla/5.0 (%' then 'non-browser'
						else 'other'
					end as platform,
					count(*)::int as human_downloads
				from human where created_at >= now() - ${`${DAYS} days`}::interval
				group by 1 order by 2 desc
			`,
			"by_platform",
		);

		// Bot pressure: top flagged UAs (window) — how much noise the funnel carries.
		emit(
			`Top bot user-agents (last ${DAYS}d, top 12)`,
			await sql`
				select coalesce(substring(ua for 60), '—') as user_agent, count(*)::int as hits
				from downloads
				where is_bot = true and source <> 'smoke-test'
					and source <> 'production-test'
					and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
					and created_at >= now() - ${`${DAYS} days`}::interval
				group by 1 order by 2 desc limit 12
			`,
			"bot_uas",
		);
	} finally {
		await sql.end();
	}

	if (JSON_MODE) console.log(JSON.stringify(out, null, 2));
}

await main();
