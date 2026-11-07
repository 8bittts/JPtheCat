// Shared `/download` human-funnel SQL, used by BOTH the growth-metrics CLI (which talks to Postgres
// through Bun's `SQL`) and the growth-digest data loader (which uses the `postgres` npm client). The
// burst window + the "real human download" CTE lived, byte-for-byte, in both files and had already
// started to drift; keeping them here is the single source of truth for the /download spine documented
// in AGENTS.md ("never report all_hits as downloads — always mac_human_downloads").
//
// Typed structurally over "anything callable as a SQL tagged template" so it works with either client
// without importing (or coupling to) either library's concrete type.

/// Same-IP burst window: a client hitting >=2 distinct CTA sources within this many seconds is treated
/// as one automated burst, not multiple human downloads (a UA check alone can't catch it).
/// Mirrored in migration 0011's redaction job, which stamps `exclusion` with the same rule before the
/// IP is nulled; change both together.
const BURST_SECONDS = 8;

/// An IP downloading on this many distinct days is a monitor, not a person; the burst window cannot
/// see a slow repeat. Mirrored in migration 0011 the same way.
const MONITOR_DISTINCT_DAYS = 4;

/// The `burst_ips` + `monitor_ips` + `human` + `mac_human` CTEs.
///
/// A row is in `human` when it is not an owner smoke source (`smoke-test`/`production-test` or the
/// `JP-the-Cat-smoke-test-bot/…` UA), not a UA-flagged bot (`is_bot = false`), not stamped with a
/// durable read-time `exclusion` (migration 0011 writes `monitor`/`burst` before the 30-day PII job
/// nulls the IP, so the rule survives redaction), not from a datacenter/hosting or anonymizing network
/// (`network_is_hosting` / `network_is_anonymous`; a `null` flag means the lookup returned nothing and
/// the row is NOT proven clean — readers print the flag coverage beside every headline), not part of a
/// same-IP multi-source burst within `BURST_SECONDS`, and not from an IP downloading on
/// >= `MONITOR_DISTINCT_DAYS` distinct days.
///
/// `mac_human` is the headline population: `human` rows whose browser can actually open the DMG
/// (`is_mac`, persisted at write time from the frozen `Macintosh; Intel Mac OS X 10_15_7` token so it
/// survives UA redaction). A Windows or Android browser pulling a macOS DMG is never an install.
/// Interpolate the result at the head of a larger query:
///   sql`${humanDownloadsCte(sql)} select count(*) from mac_human where …`
// The two callers use different SQL client libraries (bun `SQL` and `postgres`); their overloaded
// tagged-template call signatures only unify under an `any`-argument function type. The only value
// ever interpolated here is our own numeric constant, so this is not a real type hole.
export function humanDownloadsCte<Query>(
	// biome-ignore lint/suspicious/noExplicitAny: cross-library tagged-template unification (see above)
	sql: (strings: TemplateStringsArray, ...values: any[]) => Query,
): Query {
	return sql`
		with burst_ips as (
			select distinct a.ip
			from downloads a
			join downloads b
				on a.ip = b.ip
				and a.source <> b.source
				and abs(extract(epoch from a.created_at - b.created_at)) <= ${BURST_SECONDS}
			where a.ip is not null
				and a.source not in ('smoke-test', 'production-test')
				and b.source not in ('smoke-test', 'production-test')
				and coalesce(a.ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
				and coalesce(b.ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
		),
		monitor_ips as (
			select ip
			from downloads
			where ip is not null
				and source not in ('smoke-test', 'production-test')
				and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
			group by ip
			having count(distinct created_at::date) >= ${MONITOR_DISTINCT_DAYS}
		),
		human as (
			select d.*
			from downloads d
			where d.is_bot = false
				and d.exclusion is null
				and d.source not in ('smoke-test', 'production-test')
				and coalesce(d.ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
				and coalesce(d.network_is_hosting, false) = false
				and coalesce(d.network_is_anonymous, false) = false
				and (d.ip is null or (
					d.ip not in (select ip from burst_ips)
					and d.ip not in (select ip from monitor_ips)
				))
		),
		mac_human as (
			select h.*
			from human h
			where h.is_mac = true
		)
	`;
}
