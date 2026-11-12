# Quality

Gates by target, the guards that hold the rules, and the verification harnesses for JP the Cat.

## Gates

- **Docs-only:** manual review plus `git diff --check`, unless the touched doc has a renderer or test; `web/tests/no-fiction.test.ts` scans every `AGENTS.md`, `README.md`, every top-level `_docs/*.md`, `mac/Sources` and the web app for stale pre-launch copy.
- **Mac app:** the smallest meaningful Swift gate first, broadening by risk: `cd mac && swift build`, `swift test --parallel`, `swift build -c release`.
  An unchanged `.o` is not proof the build skipped a file; prove a compile with a syntax error or a semantic change ([00-foundation.md](00-foundation.md#proving-a-swift-change-compiled)).
- **Web:** `cd web && bun run check:full` before any production deploy; `web/AGENTS.md` owns the chain, its order and the Vercel-READY trap.
  `bun run build` runs the fleet performance budget gate (`web/scripts/perf-budget.ts`) between the compile and the secret scan: it caps each route's uncompressed first-load JavaScript and pins its rendering class in `web/perf-budget.json`.
  Re-baseline only for a reviewed change: `bunx next build`, `bun scripts/perf-budget.ts --baseline`, then `bunx biome format --write perf-budget.json`, with the reason in the commit.
- **Parity:** `scripts/verify-app-demo-parity.sh` and `AppDemoParityGuardTests` prove structural parity between the native dashboard and the homepage demo; a manual side-by-side of the changed surface is still required.
  `AppDemoParityGuardTests` runs `bun test` under `web/`, so a fresh worktree needs `bun install` in `web/` before `swift test`; without it the Swift suite fails with `Cannot find package 'react'`, which is setup, not a parity break.
- **Visible UI or asset work** needs a real headless screenshot or the `ImageRenderer` / `JP_RENDER=1` harness, never eyeballed intent.
- `.github/workflows/ci.yml` exists but is disabled on purpose; these local gates are the gates, and a report states which ran and why a broader one did not.

## Guards

A rule in `AGENTS.md` stays terse and names its guard; the guard is a test that fails when the rule is broken, and the incident that produced it is in [00-foundation.md](00-foundation.md).
A guard needs a floor proving its scan was non-empty, enumerates recursively, and is mutation-tested on first write by breaking what it protects.
A test that asserts on a provider's quota must inject that provider's capture path, such as `GrokProvider(root:rateLimitStoreURL:)` or `ClaudeRateLimitStore.load(url:)`.
A temp root alone still reads the fixed Application Support capture, so the developer's live reading leaks into fixtures and the suite fails only on a machine with real usage.
Two mac-to-web data bindings break a test when only one side changes: the theme catalog (`web/tests/demo-theme-catalog.test.ts`) and the pricing mirrors.

## Release verification

Review the shipped result before cleaning up a worktree: the live URL, a headless screenshot for visual work and green gates, and never remove a worktree with unverified, uncommitted or unmerged work ([05-infrastructure.md](05-infrastructure.md)).
