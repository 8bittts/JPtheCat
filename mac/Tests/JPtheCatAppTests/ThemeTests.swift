import AppKit
import SwiftUI
import XCTest

@testable import JPtheCatApp

/// Guards the theme foundation: the registry + premium-gating rule, the light↔dark toggle and its
/// persistence, and a WCAG-AA contrast gate so every shipped theme's text/UI pairs stay legible
/// (modeled on yenchat's theme-contrast gate). Adding a theme means adding its contrast case here.
final class ThemeTests: XCTestCase {

  // `JPTheme.current` is a process-global the token layer reads; reset it around every test so a
  // prior test's toggle can't leak into another running in the same xctest worker process.
  override func setUp() {
    super.setUp()
    JPTheme.current = .sunlit
  }

  override func tearDown() {
    JPTheme.current = .sunlit
    super.tearDown()
  }

  /// A `ThemeManager` backed by an isolated `UserDefaults` suite. Under `swift test --parallel`, xctest
  /// runs each method in its own process, and all processes share the on-disk `.standard` domain — so
  /// two tests mutating/removing `JPTheme.storageKey` there race (the persistence assertion read back
  /// `nil`). Persisting to a per-test suite instead removes the shared-state collision. Callers must
  /// `defer` `wipe(defaults, suite:)` to clean the on-disk plist.
  @MainActor
  private func isolatedManager(suite: String) -> (ThemeManager, UserDefaults) {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (ThemeManager(defaults: defaults), defaults)
  }

  private func wipe(_ defaults: UserDefaults, suite: String) {
    defaults.removePersistentDomain(forName: suite)
  }

  // MARK: Registry

  func testRegistryShips24Themes() {
    XCTAssertEqual(JPTheme.all.first?.id, "sunlit", "Sunlit Ledger must stay the default (first) theme")
    XCTAssertEqual(
      Set(JPTheme.all.map(\.id)),
      ["sunlit", "midnight", "ember", "yen", "retroterminal", "dracula", "nord", "gruvboxdark",
       "solarizeddark", "monokaipro", "onedark", "tokyonight", "catppuccinmocha", "rosepine",
       "everforestdark", "githubdark", "ayumirage", "nightowl", "catppuccinmacchiato", "palenight",
       "kanagawawave", "oceanicnext", "cobalt2", "synthwave"])
    XCTAssertEqual(JPTheme.all.count, 24)
    XCTAssertEqual(JPTheme.sunlit.isDark, false)
    XCTAssertEqual(JPTheme.midnight.isDark, true)
    // Only the two launch themes are free; every other theme (Ember + the 21 terminal-inspired
    // packs) is premium.
    let freeIDs = Set(JPTheme.all.filter { !$0.inMoreThemes }.map(\.id))
    XCTAssertEqual(freeIDs, ["sunlit", "midnight"])
  }

  func testWithIDResolvesKnownAndRejectsUnknown() {
    XCTAssertEqual(JPTheme.with(id: "midnight"), .midnight)
    XCTAssertNil(JPTheme.with(id: "does-not-exist"))
  }

  // MARK: Every theme is free

  @MainActor
  func testEveryThemeIsSelectable() {
    XCTAssertEqual(Set(ThemeManager.shared.selectable.map(\.id)), Set(JPTheme.all.map(\.id)))
  }

  // MARK: Selection + persistence

  @MainActor
  func testSelectSwitchesAndPersists() {
    let suite = "ThemeTests.select-persist"
    let (manager, defaults) = isolatedManager(suite: suite)
    defer { wipe(defaults, suite: suite) }

    manager.select(.sunlit)
    XCTAssertFalse(manager.theme.isDark)

    manager.select(.midnight)
    XCTAssertTrue(manager.theme.isDark)
    XCTAssertEqual(JPTheme.current.id, "midnight", "token source must track the active theme")
    XCTAssertEqual(
      defaults.string(forKey: JPTheme.storageKey), "midnight",
      "selection must persist across launches")

    manager.select(.sunlit)
    XCTAssertFalse(manager.theme.isDark)
    XCTAssertEqual(JPTheme.current.id, "sunlit")
  }

  /// Regression guard for the theme-switch freeze: `apply()` reassigns `NSApp.appearance` only when
  /// the light/dark FAMILY actually changes, since most of the 24 themes share dark/light with each
  /// other and reassigning the same `NSAppearance` still forces an expensive AppKit-wide re-resolve.
  /// This proves the whole switch-between-two-dark-themes path stays consistent without asserting on
  /// `NSApplication.shared.appearance` directly (unit tests don't get a real app appearance context).
  @MainActor
  func testSwitchingBetweenTwoDarkThemesStaysConsistent() {
    let suite = "ThemeTests.dark-to-dark"
    let (manager, defaults) = isolatedManager(suite: suite)
    defer { wipe(defaults, suite: suite) }

    manager.select(.midnight)
    XCTAssertTrue(manager.theme.isDark)
    manager.select(.ember)  // both dark: apply() should no-op the NSApp.appearance reassignment
    XCTAssertTrue(manager.theme.isDark)
    XCTAssertEqual(JPTheme.current.id, "ember")
    manager.select(.dracula)  // still dark -> dark
    XCTAssertTrue(manager.theme.isDark)
    XCTAssertEqual(JPTheme.current.id, "dracula")
  }

  /// Guards the "captured once" regression: the aggregate trend-chart tint must re-resolve to the
  /// active theme's ginger on a runtime selection change, not freeze the launch-time value.
  @MainActor
  func testAggregateTintTracksActiveThemeOnSelection() {
    let suite = "ThemeTests.aggregate-tint"
    let (manager, defaults) = isolatedManager(suite: suite)
    defer { wipe(defaults, suite: suite) }
    manager.select(.sunlit)
    XCTAssertEqual(DashboardViewModel.allTintHex, "#\(JPTheme.sunlit.ginger)")

    manager.select(.midnight)
    XCTAssertEqual(
      DashboardViewModel.allTintHex, "#\(JPTheme.midnight.ginger)",
      "aggregate chart tint must re-resolve to the active theme's ginger, not the launch value")
  }

  // MARK: WCAG-AA contrast gate

  func testEveryThemeMeetsContrastFloors() {
    for theme in JPTheme.all {
      // Body/label text ≥ 4.5:1 (WCAG 2.1 AA normal text).
      assertContrast(theme.ink, on: theme.card, atLeast: 4.5, theme, "ink on card")
      assertContrast(theme.ink, on: theme.paper, atLeast: 4.5, theme, "ink on paper")
      assertContrast(theme.inkSoft, on: theme.card, atLeast: 4.5, theme, "inkSoft on card")
      // inkFaint is the tertiary/caption text role (freshness caption, gauge sub-labels, settings
      // subtitles), rendered at normal size — so it needs full AA text contrast, not the UI floor.
      assertContrast(theme.inkFaint, on: theme.card, atLeast: 4.5, theme, "inkFaint on card")
      // inkFaint also renders on the darker `paper2` — the basis-label ticker band and the chart /
      // "last N days" eyebrows. On Sunlit that's ~4.52:1: passing but previously ungated, so a future
      // paper2 warm-up could silently drop it below AA. Lock it. (On Midnight paper2 == card, above.)
      assertContrast(theme.inkFaint, on: theme.paper2, atLeast: 4.5, theme, "inkFaint on paper2 (ticker/eyebrow)")
      // gingerDeep is the text-legible accent (attention labels, hover) — full AA text contrast.
      // Plain `ginger` is a decorative fill/sparkle tint (shipped Sunlit is ~2.97:1) and is not gated
      // as text; gingerDeep is used wherever ginger must carry meaning.
      assertContrast(theme.gingerDeep, on: theme.card, atLeast: 4.5, theme, "gingerDeep on card")
      // Positive-signal indicator (sage dot) as a graphical object ≥ 3:1 (WCAG 2.1 AA non-text).
      assertContrast(theme.sage, on: theme.card, atLeast: 3.0, theme, "sage on card")
      // Meter/bar track must stay a visible groove — distinct from the card (on the dark card,
      // `paper2` collapsed to the card color and every track vanished).
      assertContrast(theme.track, on: theme.card, atLeast: 1.15, theme, "track groove vs card")
      // [Regression guard — the unused meter groove must be VISIBLE] The `track` FILL is barely distinct
      // from the card (~1.3:1 light) AND is the exact color of a selected row's background, so on its own
      // the unfilled portion of a partial usage gauge reads as empty space and the bar looks like a stub
      // that "isn't all the way to the right". Every meter/gauge groove therefore draws an `inkFaint`
      // hairline border; that border MUST clear 3:1 vs the card (unselected rows) AND vs the track itself
      // (selected rows, whose background IS the track), in both themes, or the groove goes invisible again.
      assertContrast(theme.inkFaint, on: theme.card, atLeast: 3.0, theme, "meter groove border vs card")
      assertContrast(theme.inkFaint, on: theme.track, atLeast: 3.0, theme, "meter groove border vs selected-row track")
      // The Upgrade CTA label sits on the `[cta, ctaDeep]` accent gradient — must clear AA on BOTH
      // gradient stops for every theme (the old `.white`-on-ginger CTA was ~2–3:1).
      assertContrast(theme.ctaText, on: theme.cta, atLeast: 4.5, theme, "ctaText on cta")
      assertContrast(theme.ctaText, on: theme.ctaDeep, atLeast: 4.5, theme, "ctaText on ctaDeep")
      // "official" gauge badge: sageDeep label on a sage@0.2 chip over the card (plain sage was 3.95:1).
      // Uses THIS theme's own sage/card/sageDeep — not the global `JP.*` accessors, which resolve
      // `JPTheme.current` (frozen at `.sunlit` for this whole loop) and would silently re-check only
      // Sunlit's badge on every iteration instead of each theme's own.
      let sageChip = composite(hex: theme.sage, over: theme.card, opacity: 0.2)
      let sageDeepVsChip = contrast(componentsHex: theme.sageDeep, sageChip)
      XCTAssertGreaterThanOrEqual(
        sageDeepVsChip, 4.5,
        "\(theme.name): official badge sageDeep is \(String(format: "%.2f", sageDeepVsChip)):1 on the sage chip")
    }
  }

  /// A theme pack is a visual identity, not a renamed near-copy. The picker previews card, ink, and
  /// aggregate accent, so those exact visible roles must form a unique signature. This catches the
  /// original failure mode where packs looked different only through colors hidden from the picker.
  func testEveryThemeHasAnOpinionatedPaletteSignature() {
    for theme in JPTheme.all {
      XCTAssertGreaterThanOrEqual(
        contrastRatio(theme.paper, theme.card), 1.05,
        "\(theme.name): paper and card need visible depth, not a flat recolored slab")
    }

    for (index, theme) in JPTheme.all.enumerated() {
      for other in JPTheme.all.dropFirst(index + 1) {
        let distance = paletteDistance(theme, other)
        XCTAssertGreaterThanOrEqual(
          distance, 0.09,
          "\(theme.name) and \(other.name) are too visually similar (signature distance \(String(format: "%.3f", distance)))")
      }
    }
  }

  /// The per-provider brand tints (e.g. Codex charcoal #2F2F33) must resolve to a visible UI object
  /// on every theme via `providerTint` — on the dark card the raw charcoal is ~1.1:1 (invisible).
  @MainActor
  func testProviderTintStaysLegibleOnEveryTheme() {
    let suite = "ThemeTests.provider-tint"
    let (manager, defaults) = isolatedManager(suite: suite)
    defer { wipe(defaults, suite: suite) }
    for theme in JPTheme.all {
      manager.select(theme)
      XCTAssertEqual(
        JPTheme.current.id, theme.id,
        "select() no-opped — the legibility sweep collapsed to a single theme")
      // codex + claude + the aggregate (ginger) tint — the aggregate row now routes through providerTint
      // too, so gate it here as well.
      for tint in [JPAppColor.codexTintHex, JPAppColor.claudeTintHex, JPAppColor.aggregateTintHex] {
        let resolved = JPAppColor.providerTint(tint)
        // 1. The resolved tint must read against the card (line/sparkline/dot legibility). Plain ginger
        //    is a decorative aggregate tint (~2.97:1 on light) so it uses the 2.9 UI floor, not 3.0.
        let cardFloor = tint == JPAppColor.aggregateTintHex ? 2.9 : 3.0
        XCTAssertGreaterThanOrEqual(
          contrast(of: resolved, on: theme.card), cardFloor,
          "\(theme.name): resolved provider tint \(tint) must be a visible graphical object "
            + "(got \(String(format: "%.2f", contrast(of: resolved, on: theme.card))):1 vs card)")
        // 2. The bar FILL must be distinct from its TRACK — the metric the first dark fix missed (a
        //    gray fill on the gray track read as one uniform pill, 1.42:1). Check BOTH the share-bar
        //    opacity (`barFillOpacity`) AND the gauge opacity (0.85). Dark tints are lifted toward
        //    neutral gray, so hue can't carry the distinction — require real luminance separation; light
        //    keeps its saturated brand hue, so a softer floor still reads (verified by ImageRenderer).
        let floor = theme.isDark ? 2.3 : 1.4
        for opacity in [JPAppColor.barFillOpacity, 0.85] {
          let fill = composite(resolved, over: JPAppColor.trackFill, opacity: opacity)
          let fillVsTrack = contrast(ofComponents: fill, onHex: theme.track)
          XCTAssertGreaterThanOrEqual(
            fillVsTrack, floor,
            "\(theme.name): \(tint) fill @\(opacity) must stand out from its track "
              + "(got \(String(format: "%.2f", fillVsTrack)):1, needs \(floor))")
        }
      }
    }
  }

  // MARK: Contrast helpers (WCAG 2.1 relative luminance)

  private func assertContrast(
    _ fg: String, on bg: String, atLeast floor: Double, _ theme: JPTheme, _ label: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let ratio = contrastRatio(fg, bg)
    XCTAssertGreaterThanOrEqual(
      ratio, floor,
      "\(theme.name): \(label) is \(String(format: "%.2f", ratio)):1 (needs \(floor):1)",
      file: file, line: line)
  }

  private func contrastRatio(_ a: String, _ b: String) -> Double {
    let la = relativeLuminance(a), lb = relativeLuminance(b)
    let lighter = max(la, lb), darker = min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private func relativeLuminance(_ hex: String) -> Double {
    luminance(rgb(hex))
  }

  private func paletteDistance(_ a: JPTheme, _ b: JPTheme) -> Double {
    let rolesA = [a.card, a.ink, a.ginger]
    let rolesB = [b.card, b.ink, b.ginger]
    let squared = zip(rolesA, rolesB).reduce(0.0) { total, pair in
      let left = rgb(pair.0), right = rgb(pair.1)
      return total + pow(left.0 - right.0, 2) + pow(left.1 - right.1, 2) + pow(left.2 - right.2, 2)
    }
    return sqrt(squared / Double(rolesA.count))
  }

  private func luminance(_ c: (Double, Double, Double)) -> Double {
    func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
  }

  /// Contrast of a resolved SwiftUI `Color` (e.g. the output of `providerTint`) against a hex bg.
  private func contrast(of color: Color, on bgHex: String) -> Double {
    contrast(ofComponents: components(color), onHex: bgHex)
  }

  private func contrast(ofComponents fg: (Double, Double, Double), onHex bg: String) -> Double {
    let la = luminance(fg), lb = relativeLuminance(bg)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  /// Contrast between two composited component tuples (e.g. a label vs a translucent chip).
  private func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    let la = luminance(a), lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  private func components(_ color: Color) -> (Double, Double, Double) {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
    return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
  }

  /// Alpha-composite `top` over `bottom` at `opacity` — mirrors how a bar fill renders over its track.
  private func composite(_ top: Color, over bottom: Color, opacity: Double) -> (Double, Double, Double) {
    let t = components(top), b = components(bottom)
    return (
      t.0 * opacity + b.0 * (1 - opacity),
      t.1 * opacity + b.1 * (1 - opacity),
      t.2 * opacity + b.2 * (1 - opacity))
  }

  /// Hex-string variant of `composite(_:over:opacity:)`, for checking a THEME's own literal hex
  /// fields directly (rather than the current-theme-resolving `JP.*` accessors).
  private func composite(hex top: String, over bottom: String, opacity: Double) -> (Double, Double, Double) {
    let t = rgb(top), b = rgb(bottom)
    return (
      t.0 * opacity + b.0 * (1 - opacity),
      t.1 * opacity + b.1 * (1 - opacity),
      t.2 * opacity + b.2 * (1 - opacity))
  }

  /// Contrast of a literal hex color against a composited component tuple.
  private func contrast(componentsHex hex: String, _ b: (Double, Double, Double)) -> Double {
    contrast(rgb(hex), b)
  }

  private func rgb(_ hex: String) -> (Double, Double, Double) {
    let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)
    return (
      Double((value >> 16) & 0xFF) / 255,
      Double((value >> 8) & 0xFF) / 255,
      Double(value & 0xFF) / 255)
  }
}
