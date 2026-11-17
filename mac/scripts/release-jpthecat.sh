#!/usr/bin/env bash
#
# release-jpthecat.sh — cut a full JPtheCat release: notarized DMG → GitHub Release → live web deploy.
#
#   ./scripts/release-jpthecat.sh            # release the current Info.plist version (first time) or bump patch
#   ./scripts/release-jpthecat.sh 0.002      # release an explicit version
#   ./scripts/release-jpthecat.sh --dry-run  # build+notarize+appcast+smoke, but DO NOT publish/tag/push/deploy
#
# Pipeline: preconditions → (bump) → build-dmg (notarized) → smoke-test --production →
# generate-appcast → upload DMG+sha256+deltas to a DRAFT GitHub Release → write web/public/stable/
# {version.json, appcast.xml, JPtheCat-X.dmg.sha256, jpthecat.rb} + README markers + Homebrew cask →
# commit "release: JPtheCat vX [deploy]" + tag → push HEAD+tag → publish the release → verify download.
# The draft is published seconds after the push; Vercel needs over a minute to build the release
# commit, so the assets are public before the site and the appcast point at them.
#
# [HARDENING] The metadata commit+tag+push is done from a DEDICATED git worktree checked out at
# the current local HEAD — never this shared checkout — because concurrent agents `git reset --hard
# origin/main` the shared tree and have discarded an in-flight release commit before it could be
# pushed. A preflight fetch verifies local HEAD contains origin/main, so unpushed WIP commits are
# included while stale checkouts fail closed. The push also fetch+rebase+retries so a parallel commit
# landing on origin/main doesn't abort the release.
#
# [INVARIANT] Publishes the DOWNLOAD only — it MUST NOT install to /Applications or relaunch the
# user's installed app. Existing installs upgrade themselves via Sparkle. Do not add an install step.
#
# This is OUTWARD-FACING and hard to undo (a published tag + a live deploy). Requires:
#   - Developer ID cert + notary profile JPtheCat-Notarization (build-dmg.sh handles verification)
#   - exported Sparkle key at ~/.config/jpthecat/sparkle_ed25519_priv.key (generate-appcast.sh)
#   - gh signed in with push access to the public 8bittts/JPtheCat repository

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # = mac/
RROOT="$(cd "$REPO_ROOT/.." && pwd)"                           # = repo root (defined early: the EXIT trap needs it)
WEB_STABLE="${RROOT}/web/public/stable"
CASK_FILE="${RROOT}/Casks/jpthecat.rb"
CASK_STABLE_FILE="${WEB_STABLE}/jpthecat.rb"
HOMEBREW_TAP_URL="${JPTHECAT_HOMEBREW_TAP_URL:-https://github.com/8bittts/homebrew-jpthecat.git}"
cd "$REPO_ROOT"

APP_NAME="JPtheCat"
PLIST="Info.plist"

DRY_RUN=false
EXPLICIT_VERSION=""
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=true ;;
		-h|--help) sed -n '2,20p' "$0" | command sed 's/^# \{0,1\}//'; exit 0 ;;
		*) EXPLICIT_VERSION="$arg" ;;
	esac
done

info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
step() { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }

. "${REPO_ROOT}/scripts/release-versioning.sh"
. "${REPO_ROOT}/scripts/release-readme.sh"
. "${REPO_ROOT}/scripts/release-github.sh"

[ -d "$WEB_STABLE" ] || fail "web stable dir not found at ${WEB_STABLE}"

# --- Precondition: release-metadata files must be clean (no half-edited version/manifest) ---
info "Preconditions"
DIRTY="$(git -C "$RROOT" status --porcelain -- \
	mac/Info.plist README.md Casks/jpthecat.rb web/public/stable 2>/dev/null || true)"
[ -z "$DIRTY" ] || fail "release-metadata files have uncommitted changes — commit/stash first:\n${DIRTY}"
# DMG build inputs must match HEAD. build-dmg.sh compiles the LIVE working tree, but the release
# commit stages only the metadata bump — so uncommitted mac/ source or config would ship inside the
# notarized app yet be ABSENT from the pushed commit (a shipped build silently diverging from HEAD,
# which no later gate flags). Enforce /jp Phase 4-pre here: commit mac changes first. Scoped to the
# compiled/bundled inputs, so unrelated web/ or _docs/ WIP from a parallel agent never blocks a release.
BUILD_DIRTY="$(git -C "$RROOT" status --porcelain -- \
	mac/Sources mac/Package.swift mac/Package.resolved \
	mac/JPtheCat.entitlements mac/JPtheCatWidgetExtension.entitlements \
	mac/JPtheCatWidgetExtension-Info.plist mac/AppIcon.icns mac/tools 2>/dev/null || true)"
[ -z "$BUILD_DIRTY" ] || fail "uncommitted DMG build inputs — the notarized app would not match HEAD; commit them first (/jp Phase 4-pre):\n${BUILD_DIRTY}"
jptc_verify_release_repo || fail "GitHub release repository is not ready (see the error above)"
git -C "$RROOT" fetch origin main -q
git -C "$RROOT" merge-base --is-ancestor origin/main HEAD \
	|| fail "local HEAD does not include origin/main — rebase or merge before releasing so the isolated worktree cannot ship stale code"
step "clean metadata + GitHub release repository public and pushable; local HEAD includes origin/main"

# --- Web production gate (react-doctor 100/100 + full quality chain), BEFORE the expensive mac
# steps. A bare release ALWAYS ships a "[deploy]" commit that promotes the site, and AGENTS.md's
# production gate forbids deploying the web app without a passing quality chain (doctor 100/100).
# Fail fast here so a web regression can never ride out on a notarized release. Runs for --dry-run
# too, so a dry run is a true release-readiness check. ---
info "Web production gate (bun run check:full)"
command -v bun >/dev/null 2>&1 || fail "bun CLI not found — required for the web quality gate"
if [ ! -d "${RROOT}/web/node_modules" ]; then
	step "restoring pinned web devDependencies (bun install)"
	( cd "${RROOT}/web" && bun install ) || fail "bun install failed in web/ — cannot run the web quality gate"
fi
( cd "${RROOT}/web" && bun run check:full ) \
	|| fail "web quality gate failed (type-check / biome / tests / knip / react-doctor / build) — fix before releasing"
step "web quality passed (react-doctor 100/100 + green build)"

# --- Version + build number ---
CUR_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
CUR_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

if [ -n "$EXPLICIT_VERSION" ]; then
	VERSION="$EXPLICIT_VERSION"
else
	VERSION="$CUR_VERSION"
fi

LATEST_PUBLISHED_BUILD="$(jptc_latest_published_build_number "${WEB_STABLE}/appcast.xml")"
SKIPPED_TAGS=0
if [ -z "$EXPLICIT_VERSION" ]; then
	# The source plist can lag behind the latest shipped manifest if a prior release was cut from
	# another checkout. Walk to the first unused patch tag and advance CFBundleVersion with it, so
	# Sparkle's build number stays strictly newer than the skipped release(s).
	while git -C "$REPO_ROOT/.." rev-parse "v${VERSION}" >/dev/null 2>&1; do
		VERSION="$(jptc_bump_patch_version "$VERSION")"
		SKIPPED_TAGS=$((SKIPPED_TAGS + 1))
	done
fi
# Sparkle compares this integer only. A repair release must outrank the signed appcast even when
# the source plist or skipped tag count would otherwise choose the same build.
BUILD_NUMBER="$(jptc_release_build_number "$CUR_BUILD" "$LATEST_PUBLISHED_BUILD" "$SKIPPED_TAGS")"
TAG="v${VERSION}"
git -C "$REPO_ROOT/.." rev-parse "$TAG" >/dev/null 2>&1 && fail "tag ${TAG} already exists"

info "Releasing ${APP_NAME} ${TAG} (build ${BUILD_NUMBER})"

# Stamp version/build into Info.plist so the DMG + appcast carry them.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PLIST"

# The release COMMIT lands via a dedicated git worktree (see "Commit + tag" below), NOT this shared
# checkout — so a concurrent `git reset --hard origin/main` here (parallel agents do this and it has
# discarded release commits before) cannot clobber it. This checkout is only scratch space for
# building/staging. On ANY exit, tear down the release worktree and revert the scratch stamp/manifest
# edits so we never leave a stray version bump behind (the leftover that used to get manually stashed).
REL_WORKTREE=""
cleanup_release() {
	[ -n "$REL_WORKTREE" ] && git -C "$RROOT" worktree remove --force "$REL_WORKTREE" 2>/dev/null || true
	git -C "$RROOT" checkout -- mac/Info.plist README.md Casks/jpthecat.rb web/public/stable/version.json web/public/stable/appcast.xml 2>/dev/null || true
	# Remove a freshly-written (still-untracked) per-version sha256; leave it if it's already tracked.
	if [ -n "${WEB_SHA_FILE:-}" ] && ! git -C "$RROOT" ls-files --error-unmatch "$WEB_SHA_FILE" >/dev/null 2>&1; then
		rm -f "$WEB_SHA_FILE"
	fi
}
trap cleanup_release EXIT

# --- Build (notarized) → smoke gate → signed appcast ---
info "Build + notarize"; bash scripts/build-dmg.sh
info "Smoke test (production)"; bash scripts/smoke-test.sh --production
info "Generate signed appcast"; bash scripts/generate-appcast.sh

DMG="build/${APP_NAME}-${VERSION}.dmg"
SHA_FILE="build/${APP_NAME}-${VERSION}.sha256"
CHECKSUM="$(awk '{print $1}' "$SHA_FILE")"
DOWNLOAD_URL="$(jptc_release_asset_url "$VERSION" "${APP_NAME}-${VERSION}.dmg")"
RELEASE_DATE="$(date -u +%Y-%m-%d)"

if [ "$DRY_RUN" = true ]; then
	info "DRY RUN — built + notarized + appcast + smoke OK. NOT publishing."
	echo "  DMG:      ${DMG}"
	echo "  Checksum: ${CHECKSUM}"
	echo "  Would tag/release: ${TAG} → ${DOWNLOAD_URL}"
	git -C "$RROOT" checkout -- mac/Info.plist   # revert version stamp on dry run
	exit 0
fi

# --- Upload DMG + checksum + deltas to a DRAFT GitHub Release ---
# A draft is not public, so nothing is downloadable until the release commit is pushed and the draft
# is published below. The bytes are proven identical through the authenticated draft download.
info "Uploading to a draft GitHub Release (${TAG})"
jptc_prepare_draft_release "$TAG" "JP the Cat ${VERSION}" || fail "could not prepare the draft release ${TAG}"
jptc_upload_release_asset "$TAG" "$DMG" || fail "DMG upload failed"
jptc_upload_release_asset "$TAG" "$SHA_FILE" || fail "checksum upload failed"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jpthecat-release-verify.XXXXXX")"
gh release download "$TAG" --repo "$JPTC_RELEASE_REPO" --pattern "${APP_NAME}-${VERSION}.dmg" --dir "$VERIFY_DIR" \
	|| fail "could not download the draft DMG back for verification"
REMOTE_SHA="$(shasum -a 256 "${VERIFY_DIR}/${APP_NAME}-${VERSION}.dmg" | awk '{print $1}')"
/bin/rm -rf "$VERIFY_DIR"
[ "$REMOTE_SHA" = "$CHECKSUM" ] || fail "uploaded DMG sha mismatch (${REMOTE_SHA} != ${CHECKSUM})"
step "uploaded + verified draft DMG (${CHECKSUM})"

# Deltas from past versions (build/archives/*.delta, referenced by the appcast's sparkle:deltaFrom
# entries). A delta upload failure is NOT fatal — Sparkle falls back to the full DMG for any client
# whose delta enclosure 404s, so the worst case is a slower update, never a broken one.
DELTA_FILES=(build/archives/*.delta)
if [ -e "${DELTA_FILES[0]:-}" ]; then
	for f in "${DELTA_FILES[@]}"; do
		if jptc_upload_release_asset "$TAG" "$f"; then
			step "uploaded delta: $(basename "$f")"
		else
			step "WARNING: delta upload failed (non-fatal, falls back to full DMG): $(basename "$f")"
		fi
	done
fi

# --- Publish web manifest (drives /download + the Sparkle feed) ---
info "Writing web manifest + appcast"
cat > "${WEB_STABLE}/version.json" <<JSON
{
  "version": "${VERSION}",
  "url": "${DOWNLOAD_URL}",
  "sha256": "${CHECKSUM}",
  "notes": "Sparkle release notes are generated from git history in JP's strict-but-cute voice.",
  "minOS": "14.0",
  "releaseDate": "${RELEASE_DATE}"
}
JSON
cp build/appcast.xml "${WEB_STABLE}/appcast.xml"
WEB_SHA_FILE="${WEB_STABLE}/${APP_NAME}-${VERSION}.dmg.sha256"
cp "$SHA_FILE" "$WEB_SHA_FILE"
jptc_update_readme_release_markers "$RROOT/README.md" "$VERSION" "$DOWNLOAD_URL"
perl -0pi -e "s/version \"[^\"]+\"/version \"${VERSION}\"/; s/sha256 \"[a-f0-9]{64}\"/sha256 \"${CHECKSUM}\"/" "$CASK_FILE"
cp "$CASK_FILE" "$CASK_STABLE_FILE"
step "web/public/stable/{version.json,appcast.xml,$(basename "$WEB_SHA_FILE"),jpthecat.rb} updated"
step "README release markers updated"
step "Homebrew cask updated"

# --- Commit + tag + push from an ISOLATED worktree (repo root: mac Info.plist + web manifest) ---
# The metadata commit is made in a dedicated worktree checked out at the current local HEAD, NOT this
# shared checkout, so a concurrent hard-reset here cannot discard it. The DMG/appcast are already
# built + uploaded — only the git side remains.
info "Commit + tag (isolated worktree)"
git -C "$RROOT" fetch origin main -q
REL_WORKTREE="${TMPDIR:-/tmp}/jpthecat-release-$$"
git -C "$RROOT" worktree add -q --detach "$REL_WORKTREE" HEAD \
	|| fail "could not create release worktree at ${REL_WORKTREE}"
cp "$PLIST" "$REL_WORKTREE/mac/Info.plist"
cp "$RROOT/README.md" "$REL_WORKTREE/README.md"
cp "$CASK_FILE" "$REL_WORKTREE/Casks/jpthecat.rb"
cp "${WEB_STABLE}/version.json" "$REL_WORKTREE/web/public/stable/version.json"
cp "${WEB_STABLE}/appcast.xml" "$REL_WORKTREE/web/public/stable/appcast.xml"
cp "$WEB_SHA_FILE" "$REL_WORKTREE/web/public/stable/$(basename "$WEB_SHA_FILE")"
cp "$CASK_STABLE_FILE" "$REL_WORKTREE/web/public/stable/jpthecat.rb"
git -C "$REL_WORKTREE" add README.md Casks/jpthecat.rb mac/Info.plist web/public/stable
git -C "$REL_WORKTREE" commit -q -m "release: ${APP_NAME} ${TAG} [deploy]"
step "release commit staged in isolated worktree"

# --- Push main with fetch+rebase+retry so a parallel commit on origin/main can't abort the release
# (Vercel builds on [deploy]). Tag only AFTER the commit lands, since a rebase changes its SHA. ---
info "Push"
pushed=false
for i in $(seq 1 5); do
	if git -C "$REL_WORKTREE" push origin HEAD:main 2>/dev/null; then pushed=true; break; fi
	step "main advanced — rebasing release onto origin/main (attempt ${i}/5)"
	git -C "$RROOT" fetch origin main -q
	git -C "$REL_WORKTREE" rebase origin/main \
		|| fail "release rebase conflict on Info.plist/web manifest — resolve manually in ${REL_WORKTREE}"
done
[ "$pushed" = true ] || fail "could not push release to main after 5 attempts"
git -C "$REL_WORKTREE" tag -a "$TAG" -m "${APP_NAME} ${VERSION}"
git -C "$REL_WORKTREE" push origin "$TAG"
step "pushed HEAD + ${TAG}"

# --- Publish the draft release on the pushed tag. Vercel is still building the release commit, so
# the assets go public before /download, version.json and the appcast point at them. ---
info "Publish GitHub Release ${TAG}"
gh release edit "$TAG" --repo "$JPTC_RELEASE_REPO" --draft=false --latest >/dev/null \
	|| fail "could not publish the draft release ${TAG}; publish it now: gh release edit ${TAG} --repo ${JPTC_RELEASE_REPO} --draft=false --latest"
step "published release ${TAG}"

# --- Sync the public Homebrew tap. The public install path is
# `brew tap 8bittts/jpthecat && brew trust 8bittts/jpthecat && brew install --cask jpthecat`; this
# keeps that tap pinned to the same notarized DMG + SHA as `/download` and Sparkle.
info "Sync Homebrew tap"
TAP_WORKTREE="${TMPDIR:-/tmp}/jpthecat-homebrew-tap-$$"
git clone -q "$HOMEBREW_TAP_URL" "$TAP_WORKTREE" \
	|| fail "could not clone Homebrew tap ${HOMEBREW_TAP_URL}"
mkdir -p "$TAP_WORKTREE/Casks"
cp "$CASK_FILE" "$TAP_WORKTREE/Casks/jpthecat.rb"
if ! git -C "$TAP_WORKTREE" diff --quiet -- Casks/jpthecat.rb; then
	git -C "$TAP_WORKTREE" add Casks/jpthecat.rb
	git -C "$TAP_WORKTREE" commit -q -m "Update JPtheCat ${TAG}"
	git -C "$TAP_WORKTREE" push origin HEAD:main
	step "Homebrew tap updated"
else
	step "Homebrew tap already current"
fi

# Re-sync this scratch checkout to the pushed release: discard the local stamped copies (now committed
# on origin) and fast-forward main to include the release, so the final-state gate sees a clean tree.
git -C "$RROOT" checkout -- mac/Info.plist README.md Casks/jpthecat.rb web/public/stable/version.json web/public/stable/appcast.xml web/public/stable/jpthecat.rb 2>/dev/null || true
rm -f "$WEB_SHA_FILE"
git -C "$RROOT" merge --ff-only origin/main -q 2>/dev/null || true

# --- Verify: download URL 200. The live appcast changes only when Vercel promotes the
# release commit, so it is proven after promotion by sparkle-upgrade-smoke.sh, not here. ---
info "Verify download URL"
ok=false
for i in $(seq 1 10); do
	code="$(curl -s -o /dev/null -w '%{http_code}' -L "$DOWNLOAD_URL?cb=$i")"
	[ "$code" = "200" ] && { ok=true; break; }
	step "download not ready (${code}) — retry ${i}/10"; sleep 3
done
[ "$ok" = true ] && step "download URL 200" || fail "download URL never returned 200"

# --- Final cleanliness gate: no leftovers. The release commit is the LAST write; the tree must be
# clean of release-metadata changes and there must be no stray release stash. ---
info "Final state check"
LEFTOVER="$(git -C "$RROOT" status --porcelain -- mac/Info.plist README.md Casks/jpthecat.rb web/public/stable)"
[ -z "$LEFTOVER" ] || fail "leftover uncommitted release files (should be committed):\n${LEFTOVER}"
git -C "$RROOT" stash list 2>/dev/null | grep -qi 'Info.plist version bump' \
	&& fail "a release version-bump stash is still present — inspect \`git stash list\` and drop it" || true
step "clean final state — release fully committed, no leftovers (Info.plist stamp is in the commit)"

# The freshly built local .app remains in mac/build/ for local testing (a DIFFERENT copy than
# whatever is installed in /Applications). The release never installs to /Applications.
[ -d build/${APP_NAME}.app ] && step "local test build kept at mac/build/${APP_NAME}.app (v${VERSION}); /Applications untouched"

echo ""
info "RELEASE COMPLETE: ${APP_NAME} ${TAG}"
echo "  Download: ${DOWNLOAD_URL}"
echo "  Checksum: ${CHECKSUM}"
echo "  Verify the Vercel production deploy promoted to the release commit (see /ship step 9)."
