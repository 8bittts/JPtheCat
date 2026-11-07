import AppKit
import SwiftUI

/// The ONE implementation of the parent-anchored tray child window: a genuine `NSWindow` attached as an
/// AppKit CHILD of the single owned `dashboardWindow` via `addChildWindow(_:ordered:)` — explicitly NOT a
/// second independent top-level window. Child-window semantics make AppKit propagate
/// Quit/Dock-hide/close/ordering from the parent for free; this controller owns positioning, the
/// drag-detection lock, and observer teardown.
///
/// `AdvancedAnalyticsWindowController`, `LiveDataWindowController` and `ThemesWindowController` were three
/// byte-identical copies of everything below. The cost was not the line count: it was that ONE
/// observer-teardown path had become three that each had to stay correct forever. They are now thin
/// subclasses supplying only their four genuine deltas — root view, sizing, key policy, and (analytics
/// only) an extra observer removed through `willTearDown()`.
///
/// [Regression guard — stale-state after standard close button] Every subclass's `styleMask` includes
/// `.closable`, so AppKit's standard `close()` path (red traffic light, Escape) must converge on this
/// controller's teardown. `TrayWindow` is its own delegate and implements `windowWillClose(_:)`; `close()`
/// nils `trayWindow` as its first step so a re-entrant call is a guaranteed no-op.
@MainActor
class TrayChildWindowController {
  /// How `open()` sizes the window before anchoring.
  enum ContentSizing {
    /// Fixed width, height measured from the hosted content (`fittingSize` after
    /// `layoutSubtreeIfNeeded()`) so there is no dead space and the window grows a row taller as its
    /// content grows. Explicitly NOT `.preferredContentSize`, which settles the size AFTER anchoring and
    /// left the window mis-positioned. The window is not `.resizable`.
    case intrinsic(width: CGFloat)
    /// A fixed-default, resizable canvas: the hosting view fills the window rather than shrinking to its
    /// intrinsic content, and `contentMinSize` floors a user resize.
    case fixedResizable(default: NSSize, min: NSSize)
  }

  /// Whether the tray may take key focus from the dashboard.
  enum KeyPolicy {
    /// `makeKeyAndOrderFront`. Required by any tray hosting SwiftUI `Toggle(.switch)` rows: AppKit renders
    /// switches DESATURATED GRAY while their window is non-key, so every "on" switch looked off (a real
    /// reported bug). Safe for a tray opened from a Settings ROW rather than a footer toggle.
    case key
    /// `becomesKeyOnlyIfNeeded` + `orderFront`. Required by any tray opened from a FOOTER toggle: staying
    /// non-key keeps the dashboard key, so the footer icon stays single-click responsive and a second
    /// click reliably CLOSES the tray. (A window that becomes key on interaction swallows the next footer
    /// click as an AppKit first-mouse that only re-keys the dashboard.) Only valid with no text input.
    case nonKeyOnlyIfNeeded
  }

  /// An NSPanel (not a plain NSWindow) so a `.nonKeyOnlyIfNeeded` tray can stay non-key while the
  /// dashboard keeps key focus; its controls still respond.
  private final class TrayWindow: NSPanel, NSWindowDelegate {
    var onEscape: (() -> Void)?
    var onWillClose: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    func windowWillClose(_ notification: Notification) { onWillClose?() }
  }

  private weak var parentWindow: NSWindow?
  private var trayWindow: TrayWindow?
  private var resizeObserver: Any?
  private var closeObserver: Any?
  private var trayMoveObserver: Any?
  // [Apple-docs finding] `NSWindow.addChildWindow(_:ordered:)`'s own documentation states "moving the
  // window will cause childWin to move" — AppKit ALREADY relatively-repositions a child window when its
  // parent moves, so this controller does NOT listen for the parent moving. The tray is ANCHORED to its
  // parent at open (right edge flush against the dashboard's left edge, top edges aligned, via
  // `TrayGeometry.trayOrigin`) and immediately marked `userMovedTray` (see `open()`), so
  // `repositionIfOpen()` never fires on a parent resize — the window must not snap back to a default spot
  // when the user switches the parent to the Settings face. The reposition machinery is retained (inert
  // once locked) so the drag-detection / off-primary-clamp guards stay in place.
  private var isRepositioningProgrammatically = false
  private var userMovedTray = false
  private var lastParentFrameSnapshot: NSRect?

  private let contentSizing: ContentSizing
  private let keyPolicy: KeyPolicy
  private let dashboardChrome: DashboardChromeState

  /// The center EVERY tray observer — the base's three and any a subclass adds — must register with.
  /// Production always gets `.default`; injecting it lets `TrayChildWindowTests` COUNT registrations
  /// against removals, so "every observer registered in `open()` is removed in `close()`" is proved at
  /// runtime instead of asserted in a comment.
  let notificationCenter: NotificationCenter

  init(
    dashboardChrome: DashboardChromeState, notificationCenter: NotificationCenter = .default,
    contentSizing: ContentSizing, keyPolicy: KeyPolicy
  ) {
    self.dashboardChrome = dashboardChrome
    self.contentSizing = contentSizing
    self.keyPolicy = keyPolicy
    self.notificationCenter = notificationCenter
  }

  // MARK: - Subclass hooks

  /// The SwiftUI body this tray hosts. Every subclass overrides it; the base has no sensible default, and
  /// an empty one would render a blank window instead of failing.
  func makeRootView() -> AnyView {
    fatalError("TrayChildWindowController subclasses must override makeRootView()")
  }

  /// Called once, at the end of `open()`, with the newly attached window. Default: nothing. A subclass
  /// registering an EXTRA observer here must remove it in `willTearDown()`.
  func windowDidOpen(_ window: NSWindow) {}

  /// Called from `close()` immediately after `trayWindow` is nil'd, before the base tears down its own
  /// three observers. Default: nothing. Every observer a subclass registered in `windowDidOpen(_:)` must
  /// be removed here and its token nil'd.
  func willTearDown() {}

  // MARK: - Lifecycle

  var isOpen: Bool { trayWindow != nil }

  /// Mirrors `StatusBarController.applyDashboardWindowLevel(_:)` — called explicitly from
  /// `toggleDashboardPin()`. No-op if the window isn't open.
  func applyPinnedLevel(_ isPinned: Bool) {
    guard let trayWindow else { return }
    DashboardWindowPresence.apply(
      DashboardWindowPresence.configuration(isPinned: isPinned), to: trayWindow)
  }

  func toggle(attachingTo parent: NSWindow) {
    if isOpen {
      close()
    } else {
      open(attachingTo: parent)
    }
  }

  func open(attachingTo parent: NSWindow) {
    guard !isOpen else { return }
    parentWindow = parent
    // Pre-lock so a later parent RESIZE (e.g. switching the parent to the Settings face) can never
    // auto-snap this parent-anchored window back to its default spot.
    userMovedTray = true
    lastParentFrameSnapshot = parent.frame

    let host = NSHostingController(rootView: makeRootView())
    // Matches `StatusBarController.makeDashboardWindow()`'s `host.safeAreaRegions = []` so the chrome row
    // draws inline with the traffic lights instead of below them.
    host.safeAreaRegions = []
    let window = TrayWindow(contentViewController: host)
    window.styleMask = styleMask
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.backgroundColor = JPAppColor.cardNS
    // Same presence as the dashboard. A pinned tray stays on every Space and does not hide when the
    // user clicks another app. `closeObserver` still closes the tray with the parent.
    DashboardWindowPresence.apply(
      DashboardWindowPresence.configuration(isPinned: dashboardChrome.isPinned), to: window)
    if case .nonKeyOnlyIfNeeded = keyPolicy { window.becomesKeyOnlyIfNeeded = true }
    window.delegate = window
    window.onEscape = { [weak self] in self?.close() }
    window.onWillClose = { [weak self] in self?.close() }
    applyContentSizing(to: window, host: host)
    anchorToParent(window, against: parent)

    parent.addChildWindow(window, ordered: .above)
    switch keyPolicy {
    case .key: window.makeKeyAndOrderFront(nil)
    case .nonKeyOnlyIfNeeded: window.orderFront(nil)
    }
    trayWindow = window

    resizeObserver = notificationCenter.addObserver(
      forName: NSWindow.didResizeNotification, object: parent, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.repositionIfOpen() }
    }
    closeObserver = notificationCenter.addObserver(
      forName: NSWindow.willCloseNotification, object: parent, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
    trayMoveObserver = notificationCenter.addObserver(
      forName: NSWindow.didMoveNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.isRepositioningProgrammatically else { return }
        let currentParentFrame = self.parentWindow?.frame
        guard currentParentFrame == self.lastParentFrameSnapshot else {
          self.lastParentFrameSnapshot = currentParentFrame
          return
        }
        self.userMovedTray = true
      }
    }

    windowDidOpen(window)
  }

  func close() {
    guard let window = trayWindow else { return }
    trayWindow = nil
    willTearDown()
    parentWindow?.removeChildWindow(window)
    window.delegate = nil
    window.orderOut(nil)
    parentWindow = nil
    // [Regression guard] EVERY observer registered in `open()` is removed here and its token nil'd — the
    // invariant that three cloned copies of this method each had to uphold independently.
    if let resizeObserver { notificationCenter.removeObserver(resizeObserver) }
    if let closeObserver { notificationCenter.removeObserver(closeObserver) }
    if let trayMoveObserver { notificationCenter.removeObserver(trayMoveObserver) }
    resizeObserver = nil
    closeObserver = nil
    trayMoveObserver = nil
    lastParentFrameSnapshot = nil
  }

  // MARK: - Geometry

  private var styleMask: NSWindow.StyleMask {
    switch contentSizing {
    case .intrinsic:
      return [.titled, .closable, .fullSizeContentView]
    case .fixedResizable:
      return [.titled, .closable, .resizable, .fullSizeContentView]
    }
  }

  /// Sizes the window BEFORE anchoring so the top-edge anchor math uses the final size.
  private func applyContentSizing(to window: NSWindow, host: NSHostingController<AnyView>) {
    switch contentSizing {
    case .intrinsic(let width):
      host.view.layoutSubtreeIfNeeded()
      window.setContentSize(NSSize(width: width, height: host.view.fittingSize.height))
    case .fixedResizable(let defaultSize, let minSize):
      window.contentMinSize = minSize
      window.setContentSize(defaultSize)
    }
  }

  private func repositionIfOpen() {
    guard !userMovedTray else { return }
    guard let window = trayWindow, let parent = parentWindow else { return }
    anchorToParent(window, against: parent)
  }

  /// Anchors the window to the LEFT of the main dashboard (right edge flush against the dashboard's left
  /// edge, top edges aligned) via the shared `TrayGeometry.trayOrigin`, keeping its
  /// multi-display/negative-origin clamp. Since `open()` pre-locks `userMovedTray`, this only runs at
  /// open — a parent resize never re-anchors it.
  private func anchorToParent(_ window: NSWindow, against parent: NSWindow) {
    guard let screen = parent.screen ?? NSScreen.main else { return }
    let display = StatusItemGeometry.Display(screen: screen)
    let origin = TrayGeometry.trayOrigin(
      mainWindowFrame: parent.frame, traySize: window.frame.size, display: display)
    isRepositioningProgrammatically = true
    window.setFrameOrigin(origin)
    isRepositioningProgrammatically = false
    lastParentFrameSnapshot = parent.frame
  }
}
