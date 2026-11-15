# Quality

Gates by target, the guards that hold the rules, and the verification harnesses for JP the Cat.

## Gates

Root `AGENTS.md` (Gates) declares the gate for each target as a hard rule; this section owns what the gates cover.

- **Docs:** `web/tests/no-fiction.test.ts` scans every `AGENTS.md`, `README.md`, every top-level `_docs/*.md`, `mac/Sources` and the web app for stale pre-launch copy.
- **Web:** `web/AGENTS.md` owns the `check:full` chain, its order and the Vercel-READY trap.
  `bun run build` runs the fleet performance budget gate (`web/scripts/perf-budget.ts`) between the compile and the secret scan: it caps each route's uncompressed first-load JavaScript and pins its rendering class in `web/perf-budget.json`.
  Re-baseline only for a reviewed change: `bunx next build`, `bun scripts/perf-budget.ts --baseline`, then `bunx biome format --write perf-budget.json`, with the reason in the commit.
- **Parity:** root `AGENTS.md` (Mac/Web Parity) carries the rule and names the script and the guard.
  `AppDemoParityGuardTests` runs `bun test` under `web/`, so a fresh worktree needs `bun install` in `web/` before `swift test`; without it the Swift suite fails with `Cannot find package 'react'`, which is setup, not a parity break.

## Guards

A rule in `AGENTS.md` stays terse and names its guard; the guard is a test that fails when the rule is broken, and the incident that produced it is in [00-foundation.md](00-foundation.md).
A guard needs a floor proving its scan was non-empty, enumerates recursively, and is mutation-tested on first write by breaking what it protects.
A test that asserts on a provider's quota must inject that provider's capture path, such as `GrokProvider(root:rateLimitStoreURL:)` or `ClaudeRateLimitStore.load(url:)`.
A temp root alone still reads the fixed Application Support capture, so the developer's live reading leaks into fixtures and the suite fails only on a machine with real usage.
The two mac-to-web data bindings and their parity tests are in root `AGENTS.md` (Mac/Web Parity).

## Release verification

Root `AGENTS.md` (Git, Release & Worktree Workflow) carries the review-before-cleanup rule; the post-release proofs are in [05-infrastructure.md](05-infrastructure.md#release-pipeline).
