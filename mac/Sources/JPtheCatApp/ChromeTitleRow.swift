import SwiftUI

/// The single shared 32pt chrome/title row: `JP the Cat 🐾` (optionally followed by `— Subtitle`),
/// drawn inline with the traffic lights, with optional trailing controls on the right.
///
/// This replaces six hand-rolled copies (the dashboard + settings + onboarding faces and the
/// Advanced Analytics / Live data / Themes child windows). Those copies had silently drifted — four
/// different `HStack` spacings, a subtitle in `inkSoft` in one window but `inkFaint` in the others
/// (two windows AGENTS.md calls 1:1 clones), inconsistent `Spacer` minimums, and a `.background(JP.card)`
/// present on some rows and missing on others. One definition makes that drift impossible.
///
/// It observes `ThemeManager` because it is now an independent leaf `View`: a static leaf that reads
/// `JP.*` would otherwise freeze at first-render theme when its parent's structural diff skips it (see
/// the theme-freeze lesson in AGENTS.md).
struct ChromeTitleRow<Trailing: View>: View {
  /// The secondary label after the em-dash (e.g. `— Advanced Analytics`), or nil for the bare title.
  let subtitle: String?
  /// True inside a real window drawn behind the traffic lights (inset past them); false in the raw
  /// executable / no-window mode (compact leading inset). Windows always pass `true`.
  let windowChrome: Bool
  @ViewBuilder let trailing: () -> Trailing

  // periphery:ignore - intentional theme dependency.
  @ObservedObject private var themeManager = ThemeManager.shared

  init(
    subtitle: String? = nil,
    windowChrome: Bool = true,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.subtitle = subtitle
    self.windowChrome = windowChrome
    self.trailing = trailing
  }

  var body: some View {
    HStack(spacing: 0) {
      Text("JP the Cat 🐾")
        .font(JPAppFont.chromeTitle)
        .foregroundStyle(JP.ink)
      if let subtitle {
        Text(subtitle)
          .font(JPAppFont.chromeTitle)
          .foregroundStyle(JP.inkSoft)
          .lineLimit(1)
          .padding(.leading, JPAppSpacing.chromeTitleGap)
      }
      Spacer(minLength: 8)
      trailing()
    }
    .padding(.leading, windowChrome ? JPAppSpacing.chromeTrafficLightInset : JPAppSpacing.chromeLeading)
    .padding(.trailing, JPAppSpacing.chromeTrailing)
    // Fixed 32pt bar centers the title on the traffic-light row, with even padding above and below.
    .frame(height: JPAppSpacing.chromeHeight, alignment: .center)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(JP.card)
  }
}

/// A small green "on air" light for the top-right chrome cluster that gently breathes (a slow
/// opacity pulse) while the menu-bar pill is on a rotating display format, and stays hidden on any
/// static/pinned format.
///
/// The blink is driven by `TimelineView(.animation)` (a per-frame display link), not
/// `withAnimation(...).repeatForever` — the same lesson `PulseDot` documents: a `.onAppear`
/// repeating animation silently fails to run here. Reduce-motion callers get a steady dim light
/// instead of a pulse, and a non-rotating format collapses the view to zero width.
struct RotationIndicatorLight: View {
  /// True when the selected menu-bar format rotates (a limit format with no pinned provider).
  let isRotating: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.jpMotionPaused) private var motionPaused
  // periphery:ignore - intentional theme dependency.
  @ObservedObject private var themeManager = ThemeManager.shared

  private let diameter: CGFloat = 7

  var body: some View {
    Group {
      if isRotating {
        if reduceMotion {
          light(opacity: 0.85)
        } else {
          // `paused:` stops the display-link subscription entirely while the window is hidden. The
          // phase is a pure function of absolute time, so the frame on resume is the frame it would
          // have shown anyway — the pulse cadence is untouched. See `DashboardMotionGate`.
          TimelineView(.animation(paused: motionPaused)) { timeline in
            let s = timeline.date.timeIntervalSinceReferenceDate
            // Slow, gentle breathe: a ~2.6s period cosine kept in a soft 0.35…1.0 band.
            let pulse = (1 - cos(2 * .pi * s / 2.6)) / 2
            light(opacity: 0.35 + 0.65 * pulse)
          }
        }
      }
    }
    .frame(width: isRotating ? diameter : 0, height: diameter)
    .accessibilityHidden(true)
  }

  private func light(opacity: Double) -> some View {
    Circle()
      .fill(JP.sage)
      .frame(width: diameter, height: diameter)
      .overlay(Circle().strokeBorder(JP.ink.opacity(0.12), lineWidth: 0.5))
      .shadow(color: JP.sage.opacity(0.55 * opacity), radius: 3)
      .opacity(opacity)
      .help("Menu bar is rotating through providers")
  }
}

extension ChromeTitleRow where Trailing == EmptyView {
  /// Convenience for the trailing-less rows (the Live data + Themes windows).
  init(subtitle: String? = nil, windowChrome: Bool = true) {
    self.init(subtitle: subtitle, windowChrome: windowChrome) { EmptyView() }
  }
}
