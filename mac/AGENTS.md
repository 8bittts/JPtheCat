# AGENTS.md — jpthecat/mac

The native Swift menu-bar app, its WidgetKit extension, and the release and QA scripts that ship them.
The repo root's [AGENTS.md](../AGENTS.md) owns the cross-cutting rules (branding, mac/web parity, the provider model, worktrees, release and Sparkle-notes workflow, gate order, privacy) and they are not restated here.
Architecture lives in [../_docs/01-architecture.md](../_docs/01-architecture.md) and release mechanics in [../_docs/05-infrastructure.md](../_docs/05-infrastructure.md).
Paths below are relative to this directory.

## Release & Distribution

`scripts/build-dmg.sh` builds and notarizes the drag-to-Applications DMG (layout verified by `scripts/verify-dmg-layout.sh`); `scripts/release-jpthecat.sh` floors every new `CFBundleVersion` above the latest published `<sparkle:version>`; `scripts/release-dmg-qa.sh` verifies the live DMG without touching the installed app.
App, core and widget code logs through `os.Logger` (`Log.usage`, `Log.updater` and `Log.api` in `Sources/JPtheCatApp/Log.swift`), never `NSLog` or `print`; only the CLI prints. Guard: `UnifiedLoggingGuardTests`.
Never hand-edit a signed or stable release artifact to make a test green — fix the generator or re-run the release path, and never create a changelog file (git history is the changelog).

Production app and core code must not call SwiftPM's generated `Bundle.module`; `scripts/build-dmg.sh` stages `JPtheCat_*.bundle` under `Contents/Resources` and code resolves through `JPResourceBundle`/`AppResources` (tests may still use `Bundle.module` for fixtures).
`swift run JPtheCat` is NOT equivalent to a LaunchServices-launched `.app` — anything depending on bundle identity, Sparkle, activation policy, resource bundles, or notifications must route through the staged `.app` (`scripts/build_and_run.sh`) or no-op in raw executable mode.
`scripts/build_and_run.sh` and `swift test` write the same `.build/out/Products/Debug/JPtheCat_*.bundle` in different layouts, so running one after the other in a worktree can fail `codesign` with `unsealed contents present in the bundle root`.
That is stale build output, not your change: delete those `JPtheCat_*.bundle` directories and rebuild.

**[CRITICAL] The repository-root `tools` symlink (`tools -> mac/tools`) is load-bearing — never delete it.**
This package's `-F tools/sparkle` unsafe flag is cwd-relative, and SwiftPM's default `swiftbuild` backend runs compile and link steps with the working directory set to the enclosing **git repository root**, not the package root.
It therefore resolves `<repo-root>/tools/sparkle`, which exists ONLY because that symlink is tracked.
Delete it and nothing compiles: `error: unable to resolve module dependency: 'Sparkle'`, on a fresh clone and in a worktree alike.
The deprecated `native` backend used the package root, where `mac/tools/sparkle` is the real vendor directory — which is why this stayed invisible until the toolchain switched defaults.

## Widget

**[CRITICAL] The widget executable must be linked with the legacy `_NSExtensionMain` entry point** (`Package.swift` `linkerSettings`) — the synthesized `@main WidgetBundle` traps at launch otherwise.
Guard: `WidgetExtensionPackagingTests.testWidgetForcesNSExtensionMainEntryPoint`.

The widget design is shipped and settled ([../_docs/12-ui-surface-invariants.md#widget](../_docs/12-ui-surface-invariants.md#widget)); treat it as canonical and do not re-litigate.
Any change must re-render EVERY face at its exact point size via the `ImageRenderer` harness first.
The exact-size render OVERSTATES the real placed Large face's usable height, so budget Large conservatively below 382pt with real slack and treat a Large vertical-layout change as unverified until confirmed on a real placed widget (this clipped the footer twice).

**[HARD REQUIREMENT] Every provider addition or promotion must audit WidgetKit in the SAME change, even when the intended result is exclusion** — update `JPWidgetProviderChoice`, `WidgetPreviewData`, snapshot publishing, marks, and badge formatting when eligible, and add a regression assertion when excluded.
The checklist is "Widget audit" in [../_docs/11-adding-a-provider.md](../_docs/11-adding-a-provider.md#step-5--dashboard-rows-and-widgets).

Data flow is one-way and snapshot-based: `DashboardViewModel` is the only refresh-work owner, `DashboardWidgetPublisher` writes `WidgetSnapshotStore` JSON into the App Group, and the extension only reads that file — never parse logs, open `usage.sqlite`, or run `UsageIndexer` inside it.
Each placed widget picks its own 7/14/30/90-day timeframe backed by `WidgetSnapshot.windows` from ONE `UsageIndex.multiWindowSummaries` scan bounded at 90 days — never a second DB scan per window.
Marks and brand chips load via `NSImage` through `JPResourceBundle`/`WidgetAssets`, never SwiftUI `Image(name:bundle:)` (renders blank); dark-mode tint lift is `ProviderTintLegibility.legibleHex(...)`, the one source of truth for both `JPAppColor.providerTint` and `WidgetPalette.viz(_:_)`.
SwiftPM has no asset catalogs — the loose-resource + `NSImage` loader IS the canonical path; never add `Assets.xcassets`.
A placed widget showing an older release is first a leftover extension process (retired at launch by `WidgetExtensionRetirer`), then a `chronod` cache, not a regression; the checks and every render guard live in [../_docs/00-foundation.md#widget](../_docs/00-foundation.md#widget).

## Correctness

**[HARD REQUIREMENT] Least privilege — NO Full Disk Access, NO Accessibility, ever.**
Sources use exact home-root provider dotfolders, JP's own container/App Group, or the explicitly opted-in Cursor/Grok Bot sign-in stores in Application Support; none requires TCC access.
Never add an entitlement, TCC usage description, `AXIsProcessTrusted`, `CGEventTap`, or Apple-events surface; never enumerate `$HOME` (providers read exact paths only); a future source inside another app's container needs an App Group or a scoped `NSOpenPanel` bookmark, never blanket FDA.
This is a shipped marketing claim, guarded by `../web/tests/site-copy.test.ts`.

Every money figure routes through `MoneyFormatter` (Core), never bare `String(format: "$%.2f")` (drops thousands separators); all figures are USD and a conversion is never invented.

**[CRITICAL] EVERY accumulating scan loop in Core must use `while try stmt.step()`, never `while (try? stmt.step()) == true` or `while let row = try? stmt.step()`** — the latter collapse a real `SQLiteError.step` into loop-end and silently present a truncated total as authoritative.
This is a Core-wide rule, not a `UsageIndex` one: the guard scanned only `UsageIndex.swift` for one literal statement name and stayed green while `MuseSparkProvider` and `OpenCodeProvider` shipped five of the forbidden loops on the same money path.
Single-row `guard`/`if` fetches keep the `try?` form legitimately — one row has nothing to truncate — which is why the guard's regexes anchor on `while`.
A non-throwing `UsageProvider.loadEvents()` cannot propagate, so a provider decode wraps its loop in `do/catch` and returns empty rather than partial.
Shared projections route through `forEachEvent(stmt:)`; public scans `throw` and callers fall back so per-provider and aggregate figures degrade together.
Guard: `ScanErrorSurfacingTests`.

**[CRITICAL] `sqlite3_exec` halts a multi-statement string at the first failure and returns WITH THE TRANSACTION STILL OPEN.**
Every `db.execute("BEGIN IMMEDIATE; …; COMMIT;")` must wrap in `do/catch { try? db.execute("ROLLBACK;"); throw error }` or the connection wedges and the app silently stops recording spend for the rest of the process.
Guard: `UsageIndexTests.testAFailedMultiStatementTransactionDoesNotWedgeTheConnection`.

**[CRITICAL] A reused prepared statement on the shared connection must `reset()` on the way OUT, not only on the way in.**
A statement parked in `SQLITE_ROW` after a cache HIT holds an open read snapshot that blocks both `VACUUM` and WAL auto-checkpointing, so the WAL grows without bound within a session.
`UsageIndex.cursor(for:)` is the one such statement today; do not add another without the same exit reset.
Guard: `UsageIndexTests.testCursorLookupDoesNotParkAStatementThatBlocksCheckpointing`.

`RefreshCoordinator` owns cadence and triggers; `DashboardViewModel` is the single refresh-work owner — never add a second refresh loop or a fixed `Timer` in `StatusBarController`.
Never re-add a per-file fingerprint walk or a second reindex queue: cold start relies on the PERSISTED `(size, mtime, ctime)` on `cursors`, and a size+mtime-only match is NOT sufficient because mtime-preserving copy tools rewrite content silently.
Never eager-load full provider corpora on refresh when `UsageIndex` already has summaries — route tier-4 call sites through `resolveOfficialProviderInputs`, and resolve `ProviderRow.series` through `resolvedDailyCostSeries` rather than the raw index series.
When a provider rotates its own logs, `UsageIndexer.refresh` intentionally KEEPS indexed events and forgets only the FILE; the stale sweep iterates `UsageIndex.cursorPaths(provider:)`, never the unbounded event-derived `sourcePaths`.
The grouped `multiWindowSummaries` scan stays exact only if the day bucket goes through `sqlLocalDayExpression(_:)` (nil falls back to the per-event path for any non-Gregorian calendar or unreproducible timezone), all configured model context thresholds stay in the `GROUP BY` with `CostCalculator.cost(model:usage:forceTier:)`, and the scan stays covered by `idx_events_scan`.
Always run the full test suite after touching shared indexing or caching logic, and re-profile live — a green suite does not prove a performance fix landed.
Postmortems: [reindex storm](../_docs/00-foundation.md#reindex-storm), [grouped scan](../_docs/00-foundation.md#window-summaries-grouped-scan).

Official rate-limit percentages are current only while `resetsAt > now`; never show a past-reset percentage, roll an expired window forward, invent a missing duration, or mix windows across snapshots.
Select the newest snapshot that still carries a recognized (`300`/`10080`) current window and normalize by `window_minutes` — selecting the newest unconditionally blanks the gauge on a degenerate `window_minutes:0` line.
When a window has just rolled past its reset with no fresher reading the gauge stays blank and the provider flags `awaitingResetRefresh` for an explanatory hint, never a synthesized 0%.
Detail: [../_docs/00-foundation.md#rate-limit-window-freshness](../_docs/00-foundation.md#rate-limit-window-freshness).

`ThemeManager` owns the active `JPTheme` and every color resolves via `JPAppColor` — never re-pin a single appearance or a fixed `colorScheme`; add a theme by appending to `JPTheme.all` (`inMoreThemes: true` to list it in the More themes window), which needs no view changes.
A static leaf `View` that reads `JP.*` FREEZES at first-render theme when its parent's structural diff skips it — such leaves need `@ObservedObject var themeManager = ThemeManager.shared` or pre-resolved `Color` inputs, never `.id(theme)` at the root.
Guards: `ThemeTests` (WCAG-AA gate plus palette signature); visual proof `JP_RENDER=1 swift test --filter ThemeCatalogRenderTests`.

**The only reliable foregrounding is `AppForeground.raiseAboveOtherApps()`** (`NSApp.activate(ignoringOtherApps: true)`) — every summoned-from-outside surface (Sparkle window, tapped-alert reveal, ordinary status-item clicks) must use it.
The "modern combo" (`NSApp.activate()` + `.activateAllWindows`) does not rise above other apps; do not reintroduce it.
The plain-click dismiss toggle closes when the dashboard is on-screen and either JP is active OR no other app's window covers it (`CGWindowListCopyWindowInfo` occlusion); never key it on `NSWindow.isVisible`, `isKeyWindow`, or `NSApp.isActive` alone (each caused a real regression — on macOS 27 a status-item click never makes JP active).
Guard: `StatusItemClickDecisionTests`.

Zero deprecated or legacy Apple APIs, with ONE documented exception: `NSApp.activate(ignoringOtherApps: true)` inside `AppForeground`.
Keep a clean rebuild warning-free.

**JP the Cat makes no Security-framework Keychain calls.** It is free: there is no license, trial, or seat state to store.
The reviewed credential reads are unified opt-in Grok plan usage using the existing Cursor / Grok Bot sign-ins via `/usr/bin/security` (guard: `PlanTierKeychainReadTests`).

Every multi-line text input is `JPTextEditorField`, never a hand-rolled `TextEditor` + placeholder overlay (guard: `JPTextEditorFieldTests.testNoSurfaceHandRollsItsOwnPlaceholderOverlay`).
Its insets are settled and test-pinned — do not re-measure or eyeball-tune them.
`ImageRenderer` cannot draw a `TextEditor` or `TextField` at all, so any surface holding one is verifiable ONLY by screenshotting the running app; read [../_docs/12-ui-surface-invariants.md#text-inputs](../_docs/12-ui-surface-invariants.md#text-inputs) for the inset table and the four traps in that screenshot path before touching one.

`LoginItem`/`SMAppService.mainApp` must never swallow errors or dead-end on `.notFound`, which maps to an attemptable "Off", not "Unavailable"; sweep stray registered bundle-id copies with `scripts/ls-sweep.sh` before `git worktree remove` (guard: `LoginItemTests`).

Native UI surface contracts (dashboard chrome and footer, selector rows and badges, Advanced Analytics fixed-height budget, Live Data and Themes windows, menu-bar format and status pill, hero sparkline, alerts, typography) live in [../_docs/12-ui-surface-invariants.md](../_docs/12-ui-surface-invariants.md) — read the matching section before changing one.
The running app IS self-verifiable: `scripts/gui-verify.sh` drives it headlessly via Accessibility (`windows`, `tree`, `press "<AX description>"`, `frame`, `shot`).
Raw synthetic CGEvent clicks do not route to a non-frontmost window here, so drive via AX `press`, not coordinates.
