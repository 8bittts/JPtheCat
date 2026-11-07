-- Add privacy-preserving download intelligence for operator review.
--
-- Postal code comes from Vercel's approximate IP geo header. Network fields are
-- optional ipapi.is-derived context used to distinguish normal browser traffic
-- from hosting/VPN/datacenter-looking downloads. No latitude/longitude is stored.

alter table public.downloads
	add column if not exists postal_code text,
	add column if not exists network_asn text,
	add column if not exists network_org text,
	add column if not exists network_is_hosting boolean,
	add column if not exists network_is_anonymous boolean;

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
		and char_length(coalesce(city, '')) <= 512
		and char_length(coalesce(country, '')) <= 8
		and char_length(coalesce(postal_code, '')) <= 32
		and char_length(coalesce(region, '')) <= 64
		and char_length(coalesce(timezone, '')) <= 128
		and char_length(coalesce(network_asn, '')) <= 32
		and char_length(coalesce(network_org, '')) <= 240
		and char_length(coalesce(ua, '')) <= 512
	);
