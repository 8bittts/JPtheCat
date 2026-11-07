-- Bound growth of the request_throttle rate-limit sink. Rows are only meaningful for their window
-- (at most 1 hour, for the download-owner-email bucket), so an hourly job deletes anything older
-- than 2 hours. pg_cron runs in-DB as the table owner, so NO web-runtime key needs DELETE on the
-- table — consistent with the anon INSERT-only design. Revert: unschedule the job + drop pg_cron.
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive only.

create extension if not exists pg_cron;

select cron.schedule(
	'purge_request_throttle',
	'17 * * * *',
	$$delete from public.request_throttle where created_at < now() - interval '2 hours'$$
);
