-- Hardening pass after Supabase security advisors.
--
-- 1. downloads_insert_anon was WITH CHECK (true) — flagged rls_policy_always_true. Replace it
--    with a payload-shape check: still INSERT-only for the public sink, but bounds field
--    lengths so the anon endpoint can't be used to store arbitrary/oversized junk. The web
--    route always sends a non-null version + source, so legitimate writes still pass.
-- 2. rls_auto_enable() is a pre-existing SECURITY DEFINER event trigger (auto-enables RLS on
--    new public tables). It was callable via /rest/v1/rpc by anon/authenticated through the
--    default PUBLIC EXECUTE grant. Event triggers fire as the table owner regardless of
--    grants, so revoking EXECUTE from PUBLIC removes it from the exposed API with no behavior
--    change. Clears advisors 0028/0029.

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
		and char_length(coalesce(country, '')) <= 8
		and char_length(coalesce(ua, '')) <= 512
	);

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
