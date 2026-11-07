# Foundation

History, decisions and the engineering log for JP the Cat; every other doc describes the code as it is.

## Timeline

Dates are the evidence in this doc; the owner docs carry none.

- 2026-06-30: the initial commit with the marketing site, the product plan and competitive research, and `v0.001` ships the same day.
- 2026-07-01: the Codex provider and the usage index land, the dashboard becomes a real Dock window with a demo top bar, and the first SwiftUI dashboard popover ships.
- 2026-07-02: the macOS widget, launch at login, notifications by the book and the pSEO `/library` engine land.
- 2026-07-03: the full `/library` pSEO site ships, and the remote pricing layer lands.
- 2026-11-06: the source goes public under MIT as a fresh repository with a new root commit, because the old history held customer emails, Stripe IDs, and device hashes; that history lives only in the private `8bittts/JPtheCat-archive`.
- The rest of the record is the engineering log below: each entry states what broke, the rule now, and the guard that holds it, while the contract it protects lives in its owner doc.

## Decisions

- **The name is `JP the Cat`.** Every user-facing surface reads the spaced name and `JPtheCat` survives only as a code identifier, an artifact filename or the domain; `AGENTS.md` carries the rule and its guards.
- **Local-first and private.** Prompts, code, transcripts, credentials and local usage databases never leave the Mac, and the app holds no Full Disk Access or Accessibility grant; the two opt-in plan-usage fetches are the disclosed exceptions ([04-security.md](04-security.md)).
- **Never fabricate a quota.** A provider without a trustworthy official window shows tokens and says the quota is unavailable; the honest tri-state headroom and the capture-age rule came out of two reverted gates recorded in the log below.
- **The homepage is a fixed curated presentation**, not the native catalog; native layout experiments and provider additions never expand it ([02-design-system.md](02-design-system.md)).
- **Sparkle release notes are customer-facing only** and cover the latest release only; an all-internal release aborts rather than publishing empty notes ([05-infrastructure.md](05-infrastructure.md)).
- **Worktrees live under `workstreams/`**, because concurrent agents and automation reset the shared checkout and have destroyed uncommitted work there.
- **No CI.** `.github/workflows/ci.yml` exists but is disabled on purpose; the local gates are the gates ([09-quality.md](09-quality.md)).
- **One store, one reader, one pricing rule** for every OpenCode-derived row ([11-adding-a-provider.md](11-adding-a-provider.md)).

## Engineering Log

The incident record behind the rules in `AGENTS.md` and the owner docs.
Each entry states what broke, the rule now, and the guard that holds it.
The contract itself lives in its owner doc; full investigations live in git history.

### Guards and gates

**A guard needs a floor proving its scan was non-empty.**
One audit found four green guards over broken subjects: `ScanErrorSurfacingTests` read one file and one literal while `MuseSparkProvider` and `OpenCodeProvider` shipped five forbidden `while (try? stmt.step())` loops on the money path; a `ThemeTests` sweep never set `isPro` and checked 2 of 24 themes; `ModelEffortTests` threw `XCTSkip` when the web symbol it parses was renamed; two scans used hardcoded or non-recursive file lists.
Each now enumerates recursively and asserts a non-empty count.
A skip is for a missing environment capability, never for a changed subject.
Shell gates had the same shape: a command left of `&&` is `set -e`-exempt, a `case` without `*)` launched the app on a typo, and globs without `nullglob` reported success after copying nothing.
Mutation-test every new guard: break what it protects and watch it fail.
Three guards failed that check on first write (`PackageResourceBundleTests`, `testColdStartSkipsFingerprintReadViaPersistedCtime` before `Stats.fingerprintReads` existed, and the `[notes]` guard before it ran the real awk).

**Do not bulk-delete source-pin tests on a "formatting pins" premise.**
`SettingsCopyTests` and `DashboardChromePlacementTests` alone own the spaced-name settings copy, the VoiceOver cycle-row subtitle, chrome ORDER (the parity script's `grep -Fq` is order-blind), the switch-slot contract, and "Test meow fires with interactive sounds off".
Migrate an invariant to an executable form before deleting its grep.

**A test must never touch a real-filesystem default path.**
Early `ClaudeRateLimitStore` tests called `defaultURL()` and deleted a developer's real capture file while staying green.
Stores take an injectable `url:`; tests use a temp file.
Seed cursors under the URL the provider's own enumeration returns: a hand-built `NSTemporaryDirectory()` path does not match the `/private/var/...` form `FileManager.enumerator` yields.

#### Measurement hygiene

1. `ps -o %cpu` on Darwin is a decaying ~1-minute average, not a lifetime figure.
2. The named leaf of a sampled stack is not the cost: `HexColor.components` measured 0.03%; the cost was the SwiftUI view-graph update above it.
3. Never compare a debug build with a signed release build, and never measure anything Keychain-adjacent with an ad hoc build.
4. Read the app's own budget log first: `/usr/bin/log stream --level info --predicate 'subsystem == "com.8bittts.jpthecat"'`; both `--level info` and the absolute path are required.
5. Quit every other JP copy and do not build while sampling; concurrent tooling inflated one launch figure.

#### Proving a Swift change compiled

A comment-only edit produces a byte-identical `.o`, so no object mtime changes and nothing relinks; that is correct, not a skipped file.
Prove a compile by injecting a syntax error (non-zero exit) or by making a semantic change and watching the object bytes change.

#### Swift 6 Language Mode

`mac/` builds in full Swift 6 mode (`swift-tools-version:6.0`, `swiftLanguageModes: [.v6]`) and stays warning-free.
- `nonisolated(unsafe)` only for configured-once, read-only statics such as formatters and `NSFont`.
- `Updater` is `@MainActor`; its Sparkle delegate callbacks are `nonisolated` and wrap their bodies in `MainActor.assumeIsolated`.
- `UsageAlertCenter` is deliberately not `@MainActor`: `shared` is `nonisolated(unsafe)` and `@preconcurrency import UserNotifications` covers the un-annotated module.
- `StatusBarController` and `DashboardViewModel` use `isolated deinit`; settings observers pass only the `Sendable` `SettingsStore.Change` across the hop.
- The app test target needs its own `-F tools/sparkle` search path and rpath.

#### SwiftPM build backend

Swift 6.4 made `swiftbuild` the default: products moved to `.build/out/Products/<Config>`, `<Target>.build/` disappeared, staged resource bundles became `X.bundle/Contents/Resources`, and compile/link steps run from the git repository root.
The last change is why the tracked root `tools -> mac/tools` symlink is load-bearing (`mac/AGENTS.md`).
Scripts now derive widget sources from the package, collect whatever const-values files the build produced, accept either bundle shape, list both Sparkle rpath depths, and anchor scratch paths to `REPO_ROOT`.
`/jp`'s pre-release step stages every path in `git status --porcelain`, so a stray file at the repo root is a `/jp` hazard.

**A deprecation swap must keep behavior.**
Replacing `NSApp.activate(ignoringOtherApps:)` with the cooperative combo silenced a warning and broke foregrounding; that is why `AppForeground` holds the one documented deprecated call.

### Keychain and identity

**Never read a Keychain item another app owns.**
`PlanDetector` read Claude Code's `Claude Code-credentials` item for a cosmetic "Max 20x" label.
That read is gated by the owner's ACL, so macOS prompted for the login password; Claude Code rewrites the item on every token refresh and each Sparkle update changes JP's signature, so the prompt returned daily and on every update.
It survived a month because this log called the prompt a dev-build profiling artifact; identity-mismatch prompts are dev-only only for items JP creates.
An earlier version also defaulted an unmatched `max` tier to `.max20`.
`PlanDetector` is deleted, and no local source carries a Claude tier, so none is shown.
A future tier must come from the provider's own live signal and fall back to no label.
Guards: `PlanTierKeychainReadTests`, `ClaudeRateLimitTests.testDecodedSnapshotClaimsNoPlanTier`.

### Model Pricing Coverage

**Pricing coverage is emitted-ID coverage.**
Audits found rows copied from the wrong sibling (`gpt-5.6-luna` and `terra` at Sol's rates, a 5x overcount), documented aliases missing, and hyphenated snapshot dates the Claude-only normalizer missed.
Spot-check family-specific rates, aliases, and snapshots; a list-presence test would not have caught Luna.
The operator-local `.agents/skills/jp-models/scripts/audit_model_coverage.py` inventories locally emitted ids, and `OpenCodeGoProviderTests.testEveryRoutedAccountingIDIsAnExactPriceRow` covers the accounting ids gateways derive.

**A new generation is a distinct row until its rates prove otherwise.**
Fable 5.1 and Mythos 5.1 bill cache reads at 0.025x input and Opus 5.5 at 0.05x, so normalizing them onto Fable 5 or Opus 5 would overbill the largest token class.
`grok-4.6` differs from `grok-4.5` only in its cached rate, and `gpt-6.1-sol` halves GPT-6 Sol's cached input.
Costs are computed at query time from the stored raw model id, so a new row reprices existing turns without a `parserRevision` bump, and a web deploy of `pricing-v1.json` reaches installed apps through `RemotePricingStore`.
Guards: per-model `PricingTableTests`, `MultiWindowSummariesParityTests`.

**One model identity pipeline.**
Seven normalizers disagreed on `[1m]`, snapshot dates, vendor prefixes, aliases, free tiers, and gateway suffixes, so one Go row listed a model twice and an alias showed a guessed effort chip.
`ModelIdentity` (Core) and `web/lib/model-identity.ts` are the one pipeline: pricing keeps accounting suffixes, display and grouping drop them, aliases are data in `pricing-default.json`, and an unclassified model shows no effort chip.
`PricingTable.aliasDefects` validates the bundled map and the remote feed.
Guards: `ModelIdentityTests` and `web/tests/model-identity.test.ts` over `web/tests/fixtures/model-identity-cases.json`.

**Some premiums are not in the model id.**
Claude fast mode doubles every rate but logs the same `message.model`; only `usage.speed == "fast"` says so, so the parser appends `-fast-mode` (never bare `-fast`, which real ids end in).
US-only inference (`usage.inference_geo == "us"`) adds a flat 1.1x, stored as a `rate_multipliers` factor rather than a row per model.
A test that seeds a Claude cursor must pass the provider's current `parserRevision`.
Guards: `ClaudeFastModeTests`, `ClaudeUSInferenceTests`.

**Free tiers are unpriced, not zero-priced and not paid.**
Stripping `-free` priced free Zen turns at the paid rate on the brand rows and added them to the dollar total.
Keep the suffix through normalization and check the normalized id; a free id decorated with a date or `[1m]` once escaped the check.

**Grok bills per request and records per turn.**
Grok Build writes `update.usage` only at `turn_completed`, so Today read `$0.00` through long turns.
The billed mid-turn source is `~/.grok/logs/unified.jsonl` `shell.turn.inference_done`, overlaid as `sum(rounds) − sum(turn_completed)` per session; `_meta.totalTokens` is context occupancy and is never priced.
xAI applies the 200K premium per request, so a reconciling single-model turn is split into one event per request (`GrokRequestRounds`); otherwise the turn stays one upper-bound event.
Guards: `GrokProviderTests`.

**Codex token totals can precede the model.**
Resumed rollouts emit token counts before the first `turn_context`; `CodexProvider` backfills them from the same file's later model id, else leaves them unpriced as `unknown Codex model`.

**Pricing revisions protect corrected bundles.**
A cached revision-1 remote table restored Sonnet 5.5's old cache-read rate over the corrected bundle at launch.
A bundled correction advances `pricing_revision` and `RemotePricingStore.minimumPricingRevision` together, which also rejects the stale ETag.
`web/public/stable/pricing.json` stays byte-identical to the v1.125 table for older apps that ignore context thresholds; new builds read `/stable/pricing-v1.json` (guard: `remote-pricing-endpoint-parity.test.ts`).

**Library calculators must price like `CostCalculator`.**
They once claimed a flat 0.1x cache read, ignored cache writes, never applied the 200K tier, and dropped GPT models from the Codex calculator.
The tier applies per request, so only the single-request calculator uses it; per-MTok rates keep up to six decimals (`usdPerMTok`).
Guard: `web/tests/library-calculators.test.ts` over `web/lib/library/calculator-math.ts`.

### Providers

#### Provider/tool detection

- A bare dotfolder survives uninstall (`~/.copilot` outlived the CLI by weeks); check the real executable.
- A GUI app does not inherit the shell `$PATH`; also check fixed install directories (`CopilotOtelSetup.defaultCopilotSearchDirectories()`), never a `$HOME` walk.
- A detected binary is often a symlink; `FileManager.isExecutableFile(atPath:)` follows it, while `lstat`-style checks break detection.
- A correctly named env var may not do what it says: `COPILOT_OTEL_ENABLED=true` enabled OTel but kept the network exporter, and the file exporter needs `COPILOT_OTEL_FILE_EXPORTER_PATH`.
  Verify against the tool's own log, and keep the stale-block migration in `CopilotOtelSetup.install()`.
- Shell-config edits reach only shells opened after the edit, so empty-state copy says "open a NEW terminal window"; test with `zsh -i`, since `-l` alone skips `.zshrc`.

**A fully unpriced provider shows tokens.**
Copilot's only model had no price row, so every dollar surface read `$0.00` beside 53.6K real tokens; the token-display contract is Step 4 of `11-adding-a-provider.md`.

**Indexed rows need an event-series fallback, loaded lazily.**
Muse Spark's hero chart was blank because `ProviderRow.series` took the index series with no fallback (now `resolvedDailyCostSeries`).
The first fix called `loadEvents()` on every refresh and re-read heavy corpora (v1.054, reverted in v1.056); `resolveOfficialProviderInputs` loads events only when the rollup is missing or `needsEventSeriesFallback` is true.
Guards: `DashboardViewModelMuseSparkEstimateTests`, `DashboardViewModelLazyEventLoadTests`.

**Muse Spark "live" means OpenCode on this Mac.**
Meta's dashboard aggregates every client, JP reads only local OpenCode rows, and Meta ships no usage-history API.
The row matched only `spark` ids, so 243 Meta-direct Muse Wonder turns had no owning row; it now owns Meta's Muse text family by name (`MuseSparkProviderTests.testMuseWonderTurnsLandOnThisRowAtMetaListRates`).
`MuseSparkScope` and `ProviderRow.sourceScopeNote` say so (guard: `MuseSparkScopeTests`).

**Cursor's stop hook needs an interactive turn.**
`cursor-agent --print` completes without emitting `stop`, so verify with an interactive turn, then `jpthecat-cli --cursor` and the staged row.
The plan-usage fetch keeps a still-current Grok Bot meter when one best-effort call fails (`CursorPlanUsage.carryingOver`).

#### OpenCode gateways

`opencode.db` records the gateway on every message, and model-brand rows derive from the same rows, so Zen and Go are `ProviderBasis.gateway`: dollar-displayed, never summed.
Go publishes per-model dollar caps and writes no local reset or remaining quota, so its gauge is measured local cost against those caps with `resetsAt` nil.
`OpenCodeGoLimits.measuredWindows` owns that math, and a capped model JP cannot price contributes nothing rather than a 0% bar.
Its menu-bar rotation is a deliberate, approved exception to the "official = provider-reported" rule; the widget capsule and alerts stay official-only.
Guards: `OpenCodeGoProviderTests.testMeasuredWindowsAreOrderedAndCarryNoReset`, `testMeasuredWindowsDropCappedModelsJPCannotPrice`, `DashboardStateTests.testWidgetAndAutomationTreatAMeasuredGatewayWindowAsNotOfficial`.

**OpenCode-family standardization.**
An audit found one turn priced three ways and second copies of Core tables: brand rows stripped `-free`, two rows carried guessed rates, `LocalAutomationSnapshotBuilder` and the CLI re-derived `ProviderBasis` by hand, the web fell unknown vendors through to `gemini`, the CLI total excluded brand rows the dashboard summed, four brand providers were verbatim clones, Zen re-decoded its whole history on every change, and Settings opened seven SQLite connections.
One `OpenCodeBrandProvider` and `OpenCodeModelReader` now serve all seven rows, `ProviderCatalog.localAccountingIDs` and `aggregateIDs` define the sets once, and `OpenCodeDetection` is one cached probe.
Guards: `OpenCodeDerivedProviderTests`, `CLIProviderTableTests.testProviderAllMatchesTheDashboardAggregateSetExactly`, `ProviderBasisTests.testKeyMeaningIsPinnedForEveryBasis`, `web/tests/provider-catalog-parity.test.ts`.

**OpenCode store reads.**
- The composite-cursor migration probed SQL spelling and missed the inline `path TEXT PRIMARY KEY` schema; it now inspects `pragma_table_info`.
- A path-only verification cache let one provider mark another's source as consumed; each provider's persisted cursor owns the skip, including WAL state.
- A response finishing after a newer message advanced the creation watermark lost tokens; indexed reads rewind from `message.time_updated` inside one read transaction.
- A failed scan once erased accepted history; failed decodes now stop before deletion or cursor advance.
- OpenCode's 200K premium is exclusive while direct xAI's is inclusive, so gateway Grok keeps its own accounting ids (`OpenCodeGoProviderTests.testGatewayGrokContextBoundaryDiffersFromDirectXAI`).
- OpenCode's session-v2 store moved turns to `session_message` and stopped appending to `message`, so a `message`-only reader silently dropped every later turn while the audit script reported full coverage.
  `OpenCodeStore.assistantProjection` reads both tables, and the script mirrors it (`OpenCodeSessionMessageTests`).

**Library copy drifted behind the live set.**
Hand-typed "tracked today" lists named four providers after six were live, and two pages claimed or linked things that did not exist.
Copy names the live set through `liveProviderNames()`, and `library-links.test.ts` resolves every generated link.
A Tailwind utility naming an undefined color emits no rule; `design-system-normalization.test.ts` fails on any palette utility without a token.

### Rate-Limit Window Freshness

Codex quota windows:
- Choose the newest `rate_limits` snapshot by event timestamp and normalize its slots by `window_minutes`.
  Never merge an older unexpired 5-hour value into a newer weekly-only snapshot; that hung a 5-hour value after Codex removed the limit upstream.
- Reject only the rolling-zero signature: two consecutive weekly-only `0%` snapshots whose reset moves with the timestamp.
  A genuine zero with a fixed reset stays.
- Accept only the account pool (`limit_id: "codex"`, plus identifier-less legacy records); a model pool never replaces it.
- A weekly reading can sit for days while usage continues elsewhere; it once held 26% for 23 hours against an account at 100% after the default model moved to another pool.
  v1.113 aged such readings out after 300 minutes, which collapsed the row and discarded a valid reset countdown, so v1.114 reverted it.

Claude had the same defect through a 12-hour capture-age gate in `ClaudeRateLimitStore.decodeRaw`; v1.117 removed it, and capture age now feeds only `isActive`.
Guards: the `CodexProviderTests` `testLatestRateLimits…` cases and `testOldCaptureStillReportsWhileItsWeeklyResetIsAhead`.

**A capture gate must accept every optional window.**
The statusline block wrote only when `five_hour` was present; Claude Code 2.1.318 sends a weekly-only payload, so the file froze and the gauge showed 8% against a live 75% for four days.
Revision 3 writes whenever any official window is present, migrates at launch rather than only when Live Data opens, and never downgrades a newer block.
Guards: `StatuslineCaptureTests.testBlockWritesAWeeklyOnlyPayloadThatDecodesToTheWeeklyWindow`, `testMigrationOnlyMovesForward`.

**A frozen Claude reading must not contradict the limit notice.**
Claude's statusline stops after a session-limit refusal, freezing the last official value below 100%.
When the high-and-stale heuristic says "likely exhausted", the gauge shows an explicitly estimated 100% and names the frozen reading; it once showed 86% beside a confirmed refusal.

**A toggle reads one ground-truth signal.**
The Claude live-limits switch was `active || installed`, so a leftover capture file kept it ON for up to 12 hours after uninstall, including after Claude Code regenerated its own statusline script.
`ProviderOptInRow.isInstalled` reads the install marker only, and `refresh()` clears an orphaned capture whenever the marker is absent.
Guards: `ClaudeRateLimitTests.testClearDeletesTheCapturedFileSoIsActiveFlipsToFalse`, `testClearOnAMissingFileIsHarmless`.

**Codex credits are a separate balance.**
JP dropped the sibling `credits` object, so an exhausted weekly window could not be explained beside available credits.
Credits persist through streaming, cursors, and the bounded legacy fallback, show separately in provider detail and automation, and never raise headroom.
Guards: `CodexCreditsTests`, `CodexCreditsPresentationTests`.

### Refresh, indexing, and SQLite

#### Reindex storm

"Freeze" and "memory" reports were a profiler-confirmed reindex storm, found in four rounds of `sample <pid>`; each fix exposed the next hot path.
1. Fingerprinting every file each pass was slow, and the size+mtime shortcut (v1.013–v1.015) served stale data, because `rsync --times`, `cp -p`, and `touch -r` preserve mtime across a rewrite.
   The safe skip is `(size, mtime, ctime)`, since userspace cannot set ctime; it is persisted on `cursors`, and a legacy `ctime == 0` cursor never matches.
2. Queued reindexes chained back to back during an active session until `minQueuedRefreshSpacing` added a floor.
3. File changes trigger an immediate window-only refresh, while indexing uses a 5-second trailing debounce capped at 15 seconds.
4. `DashboardWidgetPublisher` ran the 90-day scan on the main actor: isolating a whole type to `@MainActor` for convenience isolates its expensive functions too.
5. A Keychain read blocked launch on the main thread; launch-time work now resolves off-main.

Related rules that came out of it:
- Closing the dashboard releases its hosting tree so hidden `TimelineView`s stop.
- `CodexProvider.latestRateLimits` caches per-file tails by `(path, size, mtime, ctime)`; never sort rollouts by mtime for cross-file recency (`testLatestRateLimitsUsesNewestTokenCountTimestampAcrossFiles`).
- Rotated-away provider files keep their events; the stale sweep iterates `cursorPaths(provider:)`, so per-refresh work scales with live files, not history (`testRetentionKeepsThePerRefreshStaleSweepBounded`).
- The reindex decode loop wraps each file in `autoreleasepool`, and `malloc_zone_pressure_relief` runs only after a pass that read files.
- Run the full suite after touching shared indexing or caching, then re-profile the running app.

#### Window summaries grouped scan

`multiWindowSummaries` and `windowSummaries` aggregate in SQLite by `(provider, model, local day, context tier)` and price the groups in Swift; a 526K-event scan fell from 24,240 ms to 784 ms with identical totals.
Days are local, so the SQL modifier must match the calendar's timezone or the per-event path runs; cost is not linear in tokens, so the per-event context-tier flag is part of the `GROUP BY`.
A non-Gregorian `Calendar.current` zeroed every total in v1.059 because SQLite dates are Gregorian; `sqlLocalDayExpression` returns nil for those calendars.
The scan also checks SQLite's day string against Foundation's, falls back on a prepare failure, and must stay a `SEARCH` on its index.
Guards: `MultiWindowSummariesParityTests`, `GroupedScanGuardsTests`, `WidgetSnapshotTests.testHasSameContentIgnoresSubCentDriftInNestedFigures`.

#### Sustained-CPU Postmortem: The Refresh Storm (2026-07-26/27, shipped v1.083)

macOS flagged JP for significant energy use: about 1.2 cores in steady state.
- `RefreshCoordinator.fileChanged()` refreshed on every FSEvents callback with no debounce, 63.9 refreshes a minute against a designed 1, and the 2-second floor never applied to window-only passes.
- `reindex: false` skipped only the indexer walk; the window scan, three Copilot OTel parses, Codex sweeps, and the widget publish still ran every time.
- The app had logged `refresh_finished … budget_ms=50` violations about once a second, unread.
- An occluded or miniaturized dashboard still drew 120 fps; the motion gate pauses on `occlusionState`, keys on `hasObservedOcclusion` because no notification arrives outside a real run loop, and takes no `isVisible`, which a miniaturized window reports as false.
- One `stat` replaced `attributesOfItem`, but `cursors.mtime` is compared with `==`, so it must match Foundation bit-for-bit through the 2001 reference epoch; the naive conversion mismatched 25% of files.
  `url.resourceValues` caches stale values and is rejected.

Refresh CPU fell 93%.
macOS small-zone malloc never unmaps regions, so a large peak-to-live ratio reads as a leak while `leaks` reports none.

#### SQLite lifecycle

- A reused prepared statement must `reset()` on the way out: after a cache hit it held a read snapshot that blocked `VACUUM` and WAL checkpoints, and the WAL grew without bound (guard: `UsageIndexTests.testCursorLookupDoesNotParkAStatementThatBlocksCheckpointing`).
- `sqlite3_exec` stops at the first failure with the transaction still open, and the next `db.transaction` wedges every later ingest (guard: `UsageIndexTests.testAFailedMultiStatementTransactionDoesNotWedgeTheConnection`).
  Crash-only testing cannot see this in-process path.

#### Compaction and path interning

`idx_events_path_id` exists because `deleteEvents` on `.reset` measured 0.56 ms indexed against 44.63 ms as a full scan.
Full `source_path` normalization was rejected, then shipped once two of its three blockers had evidence: the in-process failure path rolls back cleanly, and an older build reopening a migrated database loses nothing.
The third blocker, a user-visible win, stays unmet: the change saves about 31% of disk, not time.
Reopen a rejected design only with the evidence its criteria asked for, and name the condition still unmet.
`migrateSourcePathIndexIfNeeded()` keeps its legacy name, must stay off the main thread, and VACUUMs at `minFreelistPercent: 0` because `DROP COLUMN` leaves fragmentation, not free pages.
Guard: `UsageIndexPathInterningTests`.

### Native UI

- **A `Button` inside another `Button`'s label gets no tap target on macOS.** Make the controls siblings and verify with a real AX-scoped click (`SelectorRow`).
- **`NSAlert` spacing hacks break layout.** A leading `"\n"` overcorrected, and an `accessoryView` body overlapped the title because NSAlert reserves space from `informativeText`; use `NSAlert(jpTitle:jpMessage:)` with native layout.
- **`TextEditor` adds `lineFragmentPadding` horizontally only.** Hand-rolled placeholders jumped on the first keystroke; `JPTextEditorField` derives both layers from one inset.
- **A fixed-height window overflows symmetrically.** The Advanced Analytics chrome sat 5.5pt high because its data-sized body exceeded the window; the `GeometryReader` clamp fixed it, and pixel rows of a screenshot proved it, since the AX frame of a SwiftUI `Menu` is its label text.
- **Static leaves freeze at the first theme.** SwiftUI skips a child whose inputs never change, so its `JP.*` reads keep the old theme; observe `ThemeManager` or pass resolved colors, never `.id(theme)`.
- **Theme identity is tested, not only contrast.** Dark packs must not collapse to `paper == card` or share one accent (`ThemeTests.testEveryThemeHasAnOpinionatedPaletteSignature`).
- **The status pill has no fixed text slot.** Fixed slots left dead space right of the total; monospaced digits keep the width stable.
  After replacing the image, set `needsDisplay` and call `displayIfNeeded()`, or Control Center keeps the old bitmap (`StatusPillMetricsTests`).
- **Estimate-only activity is not a menu-bar quota.** Cursor's self-relative activity rendered as `Cursor 100%`; providers without a quota show today's tokens (`MenuBarLabelRendererTests`).
- **Selector fills must not animate on refresh.** An implicit animation replayed every meter from zero on each poll (`MotionContractTests.testProviderSelectorMetersDoNotReplayAnEntranceAnimationOnRefresh`).
- **Continuous motion uses `TimelineView(.animation)`.** A `repeatForever` phase consumed across a `GeometryReader` never ran, and the pulse sat still.
- **Show every model.** A four-row `+N more` cap hid an actively used older Codex model.
- **Foregrounding needs `activate(ignoringOtherApps:)`.** The cooperative combo left Sparkle and the dashboard behind other apps.
  On macOS 27 a status-item click no longer activates JP, so the click toggle reads window occlusion (`StatusItemClickDecisionTests`).
- **Launch at login must not dead-end on `.notFound`.** Many registered ad hoc copies of the bundle id cause it; map it to an attemptable Off, surface real errors, and run `mac/scripts/ls-sweep.sh` before removing a worktree (`LoginItemTests`).
- **Hiding the Dock icon must not call `NSApp.deactivate()`.** It can drop the visible window.
- **A raw SwiftPM launch is not an app.** Traps in `static NSBundle.module` and `bundleProxyForCurrentProcess is nil` from `UNUserNotificationCenter.current()` mark this class; guard to a no-op or use the staged `.app`.
- **A layout switch must re-anchor the trailing edge.** AppKit resizes a `.preferredContentSize` window from its top-left before `syncDashboardWindowSize` runs (`DashboardSizingTests.testLayoutSwitchReanchorsAppKitsTopLeftResizeOnTheTrailingEdge`).
- **Stage resource bundles before App Intents extraction.** Extraction cleaned SwiftPM outputs and left blank provider marks under a passing staging check.

### Widget

- **`_NSExtensionMain` is required.** A SwiftPM widget's synthesized `@main` traps with "Unrecognized extension type", so it never reaches the gallery although `pluginkit` lists it.
  Running the appex directly must print "An XPC Service cannot be run directly" (guard: `WidgetExtensionPackagingTests.testWidgetForcesNSExtensionMainEntryPoint`).
- **Marks load through `NSImage`.** SwiftUI `Image(name:bundle:)` rendered them blank, and SwiftPM copies `.xcassets` without compiling them.
  The widget bundles every mark the app ships (`WidgetExtensionPackagingTests.testWidgetCarriesEveryProviderMarkTheAppShips`).
- **The exact-size render overstates the placed Large face.** The footer clipped twice on a real widget while the 382pt render looked clear; keep real slack and confirm on a placed widget.
- **A widget showing an old release is first a leftover extension process.** Sparkle moves the running app aside, and one old extension served the moved binary for four days while `ps` and `proc_pidpath` still named `/Applications`.
  `WidgetExtensionRetirer` reads each process's mapped executable region and terminates stale ones; check with `command lsof -p <pid> | command awk '$4=="txt"'`.
  Guards: `StaleWidgetExtensionTests`, `WidgetExtensionRetirerTests`.
- **No empty snapshot before the first refresh.** A forced publish one second after launch wrote "today $0.00", and the 5-minute publish floor kept it (guard: `DashboardWidgetPublisherThrottleTests.testNoDataSnapshotIsPublishedBeforeTheFirstRefreshFinishes`).
- **"Preview data" labels sample figures only** (guard: `WidgetEntryPreviewLabelTests`).
- **A stale gallery render is a cache.** Confirm the installed version, `pluginkit`, and whether current code can produce the output; clear it by logging out, or remove and re-add the widget.
  `WidgetArchiver.ValidationError.bundleStubNotSupported` means a LaunchServices version mismatch: run `mac/scripts/ls-sweep.sh`, `lsregister -f` the installed app, and restart `chronod`.
- **The Edit Widget sheet is OS-rendered** from the App Intent declaration, so its spacing is not addressable.
  macOS has no public API to open the widget gallery, and launching `NotificationCenter.app` is a no-op (guard: `WidgetGalleryButtonTests`).

### Sparkle release notes

The notes filter treats anything unmatched as customer-facing, so every leak arrived through a phrasing nobody had listed.
- v1.018 shipped five plain-English doc and refactor subjects; the denylist now covers doc files in any phrasing, CamelCase symbols, parser and audit-only groundwork, CSS token names, and URL-plus-status QA text.
- v1.096 leaked "Every document and code comment…" because `docs?` does not match "document"; add morphological neighbors together.
- The CamelCase filter blocked a real v1.093 `fix:` by matching `OpenCode`, which is why `[notes]` runs first.
- `JPTHECAT_NOTES_SINCE_TAG` re-bases the next release's notes after a leak.

Guards: `ReleaseNotesWorkflowTests.testTheExactSubjectThatLeakedIntoV1096IsInternal`, `testPlainEnglishCommentAndDocGroomingNeverReachesUsers`, `testDocRuleDoesNotSwallowRealFeatureNotes`.

### Web

#### Brand fidelity

The transactional email shipped an invented bright-gold top bar and a gold square behind the mascot for two rounds; both hexes were real palette values, so the change type-checked and passed review.
A homepage side-by-side caught it, which is why gold is mascot-only and every design starts from the shipped surface.

#### Hook crash in site-copy tests

`tests/site-copy.test.ts` renders some components as raw calls (`Hero()`), which throws once the component adopts a hook.
Before adding a hook to such a component, convert its call site to `createElement(Component, props)`; it bit `Nav` and `StickyPriceBar`.

#### Responsive overflow

- `md:whitespace-nowrap` beside a `md:` font-size jump overflowed only at 768–808px, invisible at 375px and desktop; pair the jump with `xl:whitespace-nowrap`, and sweep a width range, drilling into each section's `scrollWidth`.
- A permanent `position: fixed` bar read as "space below the footer" while document height was correct; hide it once the real CTA's `getBoundingClientRect().bottom <= window.innerHeight`.
  `IntersectionObserver` re-shows it after the target scrolls past.

#### Download telemetry

- Home and `/library` downloads stay distinct end to end: analytics event names and `channel`, and the `downloads` row `source`; the two owner-email variants were retired when downloads moved into the 8pm Pacific daily report.
- The 2026-10-22 review found `human_downloads` up 36% with no code change: ipapi.is had dropped `is_datacenter` / `is_vpn` from its keyless free tier on 2026-09-01 (HTTP 200, new JSON shape), the fail-soft lookup wrote `null` flags, and the human CTE read `null` as "not hosting".
  While the flags worked, 54% of non-bot rows were datacenter or anonymous; only 19 of the 136 "human" rows carried a macOS user agent, and 24h bucket logs showed zero Mac fetches.
  A second hole compounded it: the 30-day PII job nulls `ip` and `ua`, the CTE admits `ip is null`, so monitor and burst rows (a `GrowthScan/0.1` scanner, 136 rows) flipped to human on redaction.
  Fix: parse both ipapi.is shapes and keep absent flags `null`, print `network_flagged / network_flaggable` beside every headline and raise a digest issue on any gap, persist `is_mac` at write time and lead with `mac_human_downloads`, stamp `exclusion` before redaction (migration `0011`), and add the scanner markers to the UA denylist.
  `IPAPI_IS_KEY` is now required for the hosting filter (guards: `web/tests/download-network-intel.test.ts`, `web/tests/growth-download-sql.test.ts`, `web/tests/growth-digest.test.tsx`).

#### Web design normalization

Dialogs repeated private type sizes, radii, and widths; `web/app/globals.css` now owns named roles.
The dialog backdrop is a fixed warm-ink token, because Midnight turns `--color-ink` light.
Sharing a component between two files on one import chain closed a cycle; hoist it to a leaf module (`ticker-band.tsx`).

Reviewed and kept — do not re-flag:
- `/library` `FaqList` is an always-expanded `<dl>`, unlike the homepage accordion.
- `SplitFlapCharacter`'s theme-independent shadow and highlight stay legible on every theme; a theme-aware change must re-render Midnight and stay freeze-safe.

The homepage demo re-renders continuously, so synthetic clicks go stale and its `<dialog>` popups do not open under non-gesture events; dispatch a real `MouseEvent` and read the card's inline `--color-card`.
