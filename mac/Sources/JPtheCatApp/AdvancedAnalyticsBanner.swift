import SwiftUI
import JPtheCatCore

/// A small icon-only footer button (mirrors `DashboardFooterActionButton`'s exact recipe — same font/
/// frame/hover/content-shape — since it sits in that SAME icon row, right after Refresh). Opens the
/// Advanced Analytics tray.
struct AdvancedAnalyticsFooterButton: View {
  let onOpenTray: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: tap) {
      Image(systemName: "chart.bar.doc.horizontal")
        .font(JPAppFont.chromeIcon)
        .foregroundStyle(hovering ? JP.gingerDeep : JP.inkSoft)
        .frame(width: JPAppSpacing.footerIconBox, height: JPAppSpacing.footerIconBox)
        .contentShape(RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
    .help("Advanced Analytics")
    .accessibilityLabel("Advanced Analytics")
  }

  private func tap() {
    InteractiveSounds.shared.bottomClick()
    onOpenTray()
  }
}
