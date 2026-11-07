-- Add coarse Vercel edge geo context to the durable /download spine.
--
-- The web route records city, country region, and timezone when Vercel provides
-- those headers. No latitude/longitude is stored. The sink remains INSERT-only:
-- anon/authenticated can append bounded telemetry rows but cannot read them back.

alter table public.downloads
	add column if not exists city text,
	add column if not exists region text,
	add column if not exists timezone text;

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
		and char_length(coalesce(region, '')) <= 64
		and char_length(coalesce(timezone, '')) <= 128
		and char_length(coalesce(ua, '')) <= 512
	);
