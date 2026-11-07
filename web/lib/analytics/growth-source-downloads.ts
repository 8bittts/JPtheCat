import type postgres from "postgres";
import type { GrowthCountRow } from "@/lib/analytics/growth-digest";
import { humanDownloadsCte } from "@/lib/analytics/growth-download-sql";
import { OWNER_VALUE } from "@/lib/email/owner-vocabulary";

type SqlClient = ReturnType<typeof postgres>;

type HeadlineRow = {
	all_hits: number;
	bot_ua_hits: number;
	human_downloads: number;
	mac_human_downloads: number;
	network_flagged: number;
	network_flaggable: number;
	unique_human_ips: number;
};

type RollingRow = {
	current: number;
	delta_pct: number | null;
	prior: number;
};

type CountRow = {
	count: number;
	label: string;
};

function humanCte(sql: SqlClient) {
	return humanDownloadsCte(sql);
}

function toCountRows(rows: CountRow[]): GrowthCountRow[] {
	return rows.map((row) => ({
		count: Number(row.count) || 0,
		label: row.label || OWNER_VALUE.unknown,
	}));
}

export async function queryDownloadData(sql: SqlClient, windowDays: number, now: Date) {
	const since = new Date(now.getTime() - windowDays * 86_400_000).toISOString();
	const priorSince = new Date(now.getTime() - windowDays * 2 * 86_400_000).toISOString();
	const nowIso = now.toISOString();

	const [headline] = (await sql`
		${humanCte(sql)}
		select
			(select count(*)::int from downloads
				where created_at >= ${since}::timestamptz
					and created_at <= ${nowIso}::timestamptz
					and source not in ('smoke-test', 'production-test')
					and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as all_hits,
			(select count(*)::int from human
				where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz) as human_downloads,
			(select count(*)::int from mac_human
				where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz) as mac_human_downloads,
			-- Datacenter-filter coverage: non-bot rows whose ipapi.is lookup actually returned a hosting
			-- flag. Anything short of flaggable means the hosting rule is blind for the gap.
			(select count(*)::int from downloads
				where is_bot = false
					and network_is_hosting is not null
					and created_at >= ${since}::timestamptz
					and created_at <= ${nowIso}::timestamptz
					and source not in ('smoke-test', 'production-test')
					and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as network_flagged,
			(select count(*)::int from downloads
				where is_bot = false
					and created_at >= ${since}::timestamptz
					and created_at <= ${nowIso}::timestamptz
					and source not in ('smoke-test', 'production-test')
					and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as network_flaggable,
			(select count(*)::int from downloads
				where is_bot = true
					and created_at >= ${since}::timestamptz
					and created_at <= ${nowIso}::timestamptz
					and source not in ('smoke-test', 'production-test')
					and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%') as bot_ua_hits,
			(select count(distinct ip)::int from human
				where created_at >= ${since}::timestamptz
					and created_at <= ${nowIso}::timestamptz
					and ip is not null) as unique_human_ips
	`) as unknown as HeadlineRow[];

	const [rolling] = (await sql`
		${humanCte(sql)}
		select
			count(*) filter (where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz)::int as current,
			count(*) filter (where created_at >= ${priorSince}::timestamptz and created_at < ${since}::timestamptz)::int as prior,
			round(100.0 * (
				count(*) filter (where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz)
				- count(*) filter (where created_at >= ${priorSince}::timestamptz and created_at < ${since}::timestamptz)
			) / nullif(count(*) filter (where created_at >= ${priorSince}::timestamptz and created_at < ${since}::timestamptz), 0), 1) as delta_pct
		from human
	`) as unknown as RollingRow[];

	const [macRolling] = (await sql`
		${humanCte(sql)}
		select
			count(*) filter (where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz)::int as current,
			count(*) filter (where created_at >= ${priorSince}::timestamptz and created_at < ${since}::timestamptz)::int as prior,
			round(100.0 * (
				count(*) filter (where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz)
				- count(*) filter (where created_at >= ${priorSince}::timestamptz and created_at < ${since}::timestamptz)
			) / nullif(count(*) filter (where created_at >= ${priorSince}::timestamptz and created_at < ${since}::timestamptz), 0), 1) as delta_pct
		from mac_human
	`) as unknown as RollingRow[];

	// Breakdowns describe the headline population (Mac browsers), not every non-bot row.
	const bySource = (await sql`
		${humanCte(sql)}
		select coalesce(source, '—') as label, count(*)::int as count
		from mac_human
		where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz
		group by 1 order by 2 desc limit 8
	`) as unknown as CountRow[];

	const byVersion = (await sql`
		${humanCte(sql)}
		select coalesce(version, '—') as label, count(*)::int as count
		from mac_human
		where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz
		group by 1 order by 2 desc limit 8
	`) as unknown as CountRow[];

	const byLocation = (await sql`
		${humanCte(sql)}
		select
			coalesce(nullif(concat_ws(', ', nullif(city, ''), nullif(region, ''), nullif(country, '')), ''), '—') as label,
			count(*)::int as count
		from mac_human
		where created_at >= ${since}::timestamptz and created_at <= ${nowIso}::timestamptz
		group by 1 order by 2 desc limit 8
	`) as unknown as CountRow[];

	const botUserAgents = (await sql`
		select coalesce(ua, '—') as label, count(*)::int as count
		from downloads
		where is_bot = true
			and source not in ('smoke-test', 'production-test')
			and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
			and created_at >= ${since}::timestamptz
			and created_at <= ${nowIso}::timestamptz
		group by 1 order by 2 desc limit 8
	`) as unknown as CountRow[];

	return {
		botUserAgents: mergeShortenedUserAgents(toCountRows(botUserAgents)),
		byLocation: toCountRows(byLocation),
		bySource: toCountRows(bySource),
		byVersion: toCountRows(byVersion),
		headline: {
			allHits: Number(headline?.all_hits) || 0,
			botUaHits: Number(headline?.bot_ua_hits) || 0,
			humanDownloads: Number(headline?.human_downloads) || 0,
			macHumanDownloads: Number(headline?.mac_human_downloads) || 0,
			networkFlaggable: Number(headline?.network_flaggable) || 0,
			networkFlagged: Number(headline?.network_flagged) || 0,
			uniqueHumanIps: Number(headline?.unique_human_ips) || 0,
		},
		macRolling: toRolling(macRolling),
		rolling: toRolling(rolling),
	};
}

function toRolling(row: RollingRow | undefined) {
	return {
		current: Number(row?.current) || 0,
		deltaPct:
			row?.delta_pct === null || row?.delta_pct === undefined ? null : Number(row.delta_pct),
		prior: Number(row?.prior) || 0,
	};
}

const USER_AGENT_LABEL_MAX = 72;

/**
 * Shortens a bot user agent for the owner report without cutting a token in half: a cut mid-word
 * turned `seranking.com` into `seranking.c`. Prefers the crawler's own URL or name token.
 */
export function shortenUserAgent(ua: string): string {
	if (ua.length <= USER_AGENT_LABEL_MAX) return ua;
	const cut = ua.slice(0, USER_AGENT_LABEL_MAX);
	const boundary = Math.max(cut.lastIndexOf(" "), cut.lastIndexOf(";"), cut.lastIndexOf("("));
	return `${(boundary > 24 ? cut.slice(0, boundary) : cut).trimEnd()}…`;
}

/** Shortened labels can collide when two agents differ only past the cut; their counts merge. */
function mergeShortenedUserAgents<T extends { label: string; count: number }>(rows: T[]): T[] {
	const merged = new Map<string, T>();
	for (const row of rows) {
		const label = shortenUserAgent(row.label);
		const existing = merged.get(label);
		merged.set(
			label,
			existing ? { ...existing, count: existing.count + row.count } : { ...row, label },
		);
	}
	return [...merged.values()].sort((left, right) => right.count - left.count);
}
