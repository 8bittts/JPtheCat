#!/usr/bin/env bash
#
# Build the SwiftPM WidgetKit extension with App Intents constant extraction enabled, then stage
# Metadata.appintents into the .appex resources directory. SwiftPM does not do this automatically,
# but configurable widgets need the metadata for WidgetKit gallery/search discovery.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="${1:-release}"
DESTINATION_RESOURCES_DIR="${2:-}"
WIDGET_NAME="JPtheCatWidgetExtension"
MODULE_NAME="$WIDGET_NAME"
DEPLOYMENT_TARGET="14.0"
ARCH="$(uname -m)"
TARGET_TRIPLE="${ARCH}-apple-macosx${DEPLOYMENT_TARGET}"
WORK_DIR="${REPO_ROOT}/build/appintents/${CONFIG}"
PROTOCOLS_FILE="${WORK_DIR}/${WIDGET_NAME}_const_extract_protocols.json"
CONST_VALUES="${WORK_DIR}/${WIDGET_NAME}.swiftconstvalues"
CONST_VALUES_LIST="${WORK_DIR}/${WIDGET_NAME}.SwiftConstValuesFileList"
DEPENDENCY_METADATA_LIST="${WORK_DIR}/${WIDGET_NAME}.DependencyMetadataFileList"
DEPENDENCY_STATIC_METADATA_LIST="${WORK_DIR}/${WIDGET_NAME}.DependencyStaticMetadataFileList"
METADATA_OUTPUT_DIR="${WORK_DIR}/metadata-output"
METADATA_DIR="${METADATA_OUTPUT_DIR}/Metadata.appintents"

fail() { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }
step() { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }

case "$CONFIG" in
	debug|release) ;;
	*) fail "configuration must be debug or release (got ${CONFIG})" ;;
esac

mkdir -p "$WORK_DIR"
cat > "$PROTOCOLS_FILE" <<'JSON'
["AnyResolverProviding","AppEntity","AppEnum","AppExtension","AppIntent","AppIntentsPackage","AppShortcutProviding","AppShortcutsProvider","DynamicOptionsProvider","EntityQuery","ExtensionPointDefining","IntentValueQuery","Resolver","TransientEntity","_AssistantIntentsProvider","_GenerativeFunctionExtractable","_IntentValueRepresentable"]
JSON

NATIVE_SCRATCH="${WORK_DIR}/native-build"
BIN_DIR="$(swift build --build-system native --scratch-path "$NATIVE_SCRATCH" -c "$CONFIG" --show-bin-path)"
TARGET_BUILD_DIR="${BIN_DIR}/${WIDGET_NAME}.build"
rm -f "$CONST_VALUES"
if [ -d "$TARGET_BUILD_DIR" ]; then
	rm -f "${TARGET_BUILD_DIR}"/*.o "${TARGET_BUILD_DIR}"/*.swiftdeps \
		"${TARGET_BUILD_DIR}"/*.swiftconstvalues "${TARGET_BUILD_DIR}"/*.d "${TARGET_BUILD_DIR}"/*.dia
fi
rm -f "${BIN_DIR}/${WIDGET_NAME}" "${BIN_DIR}/Modules/${WIDGET_NAME}."*

# The swiftbuild backend omits release constant values on Swift 6.4; native still emits them.
# Clean first so an incremental native build cannot reuse objects without extraction output.
swift package --scratch-path "$NATIVE_SCRATCH" clean
swift build --build-system native --scratch-path "$NATIVE_SCRATCH" -c "$CONFIG" --product "$WIDGET_NAME" \
	-Xswiftc -emit-const-values-path \
	-Xswiftc "$CONST_VALUES" \
	-Xswiftc -Xfrontend \
	-Xswiftc -const-gather-protocols-file \
	-Xswiftc -Xfrontend \
	-Xswiftc "$PROTOCOLS_FILE"

# Keep native products in their own cache. Copying a flat native resource bundle into swiftbuild's
# Contents-style bundle pollutes the next build and makes codesign reject its unsealed root files.
NATIVE_BIN_DIR="$BIN_DIR"

# The target's Swift source list, derived from the PACKAGE rather than the build system's scratch
# layout. SwiftPM's default build system is now `swiftbuild` (XCBuild-based; `native` is deprecated),
# and it writes products to `.build/out/Products/<Config>` with intermediates under
# `Intermediates.noindex` — it never writes the `<Target>.build/sources` file that the old `native`
# layout had, so reading it aborted the whole release with "Widget source file list missing". This was
# a toolchain-default change, not a package one: v1.117 released fine hours before the switch.
# `appintentsmetadataprocessor` only needs the target's own Swift files, which are deterministic.
SOURCES_DIR="${REPO_ROOT}/Sources/${WIDGET_NAME}"
SOURCE_FILE_LIST="${WORK_DIR}/${WIDGET_NAME}.sources"
[ -d "$SOURCES_DIR" ] || fail "Widget sources directory missing at ${SOURCES_DIR}"
find "$SOURCES_DIR" -type f -name '*.swift' | sort > "$SOURCE_FILE_LIST"
[ -s "$SOURCE_FILE_LIST" ] || fail "no Swift sources found under ${SOURCES_DIR}"

: > "$CONST_VALUES_LIST"
if [ -s "$CONST_VALUES" ]; then
	printf "%s\n" "$CONST_VALUES" >> "$CONST_VALUES_LIST"
fi
if [ -d "$TARGET_BUILD_DIR" ]; then
	find "$TARGET_BUILD_DIR" -type f -name "*.swiftconstvalues" -print >> "$CONST_VALUES_LIST"
fi
# A DEBUG native build compiles per file (no WMO) and ignores the single explicit
# -emit-const-values-path: it writes one `<File>.swift.swiftconstvalues` per source under the
# NATIVE target dir (`.build/arm64-apple-macosx/debug/<Widget>.build/`), which is neither the
# swiftbuild `TARGET_BUILD_DIR` above nor a `<Widget>*`-prefixed name the scratch scan below matches.
# Release (WMO) writes the explicit file, which is why the DMG path passed while
# `build_and_run.sh --verify` failed with "Swift constant values missing".
NATIVE_TARGET_BUILD_DIR="${NATIVE_BIN_DIR}/${WIDGET_NAME}.build"
if [ -d "$NATIVE_TARGET_BUILD_DIR" ] && [ "$NATIVE_TARGET_BUILD_DIR" != "$TARGET_BUILD_DIR" ]; then
	find "$NATIVE_TARGET_BUILD_DIR" -type f -name "*.swiftconstvalues" -print >> "$CONST_VALUES_LIST"
fi
# `swiftbuild` (SwiftPM's default backend since the Swift 6.4 toolchain; `native` is deprecated)
# ignores the explicit -emit-const-values-path and instead writes
# `<Target>-primary.swiftconstvalues` under `.build/out/Intermediates.noindex`, scoped by
# configuration. Collect whatever the build actually produced rather than assuming one layout.
SCRATCH_DIR="$NATIVE_SCRATCH"
if [ -d "$SCRATCH_DIR" ]; then
	while IFS= read -r candidate; do
		case "$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')" in
			*/"$CONFIG"/*) printf '%s\n' "$candidate" >> "$CONST_VALUES_LIST" ;;
		esac
	done < <(find "$SCRATCH_DIR" -type f -name "${WIDGET_NAME}*.swiftconstvalues" 2>/dev/null)
fi
[ -s "$CONST_VALUES_LIST" ] || fail "Swift constant values missing; App Intents metadata cannot be extracted"
while IFS= read -r const_file; do
	[ -s "$const_file" ] || fail "empty Swift constant values file: ${const_file}"
done < "$CONST_VALUES_LIST"
FOUND_WIDGET_INTENT=false
while IFS= read -r const_file; do
	if grep -q "JPtheCatWidgetConfigurationIntent" "$const_file"; then
		FOUND_WIDGET_INTENT=true
	fi
done < "$CONST_VALUES_LIST"
[ "$FOUND_WIDGET_INTENT" = true ] || fail "Swift constant values do not include JPtheCatWidgetConfigurationIntent"

: > "$DEPENDENCY_METADATA_LIST"
: > "$DEPENDENCY_STATIC_METADATA_LIST"
[ ! -e "$METADATA_OUTPUT_DIR" ] || trash "$METADATA_OUTPUT_DIR"
mkdir -p "$METADATA_OUTPUT_DIR"

xcrun appintentsmetadataprocessor \
	--output "$METADATA_OUTPUT_DIR" \
	--toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
	--module-name "$MODULE_NAME" \
	--sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
	--xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
	--platform-family macOS \
	--deployment-target "$DEPLOYMENT_TARGET" \
	--target-triple "$TARGET_TRIPLE" \
	--source-file-list "$SOURCE_FILE_LIST" \
	--swift-const-vals-list "$CONST_VALUES_LIST" \
	--metadata-file-list "$DEPENDENCY_METADATA_LIST" \
	--static-metadata-file-list "$DEPENDENCY_STATIC_METADATA_LIST" \
	--force

[ -f "${METADATA_DIR}/version.json" ] || fail "Metadata.appintents version.json was not produced"
[ -f "${METADATA_DIR}/extract.actionsdata" ] || fail "Metadata.appintents extract.actionsdata was not produced"
grep -q "JPtheCatWidgetConfigurationIntent" "${METADATA_DIR}/extract.actionsdata" \
	|| fail "Metadata.appintents does not include JPtheCatWidgetConfigurationIntent"

if [ -n "$DESTINATION_RESOURCES_DIR" ]; then
	mkdir -p "$DESTINATION_RESOURCES_DIR"
	[ ! -e "${DESTINATION_RESOURCES_DIR}/Metadata.appintents" ] || trash "${DESTINATION_RESOURCES_DIR}/Metadata.appintents"
	cp -R "$METADATA_DIR" "$DESTINATION_RESOURCES_DIR/"
	step "Staged Metadata.appintents"
else
	step "Built Metadata.appintents at ${METADATA_DIR}"
fi
