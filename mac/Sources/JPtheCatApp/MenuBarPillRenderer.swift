import AppKit
import JPtheCatCore

/// Stateless AppKit drawing for the two menu-bar status-item faces: the data-state status PILL
/// (JP mark + figure on a light chip) and the cold-launch LOADING pixel grid.
///
/// Extracted out of `StatusBarController` so the drawing is exercisable without a live
/// `NSStatusItem`: every input arrives as a parameter and the only output is an `NSImage`, so a test
/// can render a face and assert on real pixels (`MenuBarPillRendererTests`). Everything stateful
/// stays in the controller — the `statusItem.button` image assignment, `statusItem.length`, the
/// hosted-view redraw, and the loading `Timer`.
///
/// [CRITICAL] The pill is a shipped, test-pinned surface — see
/// `_docs/12-ui-surface-invariants.md`, "Menu Bar Display Format & Status Pill". Two invariants ride
/// on this drawing:
///   - the pill is a FIXED light chip, never theme-following (the macOS menu bar's light/dark state
///     follows the SYSTEM, not the app theme), so the palette is supplied by the caller and this
///     renderer never reads `ThemeManager`/`JPAppColor`; and
///   - the 80% warning / 95% critical attention signal is BORDER-ONLY — it must never tint the fill,
///     the ink, or the mark.
/// Geometry comes from `StatusPillMetrics` alone; never re-derive it here.
enum MenuBarPillRenderer {
  /// Draws today's figure as a light, rounded "card" (mark + text) as a single
  /// resolution-independent image, so the pill stays crisp at any display scale.
  ///
  /// `thickness` is the menu bar's height (`NSStatusBar.system.thickness` in the app) — a parameter
  /// rather than a read so the face can be rendered at 22pt, 24pt, and notch heights in a test.
  static func pillImage(
    text: String,
    attention: MenuBarAttentionState,
    mark: NSImage?,
    ink: NSColor,
    fill: NSColor,
    borderNormal: NSColor,
    borderWarning: NSColor,
    borderCritical: NSColor,
    thickness: CGFloat
  ) -> NSImage {
    let font = JPAppFont.statusPillFont
    let attributed = NSAttributedString(
      string: text, attributes: [.font: font, .foregroundColor: ink])
    let textSize = attributed.size()

    let layout = StatusPillMetrics.statusItemLayout(
      measuredTextWidth: ceil(textSize.width),
      statusBarThickness: thickness)

    let border = borderColor(
      for: attention, normal: borderNormal, warning: borderWarning, critical: borderCritical)
    let image = NSImage(size: layout.imageSize, flipped: false) { _ in
      let pillRect = layout.pillRect
      // Inset by half the line width so the 1pt stroke sits fully inside the image.
      let path = NSBezierPath(
        roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5),
        xRadius: StatusPillMetrics.cornerRadius,
        yRadius: StatusPillMetrics.cornerRadius)
      fill.setFill()
      path.fill()
      border.setStroke()
      path.lineWidth = 1
      path.stroke()

      if let mark {
        // Full-size mark (no rim, no inset). Instead of a hard oval clip — which showed a crisp
        // outline where the mark overhangs onto the menu bar, notably on the leading edge — the
        // mark's rim is feathered with a VERY light radial fade: fully opaque until ~92% of the
        // radius, then dissolving to clear right at the edge so no hard circle line is visible.
        let markRect = layout.markRect
        let feathered = NSImage(size: markRect.size, flipped: false) { bounds in
          mark.draw(in: bounds)
          let center = NSPoint(x: bounds.midX, y: bounds.midY)
          let radius = min(bounds.width, bounds.height) / 2
          let mask = NSGradient(
            colors: [
              NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 0),
            ],
            atLocations: [0, 0.92, 1.0], colorSpace: .deviceGray)
          NSGraphicsContext.current?.compositingOperation = .destinationIn
          mask?.draw(
            fromCenter: center, radius: 0, toCenter: center, radius: radius,
            options: .drawsAfterEndingLocation)
          return true
        }
        feathered.draw(in: markRect)
      }

      attributed.draw(at: NSPoint(x: layout.textOriginX, y: (thickness - textSize.height) / 2))
      return true
    }
    image.isTemplate = false
    return image
  }

  /// The menu-bar loading state: a small grid of "pixels" that fills up (bottom→top, left→right per
  /// row) while data loads. Drawn as one image so it sits on the bar's exact optical center.
  static func loadingPixelImage(
    filled: Int,
    cols: Int,
    rows: Int,
    mark: NSImage?,
    thickness: CGFloat
  ) -> NSImage {
    let cell: CGFloat = 2
    let gap: CGFloat = 1
    let gridW = CGFloat(cols) * cell + CGFloat(cols - 1) * gap
    let gridH = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
    let markSize: CGFloat = 18
    let markGap: CGFloat = 4
    let width = markSize + markGap + gridW
    // Adaptive label color (not the fixed dark pill ink) so the pixels stay visible on a DARK menu
    // bar — the grid has no light pill behind it, unlike the data-state status pill.
    let ink = NSColor.labelColor
    let image = NSImage(size: NSSize(width: width, height: thickness), flipped: false) { _ in
      if let mark {
        let markRect = NSRect(x: 0, y: (thickness - markSize) / 2, width: markSize, height: markSize)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: markRect).addClip()
        mark.draw(in: markRect)
        NSGraphicsContext.restoreGraphicsState()
      }
      let originX = markSize + markGap
      let originY = (thickness - gridH) / 2
      var idx = 0
      for r in 0..<rows {  // r == 0 is the bottom row → the grid fills upward
        for c in 0..<cols {
          let on = idx < filled
          idx += 1
          let x = originX + CGFloat(c) * (cell + gap)
          let y = originY + CGFloat(r) * (cell + gap)
          (on ? ink : ink.withAlphaComponent(0.18)).setFill()
          NSBezierPath(rect: NSRect(x: x, y: y, width: cell, height: cell)).fill()
        }
      }
      return true
    }
    image.isTemplate = false
    return image
  }

  /// The attention border is the usage-limit signal (warning >=80% / critical >=95%). Never a fill.
  private static func borderColor(
    for attention: MenuBarAttentionState,
    normal: NSColor,
    warning: NSColor,
    critical: NSColor
  ) -> NSColor {
    switch attention {
    case .normal:
      normal
    case .warning:
      warning
    case .critical:
      critical
    }
  }
}
