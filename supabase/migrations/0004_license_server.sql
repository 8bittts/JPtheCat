-- License server spine (0-todos: License server + Phase 3).
--
-- Four tables backing the Supabase Edge Functions on api.jpthecat.com:
--   licenses              — one row per paid order (store only key_hash, never the raw key)
--   activations           — device seats under a license (offline_valid_until slides on validate)
--   trials                — server-anchored 7-day trial keyed by device_hash (defeats reinstall resets)
--   stripe_webhook_events — CAS idempotency lock for the Stripe webhook (throw-to-retry discipline)
--
-- These are SERVICE-ROLE ONLY. Unlike public.downloads (an anon INSERT sink), NOTHING here is
-- reachable by anon/authenticated: RLS is enabled with NO policies and grants are revoked, so the
-- only access is via the Edge Functions' service-role key (which bypasses RLS). A leaked anon key
-- can never read a license, a key_hash, a customer email, or a device seat.
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive only; does not touch downloads.

-- gen_random_uuid() lives in pgcrypto.
create extension if not exists pgcrypto;

-- ── licenses ────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.licenses (
	id                 uuid primary key default gen_random_uuid(),
	created_at         timestamptz not null default now(),
	updated_at         timestamptz not null default now(),
	-- SHA-256 (hex) of the raw JPC-XXXXX-… key. The raw key is emailed once and NEVER stored.
	key_hash           text not null unique,
	-- Idempotent mint anchor: a webhook retry re-inserting the same session is a no-op.
	stripe_session_id  text unique,
	stripe_customer_id text,
	-- Maps a later charge.refunded event back to this license (→ status refunded → Free Mode).
	stripe_payment_intent text,
	email              text,
	-- Set once the key email is confirmed sent, so a webhook retry re-emails until it succeeds and
	-- never after (the key is deterministic, so a retry would re-send the SAME key).
	key_emailed_at     timestamptz,
	-- active → full; refunded/revoked → the app slides to Free Mode on the next validate.
	status             text not null default 'active' check (status in ('active', 'refunded', 'revoked')),
	-- Seats: 1 Mac by default, +1 per extra-device add-on purchased.
	max_devices        integer not null default 1 check (max_devices >= 1),
	app_version        text
);

create index if not exists licenses_stripe_customer_idx on public.licenses (stripe_customer_id);
create index if not exists licenses_stripe_payment_intent_idx on public.licenses (stripe_payment_intent);

-- ── activations (device seats) ────────────────────────────────────────────────────────────────
create table if not exists public.activations (
	id                  uuid primary key default gen_random_uuid(),
	license_id          uuid not null references public.licenses (id) on delete cascade,
	-- SHA256(IOPlatformUUID + serial + salt) — never the raw platform UUID.
	device_hash         text not null,
	device_label        text,
	app_version         text,
	status              text not null default 'active' check (status in ('active', 'deactivated')),
	first_activated_at  timestamptz not null default now(),
	last_seen_at        timestamptz not null default now(),
	-- Server-anchored offline grace: now() + 30d on activate, slid forward on every validate.
	offline_valid_until timestamptz not null,
	deactivated_at      timestamptz,
	-- One seat row per (license, device): re-activating the same Mac updates in place, never duplicates.
	unique (license_id, device_hash)
);

create index if not exists activations_device_hash_idx on public.activations (device_hash);
create index if not exists activations_license_active_idx on public.activations (license_id, status);

-- ── trials (server-anchored) ──────────────────────────────────────────────────────────────────
create table if not exists public.trials (
	id           uuid primary key default gen_random_uuid(),
	device_hash  text not null unique,
	started_at   timestamptz not null default now(),
	last_seen_at timestamptz not null default now(),
	app_version  text
);

-- ── stripe_webhook_events (CAS idempotency lock) ──────────────────────────────────────────────
create table if not exists public.stripe_webhook_events (
	event_id     text primary key,
	type         text not null,
	status       text not null default 'processing' check (status in ('processing', 'processed', 'failed')),
	attempts     integer not null default 1,
	locked_at    timestamptz,
	processed_at timestamptz,
	created_at   timestamptz not null default now()
);

-- ── Lock everything down: RLS on, no policies, grants revoked (service role bypasses RLS) ──────
alter table public.licenses enable row level security;
alter table public.activations enable row level security;
alter table public.trials enable row level security;
alter table public.stripe_webhook_events enable row level security;

revoke all on public.licenses from anon, authenticated;
revoke all on public.activations from anon, authenticated;
revoke all on public.trials from anon, authenticated;
revoke all on public.stripe_webhook_events from anon, authenticated;

-- Keep updated_at honest on licenses (activations/trials track their own last_seen_at explicitly).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
-- Pinned empty search_path (advisor function_search_path_mutable); now() resolves from pg_catalog.
set search_path = ''
as $$
begin
	new.updated_at := now();
	return new;
end;
$$;

drop trigger if exists licenses_set_updated_at on public.licenses;
create trigger licenses_set_updated_at
	before update on public.licenses
	for each row execute function public.set_updated_at();

-- set_updated_at is only ever fired by the trigger (as table owner); it must not be callable through
-- the exposed PostgREST /rpc surface by anon/authenticated (mirrors the 0002 rls_auto_enable revoke).
revoke execute on function public.set_updated_at() from public, anon, authenticated;
