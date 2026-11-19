---
description: Build, verify, sign, notarize, and publish the JPtheCat macOS app, after checking every locally emitted model has a verified price.
---

# /jp — JPtheCat build & release

> This file is the one copy of the `/jp` workflow.
> The global Codex command and the Codex `jp` skill are short pointers to it, so a change lands here only.

JP the Cat is free (no license, trial, or purchase flow); customer-facing Sparkle notes never resurrect paid-era copy.
The marketing website is retired: `jpthecat.com` redirects to the GitHub repository, except `jpthecat.com/stable/*`, which `feed/` serves as the update channel every installed copy reads (Sparkle appcast, remote pricing, Homebrew livecheck).
`/jp` owns the whole release: model-price check → mac gates → notarized DMG → signed appcast → GitHub Release → `feed/public/stable/*` + `Casks/jpthecat.rb` → `release: … [deploy]` commit + tag → push → feed promotion check.

Bare `/jp` always does a full release.
It commits every current working-tree change first (one non-`[deploy]` WIP commit), then runs the phases below.
This is outward-facing and hard to undo; that is the intended behavior of a bare `/jp`.
Use `/jp check` when you want the gates without shipping.

Run everything from the repo root (`git rev-parse --show-toplevel`).

## Modes

| Invocation | Behavior |
|---|---|
| `/jp` | Full release (default): Phases 1 to 5. |
| `/jp release` | Alias for bare `/jp`. |
| `/jp check` | Phases 1 to 3 only. No commit, no shipping. |
| `/jp models` | Phase 2 only: the model-price check and any pricing fix, landed as a normal commit. |
| `/jp local` | Build and launch the local Dock-visible `.app` (`mac/scripts/build_and_run.sh --verify`). |
| `/jp cli` | Build and run `jpthecat-cli --json` (today/7d cost readout). |

Dry run any time without publishing: `bash mac/scripts/release-jpthecat.sh --dry-run` (builds, notarizes, smokes and signs the appcast, then reverts; no tag, release, push, or deploy).

## Phase 1 — Preflight

```bash
cd "$(git rev-parse --show-toplevel)"/mac && swift build
```

If the build fails, stop; every later phase fails at the same step, slower.

## Phase 2 — Model-price check (blocking)

Every release confirms that each model the user's agents emit today has a verified list price, so a release never ships knowing a model renders as unpriced.

1. Run the inventory and keep its JSON as evidence:
   ```bash
   python3 -I mac/scripts/audit_model_coverage.py --repo . > "$TMPDIR/jp-model-audit.json"; echo "exit=$?"
   ```
   Exit 0 means every emitted id resolves to a price row, 1 means at least one `missing_prices` entry, and 2 means the scan read nothing, which is a failure, never a pass.
   The script reads only model-identifying JSON fields from the Claude, Codex, Grok, Cursor and OpenCode roots; never print prompts, messages, code, tokens, auth data, or raw log contents.
   Its `undecorated`/`normalized`/`is_free_tier`/`fast_mode_id` mirror `ModelIdentity` exactly; change both sides together.
   OpenCode turns live in the legacy `message` table and the session-v2 `session_message` table; `scan_evidence.opencode_message_tables_read` must name every table the store has.
2. Check for new models the local tools can emit that no log shows yet: read each live provider's first-party model and pricing pages (below) and compare against `pricing-default.json`.
   A model newly offered in Claude Code, Codex, Grok Build, Cursor, or OpenCode gets a row before the release, not after a user reports it.
3. Classify every gap before editing:
   - A non-empty emitted id absent from the table is a pricing candidate.
   - An empty Codex id means attribution was absent at that event; backfill only from the same rollout's later model declaration, else leave it unpriced ("unknown Codex model").
   - Provider-prefixed, dated, selector-suffixed (`[1m]`), or alias ids usually need an `aliases` entry or `ModelIdentity` normalization, not a duplicate row.
   - Synthetic or test ids are not coverage gaps; free-tier ids stay deliberately unpriced.
4. Verify each candidate against first-party docs only:
   - Claude: `platform.claude.com/docs` model and pricing pages.
   - OpenAI/Codex: the OpenAI developer-docs MCP, else `developers.openai.com` / `platform.openai.com`.
   - Others: the vendor's own model and pricing pages. Summarizing fetch tools truncate long tables (OpenCode Zen and Go list 90+ rows), so download the raw page and parse every row.
   - Check gateway-specific rates, time-of-day rates, cache writes, and each context threshold; a matching name alone does not establish a rate.
   - `missing_prices: []` proves only that every id resolves to some row. When a vendor changed prices since the last release, diff each affected row's input, output, cached, cache-write, and tier values too.
5. Fix at the root, then mirror:
   - Add or adjust rows in `mac/Sources/JPtheCatCore/Resources/pricing-default.json` with documented rates only, and copy it byte-for-byte to `feed/public/stable/pricing-v1.json` (`UpdateFeedTests`).
   - Never touch the frozen legacy `feed/public/stable/pricing.json`; an incompatible schema change needs a new versioned URL.
   - Update `ModelName.swift`/`ModelEffort.swift` and `mac/Tests/JPtheCatCoreTests/Fixtures/model-identity-cases.json` when the model appears in those surfaces; bump a provider's `parserRevision` when indexed rows need re-reading.
   - A new price tier must be proven on the grouped SQL scan too (`MultiWindowSummariesParityTests`).
   - Add regression tests for the exact emitted ids and an official-rate spot check; record the source research in `_docs/03-data.md`.
6. Re-run the inventory until every remaining `missing_prices` id is a deliberate, documented gap: listed under "Pricing re-checks" in `_docs/todos.md` with the reason no first-party rate exists (for example `cursor-grok-4.6-high-fast`).
   An undocumented missing id blocks the release.
   Commit the pricing change on its own before the release commit, and name every deliberately unpriced id in the release report.
   Never guess a price, equate subscription usage with API spend, or turn an unknown model into `$0.00`.

Adding or promoting a whole provider is not a release step; follow [`_docs/11-adding-a-provider.md`](../../_docs/11-adding-a-provider.md).

## Phase 3 — Mac gates

```bash
cd "$(git rev-parse --show-toplevel)"/mac
swift test --parallel                          # GATE: 0 failures
swift build -c release
bash scripts/build_and_run.sh --verify         # GATE: staged .app is Dock-visible, links AppKit
swift run -c release jpthecat-cli --json | head -30   # smoke: prints today/7d cost
```

- Tests must report 0 failures; redirect the full output to a file rather than piping it through `tail`.
- The staged app must print `LSUIElement = false ✓` and `links AppKit ✓`.
- The CLI must emit valid JSON with a non-negative `today.cost_usd`.

## Phase 4 — Commit all working-tree changes (bare `/jp`)

The release script refuses to build when `mac/Sources`, `mac/Package.swift`, the entitlements or Info plists, the app icon, or `mac/tools` hold uncommitted changes, so the notarized app always matches `HEAD`.
Stage the exact modified and untracked paths that `git status --porcelain` lists (never `git add .` or `-A`; a parallel agent may hold unrelated WIP) into one non-`[deploy]` commit:

```bash
git add <every path from git status --porcelain>
git commit -m "<summary of WIP>"      # no [deploy]; the release commit carries it
```

## Phase 5 — Release and publish

```bash
cd "$(git rev-parse --show-toplevel)"/mac && ./scripts/release-jpthecat.sh [version]
```

`release-jpthecat.sh` builds the signed, notarized, stapled DMG, smokes it, signs the appcast, uploads DMG + sha256 + deltas to a draft GitHub Release, writes `feed/public/stable/{version.json,appcast.xml,JPtheCat-<ver>.dmg.sha256,jpthecat.rb}`, updates the README markers and `Casks/jpthecat.rb`, syncs the public Homebrew tap, then commits `release: JPtheCat vX [deploy]`, tags, pushes, and publishes the release.
The push to `main`: on Claude Code pass `dangerouslyDisableSandbox: true` on that Bash call; Codex under `--yolo` needs nothing.

The sub-scripts can run on their own:

```bash
./scripts/build-dmg.sh            # signed + notarized + stapled DMG (Developer ID + JPtheCat-Notarization profile)
./scripts/build-dmg.sh --local    # signed, skip notarization (fast)
./scripts/build-dmg.sh --unsigned # ad-hoc (no Developer ID; bootstrapping)
./scripts/smoke-test.sh --production   # Gatekeeper + deep codesign + checksum
./scripts/generate-appcast.sh     # signed appcast.xml (headless EdDSA, GitHub Release enclosure URLs)
```

Then verify the feed went live; a release is not shipped until this passes:

1. The Vercel project `jpthecat` (root directory `feed/`) promoted a production deployment for the pushed release SHA, in READY state, not CANCELED.
2. `curl -sS https://jpthecat.com/stable/version.json` shows the new version, and `curl -sS https://jpthecat.com/stable/appcast.xml` lists it.
3. `curl -sSI https://jpthecat.com/` answers 308 to `https://github.com/8bittts/JPtheCat`.

Signing rules: sign inner to outer, never `--deep` (Sparkle XPC/Updater → framework → app last); notarize the DMG through the `JPtheCat-Notarization` keychain profile; `spctl` must report `source=Notarized Developer ID`; the appcast enclosure is EdDSA-signed with `length=` matching the DMG bytes and points at `https://github.com/8bittts/JPtheCat/releases/download/v<version>/` (`mac/scripts/release-github.sh` owns the repository and URL shape).
Resource bundles go to `Contents/Resources` only; a copy in the `.app` root breaks codesign sealing.

## Artifacts

- `mac/build/local-run/JPtheCat.app` (local) and `mac/build/JPtheCat-<ver>.dmg` + `.sha256` (release).
- `feed/public/stable/JPtheCat-<ver>.dmg.sha256`, `version.json`, `appcast.xml`, `jpthecat.rb`: the published manifest of what shipped.
- `Casks/jpthecat.rb`: the Homebrew cask pinned to the same version and SHA-256.
- Notarization: `*.notary-submission.json` and "Notarization ticket stapled" in the output.

## One-time setup (done on this machine)

```bash
# Notary profile in the keychain (name overridable via JPTHECAT_NOTARY_PROFILE)
xcrun notarytool store-credentials JPtheCat-Notarization \
  --apple-id YOUR_APPLE_ID --team-id GRNGR33Z8A --password APP_SPECIFIC_PASSWORD

# Dedicated Sparkle EdDSA key (keychain account `jpthecat`; public key already in Info.plist)
./mac/tools/sparkle/bin/generate_keys --account jpthecat

# Export that key for headless appcast signing
mkdir -p ~/.config/jpthecat
./mac/tools/sparkle/bin/generate_keys -x ~/.config/jpthecat/sparkle_ed25519_priv.key --account jpthecat
chmod 600 ~/.config/jpthecat/sparkle_ed25519_priv.key   # outside the repo; never commit
```

`gh` must be signed in with push access to the public `8bittts/JPtheCat` repository; the release preflight fails closed otherwise.

Do not create `mac/CHANGELOG.md`; git history is the changelog.
The release flow generates the Sparkle notes from commit history in JP's voice: cute, concise, opinionated about real changes, and never empty or generic (root `AGENTS.md` owns the notes contract).

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `swift build` fails immediately | Compile error; fix before any release step. |
| Model audit exits 1 | A locally emitted model has no price row; price it or document it as a deliberate gap (Phase 2). |
| Model audit exits 2 | No log root was read; check the roots before trusting any result. |
| Menu bar shows `$0.00` | `Bundle.module` (pricing) did not resolve in the staged app; confirm `JPtheCat_JPtheCatCore.bundle` sits next to the binary in `Contents/MacOS/`. |
| `No Developer ID found` | No Developer ID cert in the login keychain; add one or use `--unsigned`. |
| Signing retry loops or `stapler` fails | Apple timestamp or notary propagation is slow; the scripts retry (5× sign, 10× staple). |
| `Notary submission unknown: unknown` with an empty `*.notary-submission.json` | `build-dmg.sh` must recover the submission through `notarytool history/info`, then staple and validate the DMG before publishing. |
| Sparkle offers no update after a release | `CFBundleVersion` did not rise above the published `<sparkle:version>`; the release script floors the next build at published build + 1. |
| Live `version.json` still shows the old version | The feed deploy was canceled or never built; check that the release commit subject carries `[deploy]` and is the tip commit. |

## Safety

- Release publishes the download, never the local app: it must not install to `/Applications` or relaunch the installed copy; existing installs update through Sparkle.
- The release commit lands from an isolated worktree at the current local `HEAD` after proving `HEAD` contains `origin/main`, with fetch, rebase and retry on push; an EXIT trap reverts the shared-checkout `Info.plist` stamp, and a final-state gate fails on leftover `Info.plist`, cask, or `feed/public/stable/*` changes (`ReleaseNotesWorkflowTests.testReleaseIsolatesCommitInAWorktreeWithRebaseRetry`).
  A `preserve … Info.plist version bump` stash is stale; drop it.
- Three copies by design: `/Applications/JPtheCat.app` (installed, only Sparkle updates it), `mac/build/JPtheCat.app` (fresh local build), and `feed/public/stable/*` + `Casks/jpthecat.rb` (published manifest).
- Never commit `mac/build/` or `.build/`; release artifacts go to GitHub Releases.
- Never hand-edit the signed appcast; fix `mac/scripts/generate-appcast.sh` when the notes contract changes.
- Stage explicit files only, never `git add .` or `-A`.
- The repository is public (MIT): never force-add `_docs/legacy-backup/`, `brand/generated/`, or `brand/reference/`, and never push the deleted pre-open-source history from an old clone (the `pre-push` hook rejects it).
- Feed deploys are `[deploy]`-gated: only a tip commit whose subject contains `[deploy]` builds; the Phase 4 WIP commit omits it, and `/jp check` never deploys.
- Commit style: concise, with no AI attribution.
