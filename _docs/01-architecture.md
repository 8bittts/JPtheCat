# Architecture

Native targets, data flow, providers, indexing, pricing, rate limits, persistence, and the widget of JP the Cat.

As-built architecture of the native app: local agent usage logs → real or notional dollars → live spend and plan-window usage.
When this doc and the code disagree, the code wins.
UI contracts live in [12-ui-surface-invariants.md](12-ui-surface-invariants.md); provider log formats and pricing evidence in [03-data.md](03-data.md); release and signing in [05-infrastructure.md](05-infrastructure.md).

## 1. Targets and shell

Four SwiftPM targets in `mac/Package.swift` (macOS 14):
- `JPtheCatCore` — pure logic with no AppKit or SwiftUI: models, providers, parsing, pricing, indexing, presentation formatters.
- `JPtheCatApp` — the executable app shell, a flat directory of AppKit and SwiftUI files.
- `JPtheCatWidgetExtension` — the WidgetKit extension (§9).
- `jpthecat-cli` — headless `snapshot` / `report` plus the legacy per-provider flags.

AppKit owns the shell: an `NSStatusItem` with variable length, a `DashboardWindow` hosting SwiftUI, child windows, login item, and Sparkle.
SwiftUI owns every surface's content.
`MenuBarExtra` is deliberately not used: the status label needs full image and width control, and the dashboard needs explicit anchoring.
Settings is the in-card `SettingsBackView` face, not a separate window.

## 2. Data flow

```
FSEvents + adaptive timer → RefreshCoordinator (cadence, triggers)
  → DashboardViewModel (the single refresh-work owner)
      → UsageIndexer.refresh per IndexableProvider → UsageIndex (usage.sqlite)
      → windowSummaries → one DashboardState on @MainActor
  → status pill · dashboard · DashboardWidgetPublisher → WidgetSnapshotStore (App Group)
  → local automation snapshot (latest-snapshot.json)
```

- Refresh intent is typed: a timeframe change enqueues a window-only requery ahead of any queued reindex; never collapse intent back to one boolean.
- `DashboardViewModel.watchPaths()` builds the FSEvents list from each enabled provider's own `watchPaths()`, deduplicated, and `StatusBarController` reads it once at launch.
  Every OpenCode-derived row shares one store root, so each of those rows is listed on its own and never relies on a sibling row being enabled (guard: `DashboardViewModelSettingsTests`).
  Copilot is not in the list and refreshes on the timer.
- `UsageIndex` serializes connection work with a recursive lock and `SQLiteDatabase` opens `FULLMUTEX` with a busy timeout, but writes still route through the one owner (`mac/AGENTS.md`).
- `DashboardState` moves provider rows, aggregate totals and series, selection, timeframe, refresh status, and tri-state provenance together.
- `SettingsStore` posts a typed `SettingsStore.Change` only after a real write; non-SwiftUI consumers observe it and remove their tokens on teardown.
- `PerformanceInstrumentation` records budgets and logs `refresh_finished`, `cold_start_first_number_ms`, and `idle_resources` under the `com.8bittts.jpthecat` subsystem; read that log before profiling.

## 3. Providers

`UsageProvider` is deliberately small: `id`, `watchPaths()`, `isAvailable()`, `loadEvents()`, plus defaulted `latestRateLimits()` and `latestRateLimitAwaitingReset(now:)`.
High-volume providers also conform to `IndexableProvider` (`UsageIndexer.swift`) with a `parserRevision` and a `canTailAppend` decision.
`ProviderCatalog` holds catalog metadata and `support` status; the catalog is not a support claim.
`ProviderBasis.of(_:)` is the one cost-basis table, and `isAggregable`, token display, notional labels, and badges all derive from it.
Third-party logs decode with tolerant `JSONSerialization`, never strict `Codable`.

## 4. The normalized record

`UsageEvent` carries `messageId`, `requestId`, `provider`, `model`, `timestamp`, `project`, and a `TokenUsage` with five buckets: `input`, `output`, `cacheCreate5m`, `cacheCreate1h`, `cacheRead`.
Cache writes stay split because 5-minute and 1-hour writes price differently; reasoning tokens are already inside `output`.
`UsageIndex`'s `PRIMARY KEY (provider, msg_id, req_id)` with a keep-max-output upsert deduplicates streaming copies across files and sessions.

## 5. Indexing

- Providers tail appended bytes through `JSONLStreamReader` (chunked `FileHandle` reads); never `String(contentsOf:)` a log.
- `FileCursor` stores offset, fingerprint, and the persisted `(size, mtime, ctime)` skip key on the `cursors` table; a `parserRevision` bump forces one scoped reread.
- `events` stores an interned `path_id` (`paths` table, `idx_events_path_id`), and money scans read the covering `idx_events_scan`; there is no materialized daily table.
- When a provider rotates its own logs, events stay and only the cursor goes.
- `multiWindowSummaries` and `windowSummaries` use the grouped SQL scan with per-event oracles kept for parity tests.
The rules that keep this correct are in `mac/AGENTS.md`; the incidents are in [00-foundation.md#reindex-storm](00-foundation.md#reindex-storm).

## 6. Pricing

`PricingTable` resolves in three layers:
1. Bundled `mac/Sources/JPtheCatCore/Resources/pricing-default.json`, a curated table with LiteLLM field names, maintained with the `jp-models` skill.
2. `RemotePricingStore` fetches `https://jpthecat.com/stable/pricing-v1.json` at launch and every 24 hours with an ETag; only a compatible `pricing_revision` merges over the bundle, remote winning per key.
3. An unknown model keeps `cost = nil` and shows as unpriced, never silently dropped.

`ModelIdentity` is the one normalizer: `pricingID` strips a vendor prefix, `[1m]`, and snapshot dates, lowercases, and applies the JSON `aliases`; accounting suffixes (`-zen`, `-go`, `-peak`, `-opencode`, `-fast-mode`, `-us-inference`) select rates and are created at parse time.
`CostCalculator` prices each bucket (1-hour writes fall back to 2x input), decides the context tier per event from the model's own threshold and inclusivity, and applies `rate_multipliers`.

## 7. Rate limits and headroom

`RateLimitWindow` carries the provider's own `usedPercent`, `windowMinutes`, and `resetsAt`; `RateLimitSnapshot` carries primary and secondary windows, `planType`, `capturedAt`, and any model-scoped windows.
`current(at:)` is the Core boundary: a window exists only while `resetsAt > now`, and `capturedAt` is diagnostics only.
There is no window reconstruction and no plan-ceiling table; JP shows an official window, a measured gateway window, or no gauge.
Sources: Codex rollout `rate_limits` (automatic), Claude statusline capture and Grok capture (opt-in), OpenCode Go measured caps, unified Grok plan usage (one opt-in API task/store for Cursor and Grok Bot; a current Grok subscription hook weekly before the Grok Bot sand weekly).
Source-scoped Grok / Cursor warehouse keys are retained, while reporting projects them into one Grok provider without rewriting persisted events.

## 8. Persistence

| Data | Store |
|---|---|
| Parsed events, cursors, parser state | `~/Library/Application Support/JPtheCat/usage.sqlite` |
| Remote pricing table and ETag | App Support `pricing-remote.json`, `pricing-remote.etag` |
| Preferences | `UserDefaults` under `JPtheCat.*` via `SettingsStore` |
| Widget snapshot | `widget-snapshot.json` in App Group `GRNGR33Z8A.com.8bittts.jpthecat` |
| Local automation snapshot | App Support `latest-snapshot.json` |

No transcript content is ever persisted, only aggregated tokens and costs.
Local outputs carry rollups, provider rows, provenance, and official windows only — never prompts, transcripts, code, secrets, or raw file paths.

## 9. Widget extension

- Built by SwiftPM and assembled into `JPtheCat.app/Contents/PlugIns/JPtheCatWidgetExtension.appex` with its own Info.plist, sandbox entitlement, App Group, and resource bundle.
- The App Group uses the TeamID-prefixed form because the app ships with Developer ID, not provisioning profiles.
- The executable links `_NSExtensionMain`; `scripts/stage-widget-appintents-metadata.sh` embeds `Metadata.appintents`, without which the appex can be registered yet missing from the gallery.
- Data flows one way: the app writes the snapshot and reloads timelines; the extension only reads it.
- `WidgetGalleryOpener` reloads timelines and shows JP-branded steps; no public API opens the gallery.

## 10. No license gate

JP the Cat is free: every feature is available with no license, lease, trial, or Keychain state.

## 11. Launch-mode boundary

A raw SwiftPM launch (`swift run JPtheCat`) lacks the bundle proxy, Info.plist identity, staged resource bundles, Sparkle UI, notifications, and activation-policy behavior of `JPtheCat.app`.
Code that depends on any of these routes through the staged app (`mac/scripts/build_and_run.sh`, DMG, or install) or no-ops in raw mode with a boundary test.
Production code resolves resources through `JPResourceBundle`/`AppResources`, never `Bundle.module`.
