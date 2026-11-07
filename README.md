<div align="center">

<img src="web/public/jpthecat-logo.png" alt="JP the Cat logo" width="112" height="112" />

# JP the Cat

### The cat that counts your agent tokens.

A calm, light macOS menu-bar app that shows Claude Code spend, Codex rate-limit usage, a unified
Grok view for Grok Build / Cursor / Grok Bot activity and optional official plan pools, Muse Spark
notional list-price cost, and OpenCode Zen / Go gateway usage, with a labelled provider catalog.
Native, local-first, private, and free.

`macOS 14+` · `Apple Silicon` · `Free` · `No account`

<!-- version-badge -->
**Stable release:** `v1.148`
<!-- /version-badge -->

<!-- download-link -->
**Download:** [JP the Cat v1.148 DMG](https://api.jpthecat.com/storage/v1/object/public/releases/JPtheCat-1.148.dmg)
<!-- /download-link -->

**Homebrew:**

```sh
brew tap 8bittts/jpthecat
brew trust 8bittts/jpthecat
brew install --cask jpthecat
```

Tap source: `https://github.com/8bittts/homebrew-jpthecat`

</div>

---

## What it is

JP the Cat answers one question: what are my AI coding agents costing right now, and how much headroom is left?

- **Real dollars, done right.** Claude Code cost comes from local logs, with the 5-minute and 1-hour cache writes priced separately.
- **Honest labels.** Claude is real spend; Codex, Grok, Muse Spark, and the OpenCode gateways are notional list price.
  A limit percentage appears only when the provider reports an official window, or, for OpenCode Go, a measured one.
- **History that lasts.** A local `usage.sqlite` warehouse outlives provider log rotation; Advanced Analytics and export are included.
- **Genuinely local.** Prompts, code, transcripts, and the usage database never leave the Mac.
  The optional Grok plan-usage fetch sends only a saved Cursor or Grok Bot access token to its own dashboard API; no refresh tokens or local usage are sent.
  The website uses disclosed Vercel Web Analytics; Mac app product analytics stay opt-in and off.
- **No provider pretending.** Only providers marked `live` in `ProviderCatalog` are marketed as supported.

Every feature — dashboard, limit gauges, widget, alerts, analytics, export, and all 24 themes — is free. There is no license, trial, or checkout.

## Repository layout

```
JPtheCat/
├── mac/      macOS app — SwiftPM: JPtheCatCore, JPtheCatApp, JPtheCatWidgetExtension, jpthecat-cli
├── web/      Marketing and /library pSEO site — Next.js 16 on Vercel
├── supabase/ Migrations — release storage, download growth table, rate limit
├── Casks/    Homebrew cask, pinned to the published DMG
├── brand/    Source brand assets and generated mascot animation
├── scripts/  Asset generation and repo-level guards
└── _docs/    Owner docs — start at _docs/00-docs-map.md
```

## Common commands

Run each line from the repository root:

```sh
(cd mac && swift build && swift test --parallel)                               # native gates
bash mac/scripts/build_and_run.sh                                               # stage and launch the real .app
(cd mac && swift run jpthecat-cli snapshot --json --provider all --indexed)     # local automation snapshot
(cd web && bun install && bun run dev)                                          # http://localhost:4444
(cd web && bun run quality)                                                     # full web gate
```

`swift run JPtheCat` is not an app-shell smoke test; use the staged `.app`.
The app also writes `~/Library/Application Support/JPtheCat/latest-snapshot.json` for local integrations; it carries rollups and official windows only, never prompts, transcripts, code, secrets, or file paths.

## Docs

- [`_docs/00-docs-map.md`](_docs/00-docs-map.md) — owner-doc index and authority order.
- [`AGENTS.md`](AGENTS.md) — the enforceable engineering contract.
- [`_docs/todos.md`](_docs/todos.md) — the only active backlog.

The repository stays private.

---

<div align="center">
JP the Cat is independent from AI providers.
</div>
