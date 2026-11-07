#!/usr/bin/env bash

jptc_update_readme_release_markers() {
	local readme_path="${1:?README path required}"
	local version="${2:?version required}"
	local download_url="${3:?download URL required}"
	local version_start="<!-- version-badge -->"
	local version_end="<!-- /version-badge -->"
	local download_start="<!-- download-link -->"
	local download_end="<!-- /download-link -->"
	local marker

	[ -f "$readme_path" ] || {
		printf 'ERROR: README not found: %s\n' "$readme_path" >&2
		return 1
	}

	for marker in "$version_start" "$version_end" "$download_start" "$download_end"; do
		command grep -Fq -- "$marker" "$readme_path" || {
			printf 'ERROR: README release marker missing: %s\n' "$marker" >&2
			return 1
		}
	done

	local tmp
	tmp="$(mktemp "${TMPDIR:-/tmp}/jpthecat-readme.XXXXXX")" || return 1

	awk \
		-v version_line="**Stable release:** \`v${version}\`" \
		-v download_line="**Download:** [JP the Cat v${version} DMG](${download_url})" \
		-v version_start="$version_start" \
		-v version_end="$version_end" \
		-v download_start="$download_start" \
		-v download_end="$download_end" '
		$0 == version_start {
			print
			print version_line
			in_version = 1
			next
		}
		$0 == version_end {
			in_version = 0
			print
			next
		}
		$0 == download_start {
			print
			print download_line
			in_download = 1
			next
		}
		$0 == download_end {
			in_download = 0
			print
			next
		}
		in_version || in_download {
			next
		}
		{
			print
		}
	' "$readme_path" > "$tmp" || {
		rm -f "$tmp"
		return 1
	}

	mv "$tmp" "$readme_path"
}
