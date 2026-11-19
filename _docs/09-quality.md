# Quality

Gates by target, the guards that hold the rules, and the verification harnesses for JP the Cat.

## Gates

Root `AGENTS.md` (Gates) declares the gate for each target as a hard rule; this section owns what the gates cover.

- **Mac:** `swift test --parallel` from `mac/` is the whole automated suite; `.github/workflows/ci.yml` stays disabled on purpose.
- **Update feed:** `UpdateFeedTests` runs inside the mac suite.
  It holds `feed/public/stable/pricing-v1.json` byte-identical to the bundled pricing table, pins the frozen legacy `pricing.json` digest, keeps both cask copies identical with their URL template and Sparkle livecheck, keeps the README install path, and checks that `feed/vercel.json` serves `/stable/*` before its GitHub redirect and keeps the 410 support endpoint.
- **Release:** `/jp` adds the pre-release model-price check (`mac/scripts/audit_model_coverage.py`); see `.claude/commands/jp.md`.

## Guards

A rule in `AGENTS.md` stays terse and names its guard; the guard is a test that fails when the rule is broken, and the incident that produced it is in [00-foundation.md](00-foundation.md).
A guard needs a floor proving its scan was non-empty, enumerates recursively, and is mutation-tested on first write by breaking what it protects.
A test that asserts on a provider's quota must inject that provider's capture path, such as `GrokProvider(root:rateLimitStoreURL:)` or `ClaudeRateLimitStore.load(url:)`.
A temp root alone still reads the fixed Application Support capture, so the developer's live reading leaks into fixtures and the suite fails only on a machine with real usage.

## Release verification

Root `AGENTS.md` (Git, Release & Worktree Workflow) carries the review-before-cleanup rule; the post-release proofs are in [05-infrastructure.md](05-infrastructure.md#release-pipeline).
