-- JP the Cat is free: retire the paid license server.
--
-- Drops everything 0004/0005/0008 created for checkout, licensing, trials, and the Stripe webhook
-- ledger. The edge functions that used these (checkout, current-price, stripe-webhook,
-- licenses-*, trials-start, growth-revenue) were removed in the same change, and the Mac app no
-- longer calls them. Downloads, request_throttle, and their pg_cron jobs stay.
--
-- DESTRUCTIVE. The final rows are archived in _docs/legacy-backup/license-server-rows-2026-11-05.json.
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft).

drop function if exists public.activate_seat(text, text, text, text, timestamptz);

drop table if exists public.activations;
drop table if exists public.trials;
drop table if exists public.stripe_webhook_events;
drop table if exists public.licenses;

-- Only the licenses updated_at trigger used this.
drop function if exists public.set_updated_at();
