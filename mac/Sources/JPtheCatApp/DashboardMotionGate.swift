import SwiftUI

/// Decides whether the dashboard's `TimelineView(.animation)` surfaces should stop evaluating.
///
/// [Why this exists — measured, not modelled] Every animated surface on the card is driven by
/// `TimelineView(.animation)`, a display-link subscription. macOS does NOT throttle that when the
/// window is covered: a probe measured **360 frames / 3 s = 120 fps while the window was 100%
/// occluded**, and the same 120 fps while MINIATURIZED. `TimelineView(.animation(paused: true))`
/// measured 0 frames and 0.000 s of CPU. On the real app that is 7-14% of a core burned rendering
/// pixels nobody can see.
///
/// That is the app's DEFAULT steady state, not a corner case: `AppDelegate` opens the dashboard on
/// every Dock-visible launch, `applicationShouldTerminateAfterLastWindowClosed` returns false, and
/// `StatusBarController`'s reveal path deliberately raises a buried window rather than closing it. A
/// launch-at-login user sits with an open, permanently-covered dashboard all day.
///
/// **This cannot change what a looking user sees.** Every gated animation is a pure function of an
/// absolute instant with no `@State` phase accumulator — `RotationIndicatorLight`'s
/// `(1 - cos(2π·s/2.6))/2`, `PulseDot`'s `(1 - cos(2π·s/28))/2` + `RadarPing.phase(at:)`,
/// `TickerTapeText`/`FloatingBubble`'s `truncatingRemainder`, and `SparkChart`'s end-dot ping. On
/// resume each renders exactly the frame it would have rendered had it never paused, so the LOCKED
/// motion spec is preserved by construction rather than by careful tuning.
///
/// A CLOSED window needs no gate — `StatusBarController`'s `onClose` already nils
/// `contentViewController`, which releases the hosting tree outright.
enum DashboardMotionGate {
  /// **Fails open by construction.** `hasObservedOcclusion` must be false until a real
  /// `NSWindow.didChangeOcclusionStateNotification` has actually arrived for the window.
  ///
  /// This is not defensive padding — it is the documented launch-mode hazard again. A probe run
  /// WITHOUT a real `NSApplication.run()` event loop read `occlusionState` as permanently
  /// non-visible and received ZERO notifications, even with the window visible and frontmost. Reading
  /// `occlusionState` eagerly would therefore freeze every animation under `swift run JPtheCat`.
  /// Deriving the flag solely from a delivered notification means "no notification ever" can only
  /// ever mean "never pause".
  ///
  /// Deliberately does NOT consult `NSWindow.isVisible` or `isMiniaturized`. A miniaturized window
  /// reports `isVisible == false`, so an `isVisible` guard would make a miniaturized case
  /// unreachable — while a miniaturized window was measured still running at a full 120 fps.
  /// `occlusionState` already reports non-visible when miniaturized, so it covers that case on its
  /// own and gating on it alone strictly increases the win.
  static func shouldPauseMotion(hasObservedOcclusion: Bool, occlusionVisible: Bool) -> Bool {
    hasObservedOcclusion && !occlusionVisible
  }
}

/// Carries `DashboardMotionGate`'s decision to every animated leaf without prop-drilling through the
/// card's whole view tree. Default `false` so any surface hosted outside the gated window (the child
/// windows, previews, tests, raw `swift run`) animates exactly as before.
private struct JPMotionPausedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var jpMotionPaused: Bool {
    get { self[JPMotionPausedKey.self] }
    set { self[JPMotionPausedKey.self] = newValue }
  }
}
