#!/usr/bin/env bash
#
# sparkle-upgrade-smoke.sh - live Sparkle update proof from an old public install.
#
# Downloads an old signed JPtheCat DMG, copies it to a temporary app bundle (never /Applications),
# drives "Check for Updates" through the app's own Sparkle menu path, installs the live appcast
# update, and verifies the temporary app relaunches at the live version/build while App Support data
# survives. Requires Accessibility permission for the shell app running the script.
#
#   ./scripts/sparkle-upgrade-smoke.sh          # default old install: JPtheCat-0.004.dmg
#   ./scripts/sparkle-upgrade-smoke.sh 0.080

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="JPtheCat"
OLD_VERSION="${1:-0.004}"
OLD_DMG="JPtheCat-${OLD_VERSION}.dmg"
RELEASE_BASE="https://api.jpthecat.com/storage/v1/object/public/releases"
MANIFEST_URL="https://jpthecat.com/stable/version.json"
APPCAST_URL="https://jpthecat.com/stable/appcast.xml"
INSTALLED_APP="/Applications/JPtheCat.app"
TMPDIR=""
APP=""
REAL_APP=""
SENTINEL=""
MOUNT_DIR=""
INSTALLED_WAS_RUNNING=false
KEYCHAIN_SERVICE="com.8bittts.jpthecat.sparkle-upgrade-smoke"
KEYCHAIN_ACCOUNT="sparkle-upgrade-smoke-${$}"
KEYCHAIN_SECRET=""
KEYCHAIN_CREATED=false

pass() { printf "\033[1;32m  ✓\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m  ✗ %s\033[0m\n" "$1" >&2; exit 1; }
info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }

cleanup() {
	if [ -n "$TMPDIR" ]; then
		if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
			hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
		fi
		for pid in $(pgrep -x "$APP_NAME" 2>/dev/null || true); do
			local command
			command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
			case "$command" in
				*"${TMPDIR}"*"/Contents/MacOS/${APP_NAME}"*) kill "$pid" 2>/dev/null || true ;;
			esac
		done
		rm -rf "$TMPDIR"
	fi
	[ -n "$SENTINEL" ] && rm -f "$SENTINEL"
	if [ "$KEYCHAIN_CREATED" = true ]; then
		security delete-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
	fi
	if [ "$INSTALLED_WAS_RUNNING" = true ] && [ -d "$INSTALLED_APP" ]; then
		open -n "$INSTALLED_APP" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

if ! swift - <<'SWIFT' >/dev/null; then
import ApplicationServices
import Foundation
exit(AXIsProcessTrusted() ? 0 : 1)
SWIFT
	fail "Accessibility permission missing. Grant Terminal/YEN in System Settings > Privacy & Security > Accessibility, then rerun."
fi

json_value() {
	local key="$1" file="$2"
	/usr/bin/plutil -extract "$key" raw -o - "$file"
}

plist_value() {
	local key="$1" file="$2"
	/usr/libexec/PlistBuddy -c "Print :${key}" "$file"
}

latest_build_from_appcast() {
	sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<.*/\1/p' "$1" | head -1
}

fetch_url() {
	local url="$1" output="$2"
	curl -fsSL \
		--retry 3 \
		--retry-all-errors \
		--connect-timeout 15 \
		--max-time 120 \
		-o "$output" \
		"$url"
}

main_process_running_from() {
	local root="$1"
	for pid in $(pgrep -x "$APP_NAME" 2>/dev/null || true); do
		local command
		command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
		case "$command" in
			"${root}/Contents/MacOS/${APP_NAME}"*) return 0 ;;
		esac
	done
	return 1
}

terminate_main_processes() {
	for pid in $(pgrep -x "$APP_NAME" 2>/dev/null || true); do
		local command
		command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
		case "$command" in
			*"/Contents/MacOS/${APP_NAME}"*) kill "$pid" 2>/dev/null || true ;;
		esac
	done
}

ax_helper() {
	local mode="$1"
	local app_root="$2"
	local needle="$3"
	swift - "$mode" "$app_root" "$needle" <<'SWIFT'
import AppKit
import ApplicationServices
import Foundation

let mode = CommandLine.arguments[1]
let appRoot = CommandLine.arguments[2]
let needle = CommandLine.arguments[3]
let needles = needle.split(separator: "|").map(String.init)

func targetApps() -> [NSRunningApplication] {
  NSWorkspace.shared.runningApplications.filter { app in
    app.bundleIdentifier == "com.8bittts.jpthecat"
      && app.executableURL?.path.contains(appRoot) == true
  }
}

func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
  if let string = value as? String { return string }
  if let number = value as? NSNumber { return number.stringValue }
  return nil
}

func childElements(_ element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
    return []
  }
  return (value as? [AXUIElement]) ?? []
}

func frame(_ element: AXUIElement) -> CGRect? {
  var positionRef: CFTypeRef?
  var sizeRef: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
    positionRef != nil,
    sizeRef != nil
  else { return nil }
  let positionValue = positionRef as! AXValue
  let sizeValue = sizeRef as! AXValue
  var position = CGPoint.zero
  var size = CGSize.zero
  guard
    AXValueGetValue(positionValue, .cgPoint, &position),
    AXValueGetValue(sizeValue, .cgSize, &size)
  else { return nil }
  return CGRect(origin: position, size: size)
}

func click(_ element: AXUIElement) -> Bool {
  guard let rect = frame(element) else { return false }
  let center = CGPoint(x: rect.midX, y: rect.midY)
  CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)?
    .post(tap: .cghidEventTap)
  usleep(120_000)
  CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)?
    .post(tap: .cghidEventTap)
  return true
}

func titleMatches(_ element: AXUIElement, role: String) -> Bool {
  guard stringAttribute(element, kAXRoleAttribute as CFString) == role else { return false }
  let title = stringAttribute(element, kAXTitleAttribute as CFString) ?? ""
  return needles.contains { title.localizedCaseInsensitiveContains($0) }
}

func find(in element: AXUIElement, role: String) -> AXUIElement? {
  if titleMatches(element, role: role) { return element }
  for child in childElements(element) {
    if let found = find(in: child, role: role) { return found }
  }
  return nil
}

func hasElement(role: String) -> Bool {
  targetApps().contains { app in
    find(in: AXUIElementCreateApplication(app.processIdentifier), role: role) != nil
  }
}

func activate(role: String) -> Int32 {
  for app in targetApps() {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard let element = find(in: root, role: role) else { continue }
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if result == .success { return 0 }
    usleep(500_000)
    if !hasElement(role: role) { return 0 }
    return click(element) ? 0 : 4
  }
  return 2
}

switch mode {
case "find-menu-item":
  exit(hasElement(role: kAXMenuItemRole as String) ? 0 : 2)
case "press-menu-item":
  exit(activate(role: kAXMenuItemRole as String))
case "find-button":
  exit(hasElement(role: kAXButtonRole as String) ? 0 : 2)
case "press-button":
  exit(activate(role: kAXButtonRole as String))
default:
  exit(9)
}
SWIFT
}

wait_for_ax() {
	local mode="$1" needle="$2" timeout="${3:-60}"
	for _ in $(seq 1 "$timeout"); do
		if ax_helper "$mode" "$REAL_APP" "$needle" >/dev/null; then return 0; fi
		sleep 1
	done
	return 1
}

press_ax() {
	local mode="$1" needle="$2"
	ax_helper "$mode" "$REAL_APP" "$needle"
}

write_keychain_sentinel() {
	KEYCHAIN_SECRET="sparkle upgrade smoke ${$} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	security add-generic-password \
		-a "$KEYCHAIN_ACCOUNT" \
		-s "$KEYCHAIN_SERVICE" \
		-w "$KEYCHAIN_SECRET" \
		-U >/dev/null
	KEYCHAIN_CREATED=true
}

keychain_sentinel_present() {
	local stored_secret
	stored_secret="$(
		security find-generic-password \
			-a "$KEYCHAIN_ACCOUNT" \
			-s "$KEYCHAIN_SERVICE" \
			-w 2>/dev/null || true
	)"
	[ "$stored_secret" = "$KEYCHAIN_SECRET" ]
}

info "Resolve live Sparkle target"
TMPDIR="$(mktemp -d /tmp/jpthecat-sparkle-upgrade.XXXXXX)"
APP="$TMPDIR/${APP_NAME}.app"
REAL_APP="$(cd "$TMPDIR" && pwd -P)/${APP_NAME}.app"
manifest="$TMPDIR/version.json"
appcast="$TMPDIR/appcast.xml"
fetch_url "$MANIFEST_URL" "$manifest"
fetch_url "$APPCAST_URL" "$appcast"
LATEST_VERSION="$(json_value version "$manifest")"
LATEST_BUILD="$(latest_build_from_appcast "$appcast")"
[ -n "$LATEST_VERSION" ] || fail "live manifest missing version"
[ -n "$LATEST_BUILD" ] || fail "live appcast missing sparkle:version"
pass "live feed target ${LATEST_VERSION} build ${LATEST_BUILD}"

info "Download old public install (${OLD_DMG})"
old_dmg_path="$TMPDIR/$OLD_DMG"
fetch_url "${RELEASE_BASE}/${OLD_DMG}" "$old_dmg_path"
sha_file="../web/public/stable/${OLD_DMG}.sha256"
if [ ! -f "$sha_file" ]; then
	fetch_url "https://jpthecat.com/stable/${OLD_DMG}.sha256" "$TMPDIR/${OLD_DMG}.sha256"
	sha_file="$TMPDIR/${OLD_DMG}.sha256"
fi
expected_sha="$(awk '{print $1}' "$sha_file")"
actual_sha="$(shasum -a 256 "$old_dmg_path" | awk '{print $1}')"
[ "$actual_sha" = "$expected_sha" ] || fail "${OLD_DMG} checksum mismatch"
pass "${OLD_DMG} checksum matches"

info "Stage old app in temp path"
MOUNT_DIR="$TMPDIR/mnt"
mkdir -p "$MOUNT_DIR"
hdiutil attach "$old_dmg_path" -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" >/dev/null
ditto "$MOUNT_DIR/${APP_NAME}.app" "$APP"
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
OLD_SHORT="$(plist_value CFBundleShortVersionString "$APP/Contents/Info.plist")"
OLD_BUILD="$(plist_value CFBundleVersion "$APP/Contents/Info.plist")"
[ "$OLD_SHORT" = "$OLD_VERSION" ] || fail "old app version ${OLD_SHORT} != ${OLD_VERSION}"
pass "staged old app ${OLD_SHORT} build ${OLD_BUILD}"

if main_process_running_from "$INSTALLED_APP"; then
	INSTALLED_WAS_RUNNING=true
fi
terminate_main_processes
sleep 1

info "Launch old app and request update"
open -n "$APP"
for _ in {1..80}; do
	if main_process_running_from "$REAL_APP" || main_process_running_from "$APP"; then
		break
	fi
	sleep 0.25
done
main_process_running_from "$REAL_APP" || main_process_running_from "$APP" || fail "old app did not launch"
pass "old app launched from temp bundle"

wait_for_ax find-menu-item "Check for Updates" 45 || fail "old app did not expose Check for Updates"
press_ax press-menu-item "Check for Updates" >/dev/null || fail "could not press Check for Updates"
pass "pressed Check for Updates"

app_support="$HOME/Library/Application Support/JPtheCat"
mkdir -p "$app_support"
SENTINEL="${app_support}/sparkle-upgrade-smoke-sentinel-${$}.txt"
printf "sparkle upgrade smoke %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SENTINEL"
write_keychain_sentinel

info "Drive Sparkle install UI"
wait_for_ax find-button "Install Update" 90 || fail "Sparkle update alert did not show Install Update"
press_ax press-button "Install Update" >/dev/null || fail "could not press Install Update"
pass "pressed Install Update"
wait_for_ax find-button "Install and Relaunch" 180 || fail "Sparkle did not reach Install and Relaunch"
press_ax press-button "Install and Relaunch" >/dev/null || true
pass "pressed Install and Relaunch"

info "Verify updated app relaunch and state preservation"
for _ in {1..120}; do
	short="$(plist_value CFBundleShortVersionString "$APP/Contents/Info.plist" 2>/dev/null || true)"
	build="$(plist_value CFBundleVersion "$APP/Contents/Info.plist" 2>/dev/null || true)"
	if [ "$short" = "$LATEST_VERSION" ] && [ "$build" = "$LATEST_BUILD" ] \
		&& { main_process_running_from "$REAL_APP" || main_process_running_from "$APP"; } \
		&& [ -f "$SENTINEL" ]; then
		keychain_sentinel_present || fail "temporary Keychain sentinel missing after upgrade"
		pass "temp app updated to ${short} build ${build} and relaunched"
		pass "App Support and Keychain sentinels survived the upgrade"
		spctl -a -t exec -vv "$APP" >/dev/null 2>&1 || fail "updated app rejected by Gatekeeper"
		pass "updated app remains accepted by Gatekeeper"
		echo ""
		info "SPARKLE UPGRADE SMOKE PASSED"
		exit 0
	fi
	sleep 2
done
fail "updated app did not relaunch at ${LATEST_VERSION} build ${LATEST_BUILD}"
