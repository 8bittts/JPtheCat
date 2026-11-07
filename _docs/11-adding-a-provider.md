# Adding a Provider

The canonical pattern for adding or promoting a provider, from research to the homepage.

The playbook for parsing, accounting, native presentation, and web parity when a provider is added or promoted.
The operator-local `$jp-models` skill (`.agents/skills/jp-models/SKILL.md`, gitignored) is the condensed checklist built from this doc.
`ProviderCatalog.swift` owns catalog metadata, root `AGENTS.md` owns the public support boundary, and [03-data.md](03-data.md) records each source format.
Reuse the existing block for every step; the most recent full builds to grep as templates are Grok and Muse Spark (`grok`, `muse`, `museSpark`), and a missing entry after your change is the tell that a surface was dropped.

## Promotion and accounting boundaries

| Tier | Meaning | Examples |
|---|---|---|
| 1. Catalog only | A `ProviderCatalog` entry with a roadmap `support` status; no parser | most catalog entries |
| 2. CLI audit-only | A real parser wired into `jpthecat-cli --provider X`; excluded from `--provider all`, the app, widgets, and alerts | Gemini |
| 3. Dashboard-visible, non-aggregable | A selectable `ProviderRow` kept out of dollar totals and alerts by its `ProviderBasis` | Copilot |
| 4. Live | `support: .live`; may be marketed | Claude Code, Codex, Grok (Build / Cursor / Grok Bot), Muse Spark, OpenCode Zen, OpenCode Go |

Visibility, aggregation, widget eligibility, pricing, and quota are separate decisions; document each.
Nemotron, MiMo, Big Pickle, and DeepSeek are local accounting rows (`ProviderCatalog.localAccountingIDs`): summed and shown, never marketed.
Promotion is a deliberate decision, not something that falls out of a working parser; tier 4 changes what the site may say (`web/tests/no-fiction.test.ts`, `library-honesty.test.ts`).

### OpenCode-derived rows: one store, one reader, one pricing rule

Seven rows read the same `opencode.db` and differ only in which assistant messages they claim: model-brand rows (`OpenCodeBrandProvider` per `OpenCodeBrand`, plus `MuseSparkProvider`) claim by model id, and gateway rows (`OpenCodeProvider` = Zen, `OpenCodeGoProvider` = Go) claim by `providerID`.
Every one decodes through `OpenCodeModelReader`, stamps `requestId: "opencode-db"`, and answers `isAvailable()` from the one cached `OpenCodeDetection` probe.
Add a brand by adding an `OpenCodeBrand` case; the dashboard, Settings, CLI table, catalog sets, and tests iterate the enum.
Parse-time normalization drops only a `vendor/` prefix and KEEPS `-free` / `-contributor-free`, which `ModelIdentity.isFreeTier` leaves unpriced; only `OpenCodeGoLimits` strips the suffix, for its published-cap lookup.
A failed source read preserves accepted events and the cursor (`OpenCodeModelReader.indexed`).
The gateway console link needs the workspace id from `log/opencode.log` (`OpenCodeWorkspace.currentID`); without it `OfficialUsageLink.sentence(for:openCodeWorkspaceID:)` returns no link.
The dashboard row is one OpenCode view; Zen and Go break out inside it.
Guards: `OpenCodeDerivedProviderTests`, `OpenCodeGoProviderTests`, `OpenCodeWorkspaceTests`, `OfficialUsageLinkTests`.

## Step 1 — Research before code

1. What does the tool write to disk, and is it on by default? Zero-setup (Codex) beats opt-in (Copilot OTel, Claude statusline); opt-in changes the Settings story (Steps 7–8).
2. Is the source stable? A maintainer's own tooling flagging it beta or lossy is a reason to hold at tier 2.
3. Read the tool's own docs and logs for exact env vars and formats; a plausible name is not proof ([00-foundation.md#providertool-detection](00-foundation.md#providertool-detection)).
4. Does it expose an official quota? If not, ship cost or token tracking only; never reconstruct one from tokens.
5. Are its models in `pricing-default.json`? If not, plan token display from day one (Step 4).

## Step 2 — The parser (`JPtheCatCore/Providers/`)

- Conform to `UsageProvider`; decode third-party logs with tolerant `JSONSerialization`, never strict `Codable`, so one odd field never drops a valid event.
- Reuse `ProviderParsingHelpers.swift` (`ISOTimestamp.parse(_:fallback:)`, `JSONNumber.int(_:)`); never write another copy.
- A small source can skip the index like `CopilotProvider` (direct `loadEvents()` and an in-memory rollup each refresh).
- A high-volume source conforms to `IndexableProvider` and decides `canTailAppend`: `true` only for append-only records that are each independently correct; `false` whenever records reconcile with each other (Copilot's span suppression double-counted under tailing) or the source is rewritten.
- Accumulating SQLite loops use `while try stmt.step()` and a non-throwing decode returns empty rather than partial (`mac/AGENTS.md`).

## Step 3 — CLI wiring (`jpthecat-cli/main.swift`)

Add one `CLIProvider` row to `CLIProviderTable.all`; it supplies flag parsing, `--provider` matching, the JSON `provider` field, availability messages, and construction.
Three things sit outside the table:
- **Help text** in three places, pinned by `CLIProviderTableTests.testHelpTextListsExactlyTheTableRows`.
- **`cost_basis`:** `notional_list_price` for list-price providers, `token_estimate` for token-only feeds (these also select the empty pricing table); Claude carries none.
- **`includedInAll`** controls CLI row enumeration, not dollar aggregation (`CLIProviderTableTests.testProviderAllMatchesTheDashboardAggregateSetExactly`).
**[CRITICAL]** The table stays a `static let` on `enum CLIProviderTable`: a top-level global initializes in statement order and segfaults `snapshot`/`report` (guard: `CLIProviderTableTests.testTableIsLazilyInitializedNotATopLevelGlobal`).

## Step 4 — Token versus dollar display

A provider whose models are unpriced shows tokens, never a dead `$0.00`.
`ProviderRow.isFullyUnpriced` is true only when there is activity and no priced model; a mixed row stays dollar-based with the "Unpriced models omitted" note.
`ProviderRow.tokenSeries` is the token twin of `series`, and every dollar call site (hero, selector amount, chart, legend, detail metrics, trend strip) branches on it.
`TokenFormatter.compact(_:suffix:)` is the one formatter for dashboard, tooltip, and widget (guards: `TokenFormatterTests`, `TokenFormatterParityTests`, `WidgetTokenFormatParityTests`); the homepage twin is `formatTokenCount` in `menubar-demo-series.ts`.

## Step 5 — Dashboard rows and widgets

- Add the provider to `ProviderBasis.of(_:)`; `isAggregable`, token display, notional labels, and badges derive from it, and `ProviderBasisTests` fails a provider without a basis. Plan-only windows are a presentation state, not necessarily a separate provider basis: unified Grok stays `.notional` for local pricing, but hero/selector/widget show official plan % when there are no local events. Detail omits the primary gauge already in the hero. See the primary-pool rule in `03-data.md`.
- Aggregate and alert consumers use `ProviderRow.contributesToAggregate`, never `isContributing` alone.
- Tier-4 indexed rows build through `makeOfficialProviderRow` with `resolveOfficialProviderInputs` (lazy event load) and `resolvedDailyCostSeries` (event fallback); never assign `summary?.dailyCostSeries ?? []` or call `loadEvents()` every refresh.
- Model bars scale on the same unit as the amount column, and sub-dollar run rates show two decimals.
- Without a current official or measured quota, `selectorTrendSeries` draws activity; pass `UsageWindowSummary.dailyTokenSeries` to indexed row builders.
- Menu-bar rotation uses today's tokens when no quota exists and omits zero-token providers; names resolve through `ProviderCatalog.shortName`.

**Widget audit — mandatory in the same change, even for an exclusion.**
1. Decide whether the provider belongs in widgets and with which metric (dollars, tokens, or official plan percent).
2. If eligible, update `JPWidgetProviderChoice`, `WidgetPreviewData`, `DashboardWidgetPublisher`, window selection, marks, badges, formatting, and accessibility copy.
3. If excluded, add a test proving the exclusion is deliberate.
4. Run `WidgetExtensionPackagingTests` and `JP_RENDER=1 swift test --filter UnlockedWidgetRenderTests`, and inspect every face in both themes.
5. Stage the real `.app` and exercise the installed widget archive path; source renders miss `chronod` and bundle-stub failures.
A tier-3 provider enters widgets only with a non-dollar metric.

## Step 6 — Advanced Analytics

Every provider, audit-only included, joins `AdvancedAnalyticsTrayView.providerOptions` and its default checked set in the same change (root `AGENTS.md`).
Add its tint and display name; basis comes from `ProviderBasis`.
An indexed provider needs only the list entry, since `modelDaySummaries` covers it; a provider that bypasses the index adds a fetch through `ModelDaySummary.bucketed(events:calculator:)` merged into the same rows.
Gate: `AnalyticsProviderCoverageTests`.

## Step 7 — Live Data window

Enable and live-limit toggles live in the Live Data window, never inline in Settings; off removes the provider from the dashboard entirely.
Add the rows grouped with the provider (enable row, then its live-limit row) in catalog order, with the real brand mark through `SettingsToggleRow`'s `providerMark:`.
The enable toggle binds a `SettingsStore` provider key; the window shell's divergences are listed in [12-ui-surface-invariants.md](12-ui-surface-invariants.md#live-data-window).

## Step 8 — Settings enablement (opt-in sources only)

1. Detect the tool before rendering anything (`is<Tool>Detected()`), checking the real executable and following symlinks.
2. Never edit silently: show an `NSAlert` after an explicit tap, and add or remove exactly one marked block (`# BEGIN/END JPTHECAT-<X>`).
3. Migrate a stale block automatically when the enablement line changes (`CopilotOtelSetup.isCurrent(inScript:)`).
4. Subtitles describe the provider's current tier, not the one it had when the row was written.
5. Shell-config edits apply only to new shells, so empty-state copy says "open a NEW terminal window".
Add the row as a `ProviderOptInDescriptor`; never copy `ProviderOptInRow`.

## Step 9 — Brand mark and tint

- Three synced copies of the white glyph: `mac/Sources/JPtheCatApp/Resources/provider-<id>.svg`, `mac/Sources/JPtheCatWidgetExtension/Resources/provider-<id>.svg`, and `web/public/provider-icons/<slug>.svg` with a line in `SOURCE-NOTES.md`.
- Marks load through `NSImage` (`JPResourceBundle`/`WidgetAssets`), never `Image(name:bundle:)`.
- Tints: `JPAppColor` (`JPAppDesignTokens.swift`), `--color-p-<id>` in `web/app/globals.css`, and `viz.light`/`viz.dark` in `menubar-demo-series.ts`; dark-mode lift comes only from `ProviderTintLegibility.legibleHex(...)`.
- Related sources: Grok Build / Cursor / Grok Bot consolidate into one `.grok` row everywhere; legacy source IDs remain private warehouse keys and configuration aliases. Never add separate public rows or duplicate weekly pools for them.

## Step 10 — Homepage

The [homepage boundary](02-design-system.md#homepage-provider-boundary) is fixed: a provider addition adds no homepage row, analytics checkbox, Live Data control, marquee item, or FAQ chip.
`web/lib/homepage-providers.ts` owns that roster; the parity script keeps positive checks for both the full native set and the homepage set.

## Step 11 — `/library`

`/library` reads `web/lib/site.ts` `PROVIDER_DEFINITIONS` and the pricing mirror, so it is the surface most often under-updated.
1. Set the provider's `status` in `PROVIDER_DEFINITIONS`; `live` is derived from it and set only on a real promotion.
2. `liveProviderIds()` in `web/lib/library/provider-registry.ts` must return exactly the live set; add a `PROVIDER_SLUG_OVERRIDES` entry for an id that is not URL-safe.
   The track page gate (`live` or two sources) decides whether a page exists; `live` decides what it may claim.
3. Mirror new price rows into `pricing-data.ts` and `pricing-registry.ts` with display names, effort, and vendor family.
4. Confirm the provider passes `eligibility.ts`, the one gate shared by routes and the sitemap.
5. Grep an existing live provider's id across `web/lib/library/` and match every hit in content and registries.
6. On a promotion, update the `liveProviderIds()` assertion in `library-honesty.test.ts` and the no-fiction rules in the same change.
Owner doc: [08-growth.md](08-growth.md).

## Step 12 — Docs

Active work goes in `_docs/todos.md`; source formats in `03-data.md`; a reusable lesson in `00-foundation.md`; this file changes only when the pattern itself changes.

## Tests a new provider needs

- Parser tests on a real-shaped fixture, with malformed records skipped rather than crashing, and `isAvailable()` true and false on temp directories.
- For an indexed provider, an idempotent re-read through `UsageIndexer.refresh`; for `canTailAppend: false`, a test proving the cross-record bug it prevents.
- Tier 3: a `DashboardStateTests` exclusion case and, if it can be fully unpriced, an `isFullyUnpriced` case.
- Tier 4: the event-series fallback (`DashboardViewModelMuseSparkEstimateTests` is the template).
- Without an official quota: token rotation, zero-token omission, and a normal attention border.
- An enablement row: detection `false` on a clean fixture and marker-block round trips against a temp file, never the user's shell rc.
- Catalog, tray, widget, and resources: `ProviderCatalogTests`, `AnalyticsProviderCoverageTests`, `WidgetExtensionPackagingTests` / `WidgetAllProvidersPresentationTests`, `AppResourcesTests`.
- Web: `menubar-demo-series.test.ts`, `analytics-demo-layout.test.ts`, `analytics-demo-figures.test.ts`, the `library-*` tests, `no-fiction.test.ts`, and `site-copy.test.ts`.

## Pricing revisions

Preserve `pricing_revision` in remote updates; for a bundled rate correction, advance it and `RemotePricingStore.minimumPricingRevision` together so a stale cached table cannot restore the old rate.
A data revision keeps the current versioned feed URL while the schema stays compatible; a schema change needs a new feed, never an overwrite.
