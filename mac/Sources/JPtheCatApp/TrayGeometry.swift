import AppKit

/// Pure, testable placement math for the Advanced Analytics tray — an AppKit CHILD window
/// (`dashboardWindow.addChildWindow(...)`, see `AdvancedAnalyticsWindowController`) that slides out to
/// the LEFT of the main dashboard window. Mirrors `StatusItemGeometry`'s multi-display/negative-origin
/// handling convention (never assume `x >= 0`), but solves a different placement problem: anchoring to
/// an arbitrary window's frame rather than the status item.
enum TrayGeometry {
  static let gap: CGFloat = 8
  static let margin: CGFloat = 8

  /// The tray's origin, preferring the LEFT edge of `mainWindowFrame` minus `traySize.width` and the
  /// gap. If that would push the tray off the left edge of `display.visibleFrame`, falls back to
  /// attaching the tray's LEADING edge to the main window's RIGHT edge instead — overlapping the
  /// dashboard is worse than an unreadable off-screen tray, but a readable right-edge attach is better
  /// than either. The vertical origin keeps the tray's top aligned with the main window's top, clamped
  /// into the visible frame the same way `StatusItemGeometry.dashboardOriginBelowStatusItem` clamps Y.
  static func trayOrigin(
    mainWindowFrame: NSRect,
    traySize: NSSize,
    display: StatusItemGeometry.Display
  ) -> NSPoint {
    let visible = display.visibleFrame
    let leftAttachX = mainWindowFrame.minX - traySize.width - gap
    let x: CGFloat
    if leftAttachX >= visible.minX + margin {
      x = leftAttachX
    } else {
      // Off the left edge of this display — attach to the main window's right edge instead. Still
      // clamp into the visible frame in case the window itself is already near the right edge.
      let rightAttachX = mainWindowFrame.maxX + gap
      x = min(rightAttachX, visible.maxX - traySize.width - margin)
    }

    let proposedY = mainWindowFrame.maxY - traySize.height
    let y = clamped(
      proposedY,
      min: visible.minY + margin,
      max: visible.maxY - traySize.height - margin,
      fallback: visible.midY - (traySize.height / 2))

    return NSPoint(x: x, y: y)
  }

  private static func clamped(
    _ value: CGFloat,
    min minValue: CGFloat,
    max maxValue: CGFloat,
    fallback: CGFloat
  ) -> CGFloat {
    guard minValue <= maxValue else { return fallback }
    return min(max(value, minValue), maxValue)
  }
}
