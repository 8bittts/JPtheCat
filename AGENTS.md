# AGENTS.md — jpthecat (root)

JP the Cat (code identifier `JPtheCat`) is a calm, light-themed macOS menu-bar app showing Claude Code spend, Codex and Grok rate-limit usage, Muse Spark notional list-price cost, and OpenCode Zen / OpenCode Go gateway usage, with a labeled provider catalog behind it.
It ships as a native Swift app (`mac/`) plus a Next.js marketing/pSEO site (`web/`), alongside `supabase/` (migrations for release storage and download growth), `Casks/`, `brand/`, and `scripts/`.

Directory-scoped rules load automatically beside the code and are not restated here:
- [mac/AGENTS.md](mac/AGENTS.md) — Swift app, widget, release scripts, native correctness invariants.
- [web/AGENTS.md](web/AGENTS.md) — Next.js stack, gate chain, downloads, email, accessibility, SEO, growth.
- [supabase/AGENTS.md](supabase/AGENTS.md) — manual migrations and the Supabase key rule.

## Documentation

This file is the enforceable contract; read the owner doc before non-trivial work in its domain.

| Task | Doc |
|------|-----|
| Doc index and authority order | [_docs/00-docs-map.md](_docs/00-docs-map.md), which follows the fleet documentation standard |
| Active backlog | [_docs/todos.md](_docs/todos.md) |
| Provider log formats, model-price evidence | [_docs/03-data.md](_docs/03-data.md) |
| Privacy invariant, permissions posture, Keychain access | [_docs/04-security.md](_docs/04-security.md) |
| Signing, Sparkle, release hosting, permissions posture | [_docs/05-infrastructure.md](_docs/05-infrastructure.md) |
| Brand, palette, typography, homepage boundary, website and email design | [_docs/02-design-system.md](_docs/02-design-system.md) |
| Native architecture, refresh, indexing, persistence | [_docs/01-architecture.md](_docs/01-architecture.md) |
| Logo, icons, mascot video, sounds | [_docs/02-design-system.md](_docs/02-design-system.md) |
| `/library` pSEO | [_docs/08-growth.md](_docs/08-growth.md) |
| Download spine, bot filter, `/growth`, owner digest | [_docs/08-growth.md](_docs/08-growth.md) |
| Adding or promoting a provider | [_docs/11-adding-a-provider.md](_docs/11-adding-a-provider.md) |
| Incident lessons behind the rules here | [_docs/00-foundation.md](_docs/00-foundation.md) |
| Gates by target and the guards that hold the rules | [_docs/09-quality.md](_docs/09-quality.md) |
| Native dashboard, window, menu-bar, alert, and typography contracts | [_docs/12-ui-surface-invariants.md](_docs/12-ui-surface-invariants.md) |

For design work, read `_docs/02-design-system.md` first, then the affected contract in `_docs/12-ui-surface-invariants.md`.

**Documentation policy:**
- `_docs/todos.md` is the only backlog; no TODOs or future plans in owner docs.
  The only dated files are the archives in the operator-local, gitignored `_docs/legacy-backup/`.
- No changelog, release-evidence, or research files; git history is authoritative.
- One owner per fact; other docs point to it.
  A rule here stays terse and names its guard; the incident goes in `_docs/00-foundation.md` as a short entry.
- `README.md` version-badge and download-link blocks are generated — never hand-edit them.
- `web/tests/no-fiction.test.ts` scans every `AGENTS.md`, `README.md`, every top-level `_docs/*.md`, `mac/Sources`, and the web app for stale pre-launch copy; when a surface flips live, update the copy and that guard's rule list in the same change.

## Identity & Branding

**The human-readable name is always the spaced `JP the Cat`.**
Every user-facing surface — menus, window titles, menu-bar labels, notifications, accessibility labels, `NSHumanReadableCopyright`, website copy, SEO/OG/manifest/JSON-LD names, `llms.txt`, Sparkle notes, DMG volume name — reads `JP the Cat`, never the closed-up form.
`JPtheCat` is permitted ONLY as a code/build identifier, an artifact filename, or the domain.
The app's localized `CFBundleDisplayName` and `CFBundleName` (`mac/en.lproj/InfoPlist.strings`) are `JP the Cat`; the base `Info.plist` display name stays `JPtheCat` because macOS applies the localized name only when the base matches the bundle's file name (guard: `AppDisplayNameTests`).
One carve-out: the Small (170pt) widget face shows the compact `JP` wordmark, while its `configurationDisplayName`, Medium/Large headers, and accessibility value still read `JP the Cat`.
Never name anything `TokenBar`/`tokenbar` — a live shipping product owns that name.
The bundle id `com.8bittts.jpthecat` is locked.

**Domain casing: if it is a URL shown to a person it reads `JPtheCat.com` (including `api.JPtheCat.com`); if it is not a URL it reads `JP the Cat`.**
Lowercase survives only as a non-displayed functional identifier — `href`/`src`, `SITE.url`, `metadataBase`/canonical/`og:url`/JSON-LD `url`, the real fetch host and CSP `connect-src`, mailboxes, storage URLs, artifact filenames.
`SITE.domain` holds the display form; `SITE.url` holds the functional link.
Never hand-edit the Sparkle-signed `web/public/stable/appcast.xml` — fix the display name in `mac/scripts/generate-appcast.sh` so the next release regenerates it.

**Ground every design in the shipped brand; never invent one.**
Look at the live homepage or app first, resolve colors from `web/app/globals.css` `--color-*` / `Theme.swift` / `JPAppColor` in their established role, and prove any color or layout change against the reference with a real headless screenshot before shipping.
The palette is cream paper + ginger/honey warm accents + ink; CTA is `--color-cta` `#a84f16` (ginger-deep `#a84d14` is the text-legible accent, a distinct token); bright gold `#fdcd2d` is JP's mascot art ONLY, never a UI surface, bar, or fill.
Incident: [_docs/00-foundation.md#brand-fidelity](_docs/00-foundation.md#brand-fidelity).

## Mac/Web Parity

**Shared native/homepage controls retain semantic parity in the same change: units, provenance, badges, actions, and themes.**
The homepage is a fixed curated presentation, not the full native catalog or a native geometry mirror; its roster and design boundary are owned by [_docs/02-design-system.md#homepage-provider-boundary](_docs/02-design-system.md#homepage-provider-boundary).
Native layout experiments and provider additions must not expand or redesign the homepage.
Inspect every shared web call site, then run `scripts/verify-app-demo-parity.sh` and `AppDemoParityGuardTests`; retain positive native and homepage coverage checks.
A green parity script proves only STRUCTURAL parity, so a manual side-by-side of the surface you changed is still required.

Two other mac-to-web bindings break a test when only one side changes:
- Adding, removing, or recoloring a theme in `mac/Sources/JPtheCatApp/Theme.swift` requires regenerating `web/components/site/demo-themes.ts` in the same change (`web/tests/demo-theme-catalog.test.ts` compares byte-for-byte).
- Pricing source of truth is `mac/Sources/JPtheCatCore/Resources/pricing-default.json`, mirrored into `web/lib/library/pricing-data.ts` and `web/public/stable/pricing-v1.json` with parity tests.

## Providers

Read [_docs/11-adding-a-provider.md](_docs/11-adding-a-provider.md) before adding or promoting any provider.

**Every new provider (dashboard-visible OR audit-only) must land in the native Advanced Analytics tray checklist (`AdvancedAnalyticsTrayView.providerOptions`) in the SAME change.**
Homepage analytics and Live Data stay within the fixed homepage roster.
A provider whose events bypass `UsageIndex` also needs a bucketing fetch feeding `ModelDaySummary.bucketed(events:calculator:)`.

Public support is Claude Code, Codex, Grok (Build, Cursor, and Grok Bot), Muse Spark, OpenCode Zen, and OpenCode Go; `ProviderCatalog` is the full catalog and only entries carrying `support: .live` may be marketed as supported.
Gemini stays audit-only — excluded from `--provider all`, the dashboard, widgets, alerts, and the local aggregate.
Copilot, OpenCode Zen, and OpenCode Go are dashboard-visible but **non-aggregable**, which every dollar-aggregate and alert consumer must filter on IN ADDITION to `isContributing` (`ProviderRow.contributesToAggregate`): Copilot via `ProviderBasis.estimate` (token display), and the two OpenCode gateways via `ProviderBasis.gateway` (dollar/token display, no aggregate).
Gateway usage can overlap a model-brand row (Muse Spark/Nemotron/MiMo/Big Pickle/DeepSeek), so gateways stay out of `--provider all` totals and every dollar total, including models without a supported brand row.
Nemotron, MiMo, Big Pickle, and DeepSeek are `ProviderCatalog.localAccountingIDs`: summed into the dashboard aggregate and `--provider all`, never marketed; every OpenCode-derived row follows [one store, one reader, one pricing rule](_docs/11-adding-a-provider.md#opencode-derived-rows-one-store-one-reader-one-pricing-rule).
OpenCode Go's 5-hour/weekly/monthly gauge is measured local cost against its PUBLISHED per-model dollar caps, never a provider-reported percentage; it sets `quotaIsMeasured` and NOT `usageOfficial`, so it draws a `measured` meter in the selector and provider detail but stays out of the widget's official capsule and every alert, and the monthly bar is detail-only.
Grok is the one public provider for Grok Build, Cursor, and Grok Bot.
Raw source IDs remain distinct in the warehouse; reporting projects them into `.grok` without rewriting history.
Local priced activity is aggregable **notional** list price; all-unpriced activity shows tokens.
`GrokPlanUsageStore` / `GrokPlanUsageClient` own one opt-in, cache and five-minute attempt throttle.
A current Grok subscription hook weekly owns `weeklyUsedPct`, menu-bar headroom, and the widget capsule.
Grok Bot's sand weekly stays a named pool and becomes that weekly only when no current hook weekly exists.
Cursor billing-cycle meters stay labeled Cursor and never become the weekly window.
Without either weekly, Cursor Models (then combined included usage, then the first reported pool) drives the selector and plan-only hero as a **billing-cycle** meter.
A maxed pool never headlines while another of the row's pools has room: the selector and plan-only hero take the first pool in that priority with room, and only when every pool is maxed show the one that resets soonest (`PlanPoolHeadline`); `weeklyUsedPct`, alerts, the menu bar and the widget capsule keep the official weekly.
Percentages never enter dollar totals.
Guard: `GrokConsolidationTests`.
A fully-unpriced provider needs TOKEN-based display, never a dead `$0.00` (`ProviderRow.isFullyUnpriced`, `tokenSeries`).
Pricing coverage is emitted-ID coverage, not a vendor-name checklist: lookup normalizes through `ModelIdentity`, and bundled, remote, and web pricing mirrors stay parity-guarded.

**Never fabricate a quota, tier, or plan ceiling for any provider — read the live entitlement or show nothing.**
Claude exposes no plan-tier label; never read another app's Keychain item for a cosmetic label, because it makes macOS prompt for the login password.
JP the Cat makes no Security-framework Keychain access of its own (guard: `PlanTierKeychainReadTests`).
The reviewed exceptions are opt-in plan usage for Cursor and Grok Bot: `CursorAuthToken` reads Cursor's own sign-in (app `state.vscdb` key, else the CLI item through `/usr/bin/security`, which that item already trusts, so no prompt) and never uses Cursor's refresh token; `GrokBotAuthToken` reads Grok Bot's sign-in from `sand-secrets.json` with the Grok Bot Keychain item through `/usr/bin/security` only, and never uses Grok Bot's refresh token.
`ProviderHeadroom.resolve(from:now:)` is the one cross-provider "room left" expression and is honestly tri-state: `.official`, `.likelyExhausted`, or `.unknown` — never a synthesized number.
Menu-bar percentages are reserved for current, trustworthy official quota windows; a provider without one shows actual tokens, says `quota unavailable` in the tooltip, and is omitted at zero.
Never render self-relative `estimatedSharePct` as a percentage-shaped menu-bar value, and never let a token fallback drive the 80%/95% attention border.
Guards: `ClaudeRateLimitTests`, `ProviderHeadroomTests`, `LocalAutomationSnapshotTests`.
Incident: [_docs/00-foundation.md#keychain-and-identity](_docs/00-foundation.md#keychain-and-identity).

**An official window is hidden ONLY by its own `resets_at`, never by how old the reading is.**
Codex writes `rate_limits` only while a CLI turn runs against that pool, so a weekly reading is routinely hours old while its 7-day boundary is still ahead; `capturedAt` is diagnostics, never a display gate.
The same rule binds Claude's opt-in statusline capture (`ClaudeRateLimitStore`): capture age feeds only the `isActive` indicator, never the gauge.
Both capture-age gates shipped once and were reverted: [_docs/00-foundation.md#rate-limit-window-freshness](_docs/00-foundation.md#rate-limit-window-freshness).
Grok's hook file is the remaining age gate: `GrokRateLimitStore.maxAgeSeconds` drops a capture older than 12 hours, and an absent hook lets the sand weekly own the row.
Sand and Cursor meters still follow only their own `resets_at`.

Claude live limits require opt-in local statusline capture.
Grok plan usage and `GrokRateLimitCapture` are separate opt-ins.
The hook weekly is the Grok subscription, not a fallback behind Grok Bot.
Neither ever invents quota from local tokens.
A local-hook opt-in alone is not consent to network sign-in access.
Copilot's OTel `token_limit`/`current_tokens` attrs are the model CONTEXT WINDOW, not a spend quota; the one honest signal is summed per-request `github.copilot.nano_aiu` deltas, never the cumulative counter.

**Any UI offering to enable, connect, or configure a provider must first detect it is locally present and stay hidden until it is.**
Pattern: a pure testable `is<Tool>Detected()` in Core checking real current footprint, a self-hiding SwiftUI row refreshed on `.onAppear`, and a test proving `false` on a clean fixture.
A bare dotfolder is not proof of install, a GUI app does not inherit shell `$PATH`, a detected binary is often a symlink, and a correctly-named env var is not proof it does what its name implies: [_docs/00-foundation.md#providertool-detection](_docs/00-foundation.md#providertool-detection).

## Git, Release & Worktree Workflow

Worktrees live under this repo's `workstreams/` container, not the global `.worktrees/` default: `git worktree add workstreams/<task> -b <task-branch>` from the canonical checkout's root.
`workstreams/` is local-only and must stay ignored by both Git and Vercel.
Reuse an existing task worktree rather than nesting another inside it.
Concurrent agents and automation hard-reset and stash the shared checkout, so editing it has repeatedly destroyed uncommitted work.

Deploy by landing the branch on `main` with `[deploy]` in the commit subject, then confirm Vercel promoted production to that commit and reached READY (not CANCELED).
Sync a worktree by REBASING, never merging: `ignoreCommand` reads only the tip commit, so a merge commit on top of your `[deploy]` commit cancels the build.
Review the shipped result — the live URL, a headless screenshot for visual work, and green gates — BEFORE cleaning up, and never remove a worktree with unverified, uncommitted, or unmerged work.
`mac/scripts/release-jpthecat.sh` makes its `release: … [deploy]` commit, tag, and push from a dedicated worktree at the current local `HEAD` after proving `HEAD` contains `origin/main` — do not move it back inline.
The public install path is `brew tap 8bittts/jpthecat` + `brew trust 8bittts/jpthecat` + `brew install --cask jpthecat` (the trust step is test-pinned in `web/lib/homebrew.ts`); `Casks/jpthecat.rb`, `web/public/stable/jpthecat.rb`, and the public tap stay pinned to the same version and SHA (`release-jpthecat.sh` syncs all three).

**Sparkle release notes are customer-facing ONLY, cover the LATEST release only, and must never contain documentation, process, or internal-implementation commits.**
`mac/scripts/generate-appcast.sh` renders exactly `PREVIOUS_TAG..HEAD` as a styled fragment — a `<style>` block, the `<h2>Small paws, strict standards. Here are the improvements:</h2>` heading, one `<ul>` of customer-facing bullets, and the `<p class="fine">Built with ❤️ from San Francisco and Honolulu.</p>` footer — strips `[deploy]` and conventional-commit prefixes, and must FAIL rather than publish empty or generic notes.
Internal prefixes (`perf`/`docs`/`refactor`/`chore`/`style`) are stripped, so an all-internal release yields empty notes and aborts; a perf-only release is the recurring case.
The sanctioned fix is a `[notes]` tag in the commit subject, which promotes that ONE commit VERBATIM — use it only when the subject already reads as user language.
`[notes]` cannot promote a `docs:`/`release:` commit, but it IS evaluated BEFORE the CamelCase-symbol filter, which is the only reason a provider name shaped like a code symbol can carry its own bullet: `[notes] Add MiMo and OpenCode support` reaches users, the identical subject untagged is dropped.
That filter matches `Upper lower Upper lower`, so a single-capital name (`Nemotron`, `Grok`) is never treated as a symbol and needs no tag.
When the honest subject would read as jargon, or the notes need wording no single subject carries, point `JPTHECAT_NOTES_HTML` at a READABLE FILE holding a matching HTML fragment (it is a path, not literal HTML; the script fails closed with "not a readable file").
Guards: `ReleaseNotesWorkflowTests` (runs the real awk categorizer), including `testNotesTagCarriesACamelCaseProviderNameThatIsOtherwiseDropped` and `testSingleCapitalVendorNamesNeedNoNotesHatch`.
Incidents: [_docs/00-foundation.md#sparkle-release-notes](_docs/00-foundation.md#sparkle-release-notes).

## Gates

- **Docs-only:** manual review plus `git diff --check`, unless the touched doc has a renderer or test.
- **Mac app:** smallest meaningful Swift gate first, broadening by risk — `cd mac && swift build`, `swift test --parallel`, `swift build -c release`.
  An unchanged `.o` is NOT proof the build skipped your file — prove a compile with a syntax error (non-zero exit) or a semantic change: [_docs/00-foundation.md#proving-a-swift-change-compiled](_docs/00-foundation.md#proving-a-swift-change-compiled).
- **Web:** `cd web && bun run check:full` before any production deploy; see `web/AGENTS.md` for the chain, its order, and the Vercel-READY trap.
  Local web secrets come from Infisical via `cd web && bun run dev:secrets`; production flows Infisical `prod` through the Vercel sync, then a redeploy.
- **Visible UI or asset work** (widget faces, themes, brand-fidelity changes, the legal 3D scene) needs a real headless screenshot or the `ImageRenderer`/`JP_RENDER=1` harness, never eyeballed intent.
- `.github/workflows/ci.yml` exists but is disabled on purpose; the local gates above are the gates.
- **Before reporting done:** state which gates ran and why a broader one was not.

## Safety & Privacy

**The one privacy invariant: prompts, code, transcripts, provider credentials, and local usage databases must never leave the user's Mac.**
The exception is unified opt-in Grok plan usage: it sends a saved Cursor or Grok Bot sign-in token only to the existing three DashboardService methods on `api2.cursor.sh`; no refresh tokens, prompts, code, paths or local usage.
The public privacy policy discloses it.
Every telemetry, analytics, and email surface (Vercel Analytics, the owner daily report, download notices, support reports) must honor it — none may ever include prompts, code, transcripts, token history, costs, credentials, project paths, or local-usage-database contents.
Mac app product analytics stay opt-in and off by default.
The app's least-privilege posture (no Full Disk Access, no Accessibility) is a shipped marketing claim guarded by `web/tests/site-copy.test.ts`; the rules that keep it true live in [mac/AGENTS.md](mac/AGENTS.md).

Never commit secrets, API keys, OAuth tokens, signing keys, notary credentials, or local credential state.

**The repository is public; never track the operator-local paths.**
`_docs/legacy-backup/` (customer data), `brand/generated/`, and `brand/reference/` stay gitignored.
The tracked runbooks in `.claude/` and `.agents/` are public, so they never hold home paths, account details, or metrics.
The pre-open-source history lives only in the private `8bittts/JPtheCat-archive`; never push it, rebase it onto, or merge it into the public repository (guard: the local `pre-push` hook rejects any push that contains an archive root commit).

**Never edit agent-harness config ad hoc; use only the explicit opt-in setup paths. `~/.claude/settings.json` remains read-only.**
The Claude-limits capture feature (`StatuslineCapture`) only READS `statusLine.command` to find the user's own statusline script and then edits that script, and only after explicit opt-in.
Grok-limits capture only writes a marked file under `~/.grok/hooks/` after the same opt-in — never `config.toml`, never `auth.json`.
Cursor's opt-in `CursorHookSetup` is the designed `~/.cursor/hooks.json` exception: preserve unrelated hooks and remove only JP's own entry (`CursorProviderTests.testSetupMergesAndRemovesOnlyItsExistingStopHook`).
