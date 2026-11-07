-- Atomic rate-limit sink for the public POST surfaces (the owner-notification email on
-- /download and newsletter signups). Same design as public.downloads: written by the web route
-- via PostgREST with the public anon key, INSERT-only under RLS, never read back through the
-- API — NO service-role key in the web runtime. The bucket_key encodes action + identifier +
-- a fixed time window; the primary key turns a second hit in the same window into a
-- unique_violation (HTTP 409) that the route reads as "rate limited".
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive only; the web code fails
-- OPEN when the table is absent, so dropping this table fully and safely reverts the feature.

create table if not exists public.request_throttle (
	bucket_key text primary key,
	created_at timestamptz not null default now()
);

-- Rows are only meaningful for their window; the index supports a periodic purge of old rows.
create index if not exists request_throttle_created_at_idx on public.request_throttle (created_at);

alter table public.request_throttle enable row level security;

-- Write-only sink: anon/authenticated may INSERT a bounded bucket key; nobody may
-- SELECT/UPDATE/DELETE through the API. A duplicate bucket_key raises a unique_violation
-- (HTTP 409) which the route interprets as "rate limited".
grant insert on table public.request_throttle to anon, authenticated;

drop policy if exists request_throttle_insert_anon on public.request_throttle;
create policy request_throttle_insert_anon
	on public.request_throttle
	for insert
	to anon, authenticated
	with check (char_length(bucket_key) between 1 and 200);
