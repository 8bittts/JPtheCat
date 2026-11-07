# JP the Cat TODOs

## Rules

1. Never remove, delete, or modify this list unless directed to do so.
2. Active work only. Completed work lives in git history.
3. `_docs/todos.md` is the only backlog file.
4. Keep clear separation of concerns with phase-based checklists and zero task duplication.
5. Validate, review, and test each phase before moving to the next phase.
6. Stage and commit only files touched for the active phase. Ignore unrelated edits from other agents.
7. Write durable findings into the `_docs/` file that owns the topic, replacing any sentence they contradict; history and research go only in `00-foundation.md`.
8. End every phase with a docs-alignment step that updates internal and public documentation and runs the project's declared gates.
9. Promote exactly one follow-on candidate into **Active Work** before implementation.
10. Fix correctness, accuracy, and routing gaps before design polish.
11. Do not reorder or delete entries you do not own; promoting or retiring your own is expected.

## Active Work

### Live-limit capture and OpenCode reader installed verification

- [ ] Confirm the Claude weekly gauge matches claude.ai's All models bar after the next Claude reply.
- [ ] Confirm the next OpenCode turn on a model with a brand row (Muse Spark, Nemotron, MiMo, Big Pickle, or DeepSeek) reaches that brand row through `session_message`.

## Follow-On Candidates

### Download confidence

Candidates, not approved implementation work.
Promote one bounded candidate at a time after confirming its evidence gap.

- **Installation and first value:** verify the public signed DMG on a clean Mac profile through detected provider data and a useful meter; distinguish redirect requests, byte fetches, installs, and first useful sessions.
- **Download confidence:** complete network-filter coverage and reconcile redirects with actual DMG byte fetches before treating download growth as acquisition growth.

Any promoted phase ends with owner-doc alignment and the affected declared gates.

### Open-source upkeep

- Ship Sparkle's MIT notice inside the app bundle (an About acknowledgement or a bundled license file); the repository copy is `mac/tools/sparkle/LICENSE`.
- Add issue and pull-request templates when the first outside contribution arrives.

### Pricing re-checks with a known date

- GPT-5.6 Sol's $4/$20 is published as promotional through 2026-11-30; re-read the OpenAI page after that date and never assume the replacement rate.
- Google bills Gemini 3.6–3.8 Flash at $0.75/$3.75 through 2026-12-31 while Zen bills $1.50/$7.50, so JP leaves them unpriced; add one row when the rates converge, or `-zen` ids if a local Zen turn appears first.
- Re-read the Go usage table if it publishes a new end date for DeepSeek V4.1 Flash.
- Gemini 4 Argon is priced at the 50%-off rate Go and Zen bill today ($2/$10/cached $0.10, list $4/$20/cached $0.20); both tables date the discount through 2026-11-30, so move the row to list price on 2026-12-01 after re-reading both tables.

### OpenCode routes JP cannot price yet

Promote only when a local turn emits one of these ids.
- Direct DeepSeek (`providerID` `deepseek`): its API names V4.1 Flash `deepseek-flash`, applies peak rates on Go's UTC schedule, and bills V4 Pro below Zen; it needs its own accounting ids.
- Zen-only GPT rows (GPT-5.5 Pro, GPT-5.4 Pro and Nano, GPT-5, GPT-5.1, GPT-5 Nano): add `-zen` ids from the Zen table.
- Zen publishes Qwen3.7 Plus and MiniMax M2.7 without Go's 256K tier and cache-write rate; one row serves both routes today.
- Go bills MiniMax M3 above 512K at $0.60/$2.40/cached $0.12 while Zen lists one flat rate, so a tier needs a Go-only accounting id.

### Dashboard focus after a status-item click on macOS 27

On macOS 27 a status-item click no longer makes JP frontmost; the dashboard still appears in front and the toggle no longer depends on activation, but the window may not be key, so Escape and typing may need a first click.
Promote only after confirming key status on macOS 27, and never fix it with a `.regular` promotion on ordinary clicks, which flashes a Dock icon in hidden-Dock mode.

### Icon Composer app icon (macOS 26 Liquid Glass)

HIG wants unmasked square layers in Icon Composer so Dock, Finder, and About pick up glass, dark, and tinted appearances; `mac/AppIcon.icns` is a baked rounded square today.
Promote only with a brand-assets pass in [`02-design-system.md`](02-design-system.md), and never add `Assets.xcassets` for widget marks.

### Match System appearance

An additive "Match System" option (Sunlit or Midnight from `NSApp.effectiveAppearance`) would need Settings and web demo parity in the same change; never replace named themes.

### Increase Contrast theme variants

Custom hex palettes skip the system Increase Contrast variants; promote only if Accessibility Inspector shows a real AA miss with Increase Contrast on.

### Grouped scan for the remaining per-event index loops

`modelDaySummaries` (Advanced Analytics and export) and `hourWeekdayBins` (Rhythm heatmap) still materialize every event with per-row `Calendar` math, off the first-paint path.
- Promote only if profiling shows real cost on a heavy corpus.
- Reuse `CostCalculator.cost(model:usage:forceTier:)` and `UsageIndex.sqlLocalDayExpression`, and keep every configured context threshold in the `GROUP BY`.
- Extend the `MultiWindowSummariesParityTests` oracle pattern before swapping.

### SEO snippet CTR re-check

Due: the 2026-09-02 title and description changes have been live more than 30 days.
Re-check CTR for `/library/compare/jp-the-cat-vs-tokens-4-breakfast` and `/library/alternatives/codexbar` in the next `/growth`; leave deep-ranked model-compare pages alone.
No locale or geographic pSEO: search demand is not geo-shaped.

### Provider Expansion

Follow [`11-adding-a-provider.md`](11-adding-a-provider.md); every provider reads its own local logs, never a hosted usage gateway.
Current tiers live in root `AGENTS.md`; only open triggers belong here.
- **Gemini:** re-check when Antigravity exposes a usable local usage signal.
- **Copilot to tier 4:** needs real model ids, trustworthy dollar accounting, and an honest quota story; quota is not a local file today.

### Claude per-model weekly meter (wired, waiting on upstream)

Capture, decode, and the provider-detail gauge are shipped and render nothing until Claude Code's statusline carries a `seven_day_<model>` key ([03-data.md](03-data.md#per-model-weekly-windows)).
When it does, verify only the label map in `ModelScopedRateLimitWindow.labels` (`seven_day_opus → "Fable"` is inferred from the `/usage` UI).

### Copilot live limits (retired — revive only on the trigger)

The honest Copilot story is opt-in OTel tokens plus summed `github.copilot.nano_aiu`, non-aggregable, with no menu-bar percentage.
No local file holds an official quota: `~/.copilot/data.db` token columns belong to Copilot, `session_context_usage.token_limit` is the context window, and the SDK `account.getQuota` call needs the user's GitHub token on the network.
Never revive it by taking a GitHub token from Copilot storage, the Keychain, or `gh`, by calling `copilot_internal/user`, by embedding the Copilot SDK, or by deriving a percentage from tokens.
Revive trigger: Copilot CLI writes an official remaining-quota snapshot to a local file; then add it as an opt-in Live Data source that stays non-aggregable.

### Copilot OTel invoke detail (low priority)

Only if users need per-invocation diagnostics: surface local duration, time to first chunk, and per-token-type counts when attributes exist; display-only and local-only, never dollars or headroom.

### Product Hunt launch

Copy is ready in [`10-gtm.md`](10-gtm.md).
- [ ] Recruit a hunter.
- [ ] Pick a launch date.
- [ ] Export the six gallery assets.
- [ ] Re-sync the launch copy with `SITE`, current features, the open-source repository, and the theme count immediately before launch.
