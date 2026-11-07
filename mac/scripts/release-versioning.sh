#!/usr/bin/env bash

jptc_bump_patch_version() {
	awk -v v="$1" 'BEGIN{split(v,a,".");p=a[2]+1;maj=a[1];if(p>999){maj++;p=0};printf "%d.%03d\n",maj,p}'
}

jptc_latest_published_build_number() {
	local appcast="${1:?appcast path required}" value
	[ -f "$appcast" ] || { printf "0\n"; return 0; }
	value="$(awk -F'[<>]' '/<sparkle:version>/{print $3; exit}' "$appcast")"
	case "$value" in
		""|*[!0-9]*) printf "0\n" ;;
		*) printf "%s\n" "$value" ;;
	esac
}

jptc_release_build_number() {
	local cur_build="${1:?current build required}"
	local latest_published_build="${2:-0}"
	local skipped_tags="${3:-0}"
	local build_number min_build_number

	build_number=$((cur_build + 1))
	if [ "$skipped_tags" -gt 0 ]; then
		build_number=$((cur_build + skipped_tags))
	fi

	min_build_number=$((latest_published_build + 1))
	if [ "$build_number" -lt "$min_build_number" ]; then
		build_number="$min_build_number"
	fi

	printf "%s\n" "$build_number"
}
