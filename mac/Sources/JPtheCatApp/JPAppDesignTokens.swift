import AppKit
import JPtheCatCore
import SwiftUI

enum JPAppFont {
  static let chromeTitle: Font = .system(size: 13, weight: .semibold)
  static let chromeAction: Font = .system(size: 12, weight: .semibold)

  static let eyebrow: Font = .system(size: 10, weight: .medium, design: .monospaced)
  static let eyebrowStrong: Font = .system(size: 10, weight: .semibold, design: .monospaced)
  static let chip: Font = .system(size: 9, weight: .medium, design: .monospaced)

  static let emptyTitle: Font = .system(size: 14, weight: .semibold)
  static let body: Font = .system(size: 12.5)
  static let bodyStrong: Font = .system(size: 12.5, weight: .medium)
  static let label: Font = .system(size: 12)
  static let labelMedium: Font = .system(size: 12, weight: .medium)
  static let labelStrong: Font = .system(size: 12, weight: .semibold)
  static let rowLabel: Font = .system(size: 13)
  static let caption: Font = .system(size: 11)
  static let captionMono: Font = .system(size: 11, design: .monospaced)
  static let captionStrong: Font = .system(size: 11, weight: .semibold)
  static let micro: Font = .system(size: 10)
  static let microMedium: Font = .system(size: 10, weight: .medium)

  /// Theme-swatch tile label (the compact Appearance picker + "More themes" tile) and its larger
  /// variant in the full Themes window — the only per-surface text sizes that lived as raw
  /// `.system(size:)` literals in `ThemePickerRow` before being named here.
  static let swatchLabel: Font = .system(size: 11, weight: .medium)
  static let swatchLabelLarge: Font = .system(size: 13, weight: .medium)

  static let metric: Font = .system(size: 13, weight: .medium, design: .monospaced)
  static let metricSmall: Font = .system(size: 12, weight: .semibold, design: .monospaced)
  // periphery:ignore - documented non-money annotation role in AGENTS.md/_docs/02-design-system.md.
  static let metricCaption: Font = .system(size: 11, weight: .semibold, design: .monospaced)
  static let metricValue: Font = .system(size: 16, weight: .semibold, design: .monospaced)
  static let metricHero: Font = .system(size: 37, weight: .semibold, design: .monospaced)
  static let settingsPrice: Font = .system(size: 22, weight: .semibold, design: .monospaced)
  /// The Advanced Analytics window's oversized money hero — the dashboard split-flap hero (`metricHero`,
  /// 37pt) scaled up ~1.25× for the large two-column analytics canvas. Monospaced so the digits stay
  /// column-aligned like every other money figure. Documented money role (see AGENTS.md "Money-text scale").
  static let analyticsHero: Font = .system(size: 46, weight: .semibold, design: .monospaced)

  static let settingsIcon: Font = .system(size: 12, weight: .medium)
  static let chevron: Font = .system(size: 9, weight: .semibold)
  static let menuChevron: Font = .system(size: 8, weight: .semibold)
  /// Icon-only chrome controls (Settings/Pin/back-to-dashboard/widget-gallery/theme-toggle
  /// glyphs) share one glyph size so the top-bar cluster can never desync.
  static let chromeIcon: Font = .system(size: 11, weight: .semibold)
  /// Numbered step chips in the widget-gallery guidance alert.
  static let stepNumeral: Font = .system(size: 12, weight: .bold, design: .rounded)

  nonisolated(unsafe) static let statusItemFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
  nonisolated(unsafe) static let statusPillFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
}

enum JPAppSpacing {
  static let chromeHeight: CGFloat = 32
  static let chromeLeading: CGFloat = 16
  static let chromeTrafficLightInset: CGFloat = 80
  static let chromeTrailing: CGFloat = 14
  static let chromeControlGap: CGFloat = 4
  static let chromeControlSize: CGFloat = 26
  static let chromeControlX: CGFloat = 7
  static let chromeControlY: CGFloat = 3
  /// Gap between the `JP the Cat 🐾` title and its optional `— Subtitle` in the shared `ChromeTitleRow`.
  /// One value so the six former hand-rolled chrome rows (which had drifted to 0/6/8) stay identical.
  static let chromeTitleGap: CGFloat = 6
  /// Fixed glyph box shared by the icon-only chrome controls, so top-bar clusters stay
  /// pixel-aligned across faces.
  static let chromeGlyphW: CGFloat = 16
  static let chromeGlyphH: CGFloat = 15
  /// Shared footer-icon hit target (Refresh / Advanced Analytics / Help / Quit / the JP mark / the
  /// update dot). The footer analogue of `chromeGlyphW/H` — every footer glyph uses this one box so
  /// their spacing reads even (a footer control on the 26pt `chromeControlSize` looked uneven).
  static let footerIconBox: CGFloat = 18

  static let contentX: CGFloat = 18
  static let panelX: CGFloat = 16
  static let headerTop: CGFloat = 8
  static let headerBottom: CGFloat = 12
  static let sectionY: CGFloat = 12
  static let footerY: CGFloat = 10
  static let rowX: CGFloat = 8
  static let rowY: CGFloat = 6
  static let settingsRowX: CGFloat = 10
  static let settingsRowY: CGFloat = 8
  /// Trailing switch slot for Settings toggle rows. Keep the row title/subtitle area from changing
  /// width as AppKit/SwiftUI redraws a switch during click tracking.
  static let settingsSwitchSlotWidth: CGFloat = 76

  // Card / pill / callout insets — named so the dashboard + settings surfaces retune in one place
  // instead of scattering raw .padding() literals across call sites.
  static let selectorFooterX: CGFloat = 12  // aggregate selector footer row (paired with footerY)
  static let emptyStateY: CGFloat = 16  // first-run / empty-state vertical inset
  static let noticeX: CGFloat = 10  // dashboard notice / callout card
  static let noticeY: CGFloat = 8
  static let metricCardX: CGFloat = 9  // composition metric card
  static let metricCardY: CGFloat = 7
  static let ctaPillX: CGFloat = 16  // accent CTA pill horizontal padding
  static let ctaPillY: CGFloat = 6
  static let settingsBodyY: CGFloat = 14  // settings body vertical inset + inter-section gap
  static let panelInset: CGFloat = 14  // settings panel all-sides inset

  // Advanced Analytics window — the large two-column deep-dive surface (fixed inputs sidebar + flexible
  // readout canvas). Named here so the window/sidebar/canvas/heatmap geometry retunes in ONE place
  // instead of scattering the 960/940/252/… magic numbers across the analytics view + controller (the
  // design system forbids inline sizes — add a role first). Default height is sized so the whole left
  // canvas (hero → stat tiles → FULL-WIDTH small-multiples trend row → FULL-WIDTH token-mix row → grain
  // switcher + heatmap + peak callout → model table; the section eyebrow lives in the chrome bar) fits
  // with NO scroll bar at the 14-day default. The full-width trend and token-mix rows (stacked, not side
  // by side) give each visualization the whole canvas width but cost ~60pt of height over the old
  // side-by-side strip, so the default height carries that headroom. The Rhythm grid's 7-row orientation
  // and the single-heatmap-at-a-time grain switcher keep the heatmap area bounded. The window is
  // resizable, so an unusually long table can enlarge past the min.
  static let analyticsWindowW: CGFloat = 960
  static let analyticsWindowH: CGFloat = 1000
  static let analyticsWindowMinW: CGFloat = 900
  static let analyticsWindowMinH: CGFloat = 800
  static let analyticsSidebarW: CGFloat = 252

  // The dedicated "Live data" window (`LiveDataWindowController`). Narrower than the analytics deep-dive
  // — it re-hosts the single-column Settings "Live data" section. Only the WIDTH is fixed; the height is
  // intrinsic (the hosting controller uses `.preferredContentSize`), so the window fits its content
  // exactly with no dead space and grows a row taller as providers are added.
  static let liveDataWindowW: CGFloat = 420

  // The dedicated "Themes" window (`ThemesWindowController`). Fixed width for a 2-column, larger,
  // readable theme grid; height is intrinsic (`fittingSize`) over the deterministic `JPTheme.all`
  // catalog, so it fits exactly with no dead space and grows only as themes are added.
  static let themesWindowW: CGFloat = 380
  static let analyticsCanvasX: CGFloat = 22  // left readout-canvas horizontal inset
  static let analyticsCanvasY: CGFloat = 16  // canvas top/bottom inset
  static let analyticsSectionGap: CGFloat = 16  // vertical gap between canvas sections
  static let analyticsSidebarX: CGFloat = 16  // sidebar content horizontal inset
  static let analyticsSidebarGap: CGFloat = 16  // gap between sidebar sections
  static let analyticsTileGap: CGFloat = 10  // gap between the three mini-stat tiles
  static let analyticsHeatmapCell: CGFloat = 15  // one heatmap cell (square)
  static let analyticsHeatmapGap: CGFloat = 3  // gap between heatmap cells
}

// MARK: - Color

/// Canonical app palette — every color resolves from the ACTIVE `JPTheme` (`ThemeManager.shared`),
/// so switching theme re-colors the whole app. Roles mirror `web/app/globals.css` "Sunlit Ledger";
/// `typealias JP = JPAppColor` keeps the short `JP.paper` call site. SwiftUI reads the `Color`
/// accessors (re-read when an observing view re-renders on a theme change — the `DashboardView` root
/// observes `ThemeManager`); AppKit chrome reads the `*NS` `NSColor` accessors and redraws on the
/// `ThemeManager.didChangeNotification`. Adding a theme is a data change in `Theme.swift` only.
enum JPAppColor {
  private static var t: JPTheme { JPTheme.current }

  static var paper: Color { Color(hex: t.paper) }
  static var card: Color { Color(hex: t.card) }
  static var paper2: Color { Color(hex: t.paper2) }
  static var ink: Color { Color(hex: t.ink) }
  static var inkSoft: Color { Color(hex: t.inkSoft) }
  static var inkFaint: Color { Color(hex: t.inkFaint) }
  static var line: Color { Color(hex: t.line) }
  static var lineStrong: Color { Color(hex: t.lineStrong) }
  static var ginger: Color { Color(hex: t.ginger) }
  static var gingerDeep: Color { Color(hex: t.gingerDeep) }
  static var sage: Color { Color(hex: t.sage) }
  // periphery:ignore - named palette role documented in _docs/02-design-system.md.
  static var sageSoft: Color { Color(hex: t.sageSoft) }
  static var honey: Color { Color(hex: t.honey) }
  // periphery:ignore - named palette role documented in AGENTS.md/_docs/02-design-system.md.
  static var creamDeep: Color { Color(hex: t.creamDeep) }
  static var gold: Color { Color(hex: t.gold) }
  /// Red/pink attention role — one of the five distinct, legible token-mix composition-bar segment
  /// tints (input/output/cache-5m/cache-1h/cache-read). A real palette role in every `JPTheme`; this
  /// accessor exposes it so the analytics token-mix bar reads as five distinct hues (never gold).
  static var coral: Color { Color(hex: t.coral) }
  static var cta: Color { Color(hex: t.cta) }
  static var ctaDeep: Color { Color(hex: t.ctaDeep) }
  /// Deep green for label text on a translucent sage chip (the "official" gauge badge).
  static var sageDeep: Color { Color(hex: t.sageDeep) }
  /// Label color drawn ON the `[cta, ctaDeep]` accent button — theme-flipped so it never paints white
  /// on a bright accent (the old `.white`-on-ginger CTA failed WCAG-AA on both themes).
  static var ctaText: Color { Color(hex: t.ctaText) }
  /// The primary CTA fill — the top→bottom `[cta, ctaDeep]` gradient shared by every accent button
  /// (empty-state unlock, onboarding "Start tracking", accent pills). One definition so
  /// the accent gradient can't drift across those call sites. Button shape/padding stays per-surface.
  static var ctaGradient: LinearGradient {
    LinearGradient(colors: [cta, ctaDeep], startPoint: .top, endPoint: .bottom)
  }
  /// Empty-meter/track groove — deliberately distinct from `card` on both themes (on the dark card,
  /// `paper2` collapses to the card color, so bar/gauge tracks need their own visible role).
  static var trackFill: Color { Color(hex: t.track) }
  /// Opacity for a share/model bar's FILL over its `trackFill` groove. On the dark card the legible
  /// (lifted-gray) provider tints sit close to the gray track, so the fill must be near-solid to read
  /// as a distinct filled portion; on light the saturated brand tints stay soft at the shipped 0.55.
  static var barFillOpacity: Double { t.isDark ? 0.9 : 0.55 }

  // AppKit chrome — the dashboard window background is theme-aware. (The menu-bar pill is a fixed
  // light chip drawn from `JPTheme.sunlit` in `StatusBarController`, so it needs no theme accessor.)
  static var cardNS: NSColor { NSColor(jpHex: t.card) }

  // Per-provider tint hexes (mirror web `--color-p-*`); the All-providers aggregate uses the active
  // ginger. These are theme-INDEPENDENT brand strings (also read off-main when building ProviderRow),
  // so legibility on the active theme is resolved at the view layer via `providerTint(_:)`.
  static var aggregateTintHex: String { "#\(t.ginger)" }
  static let claudeTintHex = "#D6783F"
  static let codexTintHex = "#2F2F33"
  static let copilotTintHex = "#8957E5"
  static let cursorTintHex = "#4A4A52"
  /// xAI / Grok brand black — lifted for dark-card legibility via `providerTint(_:)`.
  static let grokTintHex = "#111111"
	/// Grok Bot desktop client — slightly lifted from Grok Build black for mark legibility.
	static let grokBotTintHex = "#243B55"
	/// Meta Muse Spark — Meta blue, distinct from Claude terracotta and Gemini's lighter blue.
	static let museSparkTintHex = "#0866FF"
	/// NVIDIA Nemotron — NVIDIA green, distinct from Claude terracotta and Grok black.
	static let nemotronTintHex = "#76B900"
	/// Xiaomi MiMo — coral red, distinct from Claude terracotta and Muse Spark blue.
	static let mimoTintHex = "#E74856"
	/// pi.dev Big Pickle — teal, distinct from DeepSeek blue and Gemini blue.
	static let bigPickleTintHex = "#0D9488"
	/// DeepSeek — deep blue, distinct from Muse Spark blue and Gemini blue.
	static let deepSeekTintHex = "#1A56DB"
	/// OpenCode Zen / Go gateway rollups. Zen keeps OpenCode's established amber; Go gets a distinct
	/// teal-slate so the two gateway rows never read as the same provider.
	static let openCodeZenTintHex = "#D59A2E"
	static let openCodeGoTintHex = "#3E7C8C"

	/// The ONE `ProviderID` -> brand tint lookup (theme-independent, safe off-main). Every surface that
	/// colours a provider row — dashboard, Advanced Analytics, settings marks — reads it here rather
	/// than carrying its own switch; the aggregate ginger is the fallback for anything untinted.
	static func tintHex(for id: ProviderID) -> String {
		switch id {
		case .claude: claudeTintHex
		case .codex: codexTintHex
		case .grok: grokTintHex
		case .grokBot: grokBotTintHex
		case .museSpark: museSparkTintHex
		case .nemotron: nemotronTintHex
		case .mimo: mimoTintHex
		case .bigPickle: bigPickleTintHex
		case .deepseek: deepSeekTintHex
		case .opencode: openCodeZenTintHex
		case .opencodego: openCodeGoTintHex
		case .copilot: copilotTintHex
		case .cursor: cursorTintHex
		default: aggregateTintHex
		}
	}

  static func hex(_ value: String) -> Color { Color(hex: value) }

  /// A provider brand tint made legible on the ACTIVE theme. Brand tints are chosen for the light
  /// card and can vanish on the dark card (Codex charcoal `#2F2F33` reads ~1.1:1 on `#232220`). The
  /// lift math lives in Core (`ProviderTintLegibility`) so the app and the widget extension resolve it
  /// identically; the floor is set just under the 2.97:1 brand ginger so the brand tints (claude
  /// terracotta, ginger) pass through UNCHANGED on both themes and only a genuinely-too-dark tint is
  /// lifted toward the theme ink (Codex gets a curated bright neutral on dark). **Call from the view
  /// layer only** (reads `JPTheme.current` on the main thread); `ProviderRow.tintHex` stays brand.
  static func providerTint(_ hex: String, minContrast: Double = 2.9) -> Color {
    Color(hex: ProviderTintLegibility.legibleHex(
      tintHex: hex, backgroundHex: t.card, inkHex: t.ink, isDark: t.isDark, minContrast: minContrast))
  }
}

/// Short alias kept so existing `JP.*` call sites keep working after the palette
/// moved out of `DashboardView` into this token file.
typealias JP = JPAppColor

/// Corner-radius scale — replaces ad-hoc inline `cornerRadius:` literals so the
/// control/chip/card radii can be retuned in one place.
enum JPAppRadius {
  static let tile: CGFloat = 3
  static let chip: CGFloat = 4
  static let controlChip: CGFloat = 5
  static let metricCard: CGFloat = 7
  static let card: CGFloat = 9
  static let well: CGFloat = 10
  static let cardGlow: CGFloat = 11
  static let panel: CGFloat = 12
}

/// The expanding/fading "radar ping" ring shared by the aggregate-selector `PulseDot` and the hero
/// `SparkChart` end dot. AGENTS.md requires the two heartbeats read as ONE system, so both derive the
/// ring from these SAME pure functions instead of hand-copying the math — a single source that
/// `RadarPingTests` locks so the two call sites can never silently drift apart.
enum RadarPing {
  /// One expand-and-fade cycle, in seconds (a 1.4s repeat).
  static let period: Double = 1.4
  /// 0→1 sawtooth phase for clock time `s` (seconds since the reference date).
  static func phase(at s: Double) -> Double { s.truncatingRemainder(dividingBy: period) / period }
  /// Ring scale across one cycle: 1 → 2.4, ease-out.
  static func scale(_ p: Double) -> Double { 1 + 1.4 * (1 - (1 - p) * (1 - p)) }
  /// Ring opacity across one cycle: 0.4 → 0.
  static func opacity(_ p: Double) -> Double { 0.4 * (1 - p) }
}

/// Shared interaction motion. `hover` is the ONE hover-highlight timing for every chrome/footer/row
/// control, so the identical 32pt cluster feels uniform instead of drifting across the old
/// 0.14/0.16/0.18 spread. Pinned at 0.16 — the value the motion-contract tests already blessed.
/// Call sites keep the explicit `reduceMotion ? nil : JPAppMotion.hover` gate.
enum JPAppMotion {
  static let hover: Animation = .easeOut(duration: 0.16)
}

// NOTE on Dynamic Type: JPAppFont roles are intentionally fixed point sizes. The
// menu-bar pill/status item cannot grow with the user's text-size setting (NSStatusItem
// geometry is fixed), so statusItemFont/statusPillFont are deliberately non-scaling.
// The dashboard/settings surfaces are fixed-width intrinsic-height cards, so they do not
// adopt `relativeTo:` scaling either.

extension Color {
  /// Build a Color from a 6-digit hex string, with or without a leading `#`.
  /// Degrades to a visible on-theme fallback rather than silent black.
  /// Parsing + the fallback live in Core's `HexColor` so the app and widget can't drift.
  init(hex: String) {
    let c = HexColor.componentsOrFallback(hex)
    self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
  }
}

extension NSColor {
  /// AppKit bridge for a JPAppColor hex so status-item/window chrome stays on the
  /// same source values as the SwiftUI palette (no hand-typed sRGB triples that drift).
  convenience init(jpHex value: String) {
    let c = HexColor.componentsOrFallback(value)
    self.init(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
  }
}
