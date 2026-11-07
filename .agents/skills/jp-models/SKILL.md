---
name: jp-models
description: Use when the user invokes $jp-models, reports "Unpriced models omitted from cost" or "unknown Codex model" in JP the Cat, asks to audit/add/price/normalize a model against official docs and locally emitted model IDs, OR asks to add, wire, or promote a NEW provider (like Grok or Muse Spark) end-to-end across the app, web, settings, /library, widget, and demo-parity surfaces so nothing is dropped.
---

# JP Models & Providers

JP the Cat is a **free** macOS app (no license, trial, or in-app purchase). This skill covers **local AI provider usage and API list-price tables** only — not JP product pricing, seats, or entitlement flows. `WidgetAccessState` may still decode legacy snapshot values for compatibility; the app does not gate features on them.

Two related jobs live here. Pick the mode that matches the request:

- **Mode A — Model-price coverage audit.** An existing provider emits a model JP can't price ("Unpriced models omitted from cost", "unknown Codex model"), or you're refreshing rates against official docs. Scope: pricing tables + normalization + `/library` pricing. See [Mode A](#mode-a--model-price-coverage-audit).
- **Mode B — Add or promote a provider.** A net-new provider (Cursor, Windsurf, Cline, …) or a tier promotion of an existing one. Scope: the ENTIRE surface map — mac core, CLI, dashboard, Advanced Analytics tray, Live Data window, Settings, menu bar, widget, homepage demo parity, `/library`, brand assets, tests, docs. See [Mode B](#mode-b--add-or-promote-a-provider).

The homepage is a fixed curated presentation: All providers, Claude, Codex, Grok, Muse Spark, Cursor, and OpenCode Go, in that order.
All providers is an aggregate control; the other six identities apply to homepage copy, marquee, FAQ, selectors, analytics, Live Data, and menu examples.
Do not add more homepage providers or change its design when native providers or layouts change.
Keep native coverage and `/library` complete; shared control semantics still require parity.
The project contract is `_docs/02-design-system.md#homepage-provider-boundary`; implementation status belongs in `_docs/todos.md`.

Both modes share one law: **never fabricate.** Never assign a price because a warning appeared, never invent a rate-limit %, never turn an unknown model into `$0.00`, never mark a provider `live`/aggregable before it has earned it, never query a hosted account API or transmit logs. Distinguish a genuinely missing datum from missing attribution first.

Always work in a dedicated worktree under `workstreams/`. Read `AGENTS.md`, `_docs/todos.md`, and **`_docs/11-adding-a-provider.md`** (the canonical deep playbook this skill operationalizes) before editing. This skill is the exhaustive surface checklist; `11-adding-a-provider.md` carries the rationale and the durable-bug narratives behind each step.

---

## Mode A — Model-price coverage audit

1. Read `AGENTS.md`, `_docs/todos.md`, and the Model Pricing Coverage section of `_docs/00-foundation.md`.
2. Run `python3 .agents/skills/jp-models/scripts/audit_model_coverage.py --repo .` from the JPtheCat root. It reads only model-identifying JSON fields from the documented Claude/Codex/Grok log roots; never print prompts, messages, code, tokens, auth data, or raw log contents.
   This script has ONE live copy, `.agents/skills/jp-models/` in this repo: `.claude/skills/jp-models` and `~/.codex/skills/jp-models` are symlinks to it, and `8leeai/_global/codex-skills/jp-models` is a backup refreshed with `cp -RL` in the same change. Two real copies once diverged — the global one audited only Claude/Codex while the repo copy covered Grok, so a run from the wrong copy reported a clean Grok with zero Grok roots read — so never replace a symlink with a copy.
   Its `undecorated`/`normalized`/`is_free_tier`/`fast_mode_id` mirror `ModelIdentity` exactly; change both sides together.
   Aliases come from the `aliases` map in `pricing-default.json`, and ids from gateways no JP row reads (a local oMLX server) are listed under `models_no_jp_row_ingests`, not `missing_prices`.
   OpenCode turns live in the legacy `message` table and the session-v2 `session_message` table; `scan_evidence.opencode_message_tables_read` must name every table the store has, or the inventory is incomplete.
3. **`missing_prices: []` is NOT proof of accuracy — it only proves every emitted ID resolves to SOME row.** A row that exists can still hold a stale or plain wrong rate, which is invisible to the script and is the more common real defect. Every audit must independently diff each row's input / output / cached / cache-write / tier values against first-party pricing evidence, including gateway and historical rows.
   Record each row as verified, corrected, historically retained with evidence, or unverifiable; reconcile the entire row inventory without silently skipping retired models. A 2026-08 audit found `gpt-5.6-luna` priced 5x over list and `gpt-5.6-terra` ~25% over (OpenAI cut both on 2026-07-30) while the coverage script reported zero missing prices.
4. Classify every warning before editing:
   - A non-empty emitted ID absent from the pricing table is a pricing-coverage candidate.
   - An empty Codex ID means attribution was absent at that event. Check whether the same rollout later declares a model; backfill only from that authoritative same-file declaration, else leave it unpriced (displays as "unknown Codex model").
   - Provider-prefixed, dated, selector-suffixed (`[1m]`), or alias IDs (`gpt-5.6`) usually need normalization, not duplicate price rows.
   - Synthetic/test IDs are not production coverage gaps.
5. Verify every candidate against current first-party docs:
   - OpenAI/Codex: OpenAI developer-docs MCP first; else only `developers.openai.com` / `platform.openai.com`.
   - Claude: only `platform.claude.com/docs` model-ID and pricing pages.
   - Other live providers: that vendor's own first-party model + pricing docs. Never promote an audit-only provider or infer a rate from a similarly named model.
   - Summarizing fetch tools truncate long tables (the OpenCode Zen and Go pages list 90+ rows). Download the raw page and parse every table row, including the Go usage-limit table, before calling a row verified.
6. Compare official IDs/rates against what the provider's LOCAL logs actually emit. Also check newly active or limited-availability models for live providers, whenever the local tool can emit the same canonical ID. API-only catalog entries the local source can't produce don't need speculative rows; deprecated-but-historically-emitted IDs may stay for old-log correctness.
7. Check gateway-specific rates, time-of-day rates, cache writes, and each model's context threshold; matching a model name alone does not establish a rate.
   For OpenCode, reproduce older concurrent-message updates and a failed database scan through the indexed CLI.
   Preserve accepted events and retry after failed reads; bump parser revisions when indexed records need repair.
8. Implement the root fix — coverage is **emitted-ID coverage, not a vendor-name checklist**:
   - Add/adjust `mac/Sources/JPtheCatCore/Resources/pricing-default.json` with documented rates only.
   - Keep `web/public/stable/pricing-v1.json` byte-identical to the bundled JSON.
   Preserve the unversioned legacy feed for v1.125 and older; incompatible schema changes require a versioned URL.
   - Add an entry to the `aliases` map in `pricing-default.json` when several emitted forms share one documented price; decorators (vendor prefix, `[1m]`, snapshot dates) and gateway accounting suffixes live in `ModelIdentity.swift` and `web/lib/model-identity.ts`.
   - Fix provider parsing/attribution when the model is lost before pricing.
   - Bump that provider's `parserRevision` when unchanged files must be re-read to repair existing indexed rows.
   - Update `ModelName.swift`/`ModelEffort.swift` and demo data when the model participates in those surfaces.
   - Adding or removing price FIELDS (e.g. a new `*_above_200k` tier) changes `populatedPriceFieldCount`, which drives `/library`'s field-weighted anti-thin gate — models can cross it and earn standalone pages. Expect `library-structure`/`library-pricing-registry` count pins to move, and update those pins rather than suppressing the gate.
   - A new tier must be proven on the GROUPED SQL SCAN too, not just `CostCalculator`: the dashboard, widget, and Advanced Analytics read `multiWindowSummaries`. Add the tiered model to `MultiWindowSummariesParityTests`' `models` array so the grouped result is asserted against the per-event oracle.
   - **Always update `/library` pricing in the same change** (see Mode B block I): `pricing-data.ts`, `pricing-registry.ts`, display names/effort, eligible routes/vendor-family tables, and the library parity/structure/render tests. A price change is incomplete until it's visible on `/library` with no thin or fictional copy.
9. Add regression tests for exact emitted IDs, official rate spot-checks, aliases/snapshots, cache tiers, and unpriced behavior. Presence-only tests are insufficient.
10. Update `_docs/03-data.md` (source research) and `_docs/00-foundation.md` (reusable parser/correctness lesson). Keep `AGENTS.md` terse; point to the engineering log for load-bearing invariants.
11. Run focused Swift tests → `swift test --parallel` → `swift build -c release` → web parity tests. Any deploy requires the full web quality gate + React Doctor 100/100.
12. Report emitted IDs audited, missing IDs fixed, official sources consulted, files changed, gates run, and any genuinely model-less usage left honestly unpriced.

---

## Mode B — Add or promote a provider

Treat public support, local visibility, aggregation, pricing, and quota availability as separate decisions.
Local accounting for Nemotron, MiMo, Big Pickle, or DeepSeek does not itself authorize `.live` marketing support.

### The four promotion tiers (never skip one)

| Tier | Meaning | Examples | Unlocked by |
|---|---|---|---|
| 1. Catalog-only | `ProviderCatalog` entry, `support: .localRoadmap`/`.candidateRoadmap`. No parser. | catalog entries without parsers | — |
| 2. CLI audit-only | Real `UsageProvider` wired into `jpthecat-cli --provider X`/`--X`. Excluded from `--provider all`, app, widget, alerts. | Gemini | A parser that works on real samples |
| 3. Dashboard-visible, non-aggregated | Selectable `ProviderRow` with own sparkline/totals, but `isAggregable: false` keeps it out of combined dollars + alerts. Widget only via an explicit non-dollar metric (tokens). | Copilot, Cursor | Reliable enough to *show*, not to *sum as money* |
| 4. Fully live | `support: .live`; marketing may say "supported". Aggregation and alerts remain separate capability decisions. | Claude, Codex, Grok, Muse Spark, OpenCode Zen / Go | Deliberate promotion: official/near-official accounting + a real rate-limit signal (or an honest reason it has none) |

Promotion is a **decision**, not a side effect of a working parser. Tier 3→4 changes what the marketing site and `/library` may claim (`web/tests/no-fiction.test.ts`, `library-honesty.test.ts`). OpenCode Zen and Go are live gateways, but non-aggregable; model-brand rows own eligible dollars.
Go meters are measured local usage against published caps, never official entitlement or reset signals.

### Step 0 — Research before code (write an active `_docs/todos.md` note)

Answer these (per `11-adding-a-provider.md` Step 1) before writing a parser:
1. What does the tool write to disk, and is capture **on by default** (Codex `rate_limits`) or **opt-in** (Copilot OTel, Claude statusline, Grok billing hook)? This decides the Settings/Live-Data-row story.
2. Is the source stable, or does the vendor's own tooling call it beta / flag data-loss? Don't build past what the data deserves (OpenCode held at tier 2 twice).
3. Read the tool's OWN docs for exact env vars/file formats — never assume from a plausible name (`COPILOT_OTEL_FILE_EXPORTER_PATH`, not `..._ENABLED`). "Env var present" ≠ "data written"; verify against a real invocation's log.
4. Does it expose an **official** rate-limit/quota signal? If not, do NOT reconstruct one from token counts — ship cost/token only and say so.
5. Do its models exist in `pricing-default.json`? If not it will be **fully-unpriced** — build the token-display branch from day one (see block C / `isFullyUnpriced`), don't discover a dead `$0.00` in a screenshot.

### The complete surface map — touch EVERY applicable block, in the same change

Blocks A–G are the mac app; H–K are web + docs. This is the drop-nothing checklist; the tier column says the earliest tier at which each block applies.

#### A. Mac core — catalog, model, parser, pricing (tier 2+)
- `mac/Sources/JPtheCatCore/Model/UsageEvent.swift` — add the `ProviderID` case (`.grok`, `.museSpark`).
- `mac/Sources/JPtheCatCore/Providers/ProviderCatalog.swift` — catalog entry (id/name/glyph/`support`/sources/iconSlug). Only `support: .live` may be marketed as supported.
- `mac/Sources/JPtheCatCore/Providers/<X>Provider.swift` — the parser: `UsageProvider` (`id`, `root`, `watchPaths()`, `isAvailable()`, `loadEvents()`). Decode with `JSONSerialization` + tolerant `[String: Any]`, **never strict `Codable`** for third-party logs. Reuse `ProviderParsingHelpers` (`ISOTimestamp.parse`, `JSONNumber.int`) — don't re-derive a fifth copy.
- Rate-limit capture/store (only if it has an opt-in local signal): `<X>RateLimitCapture.swift` + `<X>RateLimitStore.swift` (`GrokRateLimitCapture`/`GrokRateLimitStore` are the template — installs one marked hook file, writes to `~/Library/Application Support/JPtheCat/<x>-rate-limits.json`, never touches `auth.json`/`config.toml`, never calls the vendor's network API).
- High-volume source → conform to `IndexableProvider` (`UsageIndexer.swift`); set `canTailAppend` (`true` only for append-only, per-record-independent formats — Copilot's cross-record dedup broke tailing). Low-volume → skip the index, call `loadEvents()` directly like `CopilotProvider`. (Muse Spark reads OpenCode's `opencode.db` SQLite rows; Grok reads `~/.grok/sessions/**/updates.jsonl`.)
- `mac/Sources/JPtheCatCore/Pricing/ModelIdentity.swift` (one id pipeline) + `Presentation/ModelName.swift` + `ModelEffort.swift` — labels, effort, and display order; add shared cases to `web/tests/fixtures/model-identity-cases.json`.
- `mac/Sources/JPtheCatCore/Pricing/PricingTable.swift` + `Resources/pricing-default.json` — model→price rows (run Mode A for the rates). Byte-mirror to `web/public/stable/pricing-v1.json`.

#### B. CLI (`mac/Sources/jpthecat-cli/main.swift`) (tier 2+)
Use `CLIProviderTable` for construction, accepted flags, names, cost basis, availability, and aggregate membership.
Update help and automation snapshots, then run `CLIProviderTableTests`.
`--provider all` enumerates the app's aggregable set plus gateway rows for display.
Gateway basis excludes those rows from combined dollars; local-accounting brand rows remain included in totals.


#### C. Dashboard (tier 3+)
- `DashboardViewModel.swift` — build the `ProviderRow` (provider param, `<X>Enabled` gate flag mirroring `claudeProviderEnabled`, `makeOfficialProviderRow`, widget-snapshot mark). Derive `isAggregable` from provider basis, independently of support tier; gateways and estimates remain excluded.
- **[Durable lesson] Wire every tier-4 row through `makeOfficialProviderRow`** so `ProviderRow.series` resolves via `resolvedDailyCostSeries`, NOT raw `summary?.dailyCostSeries ?? []` — charting only from the index series left a dead hero `SparkChart` while provider detail still showed real dollars (shipped on Muse Spark). Mirror provider-detail model-bar units to the displayed amount (`cost` when priced) and use ≥2 decimals for sub-dollar run rates. Guard: `DashboardViewModelMuseSparkEstimateTests.testMuseSparkFallsBackToEventSeriesWhenIndexSeriesMissing`.
- `DashboardState.swift` — every aggregate/alert consumer must filter on `isAggregable` **in addition to** `isContributing`: `DashboardCostProvenance.aggregate`, `aggregateCurrencyCode`/`weeklyShare`, the fallback reduce (`aggregableRows`), `DashboardWidgetPublisher.contributingRows` (3 sites), `UsageAlertCenter.alertableWindows`. Quota display is independent of aggregation: current official windows and explicitly measured gateway windows render meters; other rows use activity sparklines.
- **Token-vs-dollar:** for free or fully unpriced activity, wire `ProviderRow.usesTokenDisplay` + a parallel `tokenSeries`, and branch EVERY dollar call site (hero `SplitFlapMoney.textOverride`, selector amount, chart values, Composition/legend, provider-detail Today/N-days/Tokens-per-turn/trend strip) on it. `formatTokenCount(_:)` is the shared formatter; skip the "Unpriced models omitted" note for a fully-unpriced row.
- Tier-3 dashboard badge is `local` (analytics retains the `estimate` basis), styled in the row's own `vizTint` wash, independently tappable (`EstimateExplainerPopover`) — remember: a `Button` nested in another `Button`'s label collapses hit-testing to the outer button; use THREE sibling `.plain` controls like `SelectorRow`, and give `selectorMeter` an explicit `.frame(minWidth: 20, maxWidth: .infinity)`.

Selector verification:
- `ProviderRow.selectorQuota(now:)` requires an official, finite percentage and a future reset; zero percent is valid.
- `selectorTrendSeries(now:)` supplies selected-window dollars for priced models and tokens for free, fully unpriced, or token-only rows.
  Non-aggregable gateway rows still show dollars when priced.
- Supply indexed `UsageWindowSummary.dailyTokenSeries` and test parity with direct-event buckets; an empty event array on the indexed path is normal.
- Mirror `selectorPresentation` in the web demo and test expired, missing, unofficial, zero, and secondary-only quota windows.

#### D. Advanced Analytics tray (mac **and** web — same-change parity, tier 2+)
**[HARD REQUIREMENT]** every provider, including audit-only entries, joins the native analytics checklist in the same change.
The web checklist includes only the fixed homepage roster; do not expand it for native additions.
- `mac/Sources/JPtheCatApp/AdvancedAnalyticsWindow.swift` — add to `providerOptions`, the `checkedProviders` default set, the tint map, catalog short names, and the notional/basis classification. If the provider bypasses `UsageIndex` (Copilot-style), add a `ModelDaySummary.bucketed(events:calculator:)` fetch merged into `rows` in `reload()`/`export()`; index-fed providers (Claude/Codex/Grok/Muse Spark) need only the list entry.
- For homepage providers only, `web/components/site/advanced-analytics-demo.tsx` — keep `ANALYTICS_PROVIDERS` and the per-provider series map aligned with `web/lib/homepage-providers.ts` (tint pulled from `menubar-demo-series`).

Keep daily trends to four columns, wrapping remaining providers.
Use `visibleModelRowLimit(providerCount:)` to reserve space, disclose hidden model rows, and keep exports complete.
Verify the full native panel at default size with all providers and every heatmap grain; Export and the table footnote must remain visible.
Keep the homepage analytics design fixed while preserving shared control semantics.

#### E. Live Data window (mac **and** web — same-change parity, tier 3+ / any opt-in)
- `mac/Sources/JPtheCatApp/LiveDataWindow.swift` (content in `SettingsBackView.swift`'s `LiveDataWindowContent`) — add the provider's enable row grouped with its opt-in live-limit row, each carrying the real brand-mark chip via `SettingsToggleRow(providerMark:)` (the shared `AnalyticsProviderMark`, not an SF Symbol). "Live data" toggle semantics: on = visible with real data, off = fully removed from the dashboard.
- For homepage providers only, `web/components/site/menubar-demo-settings.tsx` — mirror in `LiveDataSection`/`LiveDataPopup`: `<X>Enabled` state, `<X>Limits`, and prop threading through `ToggleRow(providerMark:)` rendering `/provider-icons/*.svg` on the `PROVIDERS[*].color` chip.

#### F. Settings + provider detection (mac, tier 2+)
- `SettingsStore.swift` — `<X>ProviderEnabled` persisted key.
- `SettingsBackView.swift` — the provider toggle row. It MUST self-hide until `is<Tool>Detected()` (Core, pure, testable) confirms the REAL current footprint (executable following symlinks via `isExecutableFile`, not a bare dotfolder). Any opt-in rate-limit hook install UI uses an `NSAlert(jpTitle:jpMessage:)` after an explicit tap, edits only a `# BEGIN/END JPTHECAT-<X>`-marked block, and auto-migrates a stale block. A Settings/Live-Data row that changes what a provider reports must call `model.refresh(reindex: true)` immediately (don't wait for the next poll). Subtitle copy must describe CURRENT tier reality.

#### G. Menu bar + widget (mac)
Menu bar (tier 3+):
- `StatusBarController.swift` `providerLimitSummaries(from:)` + `SettingsBackView.swift` `menuBarLimitProviders` + `MenuBarLabelRenderer.swift` (`MenuBarDisplayFormat`). Official window (Claude statusline, Codex/Grok `used%`) → ZERO extra wiring; any non-nil `usedPct`/`weeklyUsedPct` auto-joins the rotation + gets a dedicated `Total + <Provider>`/`<Provider>` cycle entry.
- No current official signal → show actual today tokens, omit zero-token fallbacks, and say `quota unavailable` in the tooltip.
  Never render `estimatedSharePct` as a percentage or let tokens drive the 80%/95% attention border.
- Resolve persisted provider IDs through `ProviderCatalog.shortName` after settings reload; test Big Pickle, MiMo, and DeepSeek names.
- Mirror token fallback entries for homepage providers in `menubar-demo-format.ts`, including those without a `windows` array.

Widget (**mandatory audit even when the answer is "exclude"**, tier 3+):
- Decide + document widget eligibility and the explicit metric (`dollars` or `tokens`).
- Eligible: `WidgetConfiguration.swift` `JPWidgetProviderChoice` case + display representation + slug, `WidgetSupport.swift` `WidgetPreviewData`, `WidgetComponents.swift` provider mark, `WidgetSnapshot.swift` fields, and the provider SVG in `JPtheCatWidgetExtension/Resources/`.
- Excluded: add a regression assertion proving the exclusion is deliberate.
- Verify: `WidgetExtensionPackagingTests`, `WidgetAllProvidersPresentationTests`, `JP_RENDER=1 swift test --filter UnlockedWidgetRenderTests`, inspect Small/Medium/Large in Sunlit+Midnight at exact point sizes, and exercise the installed appex archive path (source renders miss `chronod`/bundle-stub failures).

#### H. Fixed homepage presentation

- Use only the fixed roster above; future native provider additions never expand homepage content or redesign its components.
- Keep homepage sample data and selection independent of the full native catalog and `web/lib/site.ts` registry used by `/library`.
- Preserve unit and provenance semantics: Cursor is token-based; OpenCode Go can show dollars but never contributes to combined totals.
- Derive aggregate, composition, chart, and analytics samples only from represented aggregable rows; omit hidden-provider contributions and gateway double counting.
- Run the parity script and native parity tests with positive native-coverage and exact-homepage-membership assertions, plus desktop/mobile visual proof.

#### I. `/library` (`web/lib/library/`) — the most commonly under-updated web surface (tier 4 for "live" claims; pricing at any tier)
- `web/lib/site.ts` — the `PROVIDERS` entry with the correct `live` flag; this is the web SoT the library reads.
- `provider-registry.ts` — `liveProviderIds()` must return exactly the live set; add a slug override if the id isn't URL-safe (`muse_spark → muse-spark`). This is THE live enumerator; the track thin-gate (`isProviderTrackEligible`) is separate (`live || sources.length >= 2`).
- `pricing-data.ts` + `pricing-registry.ts` — model→price rows and the per-provider pricing family (mirror `pricing-default.json`, guarded by `library-pricing-parity.test.ts`).
- `eligibility.ts` — family/route thin-gate (defers to `provider-registry` for the live set; confirm the new family passes for routes AND sitemap).
- `content/provider.ts`, `pricing.ts`, `limits.ts`, `calculators.ts`, `plans.ts`, `glossary.ts`, `vendor.ts` and the `competitors-registry.ts`/`plans-registry.ts`/`sections.ts`/`value-benchmark.ts` registries — add the provider where each enumerates the set.
- Honesty invariant: the live set comes from `ProviderCatalog`; it includes `claude`/`codex`/`grok`/`muse_spark`/`opencode`/`opencodego`; every non-Claude `$` co-occurs with a notional marker; no roadmap page may say JP "tracks it today/now/live". Guard: `library-honesty.test.ts` pins `liveProviderIds().sort()` — update that assertion in the SAME change on a real tier-4 promotion.

#### J. Brand assets / provider marks (any tier that renders the mark)
- mac app: `mac/Sources/JPtheCatApp/Resources/provider-<id>.svg` (white glyph).
- mac widget: `mac/Sources/JPtheCatWidgetExtension/Resources/provider-<id>.svg`.
- web: `web/public/provider-icons/<slug>.svg` (+ attribution note in `SOURCE-NOTES.md`).
- Tints: `JPAppDesignTokens.swift` `JPAppColor.<x>TintHex` (mac); `menubar-demo-series.ts` `viz.light` + `web/app/globals.css` `--color-p-<id>` (web). Tint follows the established palette role — never bright gold `#fdcd2d` (mascot-only) for a UI fill; marks load via `NSImage`/`WidgetAssets`, never SwiftUI `Image(name:bundle:)` (blank).

#### K. Tests + docs (drop nothing)
- mac: `ProviderCatalogTests` (catalog/live set + tier boundary), `<X>ProviderTests` (real fixture → events, malformed fails closed, `isAvailable` true/false), `<X>RateLimitTests`, `ModelNameTests`, `LocalAutomationSnapshotTests`, `PricingTableTests`, `AppResourcesTests` (SVG present), `DashboardStateTests`/`DashboardViewModel<X>EstimateTests` (aggregable exclusion + index-series fallback + token fallback), `MenuBarLabelRendererTests` (estimate rotation), `WidgetExtensionPackagingTests`/`WidgetAllProvidersPresentationTests`, `SettingsCopyTests`, `DashboardSizingTests` (no-scroll faces), Settings detection test (`false` on a clean fixture, not just `true`).
- web: `menubar-demo-series.test.ts`, `analytics-demo-layout.test.ts`, `library-honesty.test.ts`, `library-structure.test.ts`, `library-pricing-registry.test.ts`, `library-pricing-parity.test.ts`, `library-calculators.test.ts`, `library-value-benchmark.test.ts`, `site-copy.test.ts`, `no-fiction.test.ts`.
- docs: active work in `_docs/todos.md`; completed evidence belongs in git; `_docs/03-data.md` (parser origin), `_docs/11-adding-a-provider.md` (only if the PATTERN itself changed), and any live-set reference in `README.md`/`08-growth.md`. `AGENTS.md` (root + web) only for a new load-bearing invariant — terse, pointing to `00-foundation.md`.

### Step 9 — Gates & report
Focused Swift tests → `swift test --parallel` → `swift build -c release` → a warning-free `/bin/rm -rf mac/.build && swift build`. Web: `cd web && bun run quality` (React Doctor 100/100) before any deploy. Report the tier landed, every surface block touched (A–K), any block deliberately skipped with the reason, official sources consulted, and gates run.

---

## Hard Rules (both modes)

- Locally emitted IDs are the coverage set; official docs are the rate + canonical-ID source. Coverage is emitted-ID coverage, not a vendor-name checklist.
- Never guess a price, equate subscription usage with API spend, invent a rate-limit %, or turn an unknown model into `$0.00`.
- Codex/ChatGPT/Grok/Muse Spark dollars are **notional API-list-price** estimates and must stay labeled that way; only Claude has real-dollar spend.
- A provider with no official rate-limit signal resolves to an honest `estimate`/`.unknown` — never a fabricated number, and an estimate never drives attention color, aggregates, or alerts.
- Never hardcode or guess a subscription tier/plan ceiling — resolve it from the provider's own live entitlement, else show no tier label.
- Preserve the local-only privacy boundary: no hosted account API calls, no transmitting logs, never read OAuth tokens, never mutate `~/.claude/settings.json`/`config.toml`/`auth.json` (opt-in capture edits only its own clearly-marked block in the user's own script/hook dir).
- Keep bundled and remote pricing JSON byte-identical; retain remote fail-closed behavior.
- Never mark a provider `live`/aggregable or claim marketing support because a price was added or a parser works — promotion is a separate, deliberate tier decision.
- Shared native/homepage control semantics stay aligned in the same change; homepage roster and geometry remain fixed under the explicit presentation boundary.

## Canonical Sources

App / core
- `mac/Sources/JPtheCatCore/Model/UsageEvent.swift` (`ProviderID`)
- `mac/Sources/JPtheCatCore/Providers/ProviderCatalog.swift`, `<X>Provider.swift`, `<X>RateLimitCapture.swift`/`Store.swift`, `ProviderParsingHelpers`
- `mac/Sources/JPtheCatCore/Pricing/PricingTable.swift` + `Resources/pricing-default.json`
- `mac/Sources/JPtheCatCore/Presentation/ModelName.swift`, `ModelEffort.swift`, `MenuBarLabelRenderer.swift`
- `mac/Sources/jpthecat-cli/main.swift`
- `mac/Sources/JPtheCatApp/DashboardViewModel.swift`, `DashboardState.swift`, `DashboardView.swift`, `DashboardWidgetPublisher.swift`, `AdvancedAnalyticsWindow.swift`, `LiveDataWindow.swift`, `SettingsBackView.swift`, `SettingsStore.swift`, `StatusBarController.swift`, `JPAppDesignTokens.swift`
- `mac/Sources/JPtheCatWidgetExtension/*` + `Resources/provider-*.svg`

Web
- `web/lib/site.ts` (`PROVIDERS`, `live`)
- `web/public/stable/pricing-v1.json`
- `web/lib/library/provider-registry.ts`, `pricing-data.ts`, `pricing-registry.ts`, `eligibility.ts`, `content/*`
- `web/components/site/menubar-demo-series.ts`, `menubar-demo.tsx`, `advanced-analytics-demo.tsx`
- `web/public/provider-icons/<slug>.svg`, `web/app/globals.css` (`--color-p-*`)

Tests / docs
- mac: `ProviderCatalogTests.swift`, `<X>ProviderTests.swift`, `PricingTableTests.swift`, `WidgetExtensionPackagingTests.swift`, `DashboardViewModel<X>EstimateTests.swift`
- web: `library-honesty.test.ts`, `library-pricing-parity.test.ts`, `library-pricing-registry.test.ts`, `library-structure.test.ts`, `library-render.test.tsx`, `menubar-demo-series.test.ts`, `no-fiction.test.ts`, `site-copy.test.ts`
- `_docs/11-adding-a-provider.md` (deep playbook), `_docs/03-data.md`, `_docs/00-foundation.md#model-pricing-coverage`

Use `scripts/audit_model_coverage.py --repo .` for the deterministic local coverage inventory. Its JSON output is evidence for the audit, not permission to add prices without official verification.

## Pricing compatibility checks

Preserve `pricing_revision` in bundled and hosted JSON; `RemotePricingStore` rejects incompatible older overrides.
Verify free suffixes after removing snapshot and context decorators.
Keep gateway pricing identities distinct when rates or context boundaries differ from the direct vendor.
OpenCode Grok uses `-opencode` accounting IDs: its 200K boundary is exclusive, while direct xAI uses an inclusive boundary.
Record unverifiable historical rates and undocumented cache estimates in `_docs/03-data.md`; never describe them as verified rates.
