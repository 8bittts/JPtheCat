import AppKit

enum StatusItemGeometry {
  struct Display: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect

    init(frame: NSRect, visibleFrame: NSRect) {
      self.frame = frame
      self.visibleFrame = visibleFrame
    }

    init(screen: NSScreen) {
      self.init(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
  }

  static let dashboardMargin: CGFloat = 8
  static let dashboardGap: CGFloat = 6

  static func statusButtonContains(
    mouseLocation: NSPoint,
    statusButtonScreenFrame: NSRect?
  ) -> Bool {
    guard let statusButtonScreenFrame else { return false }
    return statusButtonScreenFrame.contains(mouseLocation)
  }

  static func compactMenuPopupPoint(buttonBounds: NSRect) -> NSPoint {
    NSPoint(x: buttonBounds.minX, y: buttonBounds.maxY)
  }

  static func dashboardOriginBelowStatusItem(
    anchor: NSRect,
    windowSize: NSSize,
    preferredDisplay: Display?,
    displays: [Display]
  ) -> NSPoint? {
    guard
      let display = preferredDisplay
        ?? displays.first(where: { $0.frame.intersects(anchor) })
        ?? displays.first
    else { return nil }

    let visible = display.visibleFrame
    let proposedX = anchor.midX - (windowSize.width / 2)
    let proposedY = anchor.minY - windowSize.height - dashboardGap
    let x = clamped(
      proposedX,
      min: visible.minX + dashboardMargin,
      max: visible.maxX - windowSize.width - dashboardMargin,
      fallback: visible.midX - (windowSize.width / 2))
    let y = clamped(
      proposedY,
      min: visible.minY + dashboardMargin,
      max: visible.maxY - windowSize.height - dashboardMargin,
      fallback: visible.midY - (windowSize.height / 2))
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
