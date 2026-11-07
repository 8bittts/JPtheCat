# Growth

Bot filtering, the download spine, readers, the owner digest, and the /library programmatic SEO strategy.

How the acquisition funnel is measured and kept honest.
The `/growth` command (`.claude/commands/growth.md`) is the runbook; dated reports live in the gitignored `_docs/growth/`; the command and reports stay operator-local.
JP the Cat is free and app usage stays local, so the server-side spine is narrow: download rows plus aggregate web traffic and search.

```
traffic → CTA click → /download redirect
(GSC, Vercel)  (Vercel events)  (downloads table)
```

> [NOTE] A raw `/download` hit is NOT an install. Every growth number leads with `mac_human_downloads`, never `human_downloads` and never `all_hits`.

## 1. Bot filtering

An early overnight sample of download notices was almost entirely automated, because the notifier fired on the redirect.
A row counts as a human download only if it passes all of these; removing any layer reopens a measured inflation hole:
1. **Owner smoke sources** (`smoke-test`, `production-test`, the `JP-the-Cat-smoke-test-bot/…` user agent) are excluded.
2. **User-agent denylist at write time** — `web/lib/analytics/download-bot.ts` sets `is_bot` for empty and known automated agents, including self-named scanners (`growthscan`, `pdfmin`, `observatory`) and the operator's `smoke` agents.
3. **Same-IP burst at read time** (`burst_ips`) — two or more distinct CTA sources from one IP inside 8 seconds.
4. **Hosting or anonymizing networks** (`network_is_hosting`, `network_is_anonymous`) — 54% of non-bot rows were datacenter or anonymous while the lookup worked (Jul–Aug 2026).
   A `null` flag means the lookup returned nothing, not "clean": every reader prints `network_flagged / network_flaggable` beside the headline, and the digest raises a `Needs attention` issue for any gap.
5. **Repeat monitors** (`monitor_ips`) — an IP downloading on four or more distinct days, which the burst window cannot see.
6. **Durable exclusion stamp** (`exclusion`) — migration `0011` rewrites the redaction job to stamp `monitor` / `burst` on a row BEFORE nulling its IP, because the human CTE admits `ip is null` rows and a scanner caught today otherwise became human a month later.
7. **Platform** (`is_mac`, persisted at write time) — the headline `mac_human` population keeps only macOS browsers, the one client that can open the DMG; 86% of "human" rows in Oct 2026 were Windows or Android browsers.

The read-time rules live in one module, `web/lib/analytics/growth-download-sql.ts`, shared by the CLI reader and the digest because the two drifted once (guard: `web/tests/growth-download-sql.test.ts`, which also pins the burst and monitor constants to migration `0011`).
The 30-day PII redaction nulls `ip`, `ua`, and `referer`; `is_bot`, `is_mac`, and `exclusion` are the only classifications that survive it, so rows redacted before `is_mac` existed (before 2026-09-21) report as `platform_unknown` and never get a Mac figure.

## 2. The download spine

- **Table** `public.downloads` (migrations `0001`, `0002`, `0003`, `0009`, `0010`, `0011`): version, source, referer, coarse geo, network context, user agent, `is_bot`, `is_mac`, and `exclusion`; `0010` schedules the daily redaction through `pg_cron` and `0011` makes it stamp `exclusion` first.
  The insert policy pins `exclusion` to null, so the web key can never stamp a row.
- **Write path:** `web/app/download/route.ts` builds a bot-classified record (`web/lib/analytics/downloads-store.ts`) and POSTs it to PostgREST inside `after()`, sending the publishable key (`SUPABASE_PUBLISHABLE_KEY`) on the `apikey` header only.
  Persistence and email run under `Promise.allSettled`, so telemetry never breaks the download; bot rows persist but never email.
- **Sources:** the route stores only `direct`, `pricing`, `library`, and `production-test` (`ALLOWED_DOWNLOAD_SOURCES`); any other value becomes `external`.
  Every homepage CTA (hero, pricing, FAQ) sends `pricing` on purpose so the by-source trend stays continuous with older rows; `hero` and `nav` are retired values.
  Splitting homepage placements would start a new series, so do it only by explicit decision.
- **Enrichment:** coarse Vercel edge headers (city, region, country, timezone; postcode is not stored since 2026-11-06) plus a fail-soft ipapi.is lookup for ASN and hosting flags; no latitude or longitude is stored.
  **`IPAPI_IS_KEY` is required for the hosting filter, not optional:** since 2026-09-01 the keyless free tier returns a string `asn`, no `is_datacenter`, and no `is_vpn`, and caps at 30 lookups per client IP per day, so without a key every row carries `null` flags and the datacenter rule is blind.
  A free ipapi.is account restores the flags at 1,000 lookups a day; set the key in Vercel Production and ship a `[deploy]`.
  The parser accepts both shapes and keeps an absent flag `null` (guard: `web/tests/download-network-intel.test.ts`).
- **RLS:** INSERT-only for `anon`/`authenticated` with a payload-shape `WITH CHECK` (never `WITH CHECK (true)`); readers connect as `postgres` over the session pooler.
  Re-run Supabase advisors after any DDL.
- **No Supabase SDK** in the web runtime; one `fetch` to `/rest/v1/downloads`.

## 3. Readers

- `web/scripts/growth-metrics.ts [days] [--json]` — read-only Postgres over the pooler (`SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`): headline (`mac_human_downloads` first, `human_downloads` for continuity, `network_flagged / network_flaggable` for filter coverage), window deltas for both populations, monthly trend with `platform_unknown`, platform split, Mac-only source, version, and country, and bot agents.
- `web/scripts/growth-extra.ts [days] [--json]` — the per-layer filter table and Vercel Web Analytics; it reads the Vercel CLI's own auth, so no token is copied into `.env.local`, and it prints aggregates only.
- `web/scripts/analytics-pull.ts` — Search Console queries, pages, trends, and countries; run at 30 and 90 days to diff rising queries.
  The OAuth refresh token is per Google account, so the existing DeathNote client with `webmasters.readonly` is reused; a clean worktree without credentials prints a setup notice and exits 0.
- **Website traffic** is Vercel Web Analytics and Speed Insights (no GA4); custom events (`download_cta_clicked`, `library_download_cta_clicked`, `download_modal_opened`, `library_download_modal_opened`) are not bot-filtered.
  They were Title Case until 2026-10-22; `LEGACY_PRODUCT_EVENT_NAMES` lets the digest count both spellings until no window reaches back that far.
  Every custom event goes through `trackProductEvent` in `web/lib/analytics/product-analytics.ts`; its `ProductEventName` union also types the digest's `countFor`, so a renamed event fails typecheck, and `web/tests/product-analytics.test.ts` fails if any other file imports `track` from `@vercel/analytics`.
- **24-hour ground truth:** Supabase Storage logs show real DMG byte fetches for one day; redirect rows without a fetch are bots.
- **Deploy cadence:** `vercel ls`, read-only.

## 4. Owner daily report and notices

`GET /api/cron/growth-digest` is the one owner report per day.
Vercel Cron calls it at `0 3 * * *` and `0 4 * * *` UTC behind `CRON_SECRET`; `lib/analytics/rollup-schedule.ts` lets through only the firing that is 20:00 in Los Angeles, so the report follows the Pacific clock through daylight saving.
It covers the last 24 hours; a Pacific Monday adds a `Trend: last 7 days` section and the Pacific 1st adds `Trend: last 30 days`, which replaced the separate weekly and monthly digests.
It renders `web/emails/growth-digest.tsx` through `web/lib/email/send-helper.tsx` (Resend idempotency plus transient retry) to `GROWTH_DIGEST_TO`, else `DOWNLOAD_NOTIFICATION_TO`; with neither set it sends nothing and returns 503 `RECIPIENT_NOT_CONFIGURED`.
The idempotency key is the Los Angeles date plus a body fingerprint, so a same-day re-run with moved data does not collide in Resend.
Any skipped or failed send returns non-200 so Vercel Cron shows the failure; the off-hour firing returns `200 {"due":false}`.
Previews use `?sample&sample_id=<slug>` (add `sample=all` for both trend sections); they skip the clock gate and carry `[Sample]` subjects and separate idempotency keys.
A preview call needs the real `CRON_SECRET`, which no env pull returns; without it, call `runGrowthDigestRequest` from `web/` with a one-time local `CRON_SECRET`, and supply `VERCEL_TOKEN`, which `.env.local` lacks, or the Vercel leg reads `not configured`.

The report leads with a `Needs attention` block from `buildIssues` (a failed data leg or a blind hosting filter), and its subject counts Mac downloads and issues; a `not configured` leg (no credentials) is a choice, not an issue.
Everything stays aggregate: download spine, Vercel analytics, and Search Console.
It never includes prompts, code, transcripts, token history, costs, credentials, project paths, raw IPs, or the local usage database.
Search Console queries and pages rank by clicks, then impressions.

Immediate notices are limited to customer messages: the in-app support report. Downloads never email one by one beyond the owner download notice.
Owner-notice idempotency keys come from body-visible event fields plus a hashed identity, never an hourly bucket.

**Production env:** `CRON_SECRET`; `RESEND_API_KEY` with `RESEND_FROM_EMAIL` and the `*_NOTIFICATION_TO` / `GROWTH_DIGEST_TO` overrides; `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`; `VERCEL_TOKEN`; `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GOOGLE_OAUTH_REFRESH_TOKEN`, `GSC_SITE_URL`.

## 5. Operating notes

- `/growth` is read-only and never deploys.
- `vercel env pull` never returns a Sensitive value: it writes an empty string or a bracketed placeholder (measured for `CRON_SECRET`), so a pulled value is neither the secret nor evidence that it is missing; a `(skipped: … not set)` line means the local shell lacks it.
- Vercel snapshots env per deployment: after adding or rotating `CRON_SECRET`, ship a fresh `[deploy]` before treating it as live.
- Reports go to `_docs/growth/<YYYY-MM-DD>-growth.md` (overwrite on a same-day re-run) with a row in `_docs/growth/README.md`; they hold real funnel metrics, so the folder is gitignored and never public.
  Read current numbers from the newest report, never from this doc.

## SEO & Programmatic SEO — the `/library` Hub

Owner doc for organic search: why `/library` exists, its page families, and the guardrails that keep it honest.
The engine is adapted from `zoedate`'s `/library` (crawlable-but-unlinked hub, anti-thin eligibility gate, pure content generators, per-page JSON-LD, gated sitemap) and swaps its geography for a bounded product registry.
Every count is a gate-computed ceiling, never a target; padding to a number is what Google's helpful-content system punishes.

### 1. Thesis

- **Out-data the field:** every page is fed by data the app ships — the bundled pricing table, the provider registry, and documented plan mechanics.
  Where our data is deep (cache-write split, model-specific context tiers) we beat flat price recaps; where it is thin, we fold the model into a family table.
- **Out-honest the field:** real dollars (Claude), notional list price (other providers), official percentages (Codex automatic; Claude and Grok opt-in), and measured gateway caps (OpenCode Go) are labelled everywhere.
  Only the live set is called tracked, which itself differentiates JP.
- **Convert intent:** the highest-intent clusters (usage tracker, cost calculator, "am I going to hit my limit", ccusage alternative) map to shipped features and a real interactive calculator.
- **Boundedness is the moat:** pages are bounded by real models, providers, plans, tools, and terms.

Competitors move fast; re-verify any rival's numbers before citing them.
The structural gaps that still hold: free CLIs publish no marketing library, content farms have no product and blur subscription versus notional cost, and other rivals lack real cache-tier data and provenance labels.

### 2. Page families

URL root `/library`, routes under `web/app/library/`, data under `web/lib/library/`.

| Family | Route | Data | Honesty rule |
|---|---|---|---|
| Hub, sections, provider status matrix | `/library`, `/library/[section]` | Live child counts from every registry | Names only the live set as tracked; every other provider shows its roadmap status word |
| Model pricing | `/library/pricing/[model]` | `pricing-default.json`; eligible with ≥5 populated price fields or a curated override (`eligibleModelIds()`) | Non-Claude titles say "API list price"; notional note above the fold; no Offer schema |
| Vendor pricing family | `/library/pricing/family/[vendor]` | Pricing registry grouped by vendor | Houses thin models in one table |
| Provider tracking | `/library/track/[provider]` | `PROVIDERS` in `web/lib/site.ts` | A non-live page never says JP tracks it today |
| Provider limits | `/library/limits/[provider]` | Exactly the `LIMIT_MECHANICS` keys in `content/limits.ts` | Claude and Grok are opt-in, Codex automatic, OpenCode Go measured, Cursor an opt-in API read; never a fabricated denominator |
| Calculators | `/library/calculators/[calc]` | `calculators-manifest.ts` over `calculator-math.ts` | SSR worked example works without JS; per-model cache rates; the 200K tier only in the single-request calculator |
| Comparisons | `/library/compare/[a]-vs-[b]` | `competitors-registry.ts`, pricing registry; allowlisted pairs with ≥3 attributes a side | No shared cost column across real and notional dollars; no disparagement |
| Alternatives | `/library/alternatives/[tool]` | Same registry | Fair to other free tools; JP is the free honest option, not "the best" |
| Guides | `/library/guides/[slug]` | `guides-manifest.ts`: real commands, paths, and opt-in flows | Never invents a request cap; Claude live percent is opt-in |
| Plans | `/library/plans/[plan]` | `plans-registry.ts` | Message counts are rough and unofficial; promotions carry their expiry |
| Glossary | `/library/glossary/[term]` | `glossary-registry.ts`; each term carries a real mechanic and a pricing or calculator link | Reinforces the provenance vocabulary |

### 3. Guardrails

1. **Honesty is a hard fail.** The live set is `{claude, codex, grok, muse_spark, opencode, opencodego}`; copy names it through `liveProviderNames()`, and every non-Claude dollar co-occurs with a notional marker.
   `library-honesty.test.ts` asserts on rendered output, not registry inspection.
2. **Route eligibility and search eligibility are separate.** `providerLibraryDataScore >= LIBRARY_DATA_SCORE_GATE` decides whether a provider page renders; only live providers are indexed, and roadmap leaves carry `noindex,follow` and stay out of the sitemap.
3. **`pricing-default.json` is the sole source** for which models get a page and their numbers; `pricing-data.ts` mirrors it under a parity test, and a canonical slug↔id map handles dotted ids, `-preview` suffixes, and the `claude`↔`claude-code` provider slug.
4. **Counts are computed and snapshotted**, never targeted; read current numbers from `libraryUrlEntries()` and `populatedPriceFieldCount()`.
5. **Every route renders per request** (the root layout is `force-dynamic` for the nonce CSP), and an ineligible slug calls `notFound()`.
6. **No fabricated structured data:** no `AggregateRating` or `Review`; `SoftwareApplication` only on JP and live-provider surfaces; the single `Offer` lives in the homepage JSON-LD (`web/lib/home-json-ld.ts`); FAQ JSON-LD only where answers vary by real data.
7. **Crawlable but unlinked:** `/library` is in `sitemap.ts` and never in nav or footer (`library-chrome.test.ts`); one low-prominence homepage FAQ link passes equity to `/library/pricing`.
8. **Canonical host** `https://jpthecat.com` via `canonicalUrl()`, per-page metadata via `pageMetadata()`, and 60/160 SERP caps enforced by `seo.test.ts`.
9. **Deterministic sitemap:** only search-eligible URLs plus important static pages; omit `lastModified` until a URL has a verifiable per-page source date.
10. **Downloads stay gated:** every `/library` CTA renders off the same `version.json` data as `/download`, and uses `DownloadCta` with `source="library"` so SEO installs are a distinct channel ([08-growth.md](08-growth.md)).
11. **Money formatting** matches the app's `MoneyFormatter` (USD, locale grouping).
12. **Calculators** are pure React state with an SSR fallback under the strict nonce CSP.
13. **Homepage curation** never removes library models, providers, routes, or sitemap entries.

**Pricing provenance in copy:** `pricing-provenance.ts` qualifies retained historical rates that the current audit could not verify, using the ledger in [03-data.md](03-data.md#model-price-ledger).
Context-tier prose reads the model's actual premium fields and threshold, and an absent cache field means no separate rate is recorded, never an assumed discount.

The ccusage #899 cache-tier case study (1-hour writes once priced at 1.25x instead of 2x, since fixed upstream) is published as "guarded against this class of bug", not as an attack on a current tool.

Gates: `library-honesty.test.ts`, `library-structure.test.ts`, `library-links.test.ts`, `library-pricing-registry.test.ts`, `library-pricing-parity.test.ts`, `library-calculators.test.ts`, `library-value-benchmark.test.ts`, `library-render.test.tsx`.
