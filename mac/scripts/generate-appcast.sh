#!/usr/bin/env bash
#
# generate-appcast.sh — Generate a signed Sparkle appcast.xml for JPtheCat.
#
# Run after build-dmg.sh has produced the signed+notarized DMG. Reads the version from
# build/JPtheCat.app, embeds release notes generated from git history, and runs Sparkle's
# generate_appcast against the DMG with the dedicated keychain key (account `jpthecat`).
#
# Signing key (headless, no keychain GUI prompt): the dedicated EdDSA private key is exported once
# to a file OUTSIDE the repo. Default: ~/.config/jpthecat/sparkle_ed25519_priv.key. If that file is
# absent, falls back to the keychain account `jpthecat` (which prompts the first time per binary).
#   Re-export with: tools/sparkle/bin/generate_keys -x <file> --account jpthecat
#
# Environment (optional):
#   JPTHECAT_ED_KEY_FILE           Path to the exported EdDSA private key (default: ~/.config/jpthecat/…)
#   JPTHECAT_ED_KEYCHAIN_ACCOUNT   Keychain account fallback (default: jpthecat)
#   JPTHECAT_NOTES_SINCE_TAG       Widen the notes git range base (corrective next-version re-surface)
#   JPTHECAT_NOTES_HTML            Path to a pre-built release-notes HTML fragment to embed instead of
#                                  generating from git (corrective re-sign of an already-built version —
#                                  never hand-edit the signed appcast; re-run this script with override)

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RROOT="$(cd "$REPO_ROOT/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="JPtheCat"
# DMG is hosted on Supabase Storage (public `releases` bucket) behind the branded Supabase custom
# domain. The raw project host remains an emergency fallback, but manifests/appcasts should prefer
# api.jpthecat.com. Override via JPTHECAT_RELEASES_BASE.
CANONICAL_RELEASES_BASE="https://api.jpthecat.com/storage/v1/object/public/releases"
SUPABASE_RELEASES_BASE="${JPTHECAT_RELEASES_BASE:-$CANONICAL_RELEASES_BASE}"
APPCAST_TOOL="tools/sparkle/bin/generate_appcast"
ED_ACCOUNT="${JPTHECAT_ED_KEYCHAIN_ACCOUNT:-jpthecat}"
ED_KEY_FILE="${JPTHECAT_ED_KEY_FILE:-$HOME/.config/jpthecat/sparkle_ed25519_priv.key}"
APP_BUNDLE="build/${APP_NAME}.app"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
OUTPUT="build/appcast.xml"
ARCHIVES_DIR="build/archives"

info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
step() { printf "\033[1;36m  ->\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }

render_notes_section() {
	local category="$1"
	local rows
	rows="$(awk -F '\t' -v category="$category" '$1 == category { print "<li>" $2 "</li>" }' "$NOTES_ROWS")"
	if [ -n "$rows" ]; then
		echo "<ul>"
		printf "%s\n" "$rows"
		echo "</ul>"
	fi
}

[ "$SUPABASE_RELEASES_BASE" = "$CANONICAL_RELEASES_BASE" ] \
	|| [ "${JPTHECAT_ALLOW_NON_CANONICAL_RELEASE_HOST:-false}" = true ] \
	|| fail "release base must be ${CANONICAL_RELEASES_BASE} (set JPTHECAT_ALLOW_NON_CANONICAL_RELEASE_HOST=true only for an intentional fallback)"

[ -d "$APP_BUNDLE" ]   || fail "App bundle not found at ${APP_BUNDLE} — run build-dmg.sh first"
[ -x "$APPCAST_TOOL" ] || fail "Sparkle generate_appcast not found at ${APPCAST_TOOL}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="build/${APP_NAME}-${VERSION}.dmg"
[ -f "$DMG_PATH" ] || fail "DMG not found at ${DMG_PATH}"

info "Generating signed appcast for ${APP_NAME} v${VERSION} (key account: ${ED_ACCOUNT})"

# Isolate the archives dir to exactly THIS run's inputs every time — always wiped and rebuilt from
# scratch, never left to accumulate stale DMGs/appcast.xml/notes from a prior local run.
/bin/rm -rf "$ARCHIVES_DIR"; mkdir -p "$ARCHIVES_DIR"
cp "$DMG_PATH" "$ARCHIVES_DIR/"

# [Delta updates] Fetch the last few PUBLISHED releases' DMGs so generate_appcast (which has BUILT-IN
# delta generation — confirmed via its own --help text) can compute BinaryDelta patches from each of
# them to this version, letting upgrading users download a small patch (~2-3% of the DMG size in
# practice) instead of the full DMG. Supabase Storage already retains every past DMG forever (nothing
# is ever deleted there), so this is just fetching material that already exists — no new retention
# policy needed. Sourced from git tags (the release script always tags AND uploads together, so tags
# are a reliable proxy for "what's actually on Supabase"). A missing/unreachable historical DMG is
# NOT fatal — generate_appcast just computes fewer (or zero) deltas for those and the release
# continues as a full-DMG-only update, exactly like today's shipped behavior. Bounded at 5 (matches
# generate_appcast's own --maximum-deltas default) so this never grows unbounded release after release.
MAX_DELTA_SOURCES=5
info "Fetching up to ${MAX_DELTA_SOURCES} past releases for delta generation"
PAST_TAGS="$(git -C "$RROOT" tag --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]' | grep -v "^v${VERSION}\$" | head -n "$MAX_DELTA_SOURCES" || true)"
FETCHED_DELTA_SOURCES=0
if [ -n "$PAST_TAGS" ]; then
	while IFS= read -r tag; do
		[ -n "$tag" ] || continue
		past_version="${tag#v}"
		past_dmg="${APP_NAME}-${past_version}.dmg"
		past_url="${SUPABASE_RELEASES_BASE}/${past_dmg}"
		if curl -fsSL "$past_url" -o "${ARCHIVES_DIR}/${past_dmg}" 2>/dev/null; then
			FETCHED_DELTA_SOURCES=$((FETCHED_DELTA_SOURCES + 1))
			step "Fetched ${past_dmg} (delta source)"
		else
			step "Skipped ${past_dmg} (not reachable — no delta from this version, not fatal)"
			/bin/rm -f "${ARCHIVES_DIR}/${past_dmg}"
		fi
	done <<< "$PAST_TAGS"
fi
if [ "$FETCHED_DELTA_SOURCES" -eq 0 ]; then
	step "No past releases fetched — this release will ship as a full-DMG-only update (no deltas)"
fi

# Start from a CLEAN feed: generate_appcast APPENDS to an existing appcast.xml, so a stale prior
# run leaves dead older-version items (e.g. a pre-Supabase GitHub URL) in the published feed.
/bin/rm -f "$OUTPUT"

# Release notes HTML (Sparkle embeds a <dmgbasename>.html sitting next to the archive). JPtheCat's
# git history is the changelog, so never require or mutate a hand-maintained CHANGELOG file here.
# The notes should be useful and JP-voiced: cute enough to be ours, strict enough to name real work.
NOTES_HTML="${ARCHIVES_DIR}/${APP_NAME}-${VERSION}.html"
NOTES_ROWS="${ARCHIVES_DIR}/${APP_NAME}-${VERSION}-notes.tsv"
PREVIOUS_TAG="$(git -C "$RROOT" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
# Latest-release notes: Sparkle notes cover PREVIOUS_TAG..HEAD — only what changed in THIS release,
# never a roll-up of every same-day micro-release. Each update's notes describe that version alone.
# A release whose commits are ALL internal (perf/docs/refactor/chore — stripped by category() below)
# therefore yields empty notes and FAILS the no-empty-notes gate on purpose: surface a real
# customer-facing change, or widen the range explicitly with JPTHECAT_NOTES_SINCE_TAG for a corrective
# re-surface. (The public /release web page keeps its own per-day browsable history; that is a
# separate human surface, not the Sparkle feed.)
if [ -n "${JPTHECAT_NOTES_SINCE_TAG:-}" ]; then
	NOTES_BASE_TAG="$JPTHECAT_NOTES_SINCE_TAG"
	step "Notes base tag override: ${NOTES_BASE_TAG}"
else
	NOTES_BASE_TAG="$PREVIOUS_TAG"
fi
if [ -n "$NOTES_BASE_TAG" ]; then
	LOG_RANGE="${NOTES_BASE_TAG}..HEAD"
else
	LOG_RANGE="HEAD"
fi

# Corrective re-sign path: when an already-published version shipped too-technical notes, set
# JPTHECAT_NOTES_HTML to a full HTML fragment (same shell as the git-generated notes: style + h2 +
# ul + fine print) and re-run this script against the existing notarized DMG. The signed appcast is
# regenerated — never hand-edited. When unset, notes still come only from filtered git history.
NOTES_OVERRIDE="${JPTHECAT_NOTES_HTML:-}"
if [ -n "$NOTES_OVERRIDE" ]; then
	[ -f "$NOTES_OVERRIDE" ] || fail "JPTHECAT_NOTES_HTML is set but not a readable file: ${NOTES_OVERRIDE}"
	cp "$NOTES_OVERRIDE" "$NOTES_HTML"
	# Minimal non-empty rows so downstream section helpers stay happy if ever re-used; the HTML
	# override is the source of truth that generate_appcast embeds.
	printf 'app\t(overridden)\n' > "$NOTES_ROWS"
	step "Using override release notes from ${NOTES_OVERRIDE}"
else

# [Regression, fixed 2026-07-10] Scope notes to the NATIVE-APP build inputs (mirrors
# release-jpthecat.sh's BUILD_DIRTY set): a commit that only touches web/, _docs/, or release tooling
# never changed the shipped app, so it must NEVER appear in the app's Sparkle notes. This PATH gate
# complements the subject-text category() filter below — the text filter alone let web-only marketing
# commits ("Swap in high-res landscape … image", "Move … showcase under the accuracy section") and a
# _docs/backlog commit ("Remove shipped analytics backlog item") through, because their subjects read
# like features; they leaked into a real dry-run of v1.024. A commit is app-relevant iff it touches
# the same inputs that determine the notarized binary.
APP_NOTE_PATHS="mac/Sources mac/Package.swift mac/Package.resolved mac/JPtheCat.entitlements mac/JPtheCatWidgetExtension.entitlements mac/JPtheCatWidgetExtension-Info.plist mac/AppIcon.icns mac/tools mac/Info.plist"

if ! git -C "$RROOT" log --no-merges --format='%s' "$LOG_RANGE" -- $APP_NOTE_PATHS 2>/dev/null | awk '
	function trim(value) { sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value); return value }
	function escape(value) {
		gsub(/&/, "\\&amp;", value)
		gsub(/</, "\\&lt;", value)
		gsub(/>/, "\\&gt;", value)
		return value
	}
	function category(lower,   rest) {
		if (lower ~ /^docs(\([^)]*\))?:/ || lower ~ /documentation|doc-truth|todos/) return "docs"
		# [Regression, fixed 2026-07-09] The checks above only caught a conventional "docs:" prefix or
		# the literal word "documentation" — a PLAIN-ENGLISH internal-doc commit ("Move incident
		# narratives out of CLAUDE.md into the engineering log", "Fix stale NSAlert doc left behind by
		# the CLAUDE.md restructure") matched none of them and fell through to the "app" default,
		# shipping straight into a real Sparkle release users saw (v1.018). Any mention of a doc
		# file/artifact or doc-editing language is ALWAYS internal, regardless of phrasing.
		if (lower ~ /\.md([^a-z]|$)/ || lower ~ /(^|[^a-z])(claude\.md|agents\.md|readme|changelog|engineering[ -]log|engineering[ -]notes?)([^a-z]|$)/) return "docs"
		# [Regression, fixed 2026-08-12] `docs?` is word-bounded, so it matches "doc"/"docs" but NOT
		# "document"/"documents" — and the line above only tests the literal "documentation". A
		# comment-and-doc grooming pass phrased as a declarative sentence ("Every document and code
		# comment states its constraint once, and nothing else") therefore matched no doc rule, fell
		# through to the "app" default, and shipped as a customer bullet in the v1.096 Sparkle notes.
		# Code comments and documents are never a user-visible surface: always internal.
		if (lower ~ /(^|[^a-z])(docs?|documents?|comments?|code comments?|doc comment|doc entr(y|ies)|narrative|narratives|restructure|stale)([^a-z]|$)/) return "docs"
		if (lower ~ /^(test|ci|build|release|package|scripts?)(\([^)]*\))?:/) return "release"
		if (lower ~ /appcast|sparkle|dmg|notar|vercel|supabase|release note|manifest|workflow|smoke|gate/) return "release"
		# [Escape hatch, added 2026-07-27] An explicit `[notes]` tag makes an otherwise-internal commit
		# customer-facing. This exists because a PERF-ONLY release is a real and recurring shape — v1.083
		# cut sustained CPU by >90%, which is exactly the kind of change a user notices, yet every one of
		# its commits was `perf:`/`test:`/`docs:` and the filter stripped them all, yielding empty notes
		# and (correctly) aborting the release. The fix is NOT to make `perf:` broadly customer-facing:
		# the overwhelming majority of perf commits are mechanical and must keep being dropped, and a
		# blanket rule would leak them. Opting IN per commit keeps the default conservative while making
		# the honest case expressible. The tag itself never reaches users — the `[...]` strip below
		# removes it from the rendered bullet, same as `[deploy]`.
		if (lower ~ /\[notes\]/) return "app"
		# perf/style join refactor/chore as always-internal build types: a `perf(core): …` or
		# `style(app): …` commit is mechanical, never a customer note. They MUST be caught by this
		# type-prefix check because the paren heuristics below no longer see the `type(scope)` prefix.
		if (lower ~ /^(refactor|chore|perf|style)(\([^)]*\))?:/) return "internal"
		# [Regression, fixed 2026-07-11] The bare-symbol heuristics below judge the commit BODY, not the
		# conventional-commit prefix: a scoped `feat(pricing):`/`fix(mac):` prefix is itself shaped like a
		# `foo(bar)` call, so running these against the whole subject misclassified EVERY scoped feat/fix
		# as internal and produced empty notes (blocked v1.025). Strip a leading `type(scope):` prefix
		# into `rest` first; the type is already handled by the checks above.
		rest = lower
		sub(/^[a-z]+(\([^)]*\))?:[[:space:]]*/, "", rest)
		# Internal/mechanical work written as a plain subject (no conventional prefix) still leaks code
		# into user notes. Skip subjects that read as engineering rather than feature+impact: a code
		# symbol/selector like foo(bar:) or foo(), or mechanical keywords (refactor, extract, move to
		# Core, with tests, rename, dedupe). Keeps concise user-facing bullets, drops the plumbing.
		# [Regression, fixed 2026-07-11] The paren char classes deliberately EXCLUDE the comma: a
		# comma-separated parenthetical is a natural-language ENUMERATION (a real feature listing what
		# it added — "Add four terminal theme packs (Kanagawa Wave, Oceanic Next, Cobalt2, Synthwave)"),
		# NOT an engineering shorthand/code symbol like "(shell rc)"/"(audit-only)"/"foo(bar:)" (which
		# never contain commas). Without this, that themes-headline commit was miscategorized internal
		# and dropped from the v1.029 notes, shipping a release that never named its own marquee feature.
		if (rest ~ /[a-z_][a-z0-9_.]*\([a-z0-9_: ]*\)/) return "internal"
		# A space before the paren still reads as engineering shorthand ("enablement (shell rc)",
		# "wiring (audit-only)") even though it dodges the tight symbol-call regex above.
		if (rest ~ /[a-z][a-z0-9_.-]* +\([a-z0-9_: -]+\)/) return "internal"
		if (lower ~ /(^|[^a-z])(refactor|extract|inline|rename|dedupe|reword|move to core|with tests?|add (unit )?tests?|unit test|as pure)([^a-z]|$)/) return "internal"
		# Provider/parser plumbing and process language — this app'\''s own provider work is explicitly
		# audit-only/non-marketed until promoted (see AGENTS.md "Providers"), so
		# "parser"/"CLI wiring"/"audit-only" describe internal groundwork, never a shipped feature.
		# "review findings"/"pre-release review"/"regression" are process language about HOW the work
		# was found, not WHAT changed for the user.
		if (lower ~ /(^|[^a-z])(parser|cli wiring|audit.only|otel|review findings?|pre-release review|regression)([^a-z]|$)/) return "internal"
		# A `--css-custom-property` or "shared … token" name is an implementation detail, not a
		# user-visible change description.
		if (lower ~ /--[a-z][a-z0-9-]*|shared[[:space:]]+(design[[:space:]]+)?token/) return "internal"
		# Dev-tooling / agent-harness work (skills, slash commands, editor/harness dirs) is not an app
		# feature and must never render as a customer note.
		if (lower ~ /(^|[^a-z])(agent skills?|slash command|\.claude|\.codex|\.factory)([^a-z]|$)/) return "internal"
		# "hack"/"chrome" (this app'\''s own vocabulary for its UI-chrome layer) and a raw URL path
		# immediately followed by an HTTP status code are all developer-facing, never customer language.
		if (lower ~ /(^|[^a-z])(hack|chrome)([^a-z]|$)/) return "internal"
		if (lower ~ /\/[a-z][a-z0-9\/-]* [0-9]{3}([^0-9]|$)/) return "internal"
		return "app"
	}
	{
		subject = trim($0)
		lower = tolower(subject)
		if (subject == "") next
		if (lower ~ /^release:/) next
		if (lower ~ /version metadata|release metadata/) next
		# A CamelCase/PascalCase identifier (TrendStrip, ClaudeLimitsRow, …) leaking into the subject is
		# always an internal code-symbol reference — checked on the ORIGINAL case, since category()
		# only ever sees the lowercased text. Exempt the product'\''s own brand name ("JPtheCat"), which
		# is legitimately CamelCase-shaped but must never be excluded from its own release notes.
		camel_subject = subject
		gsub(/JPtheCat/, "", camel_subject)
		# [notes] must be checked BEFORE the CamelCase filter. That filter matches
		# `Upper lower Upper lower`, so it fires on names like "MiMo" and "OpenCode" but never on a
		# single-capital one like "Nemotron" or "Grok" — which is why only two-word provider names need
		# the hatch. It cannot promote docs/release commits; those are internal by category.
		# Guards: ReleaseNotesWorkflowTests
		# testNotesTagCarriesACamelCaseProviderNameThatIsOtherwiseDropped and
		# testSingleCapitalVendorNamesNeedNoNotesHatch.
		if (lower ~ /\[notes\]/) {
			cat = category(lower)
			if (cat == "docs" || cat == "release") cat = "internal"
		} else {
			cat = (camel_subject ~ /[A-Z][a-z]+[A-Z][a-z]+/) ? "internal" : category(lower)
		}
		# Notes are user-facing: strip build/ship tags like [deploy] and any
		# leading conventional-commit type prefix so the bullet reads as a plain
		# sentence about what changed, not a technical commit subject.
		subject = trim(subject)
		gsub(/\[[^]]*\]/, "", subject)
		sub(/^[a-z]+(\([^)]*\))?:[[:space:]]*/, "", subject)
		# Strip an internal roadmap "Phase N:" prefix — planning jargon, not user language.
		sub(/^[Pp]hase[[:space:]]*[0-9]+[[:space:]]*(-|:|—)?[[:space:]]*/, "", subject)
		subject = trim(subject)
		# Capitalize the first letter so a de-prefixed bullet still reads as a sentence.
		if (subject != "") subject = toupper(substr(subject, 1, 1)) substr(subject, 2)
		if (subject == "") next
		# Release notes are customer-facing ONLY. Doc/operator, release-machinery, and
		# internal-grooming commits never reach users; drop them entirely.
		if (cat != "app") next
		print cat "\t" escape(subject)
		count += 1
	}
	END { if (count == 0) exit 2 }
' > "$NOTES_ROWS"; then
	fail "release notes are empty for ${LOG_RANGE}; add a meaningful customer-facing app commit before publishing"
fi

{
	echo '<style>body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;padding:14px 18px;line-height:1.55;color:#1c1b19;background:#fffaf0}h2{font-size:16px;margin:0 0 6px}h3{font-size:13px;margin:14px 0 4px;color:#8a4a17;text-transform:uppercase;letter-spacing:.04em}.lede,.fine{font-size:12px;margin:0 0 10px;color:#6b6254}ul{margin:0 0 8px 18px;padding:0}li{font-size:13px;margin-bottom:5px}</style>'
	echo "<h2>Small paws, strict standards. Here are the improvements:</h2>"
	render_notes_section "app"
	echo '<p class="fine">Built with ❤️ from San Francisco and Honolulu.</p>'
} > "$NOTES_HTML"
step "Release notes generated from git history (${LOG_RANGE})"
fi  # end of git-generated notes (skipped when JPTHECAT_NOTES_HTML is set)

DOWNLOAD_PREFIX="${SUPABASE_RELEASES_BASE}/"

# --maximum-versions 1: keep the PUBLISHED feed to exactly one <item> (the latest release) — the past
# DMGs fetched above are raw material for delta computation only, never published as their own feed
# entries (a Sparkle client always targets the newest item; it doesn't need old versions listed to
# receive a delta FROM its current version TO that newest item). --maximum-deltas 5: compute a delta
# from up to 5 of those past versions. Verified empirically (not assumed) against this app's own real
# v1.019→v1.020 DMGs before shipping this: a real ~442KB delta was produced (vs the ~17MB full DMG,
# roughly 97% smaller), --download-url-prefix correctly rewrote the sparkle:deltaFrom url= the same
# way it rewrites the main enclosure, and BinaryDelta apply reconstructed a byte-identical, still
# codesign-valid, still Gatekeeper-"Notarized Developer ID"-accepted app from the old app + delta.
if [ -f "$ED_KEY_FILE" ]; then
	step "Signing with exported key file (headless): ${ED_KEY_FILE}"
	cat "$ED_KEY_FILE" | "$APPCAST_TOOL" \
		--ed-key-file - \
		--download-url-prefix "$DOWNLOAD_PREFIX" \
		--embed-release-notes \
		--maximum-versions 1 \
		--maximum-deltas 5 \
		-o "$OUTPUT" \
		"$ARCHIVES_DIR"
else
	step "Key file not found — using keychain account '${ED_ACCOUNT}' (may prompt on first run)"
	"$APPCAST_TOOL" \
		--account "$ED_ACCOUNT" \
		--download-url-prefix "$DOWNLOAD_PREFIX" \
		--embed-release-notes \
		--maximum-versions 1 \
		--maximum-deltas 5 \
		-o "$OUTPUT" \
		"$ARCHIVES_DIR"
fi

[ -f "$OUTPUT" ] || fail "generate_appcast did not produce ${OUTPUT}"

# Enclosure must be EdDSA-signed (SURequireSignedFeed / SUVerifyUpdateBeforeExtraction).
grep -q 'sparkle:edSignature' "$OUTPUT" || fail "appcast missing sparkle:edSignature — signing failed"
step "Enclosure EdDSA-signed"

# The enclosure URL must point at the public Supabase release object.
grep -q "${DOWNLOAD_PREFIX}${APP_NAME}-${VERSION}.dmg" "$OUTPUT" \
	|| fail "appcast enclosure URL is not the expected Supabase release URL"
step "Enclosure URL → Supabase Storage"

if command -v xmllint >/dev/null 2>&1; then
	xmllint --noout "$OUTPUT" || fail "appcast.xml is not well-formed XML"
	step "xmllint OK"
fi

DELTA_COUNT="$(find "$ARCHIVES_DIR" -maxdepth 1 -name '*.delta' | wc -l | tr -d ' ')"
if [ "$DELTA_COUNT" -gt 0 ]; then
	step "Generated ${DELTA_COUNT} delta update(s) for upgrading users"
else
	step "No deltas generated this run (no reachable past DMG, or first release) — full DMG only"
fi

step "Appcast written: ${OUTPUT}"

# Purge Sparkle's extraction cache. generate_appcast extracts every archive it processes (now
# including the past-version DMGs fetched above for delta computation) into a content-addressed cache
# under ~/Library/Caches/Sparkle_generate_appcast/<sha>/, and never prunes it itself — left alone it
# accumulates one full JPtheCat.app per archive ever processed, forever (observed pre-deltas: 142
# copies / 1.8 GB from a NON-delta workload). Since the archives dir is rebuilt from scratch every run
# anyway (nothing here depends on cross-run cache reuse), clearing it after each successful run keeps
# local disk bounded at the cost of re-extracting on the next release — an acceptable tradeoff for an
# infrequent release script.
SPARKLE_APPCAST_CACHE="${HOME}/Library/Caches/Sparkle_generate_appcast"
if [ -d "$SPARKLE_APPCAST_CACHE" ]; then
	/bin/rm -rf "$SPARKLE_APPCAST_CACHE"
	step "Purged Sparkle appcast extraction cache"
fi
