import AppKit
import SwiftUI

/// The dedicated "Themes" window, opened from the "More themes" tile in the Settings → Appearance
/// compact picker. It hosts the full `JPTheme.all` catalog in a larger, 2-column, easier-to-read grid
/// (`ThemesWindowGrid`) so the growing catalog no longer lengthens the intrinsic-height Settings face.
///
/// Window mechanics — child-window attachment, anchoring, drag lock, observer teardown — all live in
/// `TrayChildWindowController`, which this and the Live Data / Advanced Analytics trays share. The only
/// deltas here: the hosted view, fixed width with intrinsic height (`fittingSize`), and a KEYABLE window.
/// The theme count is deterministic (`JPTheme.all`), so `fittingSize` gives an exact height and the window
/// grows a row taller only when the catalog itself grows.
@MainActor
final class ThemesWindowController: TrayChildWindowController {
  init(dashboardChrome: DashboardChromeState, notificationCenter: NotificationCenter = .default) {
    super.init(
      dashboardChrome: dashboardChrome,
      notificationCenter: notificationCenter,
      contentSizing: .intrinsic(width: JPAppSpacing.themesWindowW),
      // Keyable (like the Live Data window) so it can take focus for keyboard/VoiceOver navigation of the
      // tile grid; opened from a Settings tile, not a footer toggle, so no single-click-close concern.
      keyPolicy: .key)
  }

  override func makeRootView() -> AnyView {
    AnyView(ThemesWindowContent())
  }
}

/// The scrollless body hosted by `ThemesWindowController`: the `JP the Cat 🐾 — Themes` chrome row (drawn
/// inline with the traffic lights via the window's `safeAreaRegions = []`) over the full-catalog
/// `ThemesWindowGrid`. Fixed width, intrinsic height. Observes `ThemeManager` so selecting a theme
/// re-highlights the active tile live and the whole window re-colors.
struct ThemesWindowContent: View {
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      chromeBar
      Rectangle().fill(JP.line).frame(height: 1)
      ThemesWindowGrid()
        .padding(.horizontal, JPAppSpacing.panelX)
        .padding(.vertical, JPAppSpacing.settingsBodyY)
    }
    .frame(width: JPAppSpacing.themesWindowW, alignment: .top)
    .background(JP.card)
  }

  private var chromeBar: some View {
    ChromeTitleRow(subtitle: "— Themes")
  }
}
