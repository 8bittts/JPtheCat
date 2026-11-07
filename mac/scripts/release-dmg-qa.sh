#!/usr/bin/env bash
#
# release-dmg-qa.sh - live DMG release QA for JPtheCat.
#
# Usage:
#   ./scripts/release-dmg-qa.sh
#   ./scripts/release-dmg-qa.sh --dmg /path/to/JPtheCat-0.084.dmg --expected-sha <sha256>
#   ./scripts/release-dmg-qa.sh --keep-artifacts

set -euo pipefail

MAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$MAC_ROOT"

APP_NAME="JPtheCat"
MANIFEST_URL="https://jpthecat.com/stable/version.json"
DMG_PATH=""
EXPECTED_SHA=""
EXPECTED_VERSION=""
DOWNLOAD_URL=""
KEEP_ARTIFACTS=false
TMPDIR=""
MOUNT_DIR=""
FINDER_WINDOW_NAME=""

pass() { printf "\033[1;32m  ✓\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m  ✗ %s\033[0m\n" "$1" >&2; exit 1; }
info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }

usage() {
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

cleanup() {
	if [ -n "$FINDER_WINDOW_NAME" ]; then
		osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
	tell process "Finder"
		repeat with w in windows
			if (name of w as text) is "$FINDER_WINDOW_NAME" then perform action "AXClose" of w
		end repeat
	end tell
end tell
EOF
	fi
	if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
		hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 \
			|| hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1 \
			|| true
	fi
	if [ "$KEEP_ARTIFACTS" != true ] && [ -n "$TMPDIR" ]; then
		rm -rf "$TMPDIR"
	elif [ "$KEEP_ARTIFACTS" = true ] && [ -n "$TMPDIR" ]; then
		printf "Artifacts kept at %s\n" "$TMPDIR"
	fi
}
trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
	case "$1" in
		--dmg)
			shift
			[ -n "${1:-}" ] || fail "--dmg requires a path"
			DMG_PATH="$1"
			;;
		--expected-sha)
			shift
			[ -n "${1:-}" ] || fail "--expected-sha requires a sha256 value"
			EXPECTED_SHA="$1"
			;;
		--keep-artifacts)
			KEEP_ARTIFACTS=true
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			fail "unknown argument: $1"
			;;
	esac
	shift
done

TMPDIR="$(mktemp -d /tmp/jpthecat-release-dmg-qa.XXXXXX)"

fetch_url() {
	local url="$1" output="$2"
	curl -fsSL \
		--retry 3 \
		--retry-all-errors \
		--connect-timeout 15 \
		--max-time 180 \
		-o "$output" \
		"$url"
}

png_dimensions() {
	local image="$1"
	sips -g pixelWidth -g pixelHeight "$image" 2>/dev/null | awk '
		/pixelWidth:/ { w=$2 }
		/pixelHeight:/ { h=$2 }
		END {
			if (w == "" || h == "") exit 1
			print w "x" h
		}
	'
}

if [ -z "$DMG_PATH" ]; then
	info "Resolve live stable DMG"
	manifest="$TMPDIR/version.json"
	fetch_url "$MANIFEST_URL" "$manifest"
	IFS=$'\t' read -r EXPECTED_VERSION DOWNLOAD_URL EXPECTED_SHA < <(
		python3 - "$manifest" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

print(data["version"], data["url"], data["sha256"], sep="\t")
PY
	)
	DMG_PATH="$TMPDIR/${APP_NAME}-${EXPECTED_VERSION}.dmg"
	fetch_url "$DOWNLOAD_URL" "$DMG_PATH"
	pass "downloaded ${APP_NAME}-${EXPECTED_VERSION}.dmg from live manifest"
fi

[ -f "$DMG_PATH" ] || fail "DMG not found: $DMG_PATH"

info "Verify DMG checksum"
ACTUAL_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [ -n "$EXPECTED_SHA" ]; then
	[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || fail "DMG sha mismatch (${ACTUAL_SHA} != ${EXPECTED_SHA})"
	pass "DMG sha256 matches ${ACTUAL_SHA}"
else
	pass "DMG sha256 ${ACTUAL_SHA}"
fi

info "Run full DMG layout verifier"
bash scripts/verify-dmg-layout.sh --dmg "$DMG_PATH"
pass "DMG structure and Finder geometry verified"

info "Verify Retina Finder presentation"
system_profiler SPDisplaysDataType | grep -q "Retina" \
	|| fail "no Retina display detected for release visual QA"
pass "Retina display detected"

MOUNT_OUTPUT="$(hdiutil attach -readonly -noautoopen "$DMG_PATH" 2>&1)" \
	|| fail "failed to mount DMG: $MOUNT_OUTPUT"
MOUNT_DIR="$(printf "%s\n" "$MOUNT_OUTPUT" | sed -nE 's#.*(/Volumes/.*)$#\1#p' | tail -1)"
[ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ] || fail "failed to resolve mounted volume path"
FINDER_WINDOW_NAME="$(basename "$MOUNT_DIR")"

FINDER_OUTPUT="$(osascript <<EOF 2>&1
set mountPath to "$MOUNT_DIR"
set diskName to "$FINDER_WINDOW_NAME"
set mountedFolder to POSIX file mountPath as alias
tell application "Finder"
	activate
	open mountedFolder
	delay 1
	set w to window diskName
	set bounds of w to {120, 120, 855, 630}
	set current view of w to icon view
	set vo to icon view options of w
	set b to bounds of w
	set p1 to position of item "$APP_NAME.app" of w
	set p2 to position of item "Applications" of w
	return "bounds=" & (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text) & linefeed & "icon_size=" & (icon size of vo) & linefeed & "text_size=" & (text size of vo) & linefeed & "app_pos=" & (item 1 of p1 as text) & "," & (item 2 of p1 as text) & linefeed & "applications_pos=" & (item 1 of p2 as text) & "," & (item 2 of p2 as text)
end tell
EOF
)" || fail "Finder visual window read failed: $FINDER_OUTPUT"

printf "%s\n" "$FINDER_OUTPUT" | grep -q "^icon_size=112$" || fail "Finder icon size is not 112"
printf "%s\n" "$FINDER_OUTPUT" | grep -q "^text_size=14$" || fail "Finder label text size is not 14"
printf "%s\n" "$FINDER_OUTPUT" | grep -q "^app_pos=250,205$" || fail "${APP_NAME}.app label/icon position drifted"
printf "%s\n" "$FINDER_OUTPUT" | grep -q "^applications_pos=470,205$" || fail "Applications label/icon position drifted"
pass "${APP_NAME}.app and Applications labels are positioned over the quiet background area"

AX_OUTPUT="$(osascript <<EOF 2>&1
set diskName to "$FINDER_WINDOW_NAME"
tell application "System Events"
	tell process "Finder"
		set w to window diskName
		set p to position of w
		set s to size of w
		return (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
	end tell
end tell
EOF
)" || fail "Finder AX window read failed: $AX_OUTPUT"
IFS=, read -r WINDOW_X WINDOW_Y WINDOW_WIDTH WINDOW_HEIGHT <<<"$AX_OUTPUT"

SCREENSHOT="$TMPDIR/${APP_NAME}-dmg-retina.png"
screencapture -x -R"${WINDOW_X},${WINDOW_Y},${WINDOW_WIDTH},${WINDOW_HEIGHT}" "$SCREENSHOT"
SCREENSHOT_DIMENSIONS="$(png_dimensions "$SCREENSHOT")"
EXPECTED_SCREENSHOT_DIMENSIONS="$((WINDOW_WIDTH * 2))x$((WINDOW_HEIGHT * 2))"
[ "$SCREENSHOT_DIMENSIONS" = "$EXPECTED_SCREENSHOT_DIMENSIONS" ] \
	|| fail "Finder screenshot is not 2x Retina (expected ${EXPECTED_SCREENSHOT_DIMENSIONS}, got ${SCREENSHOT_DIMENSIONS})"
pass "Retina Finder capture is ${SCREENSHOT_DIMENSIONS} for ${WINDOW_WIDTH}x${WINDOW_HEIGHT} window"

info "Verify safe drag-to-Applications copy"
QA_APPLICATIONS="$TMPDIR/Applications"
mkdir -p "$QA_APPLICATIONS"
ditto "${MOUNT_DIR}/${APP_NAME}.app" "${QA_APPLICATIONS}/${APP_NAME}.app"
PLIST="${QA_APPLICATIONS}/${APP_NAME}.app/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [ -n "$EXPECTED_VERSION" ]; then
	[ "$SHORT_VERSION" = "$EXPECTED_VERSION" ] \
		|| fail "copied app version mismatch (${SHORT_VERSION} != ${EXPECTED_VERSION})"
fi
codesign --verify --deep --strict "${QA_APPLICATIONS}/${APP_NAME}.app" \
	|| fail "copied app failed deep codesign verification"
spctl -a -t exec -vv "${QA_APPLICATIONS}/${APP_NAME}.app" 2>&1 \
	| grep -q "source=Notarized Developer ID" \
	|| fail "copied app is not accepted as Notarized Developer ID"
pass "copied app ${SHORT_VERSION} build ${BUILD_VERSION} is codesigned and Gatekeeper-accepted"

info "RELEASE DMG QA PASSED"
