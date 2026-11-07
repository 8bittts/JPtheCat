# AGENTS.md — jpthecat/supabase

The Postgres migrations for the project behind `api.jpthecat.com` (release storage, the `downloads` growth table, `request_throttle`, and the growth cron jobs).
JP the Cat is free: there are no edge functions, no checkout, no license, trial, or Stripe tables (dropped in `0012_drop_license_server.sql`; the final rows are archived in `../_docs/legacy-backup/`).
The repo root's [AGENTS.md](../AGENTS.md) owns the cross-cutting rules (branding, worktrees, release, privacy).

## Migrations

Migrations under `supabase/migrations/` are applied by hand through the Supabase MCP `apply_migration` (the project's migration history carries timestamped names, not the file numbers; `0003` and `0009` were applied without a history row).
Nothing in this repository applies them automatically, so landing a migration is not shipping it.
A web change that inserts a new column (`0011` added `is_mac`) must have its migration applied BEFORE the `[deploy]`, or PostgREST rejects every `/download` row and the swallowed persistence error loses the telemetry silently.

## Keys

**[CRITICAL] Never revoke the HS256 legacy JWT signing key.**
`mac/scripts/release-jpthecat.sh` lists and uploads releases with `supabase storage`, which (CLI 2.121) still signs those requests with the legacy `service_role` JWT, so a revoked key fails every release with `signature verification failed`.
Keep it `previously_used` or `standby`.
