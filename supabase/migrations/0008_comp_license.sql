-- Complimentary "free unlock" coupon license.
--
-- The coupon code `JPJPJP` (see _shared/keys.ts COMP_LICENSE_CODE) is redeemed in the app's license
-- modal exactly like a JPC- key: licenses-activate hashes the normalized code (sha256("JPJPJP")) and
-- claims a seat via activate_seat, minting a real signed lease. This seeds the matching row so the
-- code resolves to Pro. High max_devices so it grants across many Macs without hitting the seat limit.
--
-- sha256("JPJPJP") = 8c3f4573a31c0e2b460d126245f677855c7f09aa13801c49af8d1ebd27154163
--
-- Apply to the JPtheCat project (ref duqpnrpzadrxqdbspjft). Additive; idempotent on key_hash.

-- max_devices is int-max (2147483647) so the giveaway code works effectively INFINITELY — every early
-- user's Mac claims its own seat and it never hits a seat limit.
insert into public.licenses (key_hash, status, max_devices, email)
values (
	'8c3f4573a31c0e2b460d126245f677855c7f09aa13801c49af8d1ebd27154163',
	'active',
	2147483647,
	null
)
on conflict (key_hash) do update set
	status = 'active',
	max_devices = excluded.max_devices;
