import JPtheCatCore
import Observation

/// Live description of the view the status-item pill is rendering right now.
///
/// The persisted setting describes the chosen mode, but a rotating mode also has a private current
/// window. Sharing this tiny presentation state with SwiftUI keeps the Settings row and cycle button
/// aligned with the pill on every selection change, refresh, and rotation tick.
@MainActor
@Observable
final class MenuBarDisplayPresentationState {
  var title = MenuBarDisplayFormat.total.settingsTitle
  var subtitle = MenuBarDisplayFormat.total.settingsSubtitle

  func update(format: MenuBarDisplayFormat, limit: MenuBarProviderLimit?) {
    title = MenuBarLabelRenderer.renderedSettingsTitle(for: format, limit: limit)
    subtitle = MenuBarLabelRenderer.renderedSettingsSubtitle(for: format, limit: limit)
  }
}
