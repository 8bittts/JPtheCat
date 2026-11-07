-- Make the /growth human-download filters survive two things that silently inflated the headline
-- in Sep–Oct 2026 (_docs/17-engineering-log.md#download-telemetry-and-newsletter):
--
-- 1. `is_mac` — the platform of the downloading browser, persisted at write time from the frozen
--    `Mozilla/5.0 (Macintosh; …` token. 86% of "human" rows in Oct 2026 were Windows/Android browsers
--    pulling a macOS DMG they cannot open. The 0010 redaction nulls `ua` after 30 days, so the platform
--    has to be a column or it is lost with the UA.
-- 2. `exclusion` — a durable stamp (`monitor` / `burst`) for the two read-time rules that key on the
--    IP. 0010's job nulls `ip` after 30 days and the human CTE admits `ip is null` rows outright, so a
--    scanner caught by the monitor rule today became "human" a month later (GrowthScan/0.1: 136 rows).
--    The rescheduled job now stamps `exclusion` with the same two rules (8-second burst window, 4
--    distinct days) BEFORE nulling the identifiers. The constants mirror
--    web/lib/analytics/growth-download-sql.ts; change both together.
--
-- Backfills run once on rows that still hold a UA/IP (the last 30 days); older rows keep null `is_mac`
-- and are reported as "platform unknown", never reclassified. The insert policy pins `exclusion` to
-- null so the anon web key can never stamp it. pg_cron runs as the table owner; no web key gains
-- UPDATE. Revert: `select cron.unschedule('redact_downloads_pii');` then re-run 0010's schedule.
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive only.

alter table public.downloads
	add column if not exists is_mac boolean,
	add column if not exists exclusion text;

-- Write-time platform for rows that still carry a UA.
update public.downloads
	set is_mac = (lower(ua) like 'mozilla/5.0 (macintosh%')
	where ua is not null and is_mac is null;

-- UA markers added to web/lib/analytics/download-bot.ts in the same change; rows that still hold a UA
-- get the write-time classification they would receive today.
update public.downloads
	set is_bot = true
	where is_bot = false
	  and ua is not null
	  and (lower(ua) like '%growthscan%'
	    or lower(ua) like '%scan/%'
	    or lower(ua) like '%pdfmin%'
	    or lower(ua) like '%observatory%'
	    or lower(ua) like '%smoke%');

-- Durable read-time exclusions for every row that still holds an IP.
with base as (
	select id, ip, source, created_at
	from public.downloads
	where ip is not null
	  and source not in ('smoke-test', 'production-test')
	  and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
),
monitor_ips as (
	select ip from base group by ip having count(distinct created_at::date) >= 4
),
burst_ips as (
	select distinct a.ip
	from base a
	join base b
	  on a.ip = b.ip
	 and a.source <> b.source
	 and abs(extract(epoch from a.created_at - b.created_at)) <= 8
)
update public.downloads d
	set exclusion = case
		when d.ip in (select ip from monitor_ips) then 'monitor'
		when d.ip in (select ip from burst_ips) then 'burst'
	end
	where d.exclusion is null
	  and d.ip is not null
	  and (d.ip in (select ip from monitor_ips) or d.ip in (select ip from burst_ips));

-- The anon web key may insert a row but never a stamp.
drop policy if exists downloads_insert_anon on public.downloads;
create policy downloads_insert_anon
	on public.downloads
	for insert
	to anon, authenticated
	with check (
		version is not null and char_length(version) <= 64
		and source is not null and char_length(source) <= 64
		and char_length(coalesce(referer, '')) <= 512
		and char_length(coalesce(ip, '')) <= 64
		and char_length(coalesce(city, '')) <= 512
		and char_length(coalesce(country, '')) <= 8
		and char_length(coalesce(postal_code, '')) <= 32
		and char_length(coalesce(region, '')) <= 64
		and char_length(coalesce(timezone, '')) <= 128
		and char_length(coalesce(network_asn, '')) <= 32
		and char_length(coalesce(network_org, '')) <= 240
		and char_length(coalesce(ua, '')) <= 512
		and exclusion is null
	);

-- Reschedule the daily redaction: stamp first, then null. Same 30-day window as 0010.
create extension if not exists pg_cron;

select cron.unschedule('redact_downloads_pii');

select cron.schedule(
	'redact_downloads_pii',
	'23 4 * * *',
	$$with base as (
	    select id, ip, source, created_at
	    from public.downloads
	    where ip is not null
	      and source not in ('smoke-test', 'production-test')
	      and coalesce(ua, '') not like 'JP-the-Cat-smoke-test-bot/%'
	),
	monitor_ips as (
	    select ip from base group by ip having count(distinct created_at::date) >= 4
	),
	burst_ips as (
	    select distinct a.ip
	    from base a
	    join base b
	      on a.ip = b.ip
	     and a.source <> b.source
	     and abs(extract(epoch from a.created_at - b.created_at)) <= 8
	)
	update public.downloads d
	    set exclusion = case
	        when d.ip in (select ip from monitor_ips) then 'monitor'
	        when d.ip in (select ip from burst_ips) then 'burst'
	    end
	    where d.exclusion is null
	      and d.ip is not null
	      and d.created_at < now() - interval '30 days'
	      and (d.ip in (select ip from monitor_ips) or d.ip in (select ip from burst_ips));
	update public.downloads
	    set ip = null, ua = null, referer = null
	    where created_at < now() - interval '30 days'
	      and (ip is not null or ua is not null or referer is not null)$$
);
