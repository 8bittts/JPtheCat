#!/usr/bin/env bash
#
# smoke-test.sh — pre-ship gate for JPtheCat.
#
#   ./scripts/smoke-test.sh                # Default tier: tests + release build + bundle-shape
#   ./scripts/smoke-test.sh --production   # + verify the signed/notarized/stapled DMG
#
# Non-launching (Dock/status-item visibility can't be asserted headless). Trust exit code + evidence.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="JPtheCat"
BUNDLE_ID="com.8bittts.jpthecat"
WIDGET_NAME="JPtheCatWidgetExtension"
WIDGET_BUNDLE_ID="com.8bittts.jpthecat.widget"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

PRODUCTION=false
[ "${1:-}" = "--production" ] && PRODUCTION=true

pass() { printf "\033[1;32m  ✓\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m  ✗ %s\033[0m\n" "$1" >&2; exit 1; }
info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }

info "Tests"
swift test >/dev/null 2>&1 || fail "swift test failed"
pass "swift test green"

info "Release build"
swift build -c release --product "$APP_NAME" >/dev/null 2>&1 || fail "release build failed"
swift build -c release --product "$WIDGET_NAME" >/dev/null 2>&1 || fail "widget release build failed"
pass "swift build -c release"

info "Production resource lookup"
bundle_module_hits="$(
	rg -n "Bundle\\.module\\b" Sources/JPtheCatApp Sources/JPtheCatCore Sources/JPtheCatWidgetExtension \
		| rg -v '^[^:]+:[0-9]+:[[:space:]]*(///|//)' || true
)"
if [ -n "$bundle_module_hits" ]; then
	printf "%s\n" "$bundle_module_hits" >&2
	fail "production sources must not use SwiftPM Bundle.module; packaged .app resources live under Contents/Resources"
fi
pass "production resource lookup avoids Bundle.module"

# Default tier assembles a fresh bundle for shape checks. Production tier must NOT re-assemble —
# build-dmg's clean step wipes the *.dmg the production checks need — so it verifies the existing
# signed bundle from the prior build-dmg run.
if [ "$PRODUCTION" = false ]; then
	info "Assemble bundle (build-only)"
	bash scripts/build-dmg.sh --build-only >/dev/null 2>&1 || fail "build-dmg --build-only failed"
else
	info "Using existing signed bundle from build-dmg"
fi
[ -d "$APP_BUNDLE" ] || fail "no app bundle at ${APP_BUNDLE} — run build-dmg.sh first"
PLIST="${APP_BUNDLE}/Contents/Info.plist"
WIDGET_APPEX="${APP_BUNDLE}/Contents/PlugIns/${WIDGET_NAME}.appex"
WIDGET_PLIST="${WIDGET_APPEX}/Contents/Info.plist"

info "Bundle shape"
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST" 2>/dev/null)" = "false" ] || fail "LSUIElement != false"
pass "LSUIElement = false (Dock icon visible by default)"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" = "$BUNDLE_ID" ] || fail "bundle id mismatch"
pass "bundle id = ${BUNDLE_ID}"
for k in SUFeedURL SUPublicEDKey SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
	/usr/libexec/PlistBuddy -c "Print :$k" "$PLIST" >/dev/null 2>&1 || fail "missing Sparkle key $k"
done
pass "Sparkle Info.plist keys present"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")" = "AppIcon" ] \
	&& [ -f "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" ] || fail "AppIcon.icns not wired"
pass "AppIcon.icns wired"
# Finder, Spotlight, and the widget gallery read the localized name; without it they show "JPtheCat".
[ "$(plutil -extract CFBundleDisplayName raw -o - "${APP_BUNDLE}/Contents/Resources/en.lproj/InfoPlist.strings" 2>/dev/null)" = "JP the Cat" ] \
	&& [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST")" = "$APP_NAME" ] || fail "localized app name not wired"
pass "localized app name = JP the Cat"
otool -L "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" | grep -q "@rpath/Sparkle.framework" || fail "app not linked against @rpath/Sparkle.framework"
pass "links @rpath/Sparkle.framework"
[ -d "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework" ] || fail "Sparkle.framework not staged"
[ -L "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Updater.app" ] || fail "Updater.app symlink missing"
pass "Sparkle.framework staged (Updater.app symlink intact)"
[ -d "$WIDGET_APPEX" ] || fail "WidgetKit extension not embedded at ${WIDGET_APPEX}"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WIDGET_PLIST")" = "$WIDGET_BUNDLE_ID" ] || fail "widget bundle id mismatch"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$WIDGET_PLIST")" = "XPC!" ] || fail "widget package type is not XPC!"
[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$WIDGET_PLIST")" = "com.apple.widgetkit-extension" ] || fail "widget extension point mismatch"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$WIDGET_PLIST")" = "MacOSX" ] || fail "widget supported platform missing"
[ -x "${WIDGET_APPEX}/Contents/MacOS/${WIDGET_NAME}" ] || fail "widget executable missing"
otool -L "${WIDGET_APPEX}/Contents/MacOS/${WIDGET_NAME}" | grep -q WidgetKit || fail "widget not linked against WidgetKit"
otool -L "${WIDGET_APPEX}/Contents/MacOS/${WIDGET_NAME}" | grep -q AppIntents || fail "configurable widget not linked against AppIntents"
# A staged SwiftPM resource bundle's INTERNAL layout is the build system's choice, not ours: the
# deprecated `native` backend wrote resources flat (`X.bundle/file`), while the current default
# `swiftbuild` backend writes a VERSIONED bundle (`X.bundle/Contents/Resources/file` plus
# `Contents/Info.plist`). Production resolves either through `JPResourceBundle`, which goes via
# `Bundle.url(forResource:)` and therefore reads the bundle's own `resourceURL` — so assert the same
# way instead of pinning one layout and failing a good build.
bundle_file() {
	local bundle_dir="$1" name="$2"
	[ -f "${bundle_dir}/${name}" ] || [ -f "${bundle_dir}/Contents/Resources/${name}" ]
}
bundle_file "${WIDGET_APPEX}/Contents/Resources/JPtheCat_${WIDGET_NAME}.bundle" jp-menubar.png || fail "widget JP mark resource missing"
[ -f "${WIDGET_APPEX}/Contents/Resources/AppIcon.icns" ] || fail "widget app icon resource missing"
[ -f "${WIDGET_APPEX}/Contents/Resources/Metadata.appintents/version.json" ] || fail "widget App Intents metadata version missing"
[ -f "${WIDGET_APPEX}/Contents/Resources/Metadata.appintents/extract.actionsdata" ] || fail "widget App Intents actions metadata missing"
grep -q "JPtheCatWidgetConfigurationIntent" "${WIDGET_APPEX}/Contents/Resources/Metadata.appintents/extract.actionsdata" \
	|| fail "widget App Intents metadata does not include JPtheCatWidgetConfigurationIntent"
rg -q "AppIntentConfiguration" Sources/JPtheCatWidgetExtension/JPtheCatWidget.swift || fail "widget must use AppIntentConfiguration"
# The widget MUST boot through the legacy PlugInKit XPC entry point, not SwiftPM's ExtensionFoundation
# `@main` (which traps "Unrecognized extension type" so chronod can never host it → invisible in the
# gallery). A healthy widget refuses a direct run with "cannot be run directly"; the broken one traps.
WIDGET_DIRECT_RUN="$("${WIDGET_APPEX}/Contents/MacOS/${WIDGET_NAME}" 2>&1 | head -1 || true)"
case "$WIDGET_DIRECT_RUN" in
	*"cannot be run directly"*) pass "widget uses NSExtensionMain entry (gallery-hostable)" ;;
	*"Unrecognized extension type"*) fail "widget traps at launch — missing _NSExtensionMain entry point; it will never appear in the widget gallery" ;;
	*) fail "widget direct-run gave unexpected output: ${WIDGET_DIRECT_RUN}" ;;
esac
pass "WidgetKit extension embedded (PlugIns/.appex, Info.plist, resources, App Intents metadata)"
CORE_RESOURCES="${APP_BUNDLE}/Contents/Resources/${APP_NAME}_JPtheCatCore.bundle"
APP_RESOURCES="${APP_BUNDLE}/Contents/Resources/${APP_NAME}_JPtheCatApp.bundle"
bundle_file "${CORE_RESOURCES}" pricing-default.json || fail "pricing-default.json missing from Core resource bundle"
pass "Core resource bundle present (pricing resolves)"
for resource in jp-menubar.png jp-first-run-peek.png jp-meow.m4a provider-claude.svg provider-codex.svg; do
	bundle_file "${APP_RESOURCES}" "${resource}" || fail "${resource} missing from App resource bundle"
done
pass "App resource bundle present (images, provider marks, sound resolve)"
# No loose files in the .app root (would break codesign sealing).
extra="$(ls -A "$APP_BUNDLE" | grep -v '^Contents$' || true)"
[ -z "$extra" ] || fail "unsealed files in .app root: ${extra}"
pass ".app root sealed (Contents/ only)"

if [ "$PRODUCTION" = true ]; then
	info "Production: verify notarized DMG"
	# Target the DMG for the version actually built (from the app bundle), NOT `ls | head -1` —
	# a stale/other-version DMG in build/ would otherwise be verified by mistake.
	DMG_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
	DMG="${BUILD_DIR}/${APP_NAME}-${DMG_VERSION}.dmg"
	[ -f "$DMG" ] || fail "expected DMG not found: ${DMG} — run build-dmg.sh first"
	pass "DMG present: $(basename "$DMG")"
	xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "DMG not stapled"
	pass "stapler validate OK"
	spctl -a -t open --context context:primary-signature "$DMG" >/dev/null 2>&1 || fail "DMG rejected by Gatekeeper"
	pass "spctl accepts DMG"
	bash scripts/verify-dmg-layout.sh --dmg "$DMG" --skip-finder-check || fail "DMG layout verification failed"
	pass "DMG layout verified"
	MNT="$(hdiutil attach "$DMG" -nobrowse -noautoopen 2>/dev/null | grep /Volumes | command sed 's/.*\/Volumes/\/Volumes/')"
	[ -n "$MNT" ] || fail "could not mount DMG"
	trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || hdiutil detach "$MNT" -force -quiet 2>/dev/null || true' EXIT
	spctl -a -t exec -vv "$MNT/${APP_NAME}.app" 2>&1 | grep -q "source=Notarized Developer ID" || fail "app not Notarized Developer ID"
	pass "app: Notarized Developer ID"
	codesign --verify --deep --strict "$MNT/${APP_NAME}.app" 2>/dev/null || fail "deep codesign verify failed"
	pass "codesign --verify --deep --strict OK"
	SHA_FILE="${BUILD_DIR}/${APP_NAME}-${DMG_VERSION}.sha256"
	[ -f "$SHA_FILE" ] && shasum -a 256 -c <(awk -v d="$(dirname "$DMG")" '{print $1"  "d"/"$2}' "$SHA_FILE") >/dev/null 2>&1 \
		&& pass "checksum matches" || fail "checksum file missing/mismatch"
fi

echo ""
if [ "$PRODUCTION" = true ]; then
	info "SMOKE TEST PASSED (production tier)"
else
	info "SMOKE TEST PASSED"
fi
