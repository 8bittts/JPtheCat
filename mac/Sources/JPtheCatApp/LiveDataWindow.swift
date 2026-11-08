import AppKit
import JPtheCatCore
import SwiftUI

/// The dedicated "Live data" window, opened from the single Settings → "Live data" row. It re-hosts the
/// former inline Settings "Live data" section verbatim (same rows, same styling) so the provider list can
/// grow without competing with the intrinsic-height, no-scroll Settings face for vertical space.
///
/// Window mechanics — child-window attachment (`addChildWindow(_:ordered:)`, NOT a second independent
/// top-level window), anchoring, drag lock, observer teardown — all live in `TrayChildWindowController`,
/// which this and the Themes / Advanced Analytics trays share. The only deltas here: the hosted view,
/// fixed width with intrinsic height, and a KEYABLE window.
///
@MainActor
final class LiveDataWindowController: TrayChildWindowController {
  private let model: DashboardViewModel
  /// Test-only fixture: pins which detection-gated rows render so `LiveDataWindowLayoutTests` can
  /// measure the maximum and minimum row sets. Production passes `nil` and the content probes real
  /// local presence (`LiveDataWindowContent.Detection.probe()`).
  private let detection: LiveDataWindowContent.Detection?

  init(
    model: DashboardViewModel, dashboardChrome: DashboardChromeState,
    notificationCenter: NotificationCenter = .default,
    detection: LiveDataWindowContent.Detection? = nil
  ) {
    self.model = model
    self.detection = detection
    super.init(
      dashboardChrome: dashboardChrome,
      notificationCenter: notificationCenter,
      // Height is measured from the content (no dead space) so the window grows a row taller as providers
      // are added; detection only changes on `onAppear`, so re-fitting mid-session isn't needed.
      contentSizing: .intrinsic(width: JPAppSpacing.liveDataWindowW),
      // Unlike the Advanced Analytics panel, this window MUST be able to become key: its rows are SwiftUI
      // `Toggle(.switch)` controls, and AppKit renders switches in a desaturated GRAY state (never the
      // on-tint) while their window is non-key. Staying non-key made every "on" switch look off — a real
      // reported bug — so it becomes key on open. It's opened from a Settings row (not a footer toggle),
      // so the analytics window's single-click-close rationale for staying non-key does not apply; the
      // user closes it via its own close button or Escape.
      keyPolicy: .key)
  }

  override func makeRootView() -> AnyView {
    AnyView(LiveDataWindowContent(model: model, detection: detection))
  }
}
