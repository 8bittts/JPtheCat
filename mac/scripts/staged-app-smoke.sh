#!/usr/bin/env bash
#
# staged-app-smoke.sh — AppKit runtime smoke for the staged JPtheCat.app.
#
# This is intentionally a staged-bundle gate, not `swift run`: Dock visibility, status-item geometry,
# Sparkle, notifications, LaunchServices reopen, and accessory mode only mean anything for a real .app.
#
#   ./scripts/staged-app-smoke.sh
#   ./scripts/staged-app-smoke.sh --already-built build/local-run/JPtheCat.app
#
# Requires Accessibility permission for the shell app running this command. If AX is not trusted it
# fails with setup instructions instead of silently skipping the UI proof.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/local-run/JPtheCat.app"
BUNDLE_ID="com.8bittts.jpthecat"
ALREADY_BUILT=false
if [ "${1:-}" = "--already-built" ]; then
	ALREADY_BUILT=true
	APP="${2:-$APP}"
fi

pass() { printf "\033[1;32m  ✓\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m  ✗ %s\033[0m\n" "$1" >&2; exit 1; }
info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }

if [ "$ALREADY_BUILT" = false ]; then
	bash scripts/build_and_run.sh --build-only >/dev/null
fi
[ -d "$APP" ] || fail "staged app missing at $APP"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

if ! swift - <<'SWIFT' >/dev/null; then
import ApplicationServices
import Foundation
exit(AXIsProcessTrusted() ? 0 : 1)
SWIFT
	fail "Accessibility permission missing. Grant Terminal/YEN in System Settings > Privacy & Security > Accessibility, then rerun."
fi

ORIGINAL_DOCK_VALUE="__missing__"
if ORIGINAL_DOCK_VALUE="$(defaults read "$BUNDLE_ID" JPtheCat.showDockIcon 2>/dev/null)"; then
	:
else
	ORIGINAL_DOCK_VALUE="__missing__"
fi

cleanup() {
	terminate_jpthecat_processes staged >/dev/null 2>&1 || true
	if [ "$ORIGINAL_DOCK_VALUE" = "__missing__" ]; then
		defaults delete "$BUNDLE_ID" JPtheCat.showDockIcon >/dev/null 2>&1 || true
	else
		defaults write "$BUNDLE_ID" JPtheCat.showDockIcon -bool "$ORIGINAL_DOCK_VALUE" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

terminate_jpthecat_processes() {
	local scope="${1:-all}"
	for pid in $(pgrep -x JPtheCat 2>/dev/null || true); do
		local command
		command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
		case "$command" in
		"$APP/Contents/MacOS/JPtheCat"*) kill "$pid" 2>/dev/null || true ;;
		*"/Contents/MacOS/JPtheCat"*)
			[ "$scope" = "all" ] && kill "$pid" 2>/dev/null || true
			;;
		esac
	done
}

quit_running_app() {
	terminate_jpthecat_processes all
	for _ in {1..20}; do
		local running=false
		for pid in $(pgrep -x JPtheCat 2>/dev/null || true); do
			case "$(ps -p "$pid" -o command= 2>/dev/null || true)" in
			*"/Contents/MacOS/JPtheCat"*) running=true ;;
			esac
		done
		[ "$running" = false ] && return 0
		sleep 0.2
	done
	return 1
}

wait_for_staged_process() {
	for _ in {1..40}; do
		for pid in $(pgrep -x JPtheCat 2>/dev/null || true); do
			case "$(ps -p "$pid" -o command= 2>/dev/null || true)" in
			"$APP/Contents/MacOS/JPtheCat"*) return 0 ;;
			esac
		done
		sleep 0.25
	done
	return 1
}

wait_for_dashboard() {
	osascript <<'APPLESCRIPT'
tell application "System Events"
	repeat 40 times
		if exists process "JPtheCat" then
			tell process "JPtheCat"
				if exists window "JP the Cat" then return "dashboard window visible"
			end tell
		end if
		delay 0.25
	end repeat
	error "dashboard window did not appear"
end tell
APPLESCRIPT
}

assert_dashboard_still_visible() {
	local label="$1"
	if wait_for_dashboard >/dev/null; then
		pass "$label leaves dashboard window open"
	else
		fail "$label closed the dashboard window"
	fi
}

find_ax_text() {
	local needle="$1"
	ax_helper find "$needle"
}

wait_for_ax_text() {
	local needle="$1"
	for _ in {1..40}; do
		if find_ax_text "$needle" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.25
	done
	return 1
}

press_ax_text() {
	local needle="$1"
	for _ in {1..40}; do
		if ax_helper press "$needle"; then
			return 0
		fi
		sleep 0.25
	done
	return 1
}

click_ax_text() {
	local needle="$1"
	ax_helper click "$needle"
}

right_click_ax_text() {
	local needle="$1"
	ax_helper right-click "$needle"
}

right_click_off_primary_ax_text() {
	local needle="$1"
	ax_helper right-click-off-primary "$needle"
}

find_off_primary_ax_text() {
	local needle="$1"
	ax_helper find-off-primary "$needle"
}

off_primary_screen_count() {
	swift - <<'SWIFT'
import AppKit
let main = NSScreen.main
let count = NSScreen.screens.filter { screen in
  guard let main else { return false }
  return screen != main
}.count
print(count)
SWIFT
}

ax_helper() {
	local mode="$1"
	local needle="$2"
	JPTHECAT_STAGED_EXECUTABLE="$APP/Contents/MacOS/JPtheCat" swift - "$mode" "$needle" <<'SWIFT'
import AppKit
import ApplicationServices
import Foundation

let mode = CommandLine.arguments[1]
let needle = CommandLine.arguments[2]
let stagedExecutable = ProcessInfo.processInfo.environment["JPTHECAT_STAGED_EXECUTABLE"] ?? ""
let maxNodes = 4_000
var visited = 0

func matchingPIDs() -> [pid_t] {
  NSWorkspace.shared.runningApplications.compactMap { app in
    if app.localizedName == "SystemUIServer" || app.bundleIdentifier == "com.apple.systemuiserver" {
      return app.processIdentifier
    }
    let isJPtheCat = app.localizedName == "JPtheCat" || app.bundleIdentifier == "com.8bittts.jpthecat"
    guard isJPtheCat, app.executableURL?.path == stagedExecutable else { return nil }
    return app.processIdentifier
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

func matches(_ element: AXUIElement) -> Bool {
  [
    kAXTitleAttribute,
    kAXDescriptionAttribute,
    kAXHelpAttribute,
    kAXValueAttribute,
    kAXRoleDescriptionAttribute,
  ].contains { attribute in
    stringAttribute(element, attribute as CFString)?.localizedCaseInsensitiveContains(needle) == true
  }
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

func isOffPrimary(_ element: AXUIElement) -> Bool {
  guard let mainFrame = NSScreen.main?.frame, let rect = frame(element) else { return false }
  return !mainFrame.contains(CGPoint(x: rect.midX, y: rect.midY))
}

func find(in element: AXUIElement, offPrimaryOnly: Bool = false) -> AXUIElement? {
  visited += 1
  guard visited <= maxNodes else { return nil }
  if matches(element), !offPrimaryOnly || isOffPrimary(element) { return element }
  for child in childElements(element) {
    if let found = find(in: child, offPrimaryOnly: offPrimaryOnly) { return found }
  }
  return nil
}

func click(_ element: AXUIElement, rightClick: Bool = false) -> Bool {
  var positionRef: CFTypeRef?
  var sizeRef: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
    positionRef != nil,
    sizeRef != nil
  else { return false }
  let positionValue = positionRef as! AXValue
  let sizeValue = sizeRef as! AXValue
  var position = CGPoint.zero
  var size = CGSize.zero
  guard
    AXValueGetValue(positionValue, .cgPoint, &position),
    AXValueGetValue(sizeValue, .cgSize, &size)
  else { return false }
  let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
  let button: CGMouseButton = rightClick ? .right : .left
  let down: CGEventType = rightClick ? .rightMouseDown : .leftMouseDown
  let up: CGEventType = rightClick ? .rightMouseUp : .leftMouseUp
  CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: center, mouseButton: button)?
    .post(tap: .cghidEventTap)
  usleep(80_000)
  CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: center, mouseButton: button)?
    .post(tap: .cghidEventTap)
  return true
}

for pid in matchingPIDs() {
  visited = 0
  let app = AXUIElementCreateApplication(pid)
  let offPrimaryOnly = mode.contains("off-primary")
  if let found = find(in: app, offPrimaryOnly: offPrimaryOnly) {
    if mode == "click" {
      exit(click(found) ? 0 : 4)
    }
    if mode == "right-click" {
      exit(click(found, rightClick: true) ? 0 : 4)
    }
    if mode == "right-click-off-primary" {
      exit(click(found, rightClick: true) ? 0 : 4)
    }
    if mode == "press" {
      let result = AXUIElementPerformAction(found, kAXPressAction as CFString)
      exit(result == .success ? 0 : 3)
    }
    exit(0)
  }
}
exit(2)
SWIFT
}

close_dashboard() {
	osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
	if exists process "JPtheCat" then
		tell process "JPtheCat"
			if exists window "JP the Cat" then
				perform action "AXPress" of (first button of window "JP the Cat" whose subrole is "AXCloseButton")
				delay 0.2
			end if
		end tell
	end if
end tell
APPLESCRIPT
}

wait_for_dashboard_closed() {
	osascript <<'APPLESCRIPT'
tell application "System Events"
	repeat 20 times
		if exists process "JPtheCat" then
			tell process "JPtheCat"
				if not (exists window "JP the Cat") then return "dashboard window closed"
			end tell
		else
			return "dashboard window closed"
		end if
		delay 0.2
	end repeat
	error "dashboard window did not close"
end tell
APPLESCRIPT
}

info "Bundle defaults"
[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist")" = "false" ] || fail "LSUIElement = false"
pass "LSUIElement = false"

info "Launch Dock-visible staged app"
quit_running_app || fail "could not quit existing JPtheCat process before staged launch"
defaults write "$BUNDLE_ID" JPtheCat.showDockIcon -bool true
open -n "$APP"
wait_for_staged_process || fail "staged JPtheCat process did not launch from $APP"
wait_for_dashboard >/dev/null || fail "dashboard window opens from the Dock"
pass "dashboard window opens from the Dock"

find_ax_text "JP the Cat AI coding cost" >/dev/null || fail "status item visible"
pass "status item visible"

close_dashboard
wait_for_dashboard_closed >/dev/null || fail "dashboard window closes before status-item reopen"
click_ax_text "JP the Cat AI coding cost" >/dev/null || fail "dashboard window opens from the status item"
wait_for_dashboard >/dev/null || fail "dashboard window opens from the status item"
pass "dashboard window opens from the status item"

wait_for_ax_text "Settings" || fail "Settings control becomes available"
press_ax_text "Settings" >/dev/null || fail "Settings"
wait_for_ax_text "Show Dock icon" || fail "settings face visible"
pass "Settings face visible"

info "Settings toggles keep the dashboard window open"
for toggle_label in \
	"Show Dock icon" \
	"Usage alerts at 80%" \
	"Show notification banner" \
	"Meow on alerts" \
	"Interactive sounds"; do
	click_ax_text "$toggle_label" >/dev/null || fail "$toggle_label toggle"
	assert_dashboard_still_visible "$toggle_label"
	click_ax_text "$toggle_label" >/dev/null || fail "$toggle_label toggle restore"
	assert_dashboard_still_visible "$toggle_label restore"
done

wait_for_ax_text "Unpin dashboard" || fail "dashboard starts pinned"
press_ax_text "Unpin dashboard" >/dev/null || fail "Unpin dashboard"
wait_for_ax_text "Pin dashboard" || fail "Pin dashboard after unpin"
press_ax_text "Pin dashboard" >/dev/null || fail "Pin dashboard"
wait_for_ax_text "Unpin dashboard" || fail "Unpin dashboard after repin"
pass "Pin toggles off and back to the pinned default"

close_dashboard
wait_for_dashboard_closed >/dev/null || fail "dashboard window closes before secondary-click menu proof"
right_click_ax_text "JP the Cat AI coding cost" >/dev/null || fail "secondary-click status item menu opens"
if find_ax_text "Check for Updates" >/dev/null || find_ax_text "Update is available" >/dev/null; then
	pass "secondary-click compact menu exposes Sparkle update item"
else
	fail "secondary-click compact menu missing Sparkle update item"
fi
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true

OFF_PRIMARY_SCREENS="$(off_primary_screen_count)"
if [ "$OFF_PRIMARY_SCREENS" -gt 0 ]; then
	if find_off_primary_ax_text "JP the Cat AI coding cost" >/dev/null; then
		right_click_off_primary_ax_text "JP the Cat AI coding cost" >/dev/null || fail "off-primary secondary-click status item menu opens"
		if find_ax_text "Check for Updates" >/dev/null || find_ax_text "Update is available" >/dev/null; then
			pass "off-primary secondary-click compact menu exposes Sparkle update item"
		else
			fail "off-primary secondary-click compact menu missing Sparkle update item"
		fi
		osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
	else
		info "Off-primary display detected, but no off-primary JP status item is exposed by AX; skipping off-primary secondary-click runtime proof"
	fi
else
	info "No off-primary display detected; skipping off-primary secondary-click runtime proof"
fi

info "Accessory mode persistence"
defaults write "$BUNDLE_ID" JPtheCat.showDockIcon -bool false
quit_running_app || fail "could not quit existing JPtheCat process before accessory relaunch"
open -n "$APP"
wait_for_staged_process || fail "staged JPtheCat process did not relaunch from $APP"
sleep 1
APP_VISIBLE="$(osascript <<'APPLESCRIPT'
tell application "System Events"
	if exists process "JPtheCat" then
		return visible of process "JPtheCat"
	end if
	return "missing"
end tell
APPLESCRIPT
)"
[ "$APP_VISIBLE" = "false" ] || fail "accessory mode did not hide Dock/process visibility (got ${APP_VISIBLE})"
pass "accessory mode persisted via JPtheCat.showDockIcon"


echo ""
info "STAGED APP SMOKE PASSED"
