#!/usr/bin/env bash
# Stage JPtheCat.app at a STABLE path so macOS privacy / login-item / LaunchServices state
# persists across runs (never a temp dir). `swift run` cannot exercise Dock visibility or the
# status item — always test through the staged bundle.
#
# Modes:  (default) build + stage + launch  |  --build-only  |  --verify  |  --runtime-smoke
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="debug"
APP="build/local-run/JPtheCat.app"
info() { printf "\033[36m•\033[0m %s\n" "$*"; }

info "swift build ($CONFIG)…"
swift build -c "$CONFIG" --product JPtheCat >/dev/null
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

info "staging $APP"
[ ! -e "$APP" ] || trash "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
	"$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/MacOS" \
	"$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/Resources"
cp "$BIN_DIR/JPtheCat" "$APP/Contents/MacOS/JPtheCat"
cp Info.plist "$APP/Contents/Info.plist"

# App icon (JP's eyes, rounded) — Info.plist declares CFBundleIconFile = AppIcon. Shows in the
# Dock, About panel, notifications, Finder Get Info, and the DMG.
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/Resources/AppIcon.icns"

# The localized "JP the Cat" name Finder, Spotlight, and the widget gallery show. macOS applies it only
# because Info.plist's base CFBundleDisplayName matches the bundle's file name, JPtheCat.
[ -f en.lproj/InfoPlist.strings ] || { echo "ERROR: en.lproj/InfoPlist.strings missing" >&2; exit 1; }
cp -R en.lproj "$APP/Contents/Resources/"

# Vendored Sparkle.framework → Contents/Frameworks (the production rpath the app links against:
# @executable_path/../Frameworks). ditto preserves the load-bearing symlinks + Updater.app.
if [ -d tools/sparkle/Sparkle.framework ]; then
	mkdir -p "$APP/Contents/Frameworks"
	ditto tools/sparkle/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
	# Sparkle's MIT notice ships beside the framework, matching build-dmg.sh.
	[ -f tools/sparkle/LICENSE ] || { echo "ERROR: tools/sparkle/LICENSE missing" >&2; exit 1; }
	cp tools/sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
fi

# SwiftPM resource bundles belong under Contents/Resources in a staged .app. Keep local staging
# shaped like production so resource lookup cannot be accidentally masked by loose root bundles.
# `nullglob` + the staged count are load-bearing: without them a no-match glob left the literal
# `*.bundle`, the `-d` test failed, and the loop exited 0 having staged nothing.
shopt -s nullglob
staged_bundles=0
for bundle in "$BIN_DIR"/*.bundle; do
	case "$bundle" in *Tests.bundle) continue ;; esac # never stage test resource bundles
	if [ -d "$bundle" ]; then
		case "$(basename "$bundle")" in
		JPtheCat_JPtheCatWidgetExtension.bundle)
			continue # staged after metadata extraction below
			;;
		*)
			cp -R "$bundle" "$APP/Contents/Resources/"
			;;
		esac
		staged_bundles=$((staged_bundles + 1))
	fi
done
shopt -u nullglob
[ "$staged_bundles" -gt 0 ] || { printf 'ERROR: no SwiftPM resource bundles staged from %s\n' "$BIN_DIR" >&2; exit 1; }

# Widget metadata uses an isolated native build cache.
bash scripts/stage-widget-appintents-metadata.sh "$CONFIG" \
	"$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/Resources" >/dev/null
BIN_DIR="$(swift build --build-system native --scratch-path "build/appintents/${CONFIG}/native-build" -c "$CONFIG" --show-bin-path)"
cp "$BIN_DIR/JPtheCatWidgetExtension" \
	"$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/MacOS/JPtheCatWidgetExtension"
cp JPtheCatWidgetExtension-Info.plist \
	"$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/Info.plist"

WIDGET_BUNDLE="$BIN_DIR/JPtheCat_JPtheCatWidgetExtension.bundle"
[ -d "$WIDGET_BUNDLE" ] || { echo "ERROR: widget resource bundle missing" >&2; exit 1; }
cp -R "$WIDGET_BUNDLE" "$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/Resources/"
for required in JPtheCat_JPtheCatCore JPtheCat_JPtheCatApp; do
	[ -d "$APP/Contents/Resources/$required.bundle" ] || { echo "ERROR: $required resource bundle missing" >&2; exit 1; }
done

info "staged $(pwd)/$APP ($staged_bundles resource bundle(s))"

case "${1:-}" in
--build-only)
	exit 0
	;;
--verify)
	[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist")" = "false" ]
	echo "LSUIElement = false ✓"
	otool -L "$APP/Contents/MacOS/JPtheCat" | grep -q AppKit && echo "links AppKit ✓"
	[ "$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$APP/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/Info.plist")" = "com.apple.widgetkit-extension" ]
	echo "WidgetKit extension embedded ✓"
	extra="$(ls -A "$APP" | grep -v '^Contents$' || true)"
	[ -z "$extra" ] && echo ".app root sealed ✓"
	exit 0
	;;
--runtime-smoke)
	bash scripts/staged-app-smoke.sh --already-built "$APP"
	exit 0
	;;
"")
	;;
*)
	# Without this arm a typo'd or renamed flag fell through to `open "$APP"` and exited 0 — the
	# requested gate silently never ran.
	printf 'ERROR: unknown argument: %s\n' "$1" >&2
	exit 1
	;;
esac

info "launching (Dock-visible app with menu-bar status item)…"
open "$APP"
