import AppKit
import SwiftUI
import WidgetKit

/// macOS exposes **no** public API to open the widget gallery / "Edit Widgets" (and scripting that
/// UI is off-limits). Launching the Notification Center agent via `NSWorkspace` is a silent no-op on
/// modern macOS — it's a background agent, so the panel never appears. So this control does the only
/// two honest, reliable things: refresh the widget's timelines (so an already-placed widget updates
/// immediately) and show the exact steps to add one — in a JP-branded alert (mascot icon + themed,
/// numbered step chips) rather than a generic system text-wall.
@MainActor
enum WidgetGalleryOpener {
  static func open() {
    // The user is about to place a widget, so clear the publish spacing floor: the next refresh should
    // assemble a fresh snapshot rather than let a brand-new widget sit on older numbers.
    DashboardWidgetPublisher.invalidatePublishThrottle()
    WidgetCenter.shared.reloadAllTimelines()

    let alert = NSAlert(
      jpTitle: "Add the JP the Cat widget",
      jpMessage: "macOS doesn't let apps open the widget gallery, so add it the standard way:")
    // Brand the alert with the JP mark (loaded via the app's NSImage path). The mascot replaces the
    // generic app icon so the dialog reads as JP, not a system prompt.
    if let mark = AppResources.image(forResource: "jp-menubar") {
      alert.icon = mark
    }
    alert.accessoryView = stepsAccessory()
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Got it")
    alert.runModal()
  }

  /// The three add-the-widget steps as themed numbered chips. Colors resolve through `JPAppColor`
  /// (active `JPTheme`), so they stay legible under the pinned Sunlit/Midnight appearance — chips use
  /// `trackFill` (visible on both themes; `paper2` collapses on Midnight). Keeps the literal "Edit
  /// Widgets" / "JP the Cat" strings the guidance must show.
  private static func stepsAccessory() -> NSView {
    let host = NSHostingView(rootView: WidgetGallerySteps())
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    return host
  }
}

private struct WidgetGallerySteps: View {
  private static let steps = [
    "Right-click your desktop (or open Notification Center) and choose “Edit Widgets”.",
    "Search “JP the Cat”.",
    "Drag the Small, Medium, or Large size into place.",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, text in
        HStack(alignment: .top, spacing: 10) {
          Text("\(index + 1)")
            .font(JPAppFont.stepNumeral)
            .foregroundStyle(JP.gingerDeep)
            .frame(width: 22, height: 22)
            .background(JP.trackFill, in: Circle())
            .overlay(Circle().strokeBorder(JP.lineStrong, lineWidth: 1))
          Text(text)
            .font(JPAppFont.body)
            .foregroundStyle(JP.ink)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
      }
    }
    .padding(.top, 6)
    .frame(width: 330, alignment: .leading)
  }
}
