#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
	printf 'app-demo parity: %s\n' "$1" >&2
	exit 1
}

# Resolve a native source by its CANONICAL repo path, falling back to the same basename anywhere
# under mac/Sources when that exact path is gone. The literal paths below stay literal on purpose:
# `AppDemoParityGuardTests` greps THIS file for them and asserts each still exists, so a real move is
# still reported to a human by name — the fallback only keeps this scan from going dark in the
# meantime. Fails closed: neither missing nor ambiguous resolves to a silent pass.
resolve_swift() {
	local canonical="$ROOT/$1"
	if [ -f "$canonical" ]; then
		printf '%s\n' "$canonical"
		return 0
	fi
	local matches
	matches="$(find "$ROOT/mac/Sources" -type f -name "$(basename "$1")" | sort)"
	[ -n "$matches" ] || fail "missing native source $1 (and no same-named file under mac/Sources)"
	if [ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" != "1" ]; then
		fail "ambiguous native source $1 under mac/Sources: $(printf '%s ' $matches)"
	fi
	printf '%s\n' "$matches"
}

# The native dashboard face is one mirror spread over several files: the card root + chrome + footer +
# selector rows (DASHBOARD), the provider-focus detail bay (PROVIDER_DETAIL), the header readout
# (HERO), the first-run scene (FIRST_RUN), and the footer's share cluster (SHARE). Positive checks
# below name ONE file on purpose — which file owns a surface is part of what this guard asserts — but
# every NEGATIVE runs across all of them, so a retired control cannot come back by moving into a
# sibling file the old check no longer reads. Splitting DashboardView.swift again means adding the new
# file HERE; a face-scoped check that keeps reading only the old file is a check that stopped looking.
DASHBOARD="$(resolve_swift mac/Sources/JPtheCatApp/DashboardView.swift)"
DASHBOARD_STATE="$(resolve_swift mac/Sources/JPtheCatApp/DashboardState.swift)"
PROVIDER_DETAIL="$(resolve_swift mac/Sources/JPtheCatApp/ProviderDetailView.swift)"
HERO="$(resolve_swift mac/Sources/JPtheCatApp/DashboardHeroReadout.swift)"
FIRST_RUN="$(resolve_swift mac/Sources/JPtheCatApp/DashboardFirstRunView.swift)"
SHARE="$(resolve_swift mac/Sources/JPtheCatApp/DashboardShareControls.swift)"
SETTINGS="$(resolve_swift mac/Sources/JPtheCatApp/SettingsBackView.swift)"
WIDGET="$(resolve_swift mac/Sources/JPtheCatApp/WidgetGalleryOpener.swift)"
THEME="$(resolve_swift mac/Sources/JPtheCatApp/Theme.swift)"
TOKENS="$(resolve_swift mac/Sources/JPtheCatApp/JPAppDesignTokens.swift)"
SPARKLINE="$(resolve_swift mac/Sources/JPtheCatCore/Presentation/SparklineScale.swift)"
# The selector badge words themselves now live ONLY here (the dashboard renders `ProviderBasis.badge`),
# so the mac/web badge-vocabulary comparison has to read this table too.
BASIS="$(resolve_swift mac/Sources/JPtheCatCore/Providers/ProviderBasis.swift)"
OFFICIAL_USAGE="$(resolve_swift mac/Sources/JPtheCatApp/OfficialUsageLink.swift)"
MODEL_NAME="$(resolve_swift mac/Sources/JPtheCatCore/Presentation/ModelName.swift)"
# The homepage demo card is one mirror spread over several modules: the dashboard face + card root
# (DEMO), the settings face (DEMO_SETTINGS), the chrome + card footer both faces share (DEMO_CHROME),
# the menu-bar display cycle (DEMO_FORMAT), the modal dialogs (DEMO_DIALOGS), and the data helpers
# (DEMO_SERIES). Every one of them is scanned below — a check that only reads DEMO after its subject
# moved into a sibling module is a guard that stopped looking, which is worse than a failing one.
DEMO="$ROOT/web/components/site/menubar-demo.tsx"
DEMO_SETTINGS="$ROOT/web/components/site/menubar-demo-settings.tsx"
DEMO_CHROME="$ROOT/web/components/site/menubar-demo-chrome.tsx"
DEMO_FORMAT="$ROOT/web/components/site/menubar-demo-format.ts"
DEMO_AUDIO="$ROOT/web/components/site/menubar-demo-audio.ts"
DEMO_DIALOGS="$ROOT/web/components/site/demo-dialogs.tsx"
ANALYTICS_DEMO="$ROOT/web/components/site/advanced-analytics-demo.tsx"
DEMO_SERIES="$ROOT/web/components/site/menubar-demo-series.ts"
NAV="$ROOT/web/components/site/nav.tsx"
TODOS="$ROOT/_docs/todos.md"

require_file() {
	[ -f "$1" ] || fail "missing source $1"
}

require_contains() {
	local file="$1"
	local needle="$2"
	grep -Fq "$needle" "$file" || fail "$file missing: $needle"
}

require_absent() {
	local file="$1"
	local needle="$2"
	if grep -Fq "$needle" "$file"; then
		fail "$file must not contain: $needle"
	fi
}

# Every demo module at once. Positive checks always name ONE module (which face owns the surface is
# the whole point of this guard); the negatives run across all of them, so a retired control cannot
# come back by moving into a sibling module the old check no longer read.
DEMO_MODULES=(
	"$DEMO"
	"$DEMO_SETTINGS"
	"$DEMO_CHROME"
	"$DEMO_FORMAT"
	"$DEMO_AUDIO"
	"$DEMO_DIALOGS"
)

require_absent_demo() {
	local needle="$1"
	local file
	for file in "${DEMO_MODULES[@]}"; do
		require_absent "$file" "$needle"
	done
}

# Every file the native dashboard face is spread over (see the note beside DASHBOARD above).
DASHBOARD_FACE=(
	"$DASHBOARD"
	"$PROVIDER_DETAIL"
	"$HERO"
	"$FIRST_RUN"
	"$SHARE"
)

require_absent_dashboard() {
	local needle="$1"
	local file
	for file in "${DASHBOARD_FACE[@]}"; do
		require_absent "$file" "$needle"
	done
}

for file in "${DASHBOARD_FACE[@]}" "$SETTINGS" "$WIDGET" "$THEME" "$TOKENS" "$SPARKLINE" "$MODEL_NAME" \
	"$BASIS" "${DEMO_MODULES[@]}" "$ANALYTICS_DEMO" "$DEMO_SERIES" "$NAV" "$TODOS"; do
	require_file "$file"
done

# settings chrome: native app is source of truth; homepage demo mirrors the same token locations.
require_contains "$TOKENS" "static let chromeHeight: CGFloat = 32"
require_contains "$TOKENS" "static let chromeControlGap: CGFloat = 4"
require_contains "$TOKENS" "static let chromeControlSize: CGFloat = 26"
require_contains "$DASHBOARD" "HStack(spacing: JPAppSpacing.chromeControlGap)"
require_contains "$DASHBOARD" "MenuBarDisplayCycleButton("
require_contains "$DASHBOARD" "SettingsLink { setShowingSettings(true) }"
# Pin belongs to the Settings face only. Asserted across the WHOLE dashboard face, not just its root
# file: a negative scoped to one file of a split surface can be satisfied by moving the control.
require_absent_dashboard "PinButton(isPinned: chrome.isPinned"
require_contains "$SETTINGS" "HStack(spacing: JPAppSpacing.chromeControlGap)"
require_contains "$SETTINGS" "MenuBarDisplayCycleButton("
require_contains "$SETTINGS" "DashboardBackLink(action: onClose)"
require_contains "$SETTINGS" "PinButton(isPinned: chrome.isPinned"
require_contains "$SETTINGS" "WidgetGalleryButton()"
require_contains "$SETTINGS" "UpdateStatusDot(currentVersion: appVersion)"

# Footer actions belong in DashboardCardFooter on both faces, not as settings rows or dashboard chrome.
require_contains "$DASHBOARD" "DashboardCardFooter("
require_contains "$DASHBOARD" "onRefresh: { model.refresh() }"
require_contains "$DASHBOARD" "onOpenWebsite: { SettingsBackView.open(\"https://jpthecat.com\") }"
require_absent "$SETTINGS" "ChromeRefreshButton"
require_contains "$SETTINGS" "onOpenWebsite: { Self.open(\"https://jpthecat.com\") }"
require_absent "$SETTINGS" "title: \"Refresh now\""
require_absent "$SETTINGS" "title: \"Open JP the Cat website\""

# Homepage mirror: no duplicate outer title strip, native 32px/26px/4px rhythm, canonical site URL.
# The chrome row exists twice — ChromeBar (dashboard face, in DEMO_CHROME) and the settings face's own
# inline bar — so assert BOTH call sites, not just "somewhere in the card".
require_contains "$DEMO_CHROME" "flex h-8 items-center gap-2 bg-card pr-3.5 pl-4"
require_contains "$DEMO_SETTINGS" "flex h-8 items-center gap-2 bg-card pr-3.5 pl-4"
require_contains "$DEMO_CHROME" "ml-auto flex items-center gap-1"
require_contains "$DEMO_SETTINGS" "ml-auto flex items-center gap-1"
require_contains "$DEMO_CHROME" "grid h-[26px] w-[26px] place-items-center rounded-[7px]"
# Both faces carry the menu-bar cycle button with the identical label.
require_contains "$DEMO" 'label={`Cycle menu bar display — current: ${MENU_BAR_FORMATS[menuBarFormat].title}`}'
require_contains "$DEMO_SETTINGS" 'label={`Cycle menu bar display — current: ${MENU_BAR_FORMATS[menuBarFormat].title}`}'
require_contains "$DEMO_CHROME" "aria-label=\"Open JP the Cat website\""
require_contains "$DEMO_CHROME" "href={SITE.url}"
require_absent_demo "ml-0.5 grid h-[17px] w-[17px]"
require_absent_demo ">Settings<"

# Hero chart scaling is native-owned: per-provider, min-anchored, with the same 15% headroom floor.
require_contains "$SPARKLINE" "public static let headroomFraction = 0.15"
require_contains "$SPARKLINE" '($0 - lo) / denom'
require_contains "$DEMO_SERIES" "const SPARKLINE_HEADROOM_FRACTION = 0.15"
require_contains "$DEMO_SERIES" "function sparklineFractions"
require_contains "$DEMO_SERIES" "Math.max(hi - lo, hi * SPARKLINE_HEADROOM_FRACTION, 0.000001)"
require_contains "$DEMO_SERIES" "return values.map((v) => (v - lo) / denom)"
require_absent_demo "scaleMax"
require_absent_demo "v / scaleMax"

# Every model remains visible, without a top-N cap. Native tiles now fill by token usage;
# the frozen homepage keeps its compact version-first presentation.
require_contains "$PROVIDER_DETAIL" "ForEach(ProviderDetailLayout.modelsByUsage(row.byModel7d))"
MODEL_LAYOUT="$(resolve_swift 'mac/Sources/JPtheCatApp/ProviderDetailLayout.swift')"
require_contains "$MODEL_LAYOUT" 'models.sorted'
require_contains "$MODEL_LAYOUT" 'return $0.usage.total > $1.usage.total'
require_contains "$MODEL_NAME" "sortsBeforeForCompactDisplay"
require_contains "$MODEL_NAME" 'tokens.contains("sol")'
require_contains "$DEMO_SERIES" "function orderModelLinesForDisplay"
require_contains "$DEMO_SERIES" 'tokens.includes("sol")'
# `derive()` (which builds the per-provider byModel rows via orderModelLinesForDisplay) was moved
# next to its data in menubar-demo-series.ts so it's unit-testable; verify the ordering call there.
require_contains "$DEMO_SERIES" "byModel: orderModelLinesForDisplay("

# Expanded Advanced Analytics: native geometry and the homepage mirror share the same two-column
# window, provider focus/checklist, measures, grains, readouts, and cost-basis disclosures.
require_contains "$TOKENS" "static let analyticsWindowW: CGFloat = 960"
require_contains "$TOKENS" "static let analyticsWindowH: CGFloat = 1000"
require_contains "$TOKENS" "static let analyticsSidebarW: CGFloat = 252"
require_contains "$ANALYTICS_DEMO" "w-[min(96vw,960px)]"
require_contains "$ANALYTICS_DEMO" "grid-cols-[minmax(0,1fr)_252px]"
require_contains "$ANALYTICS_DEMO" "max-h-[calc(100dvh-96px)]"
require_contains "$ANALYTICS_DEMO" "bg-card px-3.5"
require_absent "$ANALYTICS_DEMO" "h-[min(90vh,1000px)]"
require_absent "$ANALYTICS_DEMO" "pl-16"
require_contains "$ANALYTICS_DEMO" "Daily trend · last {days} days"
require_contains "$ANALYTICS_DEMO" "Token mix · last {days} days"
require_contains "$ANALYTICS_DEMO" 'values={["Calendar", "Rhythm", "Model × Day"] as const}'
require_contains "$ANALYTICS_DEMO" 'values={["Events", "Tokens", "$"] as const}'
require_contains "$ANALYTICS_DEMO" 'MEASURE_OFFSET: Record<Measure, number> = { Events: 3, Tokens: 6, $: 9 }'
require_contains "$ANALYTICS_DEMO" "peakCallout"
require_contains "$ANALYTICS_DEMO" "px-[22px] py-4"
require_contains "$ANALYTICS_DEMO" "dialog.showModal()"
require_contains "$ANALYTICS_DEMO" "<option value={7}>last 7 days</option>"
require_contains "$ANALYTICS_DEMO" "TABLE_HEADERS.map"
require_contains "$ANALYTICS_DEMO" 'dispatch({ type: "sort", key })'
require_contains "$ANALYTICS_DEMO" 'title="CSV, JSON, and Markdown export are available in the JP the Cat app"'
require_contains "$ANALYTICS_DEMO" "Cursor shows tokens (estimate, excluded from $"

# Selector basis badges share real/notional vocabulary. Non-aggregable rows present as local on both
# dashboard surfaces while Advanced Analytics retains the underlying estimate basis.
# A real-dollar provider must never fall back to an unbadged row on either surface — its basis would
# then only be readable by the ABSENCE of a pill.
# The native `.available` arm used to be the literal ternary `row.notional ? "notional" : "real"`; it
# now derives from Core's `ProviderBasis` table, so this pins the DERIVED expression instead. Same
# invariant, new spelling — never delete these lines, repoint them.
require_contains "$DASHBOARD" "switch ProviderBasis.of(rawID: row.id) {"
require_contains "$DASHBOARD" "case .real: return ProviderBasis.real.badge"
require_contains "$DASHBOARD" "case .notional: return ProviderBasis.notional.badge"
require_contains "$DASHBOARD" "case .estimate: return ProviderBasis.estimate.badge"
require_contains "$DASHBOARD" 'guard row.isAggregable else { return "local" }'
require_contains "$BASIS" 'case .real: "real"'
require_contains "$BASIS" 'case .notional: "notional"'
require_contains "$BASIS" 'case .estimate: "estimate"'
require_contains "$DEMO" ': "real"'
require_contains "$DEMO" 'return "local"'
require_contains "$DEMO" "bg-sage/20"
require_contains "$DASHBOARD_STATE" 'LOCAL TOKENS · TODAY'
require_contains "$DEMO" 'LOCAL TOKENS · TODAY'

# A quota-shaped selector meter has exactly TWO honest sources on both surfaces: an OFFICIAL window
# with a reset still ahead, or a MEASURED gateway window (OpenCode Go's local cost against the
# provider's published caps, which has no boundary to age out). A self-relative activity share is
# still never quota-shaped on either side, and a measured window never claims a reset countdown.
require_contains "$DASHBOARD_STATE" "func selectorQuota(now: Date = Date())"
require_contains "$DASHBOARD_STATE" "func detailPlanMeters(now: Date = Date())"
require_contains "$PROVIDER_DETAIL" "row.detailShowsWeeklyWindow"
require_contains "$SETTINGS" "SettingsBackView.grokPlanUsage"
require_contains "$DASHBOARD_STATE" "guard isContributing, quotaIsMeasured else { return nil }"
require_contains "$DASHBOARD_STATE" "if usageOfficial {"
require_contains "$DEMO_SERIES" "const officialQuota = p.windows?.find("
require_contains "$DEMO_SERIES" "const measuredQuota = p.windows?.find((w) => w.measured"
require_contains "$DEMO_SERIES" "const quota = officialQuota ?? measuredQuota;"
# The measured badge word is shared vocabulary: native `measured`, demo `measured`, never `official`.
require_contains "$PROVIDER_DETAIL" 'badgeWord: isGatewayRow ? "measured" : nil'
require_contains "$DEMO" 'win.official ? "official" : win.measured ? "measured" : "est."'
# A measured window carries no reset boundary, so neither surface may compute burn pace from one.
require_contains "$DEMO_SERIES" "if (w.measured || !w.official || w.resetsInMin <= 0 || w.windowMinutes <= 0) return null;"

# Credits keep distinct units and matching disclosure on both shared detail surfaces.
require_contains "$PROVIDER_DETAIL" 'Credits remaining'
require_contains "$DEMO" 'Credits remaining'
require_contains "$PROVIDER_DETAIL" 'Separate from the included allowance and notional dollars.'
require_contains "$DEMO" 'Separate from the included allowance and notional dollars.'
require_contains "$DEMO_SERIES" 'credits:'

# Official provider usage destinations must stay byte-identical across native and web surfaces.
for usage_url in \
  'https://claude.ai/settings/usage' \
  'https://chatgpt.com/settings/usage?tab=overview' \
  'https://grok.com/?_s=usage' \
  'https://dev.meta.ai/usage/' \
  'https://github.com/settings/copilot/features' \
  'https://cursor.com/dashboard/spending' \
  'https://opencode.ai/console'; do
  require_contains "$OFFICIAL_USAGE" "$usage_url"
  require_contains "$DEMO_SERIES" "$usage_url"
done
# OpenCode's console is per-workspace: native builds `<console>/<wrk_…>/{billing,go}` from the locally
# detected ID and shows NO link without one; the demo, with no signed-in workspace, links the root.
require_contains "$OFFICIAL_USAGE" 'openCodeWorkspaceID'
require_contains "$OFFICIAL_USAGE" '/billing")'
require_contains "$OFFICIAL_USAGE" '/go")'
require_contains "$OFFICIAL_USAGE" 'View official '
require_contains "$OFFICIAL_USAGE" '("Cursor", "https://cursor.com/dashboard/spending")'
require_contains "$OFFICIAL_USAGE" '("Grok", "https://grok.com/?_s=usage")'
require_contains "$OFFICIAL_USAGE" '("Zen",'
require_contains "$OFFICIAL_USAGE" '("Go",'
require_contains "$DEMO_SERIES" 'text: "Cursor"'
require_contains "$DEMO_SERIES" 'text: "Grok"'
require_contains "$DEMO_SERIES" 'text: "Zen"'
require_contains "$DEMO_SERIES" 'text: "Go"'
require_contains "$DEMO_SERIES" 'usageLinkLabel: "View official Cursor or Grok plan usage."'
require_contains "$DEMO_SERIES" 'usageLinkLabel: "View official Zen or Go usage."'

# Mobile homepage chrome must not cover the demo card; the header sticks only at desktop widths.
require_contains "$NAV" "md:sticky"
require_absent "$NAV" "className=\"sticky top-0"

# Privacy disclosure lives on public trust/legal surfaces, not in the native or demo Settings face.
require_absent "$TODOS" "Privacy & data"
require_absent "$TODOS" "Privacy link"
require_absent "$TODOS" "Homepage demo mirrors all three"

# Widget guidance and theme controls must remain mirrored by source, not duplicated in homepage prose.
require_contains "$WIDGET" "macOS doesn't let apps open the widget gallery"
require_contains "$THEME" "Sunlit Ledger"
require_contains "$THEME" "Midnight Ledger"
# The Appearance switcher IS mirrored on the demo now: a compact ThemePickerRow (2 free swatches + a
# "More themes" tile) plus the full-catalog ThemesPopup, backed by demo-themes.ts (parity-tested against
# Theme.swift by tests/demo-theme-catalog.test.ts). The palette hex itself stays sourced from Theme.swift.
require_contains "$DEMO_SETTINGS" "function ThemePickerRow"
require_contains "$DEMO_SETTINGS" "function ThemesPopup"
# WidgetPopup is rendered from the demo card but defined in the extracted demo-dialogs.tsx; verify both
# the usage (DEMO) and the definition + widget-gallery explanation copy (DEMO_DIALOGS).
require_contains "$DEMO" "WidgetPopup"
require_contains "$DEMO_DIALOGS" "export function WidgetPopup"
require_contains "$DEMO_DIALOGS" "macOS doesn't let apps open the widget gallery"

# Two independent positive rosters: native/catalog parity plus the frozen homepage controls.
(cd "$ROOT/web" && bun test tests/provider-catalog-parity.test.ts tests/homepage-providers.test.tsx) || fail "provider membership contracts failed"
printf 'app-demo parity: ok\n'
