-- Bound PII retention in the download telemetry sink (0001_downloads). The /growth review needs the
-- aggregate spine (created_at, version, source, country, is_bot) for long-term trends, but the raw
-- identifiers — ip, ua, referer — are only useful for RECENT bot/burst classification. Storing them
-- indefinitely is a standing privacy liability, so a daily job redacts (NULLs) just those three
-- columns on rows older than 30 days. Aggregate history stays intact; no raw IP/UA/referer is kept
-- beyond the window. Write-time bot classification already persists in `is_bot`, so redacting old
-- identifiers does not change how humans-vs-bots are counted.
--
-- Runs in-DB as the table OWNER (pg_cron), which bypasses RLS — so NO web-runtime UPDATE/DELETE key
-- is granted, consistent with the anon INSERT-only design of 0001/0002. Mirrors the 0007 throttle
-- purge. The `and (... is not null ...)` guard makes the daily run idempotent (already-redacted rows
-- are skipped, no write churn). Revert: `select cron.unschedule('redact_downloads_pii');`.
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive only.

create extension if not exists pg_cron;

select cron.schedule(
	'redact_downloads_pii',
	'23 4 * * *',
	$$update public.downloads
	    set ip = null, ua = null, referer = null
	    where created_at < now() - interval '30 days'
	      and (ip is not null or ua is not null or referer is not null)$$
);
