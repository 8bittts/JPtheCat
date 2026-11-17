#!/usr/bin/env bash
#
# release-github.sh — GitHub Releases hosting for JP the Cat, sourced by the release scripts.
#
# Every release is a GitHub Release on the public repository, tagged v<version>. The DMG, its
# .sha256 and the Sparkle deltas are assets of that release, so one per-tag prefix serves all of
# them. The website (/download, version.json, the signed appcast) points at these asset URLs.

JPTC_RELEASE_REPO="${JPTHECAT_RELEASE_REPO:-8bittts/JPtheCat}"
JPTC_RELEASE_DOWNLOAD_BASE="https://github.com/${JPTC_RELEASE_REPO}/releases/download"

# Prefix for every asset of one release, with a trailing slash (generate_appcast's
# --download-url-prefix).
jptc_release_download_prefix() {
	local version="${1:?version required}"
	printf '%s/v%s/\n' "$JPTC_RELEASE_DOWNLOAD_BASE" "$version"
}

jptc_release_asset_url() {
	local version="${1:?version required}"
	local name="${2:?asset name required}"
	printf '%s%s\n' "$(jptc_release_download_prefix "$version")" "$name"
}

# Fails unless the release repository is public (a private repository's assets need a login, so
# every download and Sparkle update would fail) and the gh session can push (creating a release
# needs push).
jptc_verify_release_repo() {
	command -v gh >/dev/null 2>&1 || {
		printf 'ERROR: gh CLI not found — required for release uploads\n' >&2
		return 1
	}
	local state visibility can_push
	state="$(gh api "repos/${JPTC_RELEASE_REPO}" --jq '[.visibility, .permissions.push] | @tsv' 2>/dev/null)" || {
		printf 'ERROR: release repository %s is not reachable with the current gh session\n' "$JPTC_RELEASE_REPO" >&2
		return 1
	}
	visibility="$(printf '%s\n' "$state" | cut -f1)"
	can_push="$(printf '%s\n' "$state" | cut -f2)"
	[ "$visibility" = "public" ] || {
		printf 'ERROR: release repository %s is %s, not public\n' "$JPTC_RELEASE_REPO" "${visibility:-unknown}" >&2
		return 1
	}
	[ "$can_push" = "true" ] || {
		printf 'ERROR: the gh session cannot push to %s\n' "$JPTC_RELEASE_REPO" >&2
		return 1
	}
}

# Prints "published", "draft" or "absent" for a tag's release; fails on any other gh error.
jptc_release_state() {
	local tag="${1:?tag required}"
	local output
	if output="$(gh release view "$tag" --repo "$JPTC_RELEASE_REPO" --json isDraft --jq '.isDraft' 2>&1)"; then
		[ "$output" = "true" ] && echo draft || echo published
		return 0
	fi
	if printf '%s\n' "$output" | grep -qi 'release not found'; then
		echo absent
		return 0
	fi
	printf 'ERROR: could not read release %s: %s\n' "$tag" "$output" >&2
	return 1
}

# Creates a fresh draft release for a tag. A published release is never overwritten (bump the
# version instead); a leftover draft from a failed run is not public, so it is replaced.
jptc_prepare_draft_release() {
	local tag="${1:?tag required}"
	local title="${2:?title required}"
	local state
	state="$(jptc_release_state "$tag")" || return 1
	case "$state" in
		published)
			printf 'ERROR: release %s is already published; bump the version instead of overwriting published bytes\n' "$tag" >&2
			return 1
			;;
		draft)
			gh release delete "$tag" --repo "$JPTC_RELEASE_REPO" --yes >/dev/null 2>&1 || {
				printf 'ERROR: could not remove the leftover draft release %s\n' "$tag" >&2
				return 1
			}
			;;
	esac
	gh release create "$tag" --repo "$JPTC_RELEASE_REPO" --draft --title "$title" \
		--notes "Release notes: https://jpthecat.com" >/dev/null || {
		printf 'ERROR: could not create the draft release %s\n' "$tag" >&2
		return 1
	}
}

jptc_upload_release_asset() {
	local tag="${1:?tag required}"
	local file="${2:?file required}"
	[ -f "$file" ] || {
		printf 'ERROR: release asset not found: %s\n' "$file" >&2
		return 1
	}
	local attempt
	for attempt in 1 2 3; do
		gh release upload "$tag" "$file" --repo "$JPTC_RELEASE_REPO" --clobber >/dev/null 2>&1 && return 0
		[ "$attempt" -lt 3 ] && sleep $((attempt * 2))
	done
	printf 'ERROR: upload failed after 3 attempts: %s\n' "$file" >&2
	return 1
}
