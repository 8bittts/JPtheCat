#!/usr/bin/env bash
# Sweep stray JPtheCat.app registrations out of the LaunchServices database.
#
# WHY: every dev/smoke build stages a launchable bundle (build_and_run.sh → build/local-run,
# build-dmg.sh → dmg-staging/dmg-mount, the sparkle/staged smokes → /private/tmp) and macOS registers
# each with LaunchServices on first `open`. Removing a worktree deletes the files but NOT the record,
# so duplicate registrations of the shipping bundle id (com.8bittts.jpthecat) pile up. Too many is the
# documented root cause of the login-item `.notFound` bug (SMAppService can't resolve the canonical
# app), so only /Applications/JPtheCat.app should stay registered.
#
# IMPORTANT — order matters: `lsregister -u <path>` only works while the bundle still EXISTS on disk,
# and Apple removed the bulk `-kill` rebuild. So run this BEFORE `git worktree remove`, while the
# stray copies are still on disk. Records already dangling (files gone) can't be unregistered by -u —
# they clear on their own via LaunchServices GC, or a logout/login / reboot revalidates the database.
#
# Usage:  bash mac/scripts/ls-sweep.sh          # unregister every stray, keep /Applications
#         bash mac/scripts/ls-sweep.sh --dry-run # list what would be unregistered
set -euo pipefail

KEEP="/Applications/JPtheCat.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

[ -x "$LSREGISTER" ] || { echo "lsregister not found at $LSREGISTER" >&2; exit 1; }

info() { printf "\033[36m•\033[0m %s\n" "$*"; }

# Registered JPtheCat.app bundle paths (strip the trailing " (0x…)" id and de-dup). Uses a
# while-read loop, not `mapfile` — macOS ships bash 3.2, which has no `mapfile`.
paths=()
while IFS= read -r line; do
	[ -n "$line" ] && paths+=("$line")
done < <(
	"$LSREGISTER" -dump 2>/dev/null \
		| grep -iE "^[[:space:]]*path:.*JPtheCat\.app( |$)" \
		| sed -E 's/^[[:space:]]*path:[[:space:]]*//; s/ \(0x[0-9a-f]+\)$//' \
		| grep -v "^${KEEP}\$" \
		| sort -u
)

if [ "${#paths[@]}" -eq 0 ]; then
	info "No stray JPtheCat.app registrations — only ${KEEP} remains."
	exit 0
fi

info "Found ${#paths[@]} stray JPtheCat.app registration(s) (keeping ${KEEP}):"
swept=0
for p in "${paths[@]}"; do
	[ -n "$p" ] || continue
	if $DRY_RUN; then
		printf "  would unregister: %s%s\n" "$p" "$([ -d "$p" ] || printf '   [dangling — needs reboot/GC]')"
		continue
	fi
	if [ -d "$p" ]; then
		"$LSREGISTER" -u "$p" 2>/dev/null && swept=$((swept + 1)) && printf "  unregistered: %s\n" "$p"
	else
		printf "  dangling (files gone; clears on GC / reboot): %s\n" "$p"
	fi
done

$DRY_RUN && exit 0
info "Unregistered ${swept} live copy/copies. Any remaining dangling records clear via LaunchServices GC or a logout/login."
