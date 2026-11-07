import AppKit

/// How the dashboard and its child windows behave when the user clicks another app.
///
/// Pinned (the launch default) stays above other windows on every Space and over full-screen apps.
/// Clicking away never hides, closes, or miniaturizes the window. The menu-bar item is the quick
/// show and hide control. Unpinning drops the window to a normal level on the current Space only.
enum DashboardWindowPresence {
  struct Configuration: Equatable {
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
    let hidesOnDeactivate: Bool
  }

  static func configuration(isPinned: Bool) -> Configuration {
    Configuration(
      level: isPinned ? .floating : .normal,
      collectionBehavior: isPinned
        ? [.canJoinAllSpaces, .fullScreenAuxiliary]
        : [.managed],
      hidesOnDeactivate: false)
  }

  @MainActor
  static func apply(_ configuration: Configuration, to window: NSWindow) {
    window.level = configuration.level
    window.collectionBehavior = configuration.collectionBehavior
    window.hidesOnDeactivate = configuration.hidesOnDeactivate
  }
}
