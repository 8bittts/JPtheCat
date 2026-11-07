#!/usr/bin/env bash
#
# verify-dmg-layout.sh - verify the JPtheCat drag-to-Applications DMG layout.
#
# Usage:
#   ./scripts/verify-dmg-layout.sh
#   ./scripts/verify-dmg-layout.sh --dmg build/JPtheCat-0.001.dmg
#   ./scripts/verify-dmg-layout.sh --skip-finder-check

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="JPtheCat"
BUILD_DIR="build"
DMG_RESOURCE_DIR="scripts/dmg-resources"
EXPECTED_BG_1X="720x450"
EXPECTED_BG_2X="1440x900"
EXPECTED_WINDOW_SIZE="735x510"
EXPECTED_ICON_SIZE="112"
EXPECTED_TEXT_SIZE="14"
EXPECTED_ARRANGEMENT="not arranged"
EXPECTED_APP_POS="250,205"
EXPECTED_APPLICATIONS_POS="470,205"
EXPECTED_APPLICATIONS_TARGET="/Applications"

DMG_PATH=""
SKIP_FINDER_CHECK=false
FAILURES=0
MOUNT_DIR=""

usage() {
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

pass() { printf "  OK: %s\n" "$1"; }
fail_check() { printf "  X: %s\n" "$1"; FAILURES=$((FAILURES + 1)); }
warn() { printf "  !: %s\n" "$1"; }

cleanup() {
	if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
		hdiutil detach -quiet "$MOUNT_DIR" >/dev/null 2>&1 \
			|| hdiutil detach -force -quiet "$MOUNT_DIR" >/dev/null 2>&1 \
			|| true
	fi
}
trap cleanup EXIT INT TERM

get_png_dimensions() {
	local file_path="$1"
	sips -g pixelWidth -g pixelHeight "$file_path" 2>/dev/null | awk '
		/pixelWidth:/ { w=$2 }
		/pixelHeight:/ { h=$2 }
		END {
			if (w == "" || h == "") exit 1
			print w "x" h
		}
	'
}

check_png_dimensions() {
	local file_path="$1" expected="$2" label="$3" actual=""
	if [ ! -f "$file_path" ]; then
		fail_check "$label missing: $file_path"
		return
	fi
	if ! actual="$(get_png_dimensions "$file_path")"; then
		fail_check "$label has unreadable dimensions: $file_path"
		return
	fi
	if [ "$actual" = "$expected" ]; then
		pass "$label dimensions match ($actual)"
	else
		fail_check "$label dimensions mismatch (expected $expected, got $actual)"
	fi
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--dmg)
			shift
			[ -n "${1:-}" ] || { printf "ERROR: --dmg requires a path\n" >&2; exit 1; }
			DMG_PATH="$1"
			;;
		--skip-finder-check)
			SKIP_FINDER_CHECK=true
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			printf "ERROR: Unknown argument: %s\n" "$1" >&2
			usage
			exit 1
			;;
	esac
	shift
done

if [ -z "$DMG_PATH" ]; then
	DMG_PATH="$(ls "${BUILD_DIR}/${APP_NAME}"-*.dmg 2>/dev/null | head -1 || true)"
fi

printf "\nDMG Layout Verification\n"
printf "DMG: %s\n\n" "${DMG_PATH:-<none>}"

[ -n "$DMG_PATH" ] && [ -f "$DMG_PATH" ] || { printf "ERROR: DMG not found\n" >&2; exit 1; }

printf "[1/5] Checking local DMG resources...\n"
check_png_dimensions "${DMG_RESOURCE_DIR}/background.png" "$EXPECTED_BG_1X" "background.png"
check_png_dimensions "${DMG_RESOURCE_DIR}/background@2x.png" "$EXPECTED_BG_2X" "background@2x.png"

printf "\n[2/5] Verifying DMG integrity...\n"
if hdiutil verify "$DMG_PATH" >/dev/null 2>&1; then
	pass "hdiutil verify passed"
else
	fail_check "hdiutil verify failed"
fi

printf "\n[3/5] Mounting DMG and checking installer structure...\n"
MOUNT_OUTPUT=""
MOUNT_ARGS=(-readonly -noautoopen)
if [ "$SKIP_FINDER_CHECK" = true ]; then
	MOUNT_ARGS+=(-nobrowse)
fi
if ! MOUNT_OUTPUT="$(hdiutil attach "${MOUNT_ARGS[@]}" "$DMG_PATH" 2>&1)"; then
	fail_check "failed to mount DMG: $MOUNT_OUTPUT"
else
	MOUNT_DIR="$(printf "%s\n" "$MOUNT_OUTPUT" | sed -nE 's#.*(/Volumes/.*)$#\1#p' | tail -1)"
	if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
		pass "mounted at $MOUNT_DIR"
	else
		fail_check "failed to resolve mounted volume path"
	fi
fi

if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
	[ -d "${MOUNT_DIR}/${APP_NAME}.app" ] && pass "${APP_NAME}.app present" || fail_check "${APP_NAME}.app missing"

	if [ -L "${MOUNT_DIR}/Applications" ]; then
		APP_LINK_TARGET="$(readlink "${MOUNT_DIR}/Applications" 2>/dev/null || true)"
		[ "$APP_LINK_TARGET" = "$EXPECTED_APPLICATIONS_TARGET" ] \
			&& pass "Applications symlink points to ${EXPECTED_APPLICATIONS_TARGET}" \
			|| fail_check "Applications symlink target mismatch (got ${APP_LINK_TARGET:-<empty>})"
	else
		fail_check "Applications symlink missing"
	fi

	if [ -d "${MOUNT_DIR}/.background" ]; then
		pass ".background directory present"
		if ls -ldO "${MOUNT_DIR}/.background" 2>/dev/null | grep -q "hidden"; then
			pass ".background hidden flag present"
		else
			fail_check ".background hidden flag missing"
		fi
	else
		fail_check ".background directory missing"
	fi

	check_png_dimensions "${MOUNT_DIR}/.background/background.png" "$EXPECTED_BG_1X" "mounted background.png"
	check_png_dimensions "${MOUNT_DIR}/.background/background@2x.png" "$EXPECTED_BG_2X" "mounted background@2x.png"

	[ ! -e "${MOUNT_DIR}/.fseventsd" ] && pass ".fseventsd absent" || fail_check ".fseventsd should not be present"
	[ ! -e "${MOUNT_DIR}/.metadata_never_index" ] && pass ".metadata_never_index absent" || fail_check ".metadata_never_index should not be present"
fi

printf "\n[4/5] Checking Finder metadata...\n"
if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
	if [ -f "${MOUNT_DIR}/.DS_Store" ]; then
		pass ".DS_Store present"
		DS_STRINGS="$(strings "${MOUNT_DIR}/.DS_Store" 2>/dev/null || true)"
		printf "%s\n" "$DS_STRINGS" | grep -q ".background" \
			&& pass ".DS_Store references .background" \
			|| fail_check ".DS_Store missing .background reference"
		printf "%s\n" "$DS_STRINGS" | grep -q "background.png" \
			&& pass ".DS_Store references background.png" \
			|| fail_check ".DS_Store missing background.png reference"
	else
		fail_check ".DS_Store missing"
	fi
fi

printf "\n[5/5] Checking Finder geometry...\n"
if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
	if [ "$SKIP_FINDER_CHECK" = true ]; then
		warn "Finder geometry check skipped"
	else
		DISK_NAME="$(basename "$MOUNT_DIR")"
		FINDER_OUTPUT=""
		FINDER_STATUS=0
		FINDER_OUTPUT="$(osascript <<EOF 2>&1
set mountPath to "$MOUNT_DIR"
set diskName to "$DISK_NAME"
set mountedFolder to POSIX file mountPath as alias
tell application "Finder"
	activate
	open mountedFolder
	delay 0.5
	set w to window diskName
	set vo to icon view options of w
	set b to bounds of w
	set p1 to position of item "$APP_NAME.app" of w
	set p2 to position of item "Applications" of w
	set resultText to "bounds=" & (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text) & linefeed & "icon_size=" & (icon size of vo) & linefeed & "text_size=" & (text size of vo) & linefeed & "arrangement=" & (arrangement of vo as text) & linefeed & "app_pos=" & (item 1 of p1 as text) & "," & (item 2 of p1 as text) & linefeed & "applications_pos=" & (item 1 of p2 as text) & "," & (item 2 of p2 as text)
	close w
	return resultText
end tell
EOF
		)" || FINDER_STATUS=$?

		if [ "$FINDER_STATUS" -ne 0 ]; then
			fail_check "Finder geometry read failed: $FINDER_OUTPUT"
		else
			BOUNDS="$(printf "%s\n" "$FINDER_OUTPUT" | awk -F= '/^bounds=/{print $2}')"
			ICON_SIZE="$(printf "%s\n" "$FINDER_OUTPUT" | awk -F= '/^icon_size=/{print $2}')"
			TEXT_SIZE="$(printf "%s\n" "$FINDER_OUTPUT" | awk -F= '/^text_size=/{print $2}')"
			ARRANGEMENT="$(printf "%s\n" "$FINDER_OUTPUT" | awk -F= '/^arrangement=/{print $2}')"
			APP_POS="$(printf "%s\n" "$FINDER_OUTPUT" | awk -F= '/^app_pos=/{print $2}')"
			APPLICATIONS_POS="$(printf "%s\n" "$FINDER_OUTPUT" | awk -F= '/^applications_pos=/{print $2}')"
			BOUNDS_SIZE="$(printf "%s\n" "$BOUNDS" | awk -F, 'NF==4 { print ($3 - $1) "x" ($4 - $2) }')"

			[ "$BOUNDS_SIZE" = "$EXPECTED_WINDOW_SIZE" ] && pass "window size matches ($BOUNDS_SIZE)" || fail_check "window size mismatch (expected $EXPECTED_WINDOW_SIZE, got ${BOUNDS_SIZE:-<empty>})"
			[ "$ICON_SIZE" = "$EXPECTED_ICON_SIZE" ] && pass "icon size matches ($ICON_SIZE)" || fail_check "icon size mismatch (expected $EXPECTED_ICON_SIZE, got ${ICON_SIZE:-<empty>})"
			[ "$TEXT_SIZE" = "$EXPECTED_TEXT_SIZE" ] && pass "text size matches ($TEXT_SIZE)" || fail_check "text size mismatch (expected $EXPECTED_TEXT_SIZE, got ${TEXT_SIZE:-<empty>})"
			[ "$ARRANGEMENT" = "$EXPECTED_ARRANGEMENT" ] && pass "arrangement matches ($ARRANGEMENT)" || fail_check "arrangement mismatch (expected $EXPECTED_ARRANGEMENT, got ${ARRANGEMENT:-<empty>})"
			[ "$APP_POS" = "$EXPECTED_APP_POS" ] && pass "${APP_NAME}.app position matches ($APP_POS)" || fail_check "${APP_NAME}.app position mismatch (expected $EXPECTED_APP_POS, got ${APP_POS:-<empty>})"
			[ "$APPLICATIONS_POS" = "$EXPECTED_APPLICATIONS_POS" ] && pass "Applications position matches ($APPLICATIONS_POS)" || fail_check "Applications position mismatch (expected $EXPECTED_APPLICATIONS_POS, got ${APPLICATIONS_POS:-<empty>})"
		fi
	fi
fi

if [ "$FAILURES" -gt 0 ]; then
	printf "DMG layout verification failed (%s issue(s)).\n" "$FAILURES" >&2
	exit 1
fi

printf "\n"
printf "DMG layout verification passed.\n"
