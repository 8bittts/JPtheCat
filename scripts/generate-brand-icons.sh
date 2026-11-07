#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ICONSET_DIR="mac/AppIcon.iconset"
ICNS_OUT="mac/AppIcon.icns"

info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }

command -v swift >/dev/null 2>&1 || { echo "swift is required" >&2; exit 1; }
command -v iconutil >/dev/null 2>&1 || { echo "iconutil is required" >&2; exit 1; }

info "Generating icon PNG derivatives from brand/jp-eyes.png"
swift scripts/generate-brand-icons.swift

info "Building ${ICNS_OUT} from ${ICONSET_DIR}"
rm -f "$ICNS_OUT"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUT"
rm -rf "$ICONSET_DIR"

info "Done"
