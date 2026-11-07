import SwiftUI

/// The COMPACT theme picker on the Settings "Appearance" section: a single 3-column row — the two free
/// themes (Sunlit, Midnight) plus a "More themes" tile that opens the dedicated `ThemesWindowController`
/// where the full catalog (all `JPTheme.all`) is browsable in a larger, 2-column,
/// easier-to-read grid. This keeps the Settings face short (the growing catalog no longer adds a grid row
/// per +4 themes). Every theme is free.
struct ThemePickerRow: View {
  @ObservedObject private var themeManager = ThemeManager.shared
  var onOpenThemes: (() -> Void)?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

  // The two themes shown inline — Sunlit + Midnight today. Everything else lives behind the
  // "More themes" tile / window.
  private var inlineThemes: [JPTheme] { JPTheme.all.filter { !$0.inMoreThemes } }

  var body: some View {
    LazyVGrid(columns: columns, spacing: 6) {
      ForEach(inlineThemes) { theme in
        ThemeSwatchTile(
          theme: theme,
          isActive: theme.id == themeManager.theme.id,
          onTap: { themeManager.selectWithClick(theme) })
      }
      MoreThemesTile(
        // Highlight the tile when the ACTIVE theme is one of the "more" themes, so a user whose
        // current theme isn't one of the two inline swatches still sees where their selection lives.
        isActive: themeManager.theme.inMoreThemes,
        onTap: {
          InteractiveSounds.shared.topClick()
          onOpenThemes?()
        })
    }
    // A tighter inset than the icon+title+subtitle `SettingsRow` uses — dense swatch tiles, so the
    // generous `settingsRowY` padding would waste vertical space.
    .padding(.horizontal, JPAppSpacing.settingsRowX).padding(.vertical, 6)
  }

}

/// The full-catalog grid hosted inside the `ThemesWindowController` window: EVERY `JPTheme.all` in a
/// 2-column, larger-tile layout (readable name text).
struct ThemesWindowGrid: View {
  @ObservedObject private var themeManager = ThemeManager.shared

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

  var body: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(JPTheme.all) { theme in
        ThemeSwatchTile(
          theme: theme,
          isActive: theme.id == themeManager.theme.id,
          large: true,
          onTap: { themeManager.selectWithClick(theme) })
      }
    }
  }

}

/// A swatch tile previewing a theme's OWN `card`/`ink`/`ginger` so legibility is judged before switching.
/// `large` doubles the height and uses readable name text for the dedicated Themes window; the compact
/// default is the dense Settings-inline size. Internal (not `private`) — shared by the compact picker and
/// the window grid.
struct ThemeSwatchTile: View {
  let theme: JPTheme
  let isActive: Bool
  var large: Bool = false
  let onTap: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  private var swatchCard: Color { Color(hex: theme.card) }
  private var swatchInk: Color { Color(hex: theme.ink) }
  private var swatchGinger: Color { Color(hex: theme.ginger) }

  // The compact (Settings-inline) tiles are taller with readable 11pt text — the old 20pt/9pt was too
  // small to read at a glance; `large` (Themes window) stays bigger still.
  private var tileHeight: CGFloat { large ? 40 : 30 }
  private var nameFont: Font { large ? JPAppFont.swatchLabelLarge : JPAppFont.swatchLabel }
  private var accentHeight: CGFloat { large ? 5 : 4 }

  var body: some View {
    Button(action: onTap) {
      ZStack(alignment: .bottomLeading) {
        RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
          .fill(swatchCard)
        Rectangle()
          .fill(swatchGinger)
          .frame(height: accentHeight)
          .clipShape(
            .rect(bottomLeadingRadius: JPAppRadius.controlChip, bottomTrailingRadius: JPAppRadius.controlChip)
          )
        Text(theme.name)
          .font(nameFont)
          .foregroundStyle(swatchInk)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .padding(.horizontal, large ? 8 : 6)
          .padding(.bottom, large ? 6 : 4)
      }
      .frame(maxWidth: .infinity)
      .frame(height: tileHeight)
      .overlay(
        RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
          .strokeBorder(isActive ? JP.gingerDeep : JP.lineStrong.opacity(0.7), lineWidth: isActive ? 1.5 : 0.5)
      )
      .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
      .animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(theme.name)
    .accessibilityLabel(theme.name)
    .accessibilityValue(isActive ? "Selected" : "Not selected")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

/// The compact-picker's third cell: opens the full Themes window. Styled like a swatch tile so the row
/// reads as one grid; shows a palette glyph + "More themes". Highlights (ginger border) when the active
/// theme is one of the "more" themes so the user can see their selection lives inside.
private struct MoreThemesTile: View {
  let isActive: Bool
  let onTap: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  private var moreCount: Int { JPTheme.all.filter { $0.inMoreThemes }.count }

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 4) {
        Image(systemName: "paintpalette")
          .font(JPAppFont.caption)
        Text("More themes")
          .font(JPAppFont.swatchLabel)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      .foregroundStyle(JP.gingerDeep)
      .frame(maxWidth: .infinity)
      .frame(height: 30)
      .background(
        RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
          .fill(JP.honey.opacity(0.14))
      )
      .overlay(
        RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
          .strokeBorder(isActive ? JP.gingerDeep : JP.gingerDeep.opacity(0.35), lineWidth: isActive ? 1.5 : 0.5)
      )
      .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
      .animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help("Browse all \(JPTheme.all.count) themes")
    .accessibilityLabel("More themes")
    .accessibilityValue("\(moreCount) more themes, opens the theme catalog")
  }
}
