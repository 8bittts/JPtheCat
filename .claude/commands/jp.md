---
description: Build, verify, sign, notarize, and publish the JPtheCat macOS app — the /zip-style release workflow for this repo.
---

# /jp — JPtheCat build & release

> **⚠ SYNC — mirrored command.** This file is mirrored 1:1 between **Claude**
> (`.claude/commands/jp.md`, in-repo) and **Codex** (`~/.codex/commands/jp.md`, global). If you
> change ANYTHING here — modes, gates, scripts, paths, versions, safety — update **both** files in
> the same change so they never drift.

The release workflow for JPtheCat, modeled on `/yen-zip` (YEN) and `build-dockishOS`. JP the Cat is
**free** (no license, trial, or purchase flow) — customer-facing Sparkle notes and the public site
never resurrect paid-era copy. JPtheCat has two shippable surfaces: the **macOS app** (`mac/`,
SwiftPM) and the **marketing site** (`web/`, Next.js on Vercel). `/jp` owns the **macOS**
build→verify→sign→notarize→DMG→appcast→release pipeline.

**Bare `/jp` ALWAYS does a full release — every single time.** It commits ALL current working-tree
changes first (one non-`[deploy]` WIP commit), then runs `release-jpthecat.sh`: web quality gate →
notarized DMG → production smoke gate → signed appcast → Supabase upload (DMG+sha256) →
`web/public/stable/*` + `Casks/jpthecat.rb` → `release: … [deploy]` commit + tag → push → Vercel
promotion check. It ships and deploys the website too, every time. This is outward-facing and hard
to undo — that is the intended behavior of a bare
`/jp` invoke. Use `/jp check` (below) when you only want gates without shipping.

Run everything from the repo root (`git rev-parse --show-toplevel`).

---

## Modes

| Invocation | Behavior | Status |
|---|---|---|
| `/jp` | **Full release (default).** Commit ALL working-tree changes → `release-jpthecat.sh`: web quality gate → notarized DMG → smoke → appcast → Supabase upload → `web/public/stable/*` + `Casks/jpthecat.rb` → `release: … [deploy]` commit + tag → push → verify. Ships mac + web. | ✅ **works now** |
| `/jp release` | Explicit alias for the bare-`/jp` full release above. | ✅ **works now** |
| `/jp check` | **Full green check** (old default): mac (build + test + staged-app verify + CLI smoke) **and** web (`bun run check:full`). No shipping. | ✅ works now |
| `/jp local` | Build + launch the local Dock-visible `.app` and confirm the bundle shape (`mac/scripts/build_and_run.sh --verify`). | ✅ works now |
| `/jp cli` | Build + run `jpthecat-cli --json` (today/7d cost readout). | ✅ works now |

`/jp` / `/jp release` = commit-all-WIP then `mac/scripts/release-jpthecat.sh` (all four scripts exist and are verified). It ships
BOTH surfaces atomically: the mac DMG goes to the public Supabase `releases` bucket (served over the branded CNAME `api.jpthecat.com`), `Casks/jpthecat.rb` is pinned to the same version + SHA-256, and the `[deploy]` release commit
promotes the site (the `/download` route + Sparkle feed both read `web/public/stable/`). It is
outward-facing and hard to undo (a published tag/release + a live deploy) — run it deliberately.

**Dry run** any time without publishing: `bash mac/scripts/release-jpthecat.sh --dry-run` (runs the
web quality gate, then builds + notarizes + smokes + signs the appcast, then reverts — no
tag/release/push/deploy).

---

## Process

### Phase 1 — Preflight (fail fast)

```bash
cd "$(git rev-parse --show-toplevel)"/mac && swift build 2>&1 | tail -10
```

If the build fails, stop — every downstream phase fails at the same step, slower.

### Phase 2 — Mac gates

```bash
cd "$(git rev-parse --show-toplevel)"/mac
swift test                                    # GATE: all JPtheCatCore tests green
bash scripts/build_and_run.sh --verify        # GATE: staged .app is Dock-visible, links AppKit
swift run -c release jpthecat-cli --json | head -30   # smoke: prints today/7d cost
```

Gates:
- **Tests** must be 0 failures.
- **Staged app** must print `LSUIElement = false ✓` and `links AppKit ✓`.
- The **CLI** must emit valid JSON with a non-negative `today.cost_usd`.

### Phase 3 — Web gate (only when the commit touches `web/`)

```bash
cd "$(git rev-parse --show-toplevel)"/web && bun run check:full
```

`check:full` = biome → type-check → `bun test` → knip → **react-doctor (must be 100/100)** → build.
**Production gate:** never deploy the web app without react-doctor at 100/100 (see `AGENTS.md`).

### Phase 4-pre — Commit ALL working-tree changes (bare `/jp` / `/jp release`)

A bare `/jp` release **commits everything in the working tree first**, so no WIP is left behind and
the built DMG matches HEAD. **The release script now enforces this for the DMG build inputs** — its
preconditions fail fast if `mac/Sources`, `mac/Package.swift`, the entitlements/Info plists, the app
icon, or `mac/tools` have uncommitted changes, so the notarized app can never silently diverge from
HEAD; unrelated `web/`/`docs` WIP from a parallel agent does not block the release. Stage the exact
modified + untracked files (list them from
`git status --porcelain` — do NOT `git add .`/`-A`, a parallel agent may hold unrelated WIP; here
"all changes" means every path git already shows as dirty/untracked) into one **non-`[deploy]`** WIP
commit, then run the release. The release script adds its own `release: … [deploy]` commit on top and
pushes both:

```bash
cd "$(git rev-parse --show-toplevel)"
git add <every path from git status --porcelain>
git commit -m "<summary of WIP>"                            # NO [deploy] — release commit carries that
```

### Phase 4a — Ship & deploy web (MANDATORY, every release)

The release script runs this **every single time**, before the mac steps:

```bash
cd "$(git rev-parse --show-toplevel)"/web && bun run check:full   # GATE: 100/100 doctor + green build
# release-jpthecat.sh then makes the release commit + push:
#   git commit -m "release: JPtheCat vX [deploy]"           # [deploy] is REQUIRED — it triggers Vercel
#   git push origin main                                    # pass dangerouslyDisableSandbox:true on this call
```

Then **verify promotion** (poll the Vercel API until production == the pushed short-SHA in READY
state, as in `/ship` step 9). A release is not "shipped" until production shows the new commit.

### Phase 4b — Mac DMG release (WORKS NOW)

`release-jpthecat.sh` orchestrates the whole thing; the sub-scripts can also be run individually:

```bash
cd "$(git rev-parse --show-toplevel)"/mac
./scripts/build-dmg.sh            # signed + notarized + stapled DMG (Developer ID + JPtheCat-Notarization profile)
./scripts/build-dmg.sh --local    # signed, skip notarization (fast)
./scripts/build-dmg.sh --unsigned # ad-hoc (no Developer ID; bootstrapping)
./scripts/smoke-test.sh --production   # verify the notarized DMG (Gatekeeper + deep codesign + checksum)
./scripts/generate-appcast.sh     # signed appcast.xml (headless EdDSA, api.jpthecat.com enclosure URLs)
./scripts/release-jpthecat.sh [ver] [--dry-run]   # full: web quality → DMG → smoke → appcast → Supabase upload → stable files + cask → web [deploy]
```

Verified gates (all green on a real run): sign **inner→outer, never `--deep`** (Sparkle XPC/Updater →
framework → app last); notarize the **DMG** via the `JPtheCat-Notarization` keychain profile;
`stapler staple` + `spctl -a -t open` + `spctl -a -t exec` → `source=Notarized Developer ID`; appcast
enclosure EdDSA-signed with `length=` matching the DMG bytes and the URL pointing at `api.jpthecat.com` (the release scripts default to `CANONICAL_RELEASES_BASE`; the raw project host stays as a `/download` rollback fallback).
Resource bundles go to `Contents/Resources` ONLY (a copy in the `.app` root breaks codesign sealing).

---

## Artifacts (release mode)

- `mac/build/local-run/JPtheCat.app` (local) · `mac/build/JPtheCat-<ver>.dmg` + `.sha256` (release)
  · `web/public/stable/JPtheCat-<ver>.dmg.sha256` (public checksum linked from the site)
  · `Casks/jpthecat.rb` (Homebrew cask pinned to the same public DMG version + SHA-256)
- Notarized: `*.notary-submission.json`, "Notarization ticket stapled" in the output
- The release script prints the Supabase download URL

---

## One-time setup (for `/jp release`) — DONE on this machine

Both are already configured here (team `GRNGR33Z8A`); listed for reference / a fresh machine:

```bash
# 1. Notary profile in the keychain (name overridable via JPTHECAT_NOTARY_PROFILE) — DONE
xcrun notarytool store-credentials JPtheCat-Notarization \
  --apple-id YOUR_APPLE_ID --team-id GRNGR33Z8A --password APP_SPECIFIC_PASSWORD

# 2. Dedicated Sparkle EdDSA key (keychain account `jpthecat`; public key already in Info.plist) — DONE
./mac/tools/sparkle/bin/generate_keys --account jpthecat

# 3. Export that key for HEADLESS appcast signing (no keychain GUI prompt during release) — DONE
mkdir -p ~/.config/jpthecat
./mac/tools/sparkle/bin/generate_keys -x ~/.config/jpthecat/sparkle_ed25519_priv.key --account jpthecat
chmod 600 ~/.config/jpthecat/sparkle_ed25519_priv.key   # OUTSIDE the repo; never commit
```

The Supabase CLI must be linked to the JPtheCat project in `mac/` (`supabase link --project-ref duqpnrpzadrxqdbspjft`) for the upload step.

Do not create or update `mac/CHANGELOG.md`. Git commit history is the changelog; the release flow
generates comprehensive Sparkle update notes from meaningful commit history. The notes should sound
like JP: cute, concise, and seriously opinionated about real changes. Empty or generic notes are a
release failure.

---

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `swift build` fails immediately | Compile error — fix before any release step. |
| menubar shows `$0.00` | `Bundle.module` (pricing) didn't resolve in the staged app — confirm `JPtheCat_JPtheCatCore.bundle` sits next to the binary in `Contents/MacOS/`. |
| react-doctor < 100 | Web prod gate — fix or add a justified `web/doctor.config.json` exception before any deploy. |
| `No Developer ID found` | No Developer ID cert in the login keychain — add one or use `--unsigned`. |
| Signing retry loops / `stapler` fails | Apple timestamp/notary propagation is slow — the scripts auto-retry (5× sign, 10× staple). |
| `Notary submission unknown: unknown` with an empty `*.notary-submission.json` | `notarytool submit --wait --output-format json` returned success without a local JSON body. `build-dmg.sh` must recover the matching submission through `notarytool history/info`, then staple/validate the actual DMG before publishing. |
| Sparkle says no update after a release | `CFBundleVersion` did not increase above the latest published appcast `<sparkle:version>` — `release-jpthecat.sh` must floor the next build at published build + 1, not just local Info.plist + 1. |
| `App can't be opened` on a clean machine | Sparkle `Updater.app` symlink dropped, or `CFBundleVersion` not a monotonic integer. |

---

## Safety

- **Release publishes the download — never the local app.** `/jp release` builds into `mac/build/`,
  uploads the DMG to Supabase, and deploys the web manifest; it MUST NOT install to `/Applications`
  or otherwise touch the user's installed copy. Existing installs upgrade themselves through Sparkle
  (users click "Check for Updates" or the scheduled check fires) — that is the whole point of the
  update feed. Do not add an install/relaunch step to the release path. (Verifying a build locally is
  a separate action: `build_and_run.sh` stages to `build/local-run/`, still not `/Applications`.)
- **No leftovers — the release commit lands in an ISOLATED worktree, never the shared checkout.**
  `release-jpthecat.sh` stamps `mac/Info.plist` (version/build) in the shared checkout only as scratch
  for the build, then makes the `release: … [deploy]` commit + tag + push from a **dedicated git
  worktree checked out at the current local `HEAD` after proving `HEAD` contains `origin/main`**
  (with a fetch+rebase+retry push) so a concurrent `git reset --hard origin/main` on the shared tree
  can't discard the in-flight release (it has before), while local pre-release commits are included.
  An EXIT trap **always tears down that worktree and reverts the shared-checkout stamp**, and the shared
  checkout is re-synced (ff to the pushed release), so a failed OR successful run never leaves a stray
  version bump behind. The pipeline ends with a **final-state gate** that asserts the working tree is
  clean of `Info.plist`/`Casks/jpthecat.rb`/`web/public/stable/*` changes and that no release-bump stash remains. If you
  ever see a `preserve … Info.plist version bump` stash, it's stale — drop it (`git stash drop`).
  Regression guard: `ReleaseNotesWorkflowTests.testReleaseIsolatesCommitInAWorktreeWithRebaseRetry`.
- **Three distinct copies, by design** (so you can test a build locally without disturbing the
  installed app): `/Applications/JPtheCat.app` = the *installed/user* version (only Sparkle updates
  it); `mac/build/JPtheCat.app` = the *freshly built* local version kept after a successful build for
  local testing; `web/public/stable/{version.json,appcast.xml,JPtheCat-<ver>.dmg.sha256}` plus
  `Casks/jpthecat.rb` = the *published manifest/install metadata* of the release (the "saved copy" of what shipped). A successful build/release writes the manifest to
  `public/stable` and keeps the local build in `mac/build/` — and **never touches `/Applications`.**
- **Never commit `mac/build/` or `.build/`** — gitignored; release artifacts go to Supabase Storage, not the tree.
- **Release notes are part of the release gate** — no vague "Improvements and fixes" fallback, no
  hand-maintained changelog, and no signed-appcast hand edits. Fix `mac/scripts/generate-appcast.sh`
  when the note contract needs to change.
- **Explicit file staging only** — never `git add .` / `git add -A` (a second agent may have unrelated WIP). Stage the exact files for the change.
- **The repository is public (MIT).** The release commit and tag push to `github.com/8bittts/JPtheCat`; never force-add the gitignored operator-local paths (`_docs/legacy-backup/`, `brand/generated/`, `brand/reference/`), and never push the private `JPtheCat-archive` history, which the checkout's `pre-push` hook rejects.
- **Default-branch push** — Claude Code: pass `dangerouslyDisableSandbox: true` on the `git push origin main` Bash call (the sandbox heuristic blocks it otherwise). Codex: runs under `--yolo`, so the push proceeds without a special flag.
- **Web deploys are `[deploy]`-gated** — only a commit message containing `[deploy]` triggers a Vercel build. **Bare `/jp` and `/jp release` always include `[deploy]` (in the release commit) so every release ships and deploys the site**; the WIP commit made in Phase 4-pre deliberately omits `[deploy]`, and `/jp check` never deploys.
- Commit style: concise, **no AI attribution** (no "Generated with…", no Co-Authored-By).
