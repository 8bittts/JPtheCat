#!/usr/bin/env bash
#
# build-dmg.sh — Build, sign, package, and notarize JPtheCat as a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh                  # Full release: signed + notarized DMG
#   ./scripts/build-dmg.sh --build-only     # Build .app only (no DMG)
#   ./scripts/build-dmg.sh --local          # Build + sign + DMG, skip notarization
#   ./scripts/build-dmg.sh --unsigned       # Ad-hoc sign only (no Developer ID)
#
# Environment variables (all optional):
#   JPTHECAT_CODESIGN_IDENTITY    Override signing identity
#   JPTHECAT_NOTARY_PROFILE       Keychain notarization profile (default: JPtheCat-Notarization)
#   JPTHECAT_VERSION              Override CFBundleShortVersionString
#   JPTHECAT_BUILD                Override CFBundleVersion (monotonic integer — Sparkle compares builds)
#   JPTHECAT_DMG_LAYOUT_MODE      full (default) or fast (skip Finder layout)
#
# One-time notary profile setup:
#   xcrun notarytool store-credentials JPtheCat-Notarization \
#     --apple-id you@example.com --team-id GRNGR33Z8A --password app-specific-pwd

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="JPtheCat"
BUNDLE_ID="com.8bittts.jpthecat"
WIDGET_NAME="JPtheCatWidgetExtension"
WIDGET_BUNDLE_ID="com.8bittts.jpthecat.widget"
GITHUB_REPO="8bittts/JPtheCat"
BUILD_DIR="build"
DMG_VOLUME_NAME="JP the Cat"
DMG_RESOURCE_DIR="scripts/dmg-resources"
DMG_BACKGROUND_1X="${DMG_RESOURCE_DIR}/background.png"
DMG_BACKGROUND_2X="${DMG_RESOURCE_DIR}/background@2x.png"
DMG_LAYOUT_MODE="${JPTHECAT_DMG_LAYOUT_MODE:-full}"
NOTARY_PROFILE="${JPTHECAT_NOTARY_PROFILE:-JPtheCat-Notarization}"
SOURCE_PLIST="Info.plist"
ENTITLEMENTS="JPtheCat.entitlements"
WIDGET_SOURCE_PLIST="JPtheCatWidgetExtension-Info.plist"
WIDGET_ENTITLEMENTS="JPtheCatWidgetExtension.entitlements"
ICNS_SOURCE="AppIcon.icns"
SPARKLE_SOURCE="tools/sparkle/Sparkle.framework"
SPARKLE_LICENSE_SOURCE="tools/sparkle/LICENSE"
DMG_DEVICE_NODE=""

BUILD_ONLY=false
LOCAL_MODE=false
UNSIGNED=false

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
	case "$arg" in
		-h|--help)    usage; exit 0 ;;
		--build-only) BUILD_ONLY=true ;;
		--local)      LOCAL_MODE=true ;;
		--unsigned)   UNSIGNED=true ;;
		*)            echo "Unknown flag: $arg" >&2; exit 1 ;;
	esac
done

info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }
step() { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }

cleanup_dmg_mount() {
	if [ -n "${DMG_DEVICE_NODE:-}" ]; then
		hdiutil detach -force "$DMG_DEVICE_NODE" >/dev/null 2>&1 || true
		DMG_DEVICE_NODE=""
	fi
}
trap cleanup_dmg_mount EXIT INT TERM

case "$DMG_LAYOUT_MODE" in
	auto) DMG_LAYOUT_MODE="full" ;;
	full|fast) ;;
	*) fail "JPTHECAT_DMG_LAYOUT_MODE must be full or fast (got ${DMG_LAYOUT_MODE})" ;;
esac

plist_set() {
	local plist="$1" key="$2" type="$3" value="$4"
	if /usr/libexec/PlistBuddy -c "Print :${key}" "$plist" >/dev/null 2>&1; then
		/usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$plist"
	else
		/usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "$plist"
	fi
}

resolve_signing_identity() {
	if [ "$UNSIGNED" = true ]; then
		CODESIGN_IDENTITY="-"; warn "Ad-hoc signing (--unsigned)"; return
	fi
	if [ -n "${JPTHECAT_CODESIGN_IDENTITY:-}" ]; then
		CODESIGN_IDENTITY="$JPTHECAT_CODESIGN_IDENTITY"; step "Using override identity: ${CODESIGN_IDENTITY}"; return
	fi
	local identity
	identity="$(security find-identity -v -p codesigning 2>/dev/null \
		| grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)"
	if [ -n "$identity" ]; then
		CODESIGN_IDENTITY="$identity"; step "Found identity: ${CODESIGN_IDENTITY}"
	else
		CODESIGN_IDENTITY="-"; warn "No Developer ID found — falling back to ad-hoc signing"
	fi
}

codesign_base_args() {
	CODESIGN_ARGS=(--force --sign "$CODESIGN_IDENTITY")
	if [ "$CODESIGN_IDENTITY" != "-" ]; then
		CODESIGN_ARGS+=(--options runtime --timestamp)
	fi
}

sign_target() {
	local target="$1" with_entitlements="${2:-false}"
	local args=("${CODESIGN_ARGS[@]}")
	if [ "$with_entitlements" = true ]; then
		# Fail closed: a missing entitlements file must abort, not silently sign away the App Group
		# (which would ship a widget that can't read the shared snapshot container).
		[ -f "$ENTITLEMENTS" ] || fail "App entitlements missing at ${ENTITLEMENTS}; refusing to sign without them"
		args+=(--entitlements "$ENTITLEMENTS")
	fi
	codesign "${args[@]}" "$target"
}

sign_widget_target() {
	local target="$1"
	[ -f "$WIDGET_ENTITLEMENTS" ] || fail "Widget entitlements missing at ${WIDGET_ENTITLEMENTS}; refusing to sign the widget without its App Group entitlement"
	local args=("${CODESIGN_ARGS[@]}" --entitlements "$WIDGET_ENTITLEMENTS")
	codesign "${args[@]}" "$target"
}

# Assert the App Group entitlement actually landed on a signed bundle. `codesign --verify` checks the
# signature but never the entitlement CONTENT, so a dropped group would otherwise pass every gate and
# only surface as an empty/preview widget on the user's Mac.
verify_app_group_entitlement() {
	local target="$1"
	if codesign -d --entitlements - --xml "$target" 2>/dev/null | grep -q "GRNGR33Z8A.com.8bittts.jpthecat"; then
		return 0
	fi
	fail "Signed ${target##*/} is missing App Group GRNGR33Z8A.com.8bittts.jpthecat"
}

# Run one signing command, retrying when Apple's timestamp server is slow. EVERY `--timestamp`
# signature goes through this: v1.124's first run aborted on a Sparkle helper ("A timestamp was
# expected but was not found") because only the final app signature retried.
sign_with_retry() {
	local attempt=0
	while [ $attempt -lt 5 ]; do
		if "$@" 2>&1; then return 0; fi
		attempt=$((attempt + 1)); step "Retry $attempt/5 (timestamp server may be slow)..."; sleep 2
	done
	fail "Signing failed after 5 attempts: $*"
}

verify_signature_summary() {
	local target="$1" log_file="${BUILD_DIR}/codesign-verify.log"
	codesign --verify --strict --verbose=2 "$target" > "$log_file" 2>&1
	head -3 "$log_file"
	rm -f "$log_file"
}

can_notarize() {
	[ "$BUILD_ONLY" = false ] && [ "$LOCAL_MODE" = false ] && [ "$UNSIGNED" = false ] \
		&& [ "$CODESIGN_IDENTITY" != "-" ]
}

require_notarization_access() {
	if can_notarize; then
		xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null \
			|| fail "Notarization unavailable; resolve the Apple error above before releasing"
		step "Notarization access verified"
	fi
}

json_value() { /usr/bin/plutil -extract "$1" raw -o - "$2" 2>/dev/null || true; }
print_notary_log() {
	[ -n "$1" ] || return 0
	warn "Fetching notarization log for $1"
	xcrun notarytool log "$1" --keychain-profile "$NOTARY_PROFILE" || true
}
latest_notary_id_for_archive() {
	local archive_name="$1" history_json="${BUILD_DIR}/${APP_NAME}-${VERSION}.notary-history.json"
	# Defensively ensure the output dir exists — a bare `> "$history_json"` redirect fails with
	# "No such file or directory" if BUILD_DIR is momentarily absent, which silently defeats the
	# empty-submit-JSON recovery and reports a healthy (Accepted) notarization as "unknown".
	mkdir -p "${BUILD_DIR}"
	xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json > "$history_json" \
		|| return 0
	local index=0 name id
	while name="$(/usr/bin/plutil -extract "history.${index}.name" raw -o - "$history_json" 2>/dev/null)"; do
		if [ "$name" = "$archive_name" ]; then
			id="$(/usr/bin/plutil -extract "history.${index}.id" raw -o - "$history_json" 2>/dev/null || true)"
			[ -n "$id" ] && printf "%s\n" "$id"
			return 0
		fi
		index=$((index + 1))
	done
}
write_notary_info_json() {
	local submission_id="$1" out_json="$2"
	[ -n "$submission_id" ] || return 1
	xcrun notarytool info "$submission_id" --keychain-profile "$NOTARY_PROFILE" \
		--output-format json > "$out_json"
}
recover_empty_notary_json() {
	local archive_name="$1" out_json="$2" submission_id
	submission_id="$(json_value id "$out_json")"
	if [ -z "$submission_id" ]; then
		submission_id="$(latest_notary_id_for_archive "$archive_name")"
		[ -n "$submission_id" ] || return 0
		warn "notarytool submit produced empty JSON; recovering status from history (${submission_id})"
	fi
	write_notary_info_json "$submission_id" "$out_json" || true
}
wait_for_notary_status() {
	local submission_id="$1" out_json="$2" status attempt=0
	while [ $attempt -lt 30 ]; do
		write_notary_info_json "$submission_id" "$out_json" || return 1
		status="$(json_value status "$out_json")"
		case "$status" in
			Accepted|Invalid|Rejected) return 0 ;;
		esac
		attempt=$((attempt + 1))
		step "Notary submission ${submission_id}: ${status:-unknown} — poll ${attempt}/30"
		sleep 10
	done
	return 0
}

# Guard the vendored Sparkle framework: assert every required helper is present and the main
# framework binary matches the recorded SHA-256 (dockishOS lost Updater.app once and shipped a
# broken updater — nothing checked).
verify_sparkle_vendor() {
	local version_file="tools/sparkle/VERSION"
	[ -d "$SPARKLE_SOURCE" ] || return 0
	[ -f "$version_file" ] || fail "Missing ${version_file}; cannot verify vendored Sparkle"
	# shellcheck disable=SC1090
	source "$version_file"
	local rel actual
	for rel in "${required_paths[@]}"; do
		[ -e "tools/sparkle/${rel}" ] || fail "Vendored Sparkle is missing ${rel} — re-vendor"
	done
	actual="$(shasum -a 256 "${SPARKLE_SOURCE}/Versions/B/Sparkle" | awk '{print $1}')"
	[ "$actual" = "$sparkle_binary_sha256" ] \
		|| fail "Vendored Sparkle SHA-256 ${actual} != pin ${sparkle_binary_sha256}; update tools/sparkle/VERSION if intentional"
	step "Verified vendored Sparkle ${sparkle_version} (SHA-256 matches pin)"
}

stage_dmg_background() {
	[ -f "$DMG_BACKGROUND_1X" ] || fail "Missing DMG background asset: ${DMG_BACKGROUND_1X}"
	[ -f "$DMG_BACKGROUND_2X" ] || fail "Missing DMG retina background asset: ${DMG_BACKGROUND_2X}"
	mkdir -p "${DMG_STAGING}/.background"
	cp "$DMG_BACKGROUND_1X" "${DMG_STAGING}/.background/background.png"
	cp "$DMG_BACKGROUND_2X" "${DMG_STAGING}/.background/background@2x.png"
	[ -f "$ICNS_SOURCE" ] && cp "$ICNS_SOURCE" "${DMG_STAGING}/.VolumeIcon.icns"
	touch "${DMG_STAGING}/.metadata_never_index"
}

ds_store_has_background_metadata() {
	local ds_store="$1" ds_store_strings=""
	[ -f "$ds_store" ] || return 1
	ds_store_strings="$(strings "$ds_store" 2>/dev/null || true)"
	printf "%s\n" "$ds_store_strings" | grep -q ".background" \
		&& printf "%s\n" "$ds_store_strings" | grep -q "background.png"
}

create_fast_dmg() {
	hdiutil create -srcfolder "$DMG_STAGING" \
		-volname "$DMG_VOLUME_NAME" -fs HFS+ -format UDZO -imagekey zlib-level=9 \
		-ov "$DMG_FINAL" -quiet
}

create_polished_dmg() {
	local dmg_rw="${BUILD_DIR}/${APP_NAME}-${VERSION}-rw.dmg"
	local mount_point="${BUILD_DIR}/dmg-mount"
	local staging_mb image_mb
	local layout_attempt=1 layout_max_attempts=5 layout_applied=false
	local osascript_status=0 osascript_output=""

	local window_left=120
	local window_top=120
	local window_right=855
	local window_bottom=630
	local window_right_jiggle=$((window_right - 10))
	local window_bottom_jiggle=$((window_bottom - 10))
	local icon_size=112
	local text_size=14
	local app_icon_x=250
	local app_icon_y=205
	local applications_icon_x=470
	local applications_icon_y=205
	local hidden_metadata_x=360
	local background_folder_y=610
	local fseventsd_folder_y=650
	local volume_icon_y=690

	stage_dmg_background

	/bin/rm -rf "$dmg_rw" "$mount_point"
	hdiutil create -volname "$DMG_VOLUME_NAME" -srcfolder "$DMG_STAGING" \
		-fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW \
		-ov "$dmg_rw" -quiet
	staging_mb="$(du -sm "$DMG_STAGING" | awk '{print $1}')"
	image_mb=$((staging_mb + 64))
	[ "$image_mb" -lt 128 ] && image_mb=128
	hdiutil resize -size "${image_mb}m" "$dmg_rw" >/dev/null

	mkdir -p "$mount_point"
	DMG_DEVICE_NODE="$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse \
		-mountpoint "$mount_point" "$dmg_rw" | awk '/Apple_HFS/ { print $1; exit }')"
	[ -n "$DMG_DEVICE_NODE" ] || fail "Could not mount read-write DMG"

	if [ -f "${mount_point}/.VolumeIcon.icns" ]; then
		command -v SetFile >/dev/null 2>&1 && SetFile -a C "$mount_point" 2>/dev/null || true
	fi

	rm -rf "${mount_point}/.fseventsd" 2>/dev/null || true
	rm -f "${mount_point}/.metadata_never_index" 2>/dev/null || true
	chflags hidden "${mount_point}/.background" 2>/dev/null || true
	command -v SetFile >/dev/null 2>&1 && SetFile -a V "${mount_point}/.background" 2>/dev/null || true

	while [ "$layout_attempt" -le "$layout_max_attempts" ]; do
		osascript_status=0
		osascript_output="$(osascript <<EOF 2>&1
set mountPath to "$mount_point"
set mountedFolder to POSIX file mountPath as alias
tell application "Finder"
	open mountedFolder
	delay 1
	set targetWindow to container window of mountedFolder
	tell targetWindow
		set current view to icon view
		set toolbar visible to false
		set statusbar visible to false
		set bounds to {$window_left, $window_top, $window_right, $window_bottom}
	end tell
	set theViewOptions to the icon view options of targetWindow
	set arrangement of theViewOptions to not arranged
	set icon size of theViewOptions to $icon_size
	set text size of theViewOptions to $text_size
	set background picture of theViewOptions to file "background.png" of folder ".background" of mountedFolder
	set position of item "$APP_NAME.app" of targetWindow to {$app_icon_x, $app_icon_y}
	set position of item "Applications" of targetWindow to {$applications_icon_x, $applications_icon_y}
	set position of item ".background" of targetWindow to {$hidden_metadata_x, $background_folder_y}
	try
		set position of item ".fseventsd" of targetWindow to {$hidden_metadata_x, $fseventsd_folder_y}
	end try
	try
		set position of item ".VolumeIcon.icns" of targetWindow to {$hidden_metadata_x, $volume_icon_y}
	end try
	try
		set selection to {}
	end try
	close targetWindow
	delay 1
	open mountedFolder
	set targetWindow to container window of mountedFolder
	tell targetWindow
		set statusbar visible to false
		set bounds to {$window_left, $window_top, $window_right_jiggle, $window_bottom_jiggle}
	end tell
	delay 1
	tell targetWindow
		set statusbar visible to false
		set bounds to {$window_left, $window_top, $window_right, $window_bottom}
	end tell
	delay 2
	close targetWindow
end tell
EOF
		)" || osascript_status=$?

		if [ "$osascript_status" -eq 0 ]; then
			sleep 1
			sync
			if ds_store_has_background_metadata "${mount_point}/.DS_Store"; then
				layout_applied=true
				break
			fi
			warn "DMG layout attempt ${layout_attempt}/${layout_max_attempts} did not persist background metadata"
		else
			warn "DMG layout attempt ${layout_attempt}/${layout_max_attempts} failed (exit ${osascript_status})"
			printf "%s\n" "$osascript_output" >&2
		fi

		if [ "$layout_attempt" -eq "$layout_max_attempts" ]; then
			break
		fi
		sleep 2
		layout_attempt=$((layout_attempt + 1))
	done

	[ "$layout_applied" = true ] || fail "DMG Finder layout did not persist background metadata in .DS_Store"
	step "Finder background metadata verified"

	rm -rf "${mount_point}/.fseventsd" 2>/dev/null || true
	sync
	hdiutil detach "$DMG_DEVICE_NODE" >/dev/null
	DMG_DEVICE_NODE=""

	hdiutil convert "$dmg_rw" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" -quiet
	/bin/rm -rf "$dmg_rw" "$mount_point"
}

[ -f "$SOURCE_PLIST" ] || fail "Info.plist not found at ${SOURCE_PLIST}"
[ -f "$WIDGET_SOURCE_PLIST" ] || fail "Widget Info.plist not found at ${WIDGET_SOURCE_PLIST}"
verify_sparkle_vendor

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SOURCE_PLIST")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SOURCE_PLIST")"
VERSION="${JPTHECAT_VERSION:-$CURRENT_VERSION}"
BUILD_NUMBER="${JPTHECAT_BUILD:-$CURRENT_BUILD}"

info "Packaging ${APP_NAME} v${VERSION} (build ${BUILD_NUMBER})"
resolve_signing_identity
codesign_base_args
require_notarization_access

info "Cleaning previous release artifacts"
/bin/rm -rf "${BUILD_DIR}/${APP_NAME}.app" "${BUILD_DIR}/${APP_NAME}"-*.dmg \
	"${BUILD_DIR}/${APP_NAME}"-*-rw.dmg "${BUILD_DIR}/dmg-staging" "${BUILD_DIR}/dmg-mount" \
	"${BUILD_DIR}/${APP_NAME}"-*.sha256 \
	"${BUILD_DIR}/${APP_NAME}"-*.notary-submission.json
mkdir -p "$BUILD_DIR"

info "Building release binary"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="${BIN_DIR}/${APP_NAME}"
[ -f "$BINARY_PATH" ] || fail "Binary not found at ${BINARY_PATH}"
step "App build complete"

info "Assembling ${APP_NAME}.app"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
FRAMEWORKS_DIR="${CONTENTS}/Frameworks"
PLUGINS_DIR="${CONTENTS}/PlugIns"
INFO_PLIST="${CONTENTS}/Info.plist"
WIDGET_APPEX="${PLUGINS_DIR}/${WIDGET_NAME}.appex"
WIDGET_CONTENTS="${WIDGET_APPEX}/Contents"
WIDGET_MACOS_DIR="${WIDGET_CONTENTS}/MacOS"
WIDGET_RESOURCES_DIR="${WIDGET_CONTENTS}/Resources"
WIDGET_INFO_PLIST="${WIDGET_CONTENTS}/Info.plist"

/bin/rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$WIDGET_MACOS_DIR" "$WIDGET_RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/${APP_NAME}"
step "Copied binary"

# SwiftPM resource bundles (JPtheCat_*.bundle: pricing-default.json + jp-menubar.png). For a real
# .app, resources belong under Contents/Resources — copy there ONLY. Production code must resolve
# them through JPResourceBundle/AppResources, not SwiftPM's generated Bundle.module accessor, because
# that accessor looks beside Bundle.main.bundleURL and will miss Contents/Resources in a packaged app.
# (Do NOT also copy to the .app root: loose files outside Contents/ make codesign fail with
# "unsealed contents present in the bundle root".)
# NEVER stage the *Tests.bundle.
# `nullglob` + the copied count are load-bearing: without them a no-match glob leaves the literal
# `*.bundle`, the `-d` test fails, and the loop exits 0 — shipping a signed app whose pricing and
# marks cannot resolve, under a green "Copied SwiftPM resource bundles" step.
shopt -s nullglob
copied_bundles=0
for bundle in "$BIN_DIR"/*.bundle; do
	case "$bundle" in *Tests.bundle) continue ;; esac
	case "$(basename "$bundle")" in "JPtheCat_${WIDGET_NAME}.bundle") continue ;; esac
	[ -d "$bundle" ] || continue
	cp -R "$bundle" "$RESOURCES_DIR/"
	copied_bundles=$((copied_bundles + 1))
done
shopt -u nullglob
[ "$copied_bundles" -gt 0 ] || fail "No SwiftPM resource bundles found in $BIN_DIR"
step "Copied $copied_bundles SwiftPM resource bundle(s)"

bash scripts/stage-widget-appintents-metadata.sh release "$WIDGET_RESOURCES_DIR"
BIN_DIR="$(swift build --build-system native --scratch-path build/appintents/release/native-build -c release --show-bin-path)"
WIDGET_BINARY_PATH="${BIN_DIR}/${WIDGET_NAME}"
[ -f "$WIDGET_BINARY_PATH" ] || fail "Widget binary not found at ${WIDGET_BINARY_PATH}"
cp "$WIDGET_BINARY_PATH" "$WIDGET_MACOS_DIR/${WIDGET_NAME}"
cp "$WIDGET_SOURCE_PLIST" "$WIDGET_INFO_PLIST"
plist_set "$WIDGET_INFO_PLIST" "CFBundleShortVersionString" string "$VERSION"
plist_set "$WIDGET_INFO_PLIST" "CFBundleVersion" string "$BUILD_NUMBER"
plist_set "$WIDGET_INFO_PLIST" "CFBundleIdentifier" string "$WIDGET_BUNDLE_ID"
if [ -d "${BIN_DIR}/JPtheCat_${WIDGET_NAME}.bundle" ]; then
	cp -R "${BIN_DIR}/JPtheCat_${WIDGET_NAME}.bundle" "$WIDGET_RESOURCES_DIR/"
fi
[ -f "$ICNS_SOURCE" ] && cp "$ICNS_SOURCE" "$WIDGET_RESOURCES_DIR/AppIcon.icns"
step "Embedded WidgetKit extension with App Intents metadata"

[ -f "$ICNS_SOURCE" ] && cp "$ICNS_SOURCE" "$RESOURCES_DIR/AppIcon.icns" && step "Copied app icon"

# The localized "JP the Cat" name Finder, Spotlight, and the widget gallery show. macOS applies it only
# because Info.plist's base CFBundleDisplayName matches the bundle's file name, JPtheCat.
[ -f "en.lproj/InfoPlist.strings" ] || fail "en.lproj/InfoPlist.strings not found"
cp -R en.lproj "$RESOURCES_DIR/"
step "Copied localized app name"

if [ -d "$SPARKLE_SOURCE" ]; then
	ditto "$SPARKLE_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"
	step "Copied Sparkle.framework"
	# Sparkle's MIT license requires its notice in every copy we ship, so the bundle carries it.
	[ -f "$SPARKLE_LICENSE_SOURCE" ] || fail "Missing ${SPARKLE_LICENSE_SOURCE}; the shipped app must carry Sparkle's MIT notice"
	cp "$SPARKLE_LICENSE_SOURCE" "$RESOURCES_DIR/Sparkle-LICENSE.txt"
	step "Copied Sparkle license notice"
else
	warn "Sparkle.framework not found — auto-update disabled"
fi

cp "$SOURCE_PLIST" "$INFO_PLIST"
plist_set "$INFO_PLIST" "CFBundleShortVersionString" string "$VERSION"
plist_set "$INFO_PLIST" "CFBundleVersion" string "$BUILD_NUMBER"
plist_set "$INFO_PLIST" "NSPrincipalClass" string "NSApplication"
step "Wrote Info.plist"

if [ "$BUILD_ONLY" = true ]; then
	info "Build complete (--build-only). App at: ${APP_BUNDLE}"; exit 0
fi

info "Signing ${APP_NAME}.app"
SPARKLE_FW="${FRAMEWORKS_DIR}/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
	# Inner Mach-O before its wrapping .xpc/.app, framework last, app last of all. Signing the
	# wrapper alone leaves CodeResources referencing an ad-hoc inner binary → macOS rejects it at
	# launch ("Cannot retrieve path for auxiliary tool: Updater.app"). Matches Sparkle's recipe.
	SPARKLE_HELPERS=(
		"$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
		"$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"
		"$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
		"$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"
		"$SPARKLE_FW/Versions/B/Autoupdate"
		"$SPARKLE_FW/Versions/B/Updater.app/Contents/MacOS/Updater"
		"$SPARKLE_FW/Versions/B/Updater.app"
	)
	for helper in "${SPARKLE_HELPERS[@]}"; do
		[ -e "$helper" ] || continue
		sign_with_retry sign_target "$helper" false >/dev/null
	done
	sign_with_retry sign_target "$SPARKLE_FW" false >/dev/null
	step "Signed Sparkle.framework (helpers inner→outer)"
fi

sign_with_retry sign_widget_target "$WIDGET_APPEX"
verify_signature_summary "$WIDGET_APPEX"
verify_app_group_entitlement "$WIDGET_APPEX"
step "Signed WidgetKit extension"

sign_with_retry sign_target "$APP_BUNDLE" true
verify_signature_summary "$APP_BUNDLE"
verify_app_group_entitlement "$APP_BUNDLE"
step "Signature verified"

info "Creating DMG"
DMG_STAGING="${BUILD_DIR}/dmg-staging"
DMG_FINAL="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
/bin/rm -rf "$DMG_STAGING" "$DMG_FINAL"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGING/Applications"

if [ "$DMG_LAYOUT_MODE" = "fast" ]; then
	create_fast_dmg
else
	create_polished_dmg
	if [ -x scripts/verify-dmg-layout.sh ]; then
		bash scripts/verify-dmg-layout.sh --dmg "$DMG_FINAL" --skip-finder-check
		step "DMG layout verified"
	fi
fi
/bin/rm -rf "$DMG_STAGING"
step "Compressed DMG: ${DMG_FINAL}"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
	codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_FINAL"
	step "Signed DMG"
fi

if can_notarize; then
	info "Notarizing DMG (this can take a few minutes)"
	NOTARY_JSON="${BUILD_DIR}/${APP_NAME}-${VERSION}.notary-submission.json"
	if ! xcrun notarytool submit "$DMG_FINAL" --keychain-profile "$NOTARY_PROFILE" \
		--wait --output-format json > "$NOTARY_JSON"; then
		print_notary_log "$(json_value id "$NOTARY_JSON")"; fail "Notarization submission failed"
	fi
	recover_empty_notary_json "$(basename "$DMG_FINAL")" "$NOTARY_JSON"
	NOTARY_ID="$(json_value id "$NOTARY_JSON")"
	NOTARY_STATUS="$(json_value status "$NOTARY_JSON")"
	if [ -n "$NOTARY_ID" ] && [ "$NOTARY_STATUS" != "Accepted" ] && [ "$NOTARY_STATUS" != "Invalid" ] && [ "$NOTARY_STATUS" != "Rejected" ]; then
		wait_for_notary_status "$NOTARY_ID" "$NOTARY_JSON"
		NOTARY_STATUS="$(json_value status "$NOTARY_JSON")"
	fi
	step "Notary submission ${NOTARY_ID:-unknown}: ${NOTARY_STATUS:-unknown}"
	[ "$NOTARY_STATUS" = "Accepted" ] || { print_notary_log "$NOTARY_ID"; fail "Notarization rejected"; }

	attempt=0; stapled=false
	while [ $attempt -lt 10 ]; do
		if xcrun stapler staple "$DMG_FINAL" 2>&1; then step "Notarization ticket stapled"; stapled=true; break; fi
		attempt=$((attempt + 1)); step "Staple retry $attempt/10..."; sleep 10
	done
	[ "$stapled" = true ] || fail "Staple retry limit exhausted"
	# NOT `validate … && step` — under `set -e` a failure on the LEFT of `&&` does not abort, so an
	# unstapled DMG would be checksummed and reported complete.
	xcrun stapler validate "$DMG_FINAL" >/dev/null || fail "stapler validate failed — DMG is not stapled"
	step "stapler validate OK"
	spctl -a -t open --context context:primary-signature "$DMG_FINAL" 2>&1 | head -2 || true
else
	if   [ "$LOCAL_MODE" = true ]; then step "Skipping notarization (--local)"
	elif [ "$UNSIGNED" = true ];   then step "Skipping notarization (--unsigned)"
	else fail "Notarization required for a release build"; fi
fi

info "Generating checksum"
CHECKSUM="$(shasum -a 256 "$DMG_FINAL" | awk '{print $1}')"
echo "${CHECKSUM}  $(basename "$DMG_FINAL")" > "${BUILD_DIR}/${APP_NAME}-${VERSION}.sha256"
step "SHA-256: ${CHECKSUM}"

DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/$(basename "$DMG_FINAL")"
DMG_SIZE="$(du -h "$DMG_FINAL" | awk '{print $1}')"

echo ""
info "Build complete"
echo "  App:      ${APP_BUNDLE}"
echo "  DMG:      ${DMG_FINAL} (${DMG_SIZE})"
echo "  Checksum: ${BUILD_DIR}/${APP_NAME}-${VERSION}.sha256"
echo "  Download: ${DOWNLOAD_URL}"
[ "$CODESIGN_IDENTITY" != "-" ] && echo "  Signed:   ${CODESIGN_IDENTITY}" || echo "  Signed:   ad-hoc"
echo ""
