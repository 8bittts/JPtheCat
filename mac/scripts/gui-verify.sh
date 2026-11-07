#!/usr/bin/env bash
# gui-verify.sh — headless GUI verification for the running JP the Cat app.
#
# Compiles + caches mac/scripts/gui-verify.swift, then forwards the subcommand. Use this to
# SELF-VERIFY the real UI (open the Advanced Analytics tray, toggle a checkbox, read any control,
# screenshot a window) without a human in the loop. See gui-verify.swift for the full contract.
#
# The reliable stack here is Accessibility (AX press — no coordinates, no z-order fights) plus
# `screencapture`. Raw synthetic mouse clicks do NOT route reliably in this environment; drive via
# AX `press` instead. The controlling terminal needs Accessibility + Screen Recording permission.
#
# Examples:
#   mac/scripts/gui-verify.sh windows                        # list JP windows + bounds
#   mac/scripts/gui-verify.sh tree                           # dump every labelled AX control
#   mac/scripts/gui-verify.sh press "Advanced Analytics"     # open/close the analytics tray
#   mac/scripts/gui-verify.sh press "Codex, included in export"   # toggle a tray checkbox
#   mac/scripts/gui-verify.sh frame "Advanced Analytics"     # exact screen frame + center
#   mac/scripts/gui-verify.sh shot <winid> /tmp/win.png      # capture one window by id
#   mac/scripts/gui-verify.sh region 820,180,1000,540 /tmp/r.png   # capture a screen region
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/gui-verify.swift"
bin="${TMPDIR:-/tmp}/jpthecat-gui-verify"

# Region capture is a thin screencapture pass; everything else routes through the compiled tool.
if [[ "${1:-}" == "region" ]]; then
  [[ $# -ge 3 ]] || { echo "usage: gui-verify.sh region X,Y,W,H <path>" >&2; exit 2; }
  screencapture -o -x -R"$2" "$3"
  echo "wrote $3"
  exit 0
fi
if [[ "${1:-}" == "full" ]]; then
  [[ $# -ge 2 ]] || { echo "usage: gui-verify.sh full <path>" >&2; exit 2; }
  screencapture -x "$2"
  echo "wrote $2"
  exit 0
fi

# Rebuild only when the source is newer than the cached binary.
if [[ ! -x "$bin" || "$src" -nt "$bin" ]]; then
  swiftc -O -framework AppKit -framework ApplicationServices "$src" -o "$bin"
fi

exec "$bin" "$@"
