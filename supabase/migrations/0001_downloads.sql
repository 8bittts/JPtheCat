-- Durable download spine for the /growth review.
--
-- One row per /download redirect, written by the web route via PostgREST with the
-- public anon key. INSERT-only under RLS: the web runtime can append telemetry but
-- can never read it back. Growth reads run over the direct Postgres connection
-- (postgres role bypasses RLS) in web/scripts/growth-metrics.ts.
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive only.

create table if not exists public.downloads (
	id          bigint generated always as identity primary key,
	created_at  timestamptz not null default now(),
	version     text,
	source      text,
	referer     text,
	ip          text,
	country     text,
	ua          text,
	is_bot      boolean not null default false
);

-- Query patterns: time-windowed rollups, split by human/bot and by source/version.
create index if not exists downloads_created_at_idx on public.downloads (created_at desc);
create index if not exists downloads_is_bot_created_at_idx on public.downloads (is_bot, created_at desc);

alter table public.downloads enable row level security;

-- Write-only sink: anon/authenticated may INSERT, nobody may SELECT/UPDATE/DELETE
-- through the API. (The growth script uses the postgres role, which bypasses RLS.)
drop policy if exists downloads_insert_anon on public.downloads;
create policy downloads_insert_anon
	on public.downloads
	for insert
	to anon, authenticated
	with check (true);
