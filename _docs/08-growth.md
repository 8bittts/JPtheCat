# Growth

What the site measures, and the `/library` programmatic SEO strategy.

## 1. Measurement

JP the Cat is free and app usage stays local, so the site measures only aggregate web traffic.
`/download` redirects to the current GitHub Release DMG and records nothing; there is no download database, owner email, digest, or cron.
Never add a download counter, a growth database, or an owner report without an explicit operator request and a privacy-policy update in the same change.

- **Website traffic** is Vercel Web Analytics and Speed Insights (no GA4), read in the Vercel dashboard; custom events (`download_cta_clicked`, `library_download_cta_clicked`, `download_modal_opened`, `library_download_modal_opened`, `repo_link_clicked`) are not bot-filtered, and they were Title Case until 2026-10-22.
  `repo_link_clicked` fires from every public-repository link through `components/site/repo-link.tsx`, with `placement` (`home_callout`, `faq`, `footer`, `demo_settings`) and `target` (`repo`, `contributing`).
  Every custom event goes through `trackProductEvent` in `web/lib/analytics/product-analytics.ts`, and `web/tests/product-analytics.test.ts` fails if any other file imports `track` from `@vercel/analytics`.
- **Search** is read in Search Console; no repository script reads it.
- **Release downloads** show per-asset counts on the GitHub Releases page; a count there is a byte fetch, not an install.

## 2. SEO and the `/library` hub

Organic search through `/library`: its thesis, its page families, and the guardrails that keep it honest.
The engine is adapted from `zoedate`'s `/library` (crawlable-but-unlinked hub, anti-thin eligibility gate, pure content generators, per-page JSON-LD, gated sitemap) and swaps its geography for a bounded product registry.
Every count is a gate-computed ceiling, never a target; padding to a number is what Google's helpful-content system punishes.

### Thesis

- **Out-data the field:** every page is fed by data the app ships — the bundled pricing table, the provider registry, and documented plan mechanics.
  Where our data is deep (cache-write split, model-specific context tiers) we beat flat price recaps; where it is thin, we fold the model into a family table.
- **Out-honest the field:** real dollars (Claude), notional list price (other providers), official percentages (Codex automatic; Claude and Grok opt-in), and measured gateway caps (OpenCode Go) are labeled everywhere.
  Only the live set is called tracked, which itself differentiates JP.
- **Convert intent:** the highest-intent clusters (usage tracker, cost calculator, "am I going to hit my limit", ccusage alternative) map to shipped features and a real interactive calculator.
- **Boundedness is the moat:** pages are bounded by real models, providers, plans, tools, and terms.

Competitors move fast; re-verify any rival's numbers before citing them.
The structural gaps that still hold: free CLIs publish no marketing library, content farms have no product and blur subscription versus notional cost, and other rivals lack real cache-tier data and provenance labels.

### Page families

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

### Guardrails

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
10. **Downloads stay gated:** every `/library` CTA renders off the same `version.json` data as `/download`, and uses `DownloadCta` with `source="library"` so SEO installs are a distinct channel ([§2](#2-the-download-spine)).
11. **Money formatting** matches the app's `MoneyFormatter` (USD, locale grouping).
12. **Calculators** are pure React state with an SSR fallback under the strict nonce CSP.
13. **Homepage curation** never removes library models, providers, routes, or sitemap entries.

**Pricing provenance in copy:** `pricing-provenance.ts` qualifies retained historical rates that the current audit could not verify, using the ledger in [03-data.md](03-data.md#model-price-ledger).
Context-tier prose reads the model's actual premium fields and threshold, and an absent cache field means no separate rate is recorded, never an assumed discount.

The ccusage #899 cache-tier case study (1-hour writes once priced at 1.25x instead of 2x, since fixed upstream) is published as "guarded against this class of bug", not as an attack on a current tool.

Gates: `library-honesty.test.ts`, `library-structure.test.ts`, `library-links.test.ts`, `library-pricing-registry.test.ts`, `library-pricing-parity.test.ts`, `library-calculators.test.ts`, `library-value-benchmark.test.ts`, `library-render.test.tsx`.
