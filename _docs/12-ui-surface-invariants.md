# Native UI Surface Invariants

Settled native UI contracts for the dashboard, windows, menu bar, alerts and typography.

Settled contracts for the shipped macOS surfaces; read the matching section before changing one.
The incidents behind them are in [00-foundation.md](00-foundation.md).

Dashboard, settings, and analytics have curated homepage counterparts in `web/components/site/menubar-demo.tsx` and `advanced-analytics-demo.tsx`.
The [homepage boundary](02-design-system.md#homepage-provider-boundary) fixes their roster and design independently of native geometry; shared units, provenance, badges, actions, and themes retain semantic parity.
The Application Menu and the dashboard layout toggle are native-only and have no demo mirror.
`scripts/verify-app-demo-parity.sh` + `AppDemoParityGuardTests` prove structural parity only, never that a new prop was threaded through — compare the changed surface side by side.

## Dashboard Selector UI

Every row uses the same 18pt icon box and 16pt image (`SelectorRowIconMetrics`).
The all-providers row shows the bare JP mark with no chip; provider rows show a raw-brand-tint chip with a white glyph.

Basis badges use `real` = sage, `official` = sage, and `notional` = honey across both dashboard surfaces.
Every available, aggregable provider row carries `real`, `official`, or `notional`; a real-dollar or official-plan provider must never render unbadged.
The native and web dashboards present a non-aggregable provider as `local` in the row's own `vizTint`; Advanced Analytics retains the underlying `estimate` basis for those rows.
The `local` badge is independently tappable and opens `EstimateExplainerPopover`.

A `Button` nested inside another `Button`'s label gets no independent tap target on macOS.
`SelectorRow` is therefore THREE sibling `.buttonStyle(.plain)` controls (select-button, badge-button, and an amount select-button sharing the leading button's action); the card chrome lives on the enclosing `HStack`.
`selectorMeter` needs an explicit `.frame(minWidth: 20, maxWidth: .infinity)`, and the badge-plus-amount group keeps `.layoutPriority(1)`.

Provider rows show a quota-shaped meter for exactly two honest sources: a current OFFICIAL pool (a rolling window or explicitly labeled billing cycle), or a MEASURED gateway window (`ProviderRow.quotaIsMeasured`, badged `measured`, never `official`).
`ProviderRow.selectorQuota(now:)` and the official billing-pool fallback `selectorPlanMeter(now:)` are the semantic sources; either suppresses the trend sparkline.
Otherwise `ProviderRow.selectorTrendSeries` supplies selected-window dollars for priced providers, or tokens for free, fully unpriced, and non-aggregable rows.
Never turn self-relative `estimatedSharePct` or aggregate spend share into a quota-shaped percentage; `estimatedSharePct` only drives the hero's `~NN% activity` text when no window exists.
A measured window stays OUT of the widget's official limit capsule, the spoken "N% used" value, and every alert; its monthly bar is provider-detail only.
Indexed rows must supply `UsageWindowSummary.dailyTokenSeries`; the event fallback must produce the same daily buckets.
Persisted menu-bar formats resolve display names through `ProviderCatalog.shortName`.
Fills render their current width directly and never animate on refresh.

The all-providers row is a compact sparkline heartbeat (`PulseDot` / `PulseSparklineShape` / `SelectorRowMeterMetrics`): a ball rides the full-width line on a 28s `TimelineView(.animation)` sweep (a bigger period is slower; never shrink it).
The ball emits the same radar-ping ring as `SparkChart`'s end dot, the drawn path and `y(atXFraction:in:verticalInset:)` share one inset, and `pulseFrameHeight` stays 18pt so the 7pt ball keeps vertical swing.
The line fills the full meter column (never a fixed `pulseWidth` cap), and the row renders `badge: nil`; basis is disclosed by the ticker band.
Reduce Motion skips the timeline.
Guard: `SelectorRowMeterMetricsTests`.

Clicking a provider row opens its detail; clicking it again returns to the aggregate (`select(nil)`).
Provider detail links to the provider-owned usage or account page only when a verified stable destination exists.
One provider with two official pages gets one sentence with two linked words (`OfficialUsageLink.sentence(for:openCodeWorkspaceID:)`): Grok links Cursor and Grok, and OpenCode links Zen and Go.
A row with `sourceSections` (OpenCode) shows its scope note and usage sentence once, then each source as a labeled section without its own note or link.

### Compact label badges

Effort, basis, availability, quota provenance, estimate, onboarding, analytics, and widget label badges share `LabelBadgeMetrics`: 17pt outer height and 5pt horizontal insets, independent of text, font, or border.
Native labels apply `labelBadgeLayout()` before their background and inset border; the widget uses the same metrics, and the web demos mirror them through `.demo-badge` with border-box sizing.
A border must never add to a badge's outer height.
Effort tones are one map on both platforms: Low and Medium sit on paper behind a `line` hairline, and High uses the honey wash, honey border, and `ginger-deep` text (`ProviderDetailView`, web `components/site/effort-tone.ts`).
Menu-bar readouts, icon chips, buttons, theme swatches, and larger marketing or library badges keep their own roles.
Guard: `LabelBadgeLayoutTests`.

## Dashboard Window & Chrome

AppKit-owned, SwiftUI-hosted window with two fixed-width layouts, intrinsic height, no internal scrolling, and no blank tail.
`DashboardLayout` owns the widths: one column is 384pt and two columns is 768pt, the default.
`DashboardLayoutButton` in the chrome of both faces cycles them; `SettingsStore` persists the choice under `JPtheCat.dashboard.layout`, and `DashboardView` injects it through `\.dashboardLayout`.
A layout never changes accounting, row order, badges, or which information appears; the homepage keeps its fixed 384px single-column card.

In two columns, the selector uses two equal 366pt columns, a 12pt gap, and 2pt row spacing; All providers and the selected detail span the full card.
Provider detail places 5-hour and 7-day gauges in two columns, each reset attached to its gauge; a monthly window spans the width above that pair, and a single available short or weekly window spans the width with no empty column.
Reported model-specific limits follow in descending usage; one reported model limit also spans the width.
Model tiles fill two columns by descending total tokens (`ProviderDetailLayout.modelsByUsage`), with name ties and no top-N cap; the meter compares tokens with tokens even when priced and unpriced models share a provider.
Tiles group by `ModelIdentity.presentationID`, so a gateway route, snapshot date, or `[1m]` never splits one model; a free tier keeps its own tile with a `free` label.
A model without an effort tier shows no badge, and its empty 42pt slot keeps meter length equal.
Settings keeps its JP support card full-width above two columns: General and Live data left, Alerts and Appearance right.

One column stacks the same content in reading order: 5-hour, 7-day, then monthly; model rows keep name, meter, amount, and effort on one line with the name taking a third of the card.
`DashboardDetailGrid` caps every grid at the layout's column count, so call sites need no layout branch.

A layout switch keeps the card's top and trailing edges, so the toggle stays under the pointer (`DashboardWindowSizing.frameAfterLayoutSwitch`).
`StatusBarController` captures the frame synchronously when the setting changes, then re-anchors on the window's resize notification.
A growing detail preserves the top edge when possible, then shifts inside the visible display frame; it never shrinks text or hides information to fit.
Settings/dashboard transitions are opacity crossfades, never 3D flips.

The dashboard starts pinned (`DashboardChromeState.isPinned`), and the pin is not persisted.
`DashboardWindowPresence` is the one level and Space configuration for the dashboard and its child windows: pinned means `.floating`, `canJoinAllSpaces`, and `fullScreenAuxiliary`, with `hidesOnDeactivate` false; unpinned drops to `.normal` on the current Space.
Clicking another app does not hide, close, or miniaturize the window; the menu-bar item is the quick show and hide control.

Shared 32pt chrome row: `JP the Cat` left, icon-only controls right — dashboard face `MenuBarDisplayCycleButton` + `DashboardLayoutButton` + gear; settings face `MenuBarDisplayCycleButton` + `DashboardLayoutButton` + pin/widget/`gauge.medium`.
Refresh never belongs in either top bar.
`DashboardLayoutButton` draws the CURRENT layout, voices `Dashboard layout` with the layout as its value, and its tooltip names the next layout.
BOTH faces lead their trailing cluster with `RotationIndicatorLight`: a small `JP.sage` dot that pulses ONLY while `settings.menuBarDisplayFormat.isRotating`, collapses to zero width otherwise, and honors Reduce Motion (web: `RotationLight`/`isRotatingFormat`).

Both faces share ONE footer (`DashboardCardFooter`): freshness caption, Refresh, Advanced Analytics, Help, `UpdateStatusDot`, Quit, JP mark — Quit sits immediately before the JP mark.
Every footer icon shares the same 18x18 hit target (`DashboardFooterActionButton`, `AdvancedAnalyticsFooterButton`, `UpdateDotButton`); the 26x26 `chromeControlSize` is a top-chrome size only.
`DashboardFreshness` is display-only: `TimelineView` may tick the label but never starts a refresh, stale begins after 5 minutes without a successful refresh, a failed refresh reads `Refresh failed · updated <age>`, and freshness stays out of `DashboardView.surfaceSizingKey`.
The footer JP mark opens the share popover headed `Tell others about JP`; X / Twitter copy appends `@8bit`.
The `Built with YEN` credit belongs on the website footer, never the native app.

The basis-label ticker band (`BasisLabelChip`/`TickerTapeText`) is locked to 18pt height with shared motion across the aggregate and provider focus.
Every Settings boolean uses `SettingsToggleRow` with a fixed trailing switch slot; chevron rows are only for navigation and one-shot commands such as Test meow.

## Advanced Analytics Window

Opened from `AdvancedAnalyticsFooterButton` on both faces.
It is an AppKit CHILD window of the single `dashboardWindow` via `addChildWindow(_:ordered:)`, so Quit, Dock-hide, close, and ordering propagate for free.
The controller does not observe parent moves (native child tracking handles them); only a parent RESIZE triggers `reposition()`, and once the user drags the tray (`userMovedTray`) auto-repositioning stops for that session.
The hosting controller sets `safeAreaRegions = []` so the chrome row draws inline with the traffic lights; the footer divider is an `.overlay(..., alignment: .top)`, never a standalone `rule`.
`reload()` cancels the previous load task and `.onDisappear` cancels the live one; `export()` guards re-entrancy with `isExporting`.
**[CRITICAL] Both must be `Task.detached`, and `loadData`/`loadRows` must stay `nonisolated`.**
A `View` conformance infers `@MainActor`, so a bare `Task {}` runs the SQL scans on the main thread and makes every `cancel()` dead code.

Layout: a 960x1000 two-column deep-dive with no internal scroll.
The left canvas owns the hero, stat tiles, provider trends, token mix, Calendar / Rhythm / Model x Day heatmaps with drill-down, and the sortable model table; the 252pt sidebar owns provider focus, include/export checkboxes, the Events / Tokens / $ measure, basis key, and export.
`open()` sizes via `setContentSize`, not `preferredContentSize`, and the window stays `.resizable` at `analyticsWindowMinW/H`.
The table footnote is bottom-pinned to line up with the sidebar's bottom-pinned `exportButton` (web: `min-[760px]:mt-auto`).

- **Fixed-height budget.** Every left-canvas section stays bounded: the model table renders at most `modelTableMaxRows` rows sorted over the full set, discloses the remainder as included in Export, and reserves room for trend rows via `visibleModelRowLimit(providerCount:)`.
  Verify against a running window: `mac/scripts/gui-verify.sh frame "Export analytics (CSV, JSON, or Markdown)"` must sit above the bottom edge.
- **The chrome row is top-pinned.** `AdvancedAnalyticsTrayView.body` hands its body exactly `geo.size.height - chromeHeight - 1` and `.clipped()`s it; a plain `VStack` overflows symmetrically.
- **Every grain fills the canvas width.** All heatmap grains flex cell WIDTH at fixed row height; `LabeledHeatmapGrid.fittedLayout` sizes Rhythm and Model x Day (guard: `HeatmapFillWidthTests`).
- **Calendar grain = whole months** via `CalendarMonthLayout`; in-month days outside the timeframe render recessive (guard: `CalendarMonthLayoutTests`).
- **Every checkable provider has a trend slot.** `trendProviderOrder` equals `providerOptions`, and trends wrap at four columns (guard: `AnalyticsProviderCoverageTests`).

Copilot bypasses `UsageIndex`, so its rows come from a separate fetch through `ModelDaySummary.bucketed(events:calculator:)` merged into the same `rows`.

## Live Data Window

`LiveDataWindowController` (`LiveDataWindow.swift`) hosts the per-provider enable and opt-in live-limit toggles.
It is a CHILD of `dashboardWindow` with `safeAreaRegions = []`, anchored left of the dashboard.
Four deliberate divergences from the analytics window — do not "fix" them back:
- **It must become key** (`makeKeyAndOrderFront`), because AppKit renders switches desaturated gray in a non-key window.
- **Height is intrinsic, width fixed** (`liveDataWindowW`): measure `fittingSize` after `layoutSubtreeIfNeeded()` and `setContentSize` BEFORE anchoring; never `.preferredContentSize`, a fixed height, or a `ScrollView`.
- **No section eyebrow inside**; the chrome title already says "Live data".
- **Rows are grouped by provider in ONE well**: each enable row is followed by its dependent opt-in rows, inset by `JPAppSpacing.liveDataChildIndent`, with a `LiveDataGroupDivider` hairline between providers and none inside a group; every row carries the real brand-mark chip through `SettingsToggleRow`/`AnalyticsProviderMark`, and detection-gated rows stay hidden until the tool is present.

**Subtitles wrap, never ellipsize** (`SettingsToggleRow(layout: .liveData)` plus `fixedSize(horizontal: false, vertical: true)`), because the wrapped height is what `fittingSize` measures; that layout also uses the switch-width slot (`liveDataSwitchSlotWidth`) and tighter `liveDataRowY` so fifteen rows fit a 13" display, while the one-line, shrink-to-80% default stays on the Settings face, whose intrinsic height `DashboardSizingTests` pins.
Each subtitle states the row's accounting in order: basis (real spend, notional list price, token estimate, or gateway view), the surfaces it reaches (totals, widgets, alerts), and for an opt-in what the switch installs and which official window (5-hour, weekly, billing-cycle, or measured-against-cap) it unlocks; the disabled line names every surface the provider leaves.
Cursor CLI live data feeds the one Grok row at notional list price (`ProviderID.consolidated`), so its copy never says "its own row" or "not in totals"; the OpenCode gateways share one `OpenCode` dashboard row and a `gateway`-badged widget entry and are never summed.
Detection is one `LiveDataWindowContent.Detection` value: production builds it only through `probe()` and re-probes on appear; `init(model:detection:)` lets a test pin `.everything` or an empty value without weakening a gate.
Guards: `LiveDataWindowLayoutTests` (wrap, last-row fit, gating under fixtures), `ProviderOptInRowTests`, `SettingsCopyTests`.

`LiveDataWindowContent` lives in `SettingsBackView.swift` so it can reuse the private rows, and observes `ThemeManager`.
Turning a provider off removes it from the dashboard entirely, not a zeroed row.

## Themes Window

`ThemesWindowController` (`ThemesWindow.swift`) is a 1:1 clone of the Live Data window shell hosting `ThemesWindowGrid`, the full `JPTheme.all` catalog in a two-column grid of `ThemeSwatchTile` (`large` variant).
It opens from the Appearance picker's "More themes" tile (`onOpenThemes` -> `StatusBarController.toggleThemes()`).
Every tile is selectable; there is no lock or upsell (web: `ThemesPopup`).

## Settings Face Sizing

The Settings face is intrinsic-height with NO scrolling (guard: `DashboardSizingTests`).
Fold small disclosures into an existing section rather than adding a header.
The Appearance picker is ONE compact row (2 free themes + "More themes"), and "Live data" is ONE `Providers & live limits` row opening the Live Data window; never re-inline either list (web: `NavRow` opening `LiveDataPopup`).
Support is ONE General-section `Support report` row (no honey promo card at the top of the face; web demo: `NavRow` opening the redacted support modal).
The `Open source` row follows it and opens the public repository (`SettingsBackView.repositoryURL`; web demo: `NavRow` opening `SITE.repoUrl`).

The provider opt-in rows (Claude live limits, Grok live limits, Copilot OTel, Cursor hook) are ONE `ProviderOptInRow` driven by `ProviderOptInDescriptor` values; add a descriptor, never copy the row.
`ProviderOptInIntent.resolve(requested:isOn:state:)` lets only `.installable` reach the install alert; `reconcileStaleCapture` stays optional (Claude and Grok only).
Guard: `ProviderOptInRowTests`.
A row that changes what a provider reports forces an immediate `model.refresh(reindex: true)`.
A toggle's on/off state derives from ONE ground-truth signal: `ProviderOptInRow.isInstalled` is `state == .active` only, and `captureIsFresh` may refine text but never the switch.

## Application Menu

`MainMenu.build` is the top-of-screen menu while JP is frontmost: App (About / Settings… ⌘, / Services / Hide / Quit), Edit, Window, Help last.
Window starts with Close (`⌘W` → `NSWindow.performClose(_:)`), then Minimize / Zoom / Bring All to Front.
Help is assigned to `NSApplication.shared.helpMenu`, and `JP the Cat Help` opens `https://jpthecat.com`.
Use `NSApplication.shared`, never the `NSApp` IUO, when assigning `servicesMenu` / `windowsMenu` / `helpMenu`; `NSApp` is nil in XCTest and traps.
Guard: `MainMenuTests` builds the real `NSMenu`.

## Menu Bar Display Format & Status Pill

`MenuBarDisplayFormat` is a struct (`kind` + optional `providerID` + optional `window`), not a fixed enum.
`selectable(providers:)` builds `Total`, a dedicated `Total + <provider> <window>` and `<provider> <window>` choice per live window, plus rotating `Total + limit` / `Limit` whenever more than one live window exists (including one provider with two windows).
With Claude and Codex both exposing two windows, the cycle is `Total` → `Total + Claude 5h` → `Total + Claude week` → `Total + Codex 5h` → `Total + Codex week` → `Total + limit` → `Claude 5h` → … → `Limit`.
A rotating format cycles every 3s (`StatusBarController.limitRotationInterval`); the timer runs only when `isRotating && rotatableLimits.count > 1`, and a tick redraws ONLY the pill.
`MenuBarDisplayPresentationState` is updated by that same render pass, so Settings names the metric currently visible.
Legacy provider-only persisted values remain valid.

`MenuBarLabelRenderer.rotatableLimits(from:)` emits ONE entry per live official window (300 -> `.fiveHour`, 10080 -> `.weekly`, else `.other`), and the compact pill appends `" (5hr)"` / `" (W)"` while VoiceOver speaks `windowSpoken`.
It skips official windows that round to 0% and estimate-only providers with zero tokens today.
A provider without a trustworthy quota shows today's actual tokens, the tooltip says `quota unavailable`, and VoiceOver speaks the full count.
`pillLimit(for:rotatableLimits:rotationIndex:providerLimits:)` owns selection: a rotating format shows only a filtered rotation entry and returns nil (total-only) when none qualify, never falling back to `limit(for:)`; a pinned official format defers to `limit(for:)` at any percent.
Provider labels use the SHORT name ("Claude", never "Claude Code").
Attention color is border-only and provider-limit driven (warning >=80%, critical >=95%) — never raw dollars, theme, or a token fallback.
Guard: `MenuBarLabelRendererTests`.

The status pill is a FIXED light chip (`MenuBarPillRenderer.pillImage`), never theme-following, because the menu bar's appearance is independent of the app theme.
It sizes tight to measured text via `JPAppFont.statusPillFont` with NO fixed text slot, and equal whitespace both sides (`markTextGap == textTrailingInset`, both 5pt); `NSStatusItem.length` stays pinned to the rendered image width.
After replacing the image, set `needsDisplay` and call `displayIfNeeded()` so every refresh reaches the hosted button.
`MenuBarPillRenderer` is stateless drawing: the palette and menu-bar `thickness` arrive as parameters, and geometry comes from `StatusPillMetrics` alone.
Guards: `StatusPillMetricsTests`, `MenuBarPillRendererTests`.
Any expanded aggregate dollar UI that includes notional dollars visibly says `incl notional`, accessibility value included; the compact pill may be icon+total only, but tooltip, VoiceOver, and dashboard disclose basis.
The tooltip is a multi-line summary (today, selected window, basis, official windows, freshness) with blank lines between sections, separate from the accessibility value.

## Dashboard Hero & Sparkline

The hero leads with the full-width basis-label ticker (`BasisLabelChip`), then `SplitFlapMoney` left and the provider eyebrow/window total right, with the `last N days` caption beneath.
A selected provider never inherits the aggregate split-flap or series — `today: nil` is not permission to show All providers' dollars.
Any official-plan-only window (including unified Grok with no local events) uses the official primary included-usage % in the split-flap, a plan caption on the right, basis `OFFICIAL PLAN USAGE` (weekly suffix only for a weekly primary), and `HeroOfficialQuotaMeter` instead of a flat $0 `SparkChart`.
The primary gauge may appear in hero + compact selector only: detail hides that duplicate, retains only distinct secondary pools and never reserves a blank gauge gap.
With local events, hero remains the cost/token sparkline and detail shows each pool once.
See `03-data.md` for source precedence and monthly-only semantics.
The plan-only reset countdown appears once, beneath the hero meter, never repeated in the top-right plan caption.
The chart band names the actual primary window (`7-day` or `Billing-cycle`) with a sage `official` pill and no timeframe picker.
A detail section that already names the plan uses pool-only labels such as `Weekly included usage`, never repeats the plan on each bar.
Its header comes from `CursorPlanUsage.detailHeader(providerName:)`, which never prefixes the provider name onto a plan label that already starts with it (`Grok Bot Plan · included usage`, not `Grok Grok Bot Plan`; guard: `CursorPlanUsageTests.testDetailHeaderNeverRepeatsTheProviderName`).
Selector-row trend sparklines use the 18pt sparkline height (`SelectorRowMeterMetrics.pulseFrameHeight`); the 5pt height is reserved for quota capsules only.
Pills: sage for `real` and `official`; `local` and `gateway` use the row `vizTint` wash (`gateway` opens a gateway explainer).
Priced gateway rows badge `gateway`; token-display gateways badge `local`.
The widget's official limit capsule uses `usedPercent ?? weeklyUsedPercent`; `MiniSparkline` shares Core's `SparklineScale` min-anchored mapping.

`SparkChart` auto-ranges PER PROVIDER with a MIN-anchored baseline: `y = (v - seriesMin) / max(seriesMax - seriesMin, seriesMax * 0.15, epsilon)`.
Never a shared cross-provider max and never zero-anchored; the 0.15 headroom floor keeps a near-flat series from amplifying noise.
Source of truth: `SparklineScale.fractions(_:)` (Core, pure); guard `SparklineScaleTests`.
The widget's `MiniSparkline` keeps its own glance-tuned path.

The native `By model` grid shows every model used in the window, ordered by total tokens; the homepage keeps its compact version-first order through `orderModelLinesForDisplay`, and Core `ModelName.sortsBeforeForCompactDisplay` keeps the canonical order for other consumers.
Guards: `ProviderDetailLayoutTests`, `ModelNameTests`, `ModelVersionOrderTests`, `menubar-demo-series.test.ts`.

`SplitFlapCharacter`'s `.black`/`.white` shadow and highlight are intentionally theme-independent; any change re-renders Midnight via the `JP_RENDER=1` harness and stays theme-freeze-safe.

## Timeframe, Cadence & Small Surfaces

`TimeframePicker`: 7/14/30/90 days, default 14, persisted; widening it updates EVERY window-derived figure in one refresh, and a change invalidates the in-flight refresh via `DashboardRefreshGate`.
Aggregate cost provenance is tri-state (real-only, notional-only, mixed) — never a boolean.
Provider availability is three-state: `unavailable` (excluded from aggregates, visible with a notice, no `$0` claim), `stale` (last good row kept and still contributing after a transient throw), and `available`.
When every source is unavailable the header reads `SOURCES UNAVAILABLE · TODAY` and the pill shows an em dash.
`SettingsStore` is the single `JPtheCat.*` source of truth and posts `didChangeNotification` only after a real changed value.

`RefreshCadence` (Live/Balanced/Relaxed/Battery saver) drives the ONE `RefreshSchedule` via `RefreshCoordinator.setSchedule(_:)` — never a second timer; Balanced is the 60/300 default (guard: `RefreshScheduleTests`).

The app is Dock-visible by default (`LSUIElement=false`, `.regular`) with a Settings toggle to `.accessory`; `DockIconPreference.apply` calls `setActivationPolicy` and, only when turning the icon back on, `NSApp.activate()` on the next runloop.

First-run onboarding is a dashboard card face (`OnboardingView`) gated on `SettingsStore.Key.onboardingCompleted`; `Open Settings` or `Get started` dismisses it.
The first-run empty state is a bubble bath (`ThoughtBubbles`), and the menu-bar loading indicator is a pixel grid filling bottom-up (`MenuBarPillRenderer.loadingPixelImage`) drawn in `NSColor.labelColor`, since it has no light chip behind it.

Right-click menu: disabled `JP the Cat · v<version>` header, `Refresh`, `Check for Updates…`, `Quit` — no per-provider dollar rows.
It uses the status button's contextual `NSView.menu`, not `sendAction(on:)`, and `StatusItemGeometry` supports off-primary displays with negative origins.

`UpdateStatusDot`: `JP.sage` when current, `JP.gingerDeep` when an update exists (never `JP.honey`, which fails AA); clicking runs a real Sparkle check.
The "Automatic updates" toggle binds to Sparkle's own `automaticallyChecksForUpdates`, gated on `Updater.isConfigured`.

Foregrounding and the plain-click toggle follow `mac/AGENTS.md`; a tapped alert additionally uses `showDashboardWindow(forceForeground: true)`, which briefly promotes an `.accessory` app to `.regular` (`promoteToForegroundForReveal`), while ordinary clicks never promote, so hidden-Dock mode never flashes a Dock icon.

## Alerts & Sounds

`UsageAlertCenter` fires a notification plus a meow at the first crossing of 80% (warning) and 95% (critical) of a provider's window, plus a Claude-only "likely at your limit (reading frozen)" alert (`ProviderRow.limitLikelyHit`).
Each tier is its own rising-edge `UsageAlertGate` with a distinct notification identifier, re-armed when the window's reset rolls and pruned via `pruneExpired(now:)` every refresh; a cold launch already above 95% posts one critical banner.
Three toggles default on: `alerts.usageEnabled` (master), `alerts.bannerEnabled`, `alerts.soundEnabled`; banner and meow are independent channels.
"Test meow" always gives feedback by routing on the live `getNotificationSettings` status.

Apple correctness:
- The notification delegate is assigned in `applicationDidFinishLaunching`, only for real `.app` bundles; raw SwiftPM launches never call `UNUserNotificationCenter.current()`.
- `willPresent` returns `[.banner, .list]`, and both delegate callbacks always run their completion handler.
- Authorization asks for `[.alert]` only, and only when the master and banner toggles are on (`requestBannerAuthorizationIfNeeded()`).
- The meow plays through `AVAudioPlayer`, because `UNNotificationSound` cannot play `.m4a`.
- `bannerDenialWarrants(...)` surfaces "Turn on in System Settings" when notifications are denied OR the alert style is `.none`; it is a read, never a re-request.

`web/public/meow.m4a` is the canonical JP sound, and `mac/Sources/JPtheCatApp/Resources/jp-meow.m4a` stays byte-identical to it; the global logo link stays silent.
Four synthesized UI cues are shared 1:1 between app and web: `ui-toggle-on`/`ui-toggle-off` and `ui-click-top`/`ui-click-bottom`.
`mac/scripts/generate-ui-sounds.py` regenerates them into both trees, normalized to one loudest-window RMS level (never peak-normalized), and every cue is gated on `SettingsStore.interactiveSoundsEnabled` (web: `demoUISoundsEnabled`).
Guards: `AppResourcesTests.testBundlesEveryInteractiveSoundCue`, `web/tests/ui-sound-assets.test.ts`.

## Typography

`mac/Sources/JPtheCatApp/JPAppDesignTokens.swift` owns native text and spacing roles — add a role there before introducing a new font size, padding, or spacing value.
`JPAppColor` resolves from the active `JPTheme`; change a palette value there, never at the call site.

Money-text scale: three monospaced roles — hero `metricHero` (split-flap), primary `metric` (header total, selector amounts), secondary `metricSmall` (nested detail, gauge %).
Never render money at `metricCaption`/`micro`, and every money figure routes through `MoneyFormatter`.

Native confirmations use `NSAlert(jpTitle:jpMessage:)` (`NSAlert+Spacing.swift`) with plain native layout; multi-paragraph bodies use `"\n\n"` inside the message.
Do not reintroduce a leading-newline or `accessoryView`-body spacing hack without verifying a real running alert.

## Text Inputs

**Every multi-line input is `JPTextEditorField`** (guard: `JPTextEditorFieldTests.testNoSurfaceHandRollsItsOwnPlaceholderOverlay`).
The insets are settled and derived from ONE constant; do not re-measure or tune them by eye.

`JPTextEditorFieldMetrics.contentInset` (10pt) is where the first glyph lands on both axes for both the placeholder and the typed text:

| Layer | Horizontal padding | Vertical padding | Why |
|---|---|---|---|
| `TextEditor` | `contentInset - lineFragmentPadding` (5) | `contentInset` (10) | `NSTextContainer` ADDS `lineFragmentPadding` horizontally; vertical padding applies 1:1 |
| Placeholder `Text` | `contentInset` (10) | `contentInset` (10) | a plain `Text` has neither quirk |

### Verifying a native surface by screenshot

`ImageRenderer` CANNOT draw `TextEditor` or `TextField`, so any surface holding one is verifiable only by screenshotting the running app.
1. **Kill every `MacOS/JPtheCat` process first.** `SingleInstanceGuard` lets an installed copy swallow the status-item click; check `pgrep -lf "MacOS/JPtheCat$"`.
   To test a status-item click, post real `CGEvent` mouse events at the position System Events reports for the item; `AXPress` skips `NSApp.currentEvent`.
2. **Prove the new binary is live** before trusting a pixel; a geometry change is the cheap check.
3. **Force JP frontmost immediately before `screencapture`.** `gui-verify.sh shot <winid>` fails on sheets; use a full-screen capture plus a crop.
4. **A measurement that returns your scan's starting bound is not a measurement.** Locate the control's border first and assert the hit is strictly inside it.

## Widget

The widget design is settled: Small `170x170`, Medium `364x170`, Large `364x382`, in Sunlit and Midnight, system families only (so `fullColor` rendering and no `widgetRenderingMode` branch).
- Medium omits the sparkline; content that fits Small and Large clips Medium's header.
- The limit gauge is a bare bar showing official `usedPercent ?? weeklyUsedPercent` with no caption; the accessibility value voices that percentage.
- `.contentMarginsDisabled()` with explicit per-face padding, top equal to leading.
- Notional basis (`WidgetSnapshot.disclosesNotionalBasis`, tri-state) is disclosed through `notional` badges — Small uses the same `ProviderBasisBadge` — and the accessibility value; there is no separate aggregate "incl notional" eyebrow or footer.
- Provider chips keep the raw brand tint; data-viz lifts through `ProviderTintLegibility.legibleHex(...)`, and meter grooves use the opaque `track` role.
- `placeholder(in:)` returns `WidgetPreviewData`, never a `$0` card.
- Each placed widget picks its own window (`JPWidgetTimeframeChoice`); `WidgetSnapshot.selectingWindow(days:)` runs before provider focus, and the data rule is in `mac/AGENTS.md`.
- A focused official-plan widget labels its percent `included usage` and `official`, never `today`, `last N days`, or `notional`; it has no fabricated daily sparkline or repeated window total.
- The widget is always unlocked; `WidgetAccessState` keeps its legacy cases only so older snapshots decode.
- Medium and Large keep every contributing provider; Large switches to a two-column grid above six providers, and Medium puts header and amount on one row above six.

Re-render every face at its exact size via the `ImageRenderer` harness (`JP_RENDER=1 swift test --filter UnlockedWidgetRenderTests`) in both themes before shipping, and treat a Large vertical-layout change as unverified until a real placed widget clears its footer.

## Codex credits and subscription limits

Provider detail shows the last-reported Codex credit balance and its capture time separately from subscription windows.
Credits are neither dollars nor subscription percentages, and never affect the selector gauge, menu bar, widget, alerts, headroom, or aggregate cost.
A depleted weekly allowance can coexist with available credits, and a missing five-hour window stays absent; a window's position in the payload does not define its duration.
The homepage uses labeled sample credits with the same units and disclosure.
Guards: `CodexCreditsTests`, `CodexCreditsPresentationTests`, `menubar-demo-series.test.ts`.
