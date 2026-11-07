-- Atomic seat claiming (closes the activate TOCTOU race).
--
-- The naive "read active seats, then upsert" in licenses-activate is not atomic: two concurrent
-- activations of DIFFERENT devices could both pass the seat check and both insert, exceeding
-- max_devices. This function does the check + claim under a row lock on the license (SELECT ... FOR
-- UPDATE), so concurrent activations for the same license serialize. Called via PostgREST rpc by the
-- service role only.
--
-- Returns JSONB (not a TABLE) deliberately: a `returns table (... license_id ...)` OUT column collides
-- with `activations.license_id` throughout the body ("column reference license_id is ambiguous").
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive only.

create or replace function public.activate_seat(
	p_key_hash text,
	p_device_hash text,
	p_device_label text,
	p_app_version text,
	p_valid_until timestamptz
)
returns jsonb
language plpgsql
-- Pinned empty search_path (advisor); everything below is schema-qualified and now() is pg_catalog.
set search_path = ''
as $$
declare
	v_license public.licenses;
	v_others integer;
begin
	-- Lock the license row: concurrent activations for the same license serialize here, so the
	-- seat count below can't be read stale by a racing caller.
	select * into v_license from public.licenses where key_hash = p_key_hash for update;
	if not found then
		return jsonb_build_object('result', 'invalid');
	end if;
	if v_license.status <> 'active' then
		return jsonb_build_object('result', 'inactive', 'license_id', v_license.id, 'max_devices', v_license.max_devices);
	end if;

	-- Count active OTHER devices (this device re-activating its own seat never consumes one).
	select count(distinct device_hash) into v_others
	from public.activations
	where activations.license_id = v_license.id and status = 'active' and device_hash <> p_device_hash;

	if v_others >= v_license.max_devices then
		return jsonb_build_object('result', 'seat_limit', 'license_id', v_license.id, 'max_devices', v_license.max_devices);
	end if;

	-- Claim/refresh this device's seat. first_activated_at is omitted so it survives reactivation.
	insert into public.activations (
		license_id, device_hash, device_label, app_version, status, last_seen_at, offline_valid_until, deactivated_at
	)
	values (
		v_license.id, p_device_hash, p_device_label, p_app_version, 'active', now(), p_valid_until, null
	)
	on conflict (license_id, device_hash) do update set
		device_label = excluded.device_label,
		app_version = excluded.app_version,
		status = 'active',
		last_seen_at = now(),
		offline_valid_until = excluded.offline_valid_until,
		deactivated_at = null;

	return jsonb_build_object('result', 'ok', 'license_id', v_license.id, 'max_devices', v_license.max_devices);
end;
$$;

-- Service-role only (like the tables): not callable through the exposed anon/authenticated API.
revoke execute on function public.activate_seat(text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.activate_seat(text, text, text, text, timestamptz) to service_role;
