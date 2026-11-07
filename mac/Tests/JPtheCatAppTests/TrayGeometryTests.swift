import AppKit
import XCTest

@testable import JPtheCatApp

final class TrayGeometryTests: XCTestCase {
  func testAttachesToTheLeftOfTheMainWindowOnASingleDisplay() {
    let display = StatusItemGeometry.Display(
      frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
      visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055))
    let mainWindowFrame = NSRect(x: 800, y: 300, width: 384, height: 500)
    let traySize = NSSize(width: 320, height: 420)

    let origin = TrayGeometry.trayOrigin(
      mainWindowFrame: mainWindowFrame, traySize: traySize, display: display)

    XCTAssertEqual(origin.x, mainWindowFrame.minX - traySize.width - TrayGeometry.gap, accuracy: 0.001)
    XCTAssertEqual(origin.y, mainWindowFrame.maxY - traySize.height, accuracy: 0.001)
  }

  func testStaysOnAnOffPrimaryDisplayWithANegativeOrigin() {
    let externalLeft = StatusItemGeometry.Display(
      frame: NSRect(x: -2560, y: -261, width: 2560, height: 1440),
      visibleFrame: NSRect(x: -2560, y: -261, width: 2560, height: 1440))
    // Main window sits near the LEFT edge of this off-primary display — a naive left-attach would
    // push the tray fully off-screen.
    let mainWindowFrame = NSRect(x: -2550, y: 100, width: 384, height: 500)
    let traySize = NSSize(width: 320, height: 420)

    let origin = TrayGeometry.trayOrigin(
      mainWindowFrame: mainWindowFrame, traySize: traySize, display: externalLeft)

    XCTAssertGreaterThanOrEqual(origin.x, externalLeft.visibleFrame.minX + TrayGeometry.margin - 0.001)
    XCTAssertLessThanOrEqual(origin.x + traySize.width, externalLeft.visibleFrame.maxX + 0.001)
  }

  func testFallsBackToTheRightEdgeWhenTheLeftAttachWouldGoOffScreen() {
    let display = StatusItemGeometry.Display(
      frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
      visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055))
    // Main window pinned right at the left edge of this display.
    let mainWindowFrame = NSRect(x: 4, y: 300, width: 384, height: 500)
    let traySize = NSSize(width: 320, height: 420)

    let origin = TrayGeometry.trayOrigin(
      mainWindowFrame: mainWindowFrame, traySize: traySize, display: display)

    // The naive left-attach (mainWindowFrame.minX - traySize.width - gap) would be deeply negative
    // and off this display's visible frame; the fallback must attach to the window's right edge.
    XCTAssertEqual(origin.x, mainWindowFrame.maxX + TrayGeometry.gap, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(origin.x, display.visibleFrame.minX)
  }

  func testVerticalOriginClampsIntoTheVisibleFrame() {
    let display = StatusItemGeometry.Display(
      frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
      visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055))
    // Main window near the very top, taller tray than available headroom.
    let mainWindowFrame = NSRect(x: 800, y: 1000, width: 384, height: 100)
    let traySize = NSSize(width: 320, height: 900)

    let origin = TrayGeometry.trayOrigin(
      mainWindowFrame: mainWindowFrame, traySize: traySize, display: display)

    XCTAssertGreaterThanOrEqual(origin.y, display.visibleFrame.minY + TrayGeometry.margin - 0.001)
    XCTAssertLessThanOrEqual(origin.y + traySize.height, display.visibleFrame.maxY + 0.001)
  }
}
