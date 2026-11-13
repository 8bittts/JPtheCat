import AppKit
import JPtheCatCore
import OSLog
import SwiftUI

/// The menu-bar status item. The title, dashboard window, and compact menu are all derived from the same
/// `DashboardViewModel` snapshot so the dollar figure cannot drift between surfaces. The compact
/// bar stays icon + today's total; the dashboard, menu, tooltip, and VoiceOver value carry the
/// notional/list-price and rate-limit detail.
@MainActor
final class StatusBarController {
  private let statusItem: NSStatusItem
  private var refreshCoordinator: RefreshCoordinator?
  private var loadingDotsTimer: Timer?

  // Menu-bar limit rotation (only for a rotating format — a limit kind with no pinned provider). The
  // pill cycles one live window at a time every 3s ("Claude 45% (5hr)" → "Claude 87% (W)" → …).
  // Rebuilt every refresh; the timer runs only when the format is rotating AND >1 live window exists.
  // `limitRotationIndex` is preserved across refreshes (clamped) so the visible window doesn't jump.
  private var rotatableLimits: [MenuBarProviderLimit] = []
  private var limitRotationIndex = 0
  private var limitRotationTimer: Timer?
  private static let limitRotationInterval: TimeInterval = 3

  private var loadingPixelStep = 0
  private let loadingPixelCols = 4
  private let loadingPixelRows = 4
  private let index: UsageIndex?  // held once; UsageIndex serializes its SQLite connection internally
  private let remotePricing = RemotePricingStore()  // bundled → remote ETag override; fail-closed
  private var lastRemotePricingAttempt: Date?
  private var markImage: NSImage?  // JP mark, re-applied for the loading state and drawn into the pill

  // Pill palette — a fixed LIGHT paper "card" (JP mark + total), NOT theme-following. The macOS menu
  // bar's light/dark state follows the SYSTEM (wallpaper/OS), independent of the app theme, so a
  // theme-colored pill would vanish on a mismatched bar (a Midnight-dark pill on a dark menu bar is
  // ~1:1). A light paper chip with a soft border + dark ink reads as a legible card on BOTH a light
  // and a dark menu bar — the same reason the loading grid uses the system-adaptive `labelColor`. The
  // dashboard WINDOW (an app surface) still re-themes; only this menu-bar chip is pinned light.
  private let pillFill = NSColor(jpHex: JPTheme.sunlit.paper)
  // Soft-but-present normal edge (a touch of definition without reading "strong"). The attention
  // borders are the usage-limit signal (warning >=80% / critical >=95%); they stay warm/alert but
  // are toned down from full-saturation so they read calmer, not alarming.
  private let pillBorder = NSColor(jpHex: JPTheme.sunlit.lineStrong).withAlphaComponent(0.5)
  private let pillWarningBorder = NSColor(jpHex: JPTheme.sunlit.gingerDeep).withAlphaComponent(0.65)
  private let pillCriticalBorder = NSColor(jpHex: JPTheme.sunlit.coral).withAlphaComponent(0.7)
  private let pillInk = NSColor(jpHex: JPTheme.sunlit.ink)

  // Left-click opens the movable SwiftUI dashboard window; right-click opens the compact menu.
  private let dashboard: DashboardViewModel
  private let dashboardChrome = DashboardChromeState()
  private let menuBarDisplayPresentation = MenuBarDisplayPresentationState()
  private var menu: NSMenu!
  private var localSecondaryClickMonitor: Any?
  private var globalSecondaryClickMonitor: Any?
  private var themeObserver: Any?  // re-themes the dashboard window background on a theme change
  private var settingsObserver: Any?  // fans settings mutations out to non-SwiftUI consumers
  private var layoutObserver: Any?  // captures the card frame the instant the layout setting changes

  private var updateItem: NSMenuItem?
  private var dashboardWindow: NSWindow?
  private var dashboardHost: NSHostingController<DashboardView>?
  /// Observes `NSWindow.didChangeOcclusionStateNotification` for the dashboard window so its animated
  /// surfaces can stop evaluating while nothing is visible. See `DashboardMotionGate`.
  private var occlusionObserver: Any?
  /// AppKit resizes the window to the hosting controller's new size keeping the TOP-LEFT corner, so
  /// a layout switch would move the chrome toggle away from the pointer. The pre-switch frame is kept
  /// until that resize lands, then the card is re-anchored on its trailing edge.
  private var layoutSwitchAnchorFrame: NSRect?
  private var dashboardResizeObserver: Any?
  private lazy var advancedAnalytics = AdvancedAnalyticsWindowController(
    index: index, pricing: remotePricing.resolvedTable(), dashboardChrome: dashboardChrome)
  private lazy var liveDataWindow = LiveDataWindowController(
    model: dashboard, dashboardChrome: dashboardChrome)
  private lazy var themesWindow = ThemesWindowController(dashboardChrome: dashboardChrome)
  // Set while a forced-foreground reveal (e.g. a tapped usage alert) has temporarily promoted an
  // accessory (hidden-Dock) app to `.regular` so it can truly become frontmost; restored after.
  private var activationPolicyBeforeReveal: NSApplication.ActivationPolicy?

  init() {
    index = (try? UsageIndex.defaultURL().path).flatMap { try? UsageIndex(path: $0) }
    // Seed pricing from the resolved table (bundled + any cached remote override) BEFORE the first
    // refresh, so launch figures are correct with zero network I/O; the async GET below hot-swaps only
    // on a real change.
    dashboard = DashboardViewModel(index: index, pricing: remotePricing.resolvedTable())

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      button.font = JPAppFont.statusItemFont
      if let mark = AppResources.image(forResource: "jp-menubar") {
        mark.size = NSSize(width: 18, height: 18)
        mark.isTemplate = false
        markImage = mark
        button.image = mark
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
      }
      renderLoadingPixels()
      button.action = #selector(statusItemClicked)
      button.target = self
      button.sendAction(on: [.leftMouseUp])
      button.setAccessibilityLabel("JP the Cat AI coding cost")
      button.setAccessibilityHelp("Opens today's provider dashboard")
    }

    menu = NSMenu()
    menu.autoenablesItems = false  // keep info rows at full contrast
    menu.addItem(makeHeader(Self.menuHeaderTitle))
    menu.addItem(.separator())
    let refreshItem = NSMenuItem(
      title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    refreshItem.target = self
    menu.addItem(refreshItem)
    if Updater.isConfigured {
      let item = NSMenuItem(
        title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
      updateItem = item
    }
    menu.addItem(.separator())
    let quitItem = NSMenuItem(title: "Quit JP the Cat", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
    statusItem.button?.menu = menu

    dashboard.onDidUpdate = { [weak self] in
      self?.updateFromDashboard()
      self?.scheduleDashboardWindowSizeSync()
    }
    // Tapping a usage-alert notification must foreground the app above all windows, even in
    // hidden-Dock mode — hence forceForeground.
    UsageAlertCenter.shared.onActivate = { [weak self] in
      self?.showDashboardWindow(forceForeground: true)
    }
    localSecondaryClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      guard let self else { return event }
      guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else {
        return event
      }
      return self.handleSecondaryMouseDown(event) ? nil : event
    }
    globalSecondaryClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return }
      let mouseLocation = NSEvent.mouseLocation
      Task { @MainActor [weak self] in
        _ = self?.handleSecondaryMouseDown(mouseLocation: mouseLocation)
      }
    }
    startLoadingDots()
    // Adaptive cadence, seeded from the user's "Refresh rate" preset (Balanced == 60s active / 300s
    // idle by default), with a short burst after the dashboard opens. Coalescing/one-in-flight lives
    // in DashboardViewModel; a cadence change re-arms this SINGLE timer via `setSchedule` below.
    // The same ticks re-check the hosted price table (launch, then daily), so no second loop exists.
    let coordinator = RefreshCoordinator(
      schedule: SettingsStore.refreshCadence().schedule,
      watchPaths: dashboard.watchPaths(),
      isActive: { [weak self] in self?.dashboardWindow?.isVisible ?? false },
      onRefresh: { [weak self] reindex in
        self?.dashboard.refresh(reindex: reindex)
        if reindex { self?.refreshRemotePricingIfDue() }
      })
    refreshCoordinator = coordinator
    coordinator.start()
    migrateScanIndexOffMain()

    // Re-color the dashboard WINDOW background the moment the theme flips; the SwiftUI content
    // re-themes on its own via ThemeManager, and `NSApp.appearance` (already applied by ThemeManager)
    // makes the NSMenu follow. The menu-bar pill is a fixed light chip (theme-independent), so it is
    // intentionally NOT redrawn here.
    themeObserver = NotificationCenter.default.addObserver(
      forName: ThemeManager.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.dashboardWindow?.backgroundColor = JPAppColor.cardNS
      }
    }

    settingsObserver = NotificationCenter.default.addObserver(
      forName: SettingsStore.didChangeNotification, object: SettingsStore.shared, queue: .main
    ) { [weak self] notification in
      // Extract the Sendable change in this nonisolated observer block so only it (not the
      // non-Sendable Notification) crosses into the main-actor closure.
      let change = SettingsStore.change(from: notification)
      MainActor.assumeIsolated {
        self?.handleSettingsChange(change)
      }
    }

    // `queue: nil` delivers inside the setter, before SwiftUI re-renders the card at its new width, so
    // the captured frame is still the pre-switch one. The `.main` observer above can run too late.
    layoutObserver = NotificationCenter.default.addObserver(
      forName: SettingsStore.didChangeNotification, object: SettingsStore.shared, queue: nil
    ) { [weak self] notification in
      guard SettingsStore.change(from: notification)?.key == SettingsStore.Key.dashboardLayout else { return }
      MainActor.assumeIsolated {
        guard let self else { return }
        self.layoutSwitchAnchorFrame = self.dashboardWindow?.frame
      }
    }

  }

  // `isolated deinit` runs teardown on the main actor (this is a @MainActor class), so it can safely
  // touch the main-actor-isolated, non-Sendable timers/monitors/observers/statusItem below — all of
  // which are main-thread cleanup APIs anyway. RefreshCoordinator's non-repeating [weak self] timer
  // still self-terminates on dealloc; process teardown is imminent regardless.
  isolated deinit {
    loadingDotsTimer?.invalidate()
    limitRotationTimer?.invalidate()
    if let localSecondaryClickMonitor { NSEvent.removeMonitor(localSecondaryClickMonitor) }
    if let globalSecondaryClickMonitor { NSEvent.removeMonitor(globalSecondaryClickMonitor) }
    if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    if let layoutObserver { NotificationCenter.default.removeObserver(layoutObserver) }
    NSStatusBar.system.removeStatusItem(statusItem)  // symmetric with statusItem(withLength:)
  }

  /// Fire-and-forget conditional GET of the remote pricing table, at most once per
  /// `RemotePricingRefreshPolicy.interval`. Pricing is best-effort: a `304`, network error, or
  /// malformed body returns nil and the app keeps its bundled-or-cached prices, so this must never
  /// block launch or the UI. Only a genuinely new table hot-swaps via `updatePricing`, which re-derives
  /// every dollar figure from the already-indexed tokens (no disk re-scan).
  private func refreshRemotePricingIfDue(now: Date = Date()) {
    guard RemotePricingRefreshPolicy.isDue(lastAttempt: lastRemotePricingAttempt, now: now) else { return }
    lastRemotePricingAttempt = now
    Task { [weak self] in
      guard let self, let updated = await self.remotePricing.refresh() else { return }
      self.dashboard.updatePricing(updated)
    }
  }

  private func makeHeader(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  /// The disabled first row of the right-click menu: brand name · running version (e.g.
  /// `JP the Cat · v0.050`). Reads `CFBundleShortVersionString`; raw SwiftPM launches with no
  /// Info.plist fall back to `v—`.
  private static var menuHeaderTitle: String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    return "JP the Cat · v\(short)"
  }

  @objc private func refreshNow() { refreshCoordinator?.refreshNow() ?? refreshAll() }
  @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }
  @objc private func quit() { NSApplication.shared.terminate(nil) }

  /// Reflect the latest known update state on the "Check for Updates…" row: when the feed has a
  /// newer build it reads "Update is available!". A silent probe on open keeps it fresh.
  private func syncUpdateItemTitle() {
    guard let updateItem else { return }
    updateItem.title = Updater.shared.updateAvailable ? "Update is available!" : "Check for Updates…"
  }

  private func handleSettingsChange(_ change: SettingsStore.Change?) {
    guard let change else { return }
    switch change.key {
    case SettingsStore.Key.usageAlertsEnabled, SettingsStore.Key.alertBannerEnabled:
      UsageAlertCenter.shared.requestBannerAuthorizationIfNeeded()
    case SettingsStore.Key.menuBarDisplayFormat:
      updateTitle()
    case SettingsStore.Key.refreshCadence:
      refreshCoordinator?.setSchedule(SettingsStore.refreshCadence().schedule)
    default:
      break
    }
  }

  /// Left-click (or a plain click) opens the dashboard window; Control-click opens the compact menu.
  /// Secondary-click events may be delivered either to JP's status button window or through the system
  /// menu-bar event path. Keep both monitors: local consumes app-delivered right-clicks; global catches
  /// system-routed menu-bar right-clicks after hit-testing JP's status-button screen rect.
  @objc private func statusItemClicked() {
    let event = NSApp.currentEvent
    if event?.modifierFlags.contains(.control) ?? false {
      showMenu()
    } else if let window = dashboardWindow,
      StatusItemClickDecision.shouldDismiss(
        isVisible: window.isVisible,
        isMiniaturized: window.isMiniaturized,
        appActive: NSApp.isActive,
        coveredByOtherApp: isCoveredByOtherApp(window))
    {
      // Toggle-to-dismiss only when the dashboard is the surface the user is looking at. See
      // `StatusItemClickDecision` for why `isVisible` and `NSApp.isActive` are each insufficient.
      window.close()
    } else {
      // Closed, miniaturized, OR open-but-buried/unfocused → bring it forward and focus it.
      showDashboardWindow(anchorToStatusItem: true)
    }
  }

  /// True when another app's normal-level window overlaps the dashboard from above, i.e. the
  /// dashboard is buried. Reads only window bounds, layer, and owner PID, which need no Screen
  /// Recording permission.
  private func isCoveredByOtherApp(_ window: NSWindow) -> Bool {
    guard
      let info = CGWindowListCopyWindowInfo(
        [.optionOnScreenAboveWindow, .excludeDesktopElements], CGWindowID(window.windowNumber))
        as? [[String: Any]]
    else { return false }
    let windowsAbove = info.compactMap(StatusItemClickDecision.WindowAbove.init(info:))
    return StatusItemClickDecision.isCovered(
      frame: window.frame.cgQuartzRect,
      by: windowsAbove,
      ownPID: ProcessInfo.processInfo.processIdentifier)
  }

  private func handleSecondaryMouseDown(_: NSEvent) -> Bool {
    handleSecondaryMouseDown(mouseLocation: NSEvent.mouseLocation)
  }

  private func handleSecondaryMouseDown(mouseLocation: NSPoint) -> Bool {
    guard isMouseLocationInStatusButton(mouseLocation) else { return false }
    showMenu()
    return true
  }

  private func isMouseLocationInStatusButton(_ mouseLocation: NSPoint) -> Bool {
    StatusItemGeometry.statusButtonContains(
      mouseLocation: mouseLocation,
      statusButtonScreenFrame: statusButtonScreenFrame())
  }

  private func showMenu() {
    guard let button = statusItem.button else { return }
    syncUpdateItemTitle()  // reflect the last known state immediately
    if Updater.isConfigured { Updater.shared.checkForUpdatesInBackground() }
    button.highlight(true)  // show the pressed state while the menu tracks (synchronous)
    menu.popUp(
      positioning: nil,
      at: StatusItemGeometry.compactMenuPopupPoint(buttonBounds: button.bounds),
      in: button)
    button.highlight(false)
  }

  /// Dashboard window that closes on Escape (`cancelOperation`) for keyboard dismissal.
  private final class DashboardWindow: NSWindow {
    var onClose: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
      super.close()
      onClose?()
    }
  }

  /// Hosting view that accepts the first mouse so a click on the dashboard card fires its control in
  /// the SAME click that re-activates the window, instead of being swallowed just to change focus.
  ///
  /// [Regression guard] The Advanced Analytics tray is a child `NSWindow`; clicking inside it (e.g.
  /// checking a provider) makes the TRAY the key window. A return-click on any dashboard control —
  /// notably the footer's own Advanced Analytics icon, which toggles the tray shut — then lands on the
  /// now non-key parent, and AppKit spends that click only re-keying the parent (`NSView.acceptsFirstMouse`
  /// defaults to `false`), so the tray stayed open until a THIRD click. Overriding `acceptsFirstMouse`
  /// on the card's hosting view fixes every dashboard control at once (matching menu-bar-app popover UX)
  /// without an overlay that would swallow SwiftUI hover tracking. Guard:
  /// `DashboardHostingFirstMouseTests`.
  private final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    private final class FirstMouseHostingView<V: View>: NSHostingView<V> {
      override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    override func loadView() {
      view = FirstMouseHostingView(rootView: rootView)
    }
  }

  /// The main app window hosting the full dashboard. Created lazily; shown on launch, Dock-icon
  /// reopen, and status-item click. Full-size content + hidden title bar so the card's own top bar
  /// reads as the window chrome; `windowChrome: true` insets that top bar past the traffic lights.
  ///
  /// `forceForeground` is for reveals the user explicitly summoned from outside the app — a tapped
  /// usage-alert notification — where the app MUST become frontmost above every other window. In
  /// hidden-Dock (`.accessory`) mode a bare `NSApp.activate()` cannot foreground the app, so we
  /// temporarily promote to `.regular` (mirroring `Updater`) and restore once the reveal settles.
  /// Ordinary status-item clicks leave it `false` so they don't flash a Dock icon.
  func showDashboardWindow(anchorToStatusItem: Bool = false, forceForeground: Bool = false) {
    let window = dashboardWindow ?? makeDashboardWindow()
    let shouldAnchor = anchorToStatusItem && !window.isVisible
    dashboard.refresh()
    refreshCoordinator?.burst()  // catch just-written logs, then settle to the adaptive cadence
    if shouldAnchor { positionDashboardWindowBelowStatusItem(window) }
    if window.isMiniaturized { window.deminiaturize(nil) }
    prepareDashboardWindowLevelForReveal(window)
    if forceForeground {
      // Summoned from outside (tapped usage-alert): must rise above every OTHER app's window. The
      // cooperative combo can't do that (see `AppForeground`); promote out of accessory first, then
      // force-foreground.
      promoteToForegroundForReveal()
      AppForeground.raiseAboveOtherApps()
    } else {
      // Ordinary status-item click: the user clicked OUR item, so foregrounding above the frontmost
      // app IS the intent. The cooperative zero-arg `NSApp.activate()` is only a REQUEST that macOS
      // frequently DENIES from the background (a status-item click carries no activation yield from
      // the active app), which left the revealed window visible-but-unfocused — the "trouble focusing"
      // half of the bug, and the same failure class already fixed for Sparkle/alerts. Route through
      // `AppForeground` (`NSApp.activate(ignoringOtherApps:)`) which reliably keys the window. No
      // `.regular` promotion here, so hidden-Dock (`.accessory`) mode still never flashes a Dock icon.
      AppForeground.raiseAboveOtherApps()
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    scheduleDashboardWindowSizeSync()
  }

  /// One-time schema migration to the covering scan index, on a background task at `.utility`.
  ///
  /// [Regression guard] This must NOT run inline in `UsageIndex.createSchema()`, which `init` runs
  /// synchronously on `@MainActor` at launch — a large existing corpus makes that a first-launch-after-
  /// update freeze. A fresh (empty) database still builds it inline in `createSchema`, where it costs
  /// nothing.
  ///
  /// Running it after `coordinator.start()` means the first refresh may use the old plan; that is
  /// fine (correctness is unaffected, only speed) and it keeps first paint off the migration.
  private func migrateScanIndexOffMain() {
    guard let index else { return }
    let lastCompact = SettingsStore.shared.lastIndexCompaction
    Task.detached(priority: .utility) {
      // Each step is independently caught: a failure in one must not skip the others, and none of
      // them is worth surfacing to the user — the app works fine on the old shape, just larger.
      do { try index.migrateScanIndexIfNeeded() } catch {
        Log.usage.error("Scan-index migration failed: \(String(describing: error), privacy: .public)")
      }
      do { try index.migrateSourcePathIndexIfNeeded() } catch {
        Log.usage.error("Source-path index migration failed: \(String(describing: error), privacy: .public)")
      }
      do { try index.dropUnusedTimestampIndexIfNeeded() } catch {
        Log.usage.error("Timestamp-index drop failed: \(String(describing: error), privacy: .public)")
      }
      // Compaction runs LAST, so it reclaims the pages the migrations just freed. Gated on a
      // persisted date as well as the freelist share, so it can never run on consecutive launches —
      // it is a whole-file rewrite, not a routine maintenance tick.
      // `dropUnusedTimestampIndexIfNeeded` already VACUUMs when the drop itself left ≥15% free pages.
      guard Self.compactionIsDue(lastCompact: lastCompact) else { return }
      do {
        if try index.compactIfNeeded() {
          await MainActor.run { SettingsStore.shared.lastIndexCompaction = Date() }
        }
      } catch {
        Log.usage.error("Index compaction failed: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// At most once a week. A nil date (never compacted) is due.
  nonisolated static func compactionIsDue(
    lastCompact: Date?, now: Date = Date(), interval: TimeInterval = 7 * 24 * 60 * 60
  ) -> Bool {
    guard let lastCompact else { return true }
    return now.timeIntervalSince(lastCompact) >= interval
  }

  /// Installs the occlusion observer for the dashboard window. Apple documents this notification as
  /// exactly the signal to "save power by halting expensive operations that the user can't see"
  /// (`NSWindow.didChangeOcclusionStateNotification`, macOS 10.9+).
  ///
  /// Note the ordering: `dashboardChrome.motionPaused` is written ONLY from inside this handler, never
  /// from an eager `window.occlusionState` read at construction. Outside a real `NSApplication.run()`
  /// event loop `occlusionState` reports permanently non-visible and delivers no notifications at all,
  /// so an eager read would freeze every animation in raw `swift run` mode — the same launch-mode
  /// hazard that bites bundle identity, Sparkle, and activation policy. No notification ever
  /// therefore means never paused. See `DashboardMotionGate`.
  private func observeOcclusion(of window: NSWindow) {
    teardownOcclusionObserver()
    occlusionObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
    ) { [weak self, weak window] _ in
      MainActor.assumeIsolated {
        guard let self, let window else { return }
        self.dashboardChrome.motionPaused = DashboardMotionGate.shouldPauseMotion(
          hasObservedOcclusion: true,
          occlusionVisible: window.occlusionState.contains(.visible))
      }
    }
  }

  private func observeLayoutSwitchResize(of window: NSWindow) {
    teardownDashboardResizeObserver()
    dashboardResizeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResizeNotification, object: window, queue: nil
    ) { [weak self, weak window] _ in
      MainActor.assumeIsolated {
        guard let self, let window, let anchor = self.layoutSwitchAnchorFrame,
          let next = DashboardWindowSizing.frameAfterLayoutSwitch(
            anchor: anchor, resizedFrame: window.frame, visibleFrame: window.screen?.visibleFrame)
        else { return }
        // Cleared first: the corrective `setFrame` below posts its own resize notification.
        self.layoutSwitchAnchorFrame = nil
        window.setFrame(next, display: true, animate: false)
      }
    }
  }

  private func teardownDashboardResizeObserver() {
    if let dashboardResizeObserver { NotificationCenter.default.removeObserver(dashboardResizeObserver) }
    dashboardResizeObserver = nil
    layoutSwitchAnchorFrame = nil
  }

  private func teardownOcclusionObserver() {
    if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    occlusionObserver = nil
    // A released window can never deliver another notification, so leaving a stale `true` here would
    // freeze motion on the next reveal. Always fail open.
    dashboardChrome.motionPaused = false
  }

  private func makeDashboardWindow() -> NSWindow {
    let host = FirstMouseHostingController(
      rootView: DashboardView(
        model: dashboard,
        windowChrome: true,
        chrome: dashboardChrome,
        menuBarDisplayPresentation: menuBarDisplayPresentation,
        onToggleWindowPin: { [weak self] in self?.toggleDashboardPin() },
        onSurfaceSizeChange: { [weak self] in self?.scheduleDashboardWindowSizeSync() },
        onOpenAdvancedAnalytics: { [weak self] in self?.toggleAdvancedAnalytics() },
        onOpenLiveData: { [weak self] in self?.toggleLiveData() },
        onOpenThemes: { [weak self] in self?.toggleThemes() }))
    host.sizingOptions = .preferredContentSize
    host.safeAreaRegions = []
    let window = DashboardWindow(contentViewController: host)
    window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.title = "JP the Cat"
    window.isReleasedWhenClosed = false
    window.backgroundColor = JPAppColor.cardNS  // mirrors JP.card for the active theme
    window.setContentSize(DashboardSurfaceMetrics.initialWindowSize(for: SettingsStore.shared.dashboardLayout))
    window.initialFirstResponder = host.view  // land keyboard/VoiceOver focus in the card on open
    window.onClose = { [weak self, weak window] in
      guard let self, let window, self.dashboardWindow === window else { return }
      // The dashboard contains several TimelineView(.animation) surfaces. A closed NSWindow can retain
      // and continue laying out its hosting tree indefinitely, burning CPU while JP appears idle.
      // Release the tree on close; the shared DashboardViewModel preserves the user's data/selection,
      // and the next reveal constructs a fresh lightweight view hierarchy.
      window.contentViewController = nil
      self.dashboardHost = nil
      self.dashboardWindow = nil
      self.teardownOcclusionObserver()
      self.teardownDashboardResizeObserver()
    }
    observeOcclusion(of: window)
    observeLayoutSwitchResize(of: window)
    window.center()
    applyDashboardWindowLevel(window)
    dashboardWindow = window
    dashboardHost = host
    return window
  }

  private func scheduleDashboardWindowSizeSync() {
    DispatchQueue.main.async { [weak self] in
      self?.syncDashboardWindowSize()
    }
  }

  private func syncDashboardWindowSize() {
    guard let window = dashboardWindow, let host = dashboardHost else { return }
    host.view.layoutSubtreeIfNeeded()
    let preferred = host.preferredContentSize
    guard preferred.width > 0, preferred.height > 0 else { return }
    let targetContentRect = NSRect(origin: .zero, size: preferred)
    let targetFrameSize = window.frameRect(forContentRect: targetContentRect).size
    let nextFrame = DashboardWindowSizing.framePreservingTopTrailingEdges(
      currentFrame: window.frame,
      targetFrameSize: targetFrameSize,
      visibleFrame: window.screen?.visibleFrame)
    guard
      abs(window.frame.width - nextFrame.width) > 0.5
        || abs(window.frame.height - nextFrame.height) > 0.5
        || abs(window.frame.minX - nextFrame.minX) > 0.5
        || abs(window.frame.minY - nextFrame.minY) > 0.5
    else { return }
    window.setFrame(nextFrame, display: true, animate: false)
  }

  private func toggleAdvancedAnalytics() {
    guard let dashboardWindow else { return }
    advancedAnalytics.toggle(attachingTo: dashboardWindow)
  }

  private func toggleLiveData() {
    guard let dashboardWindow else { return }
    liveDataWindow.toggle(attachingTo: dashboardWindow)
  }

  private func toggleThemes() {
    guard let dashboardWindow else { return }
    themesWindow.toggle(attachingTo: dashboardWindow)
  }

  private func toggleDashboardPin() {
    dashboardChrome.isPinned.toggle()
    guard let dashboardWindow else { return }
    applyDashboardWindowLevel(dashboardWindow)
    advancedAnalytics.applyPinnedLevel(dashboardChrome.isPinned)
    liveDataWindow.applyPinnedLevel(dashboardChrome.isPinned)
    themesWindow.applyPinnedLevel(dashboardChrome.isPinned)
    dashboardWindow.makeKeyAndOrderFront(nil)
    dashboardWindow.orderFrontRegardless()
  }

  private func applyDashboardWindowLevel(_ window: NSWindow) {
    DashboardWindowPresence.apply(
      DashboardWindowPresence.configuration(isPinned: dashboardChrome.isPinned), to: window)
  }

  private func prepareDashboardWindowLevelForReveal(_ window: NSWindow) {
    applyDashboardWindowLevel(window)
    guard !dashboardChrome.isPinned else { return }
    window.level = .floating
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak window] in
      guard let self, let window, !self.dashboardChrome.isPinned else { return }
      window.level = .normal
    }
  }

  /// Temporarily promote a hidden-Dock (`.accessory`) app to `.regular` so `NSApp.activate()` can
  /// make it frontmost, then restore the prior policy once the reveal float has settled. No-op when
  /// already `.regular` (the default Dock-visible mode) or when a promotion is already in flight.
  private func promoteToForegroundForReveal() {
    let current = NSApp.activationPolicy()
    guard current != .regular, activationPolicyBeforeReveal == nil else { return }
    activationPolicyBeforeReveal = current
    NSApp.setActivationPolicy(.regular)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self, let previous = self.activationPolicyBeforeReveal else { return }
      NSApp.setActivationPolicy(previous)
      self.activationPolicyBeforeReveal = nil
    }
  }

  private func positionDashboardWindowBelowStatusItem(_ window: NSWindow) {
    guard let anchor = statusButtonScreenFrame() else {
      window.center()
      return
    }
    let preferredDisplay = statusItem.button?.window?.screen.map(StatusItemGeometry.Display.init(screen:))
    guard
      let origin = StatusItemGeometry.dashboardOriginBelowStatusItem(
        anchor: anchor,
        windowSize: window.frame.size,
        preferredDisplay: preferredDisplay,
        displays: NSScreen.screens.map(StatusItemGeometry.Display.init(screen:)))
    else {
      window.center()
      return
    }
    window.setFrameOrigin(origin)
  }

  private func statusButtonScreenFrame() -> NSRect? {
    guard let button = statusItem.button, let buttonWindow = button.window else { return nil }
    let buttonRectInWindow = button.convert(button.bounds, to: nil)
    return buttonWindow.convertToScreen(buttonRectInWindow)
  }

  private func refreshAll() {
    dashboard.refresh()
  }

  // MARK: - UI composition (main thread)

  private func updateFromDashboard() {
    updateTitle()
    DashboardWidgetPublisher.publish(from: dashboard)
    UsageAlertCenter.shared.evaluate(rows: dashboard.state.rows)  // meow + notify on usage-limit crossings (80% / 95% / Claude limit-hit)
  }

  private func effectiveDisplayFormat() -> MenuBarDisplayFormat {
    SettingsStore.menuBarDisplayFormat()
  }

  private func updateTitle() {
    let state = dashboard.state
    let displayFormat = effectiveDisplayFormat()
    let providerLimits = providerLimitSummaries(from: state)
    // Rotating format = every provider with a live pct that rounds to ≥1% (a "0%" provider is noise,
    // not information — see `rotatableLimits`), short-named for the tight pill. Static (pinned or
    // single-provider) formats leave this empty and stop the timer.
    rotatableLimits = displayFormat.isRotating
      ? MenuBarLabelRenderer.rotatableLimits(from: providerLimits)
      : []
    if limitRotationIndex >= max(rotatableLimits.count, 1) { limitRotationIndex = 0 }
    syncLimitRotationTimer()
    renderStatus(state: state, displayFormat: displayFormat, providerLimits: providerLimits)
  }

  /// Draws the pill + accessibility + tooltip. The pill shows a DEDICATED provider window (pinned
  /// format) or the current rotation window (a rotating, no-pinned-provider format). Called on every
  /// refresh AND on every rotation tick — but a rotation tick must NOT republish the widget or
  /// re-evaluate the 80% alert (those live in `updateFromDashboard`), so that work stays out of here.
  private func renderStatus(
    state: DashboardState,
    displayFormat: MenuBarDisplayFormat,
    providerLimits: [MenuBarProviderLimitSummary]
  ) {
    let attentionState = MenuBarLabelRenderer.attentionState(providerLimits: providerLimits)
    // Only show "—" when we KNOW sources exist but none can currently contribute. A genuinely empty
    // resolved state (no logs/events yet) still shows Total-only "$0.00" instead of falling back to the
    // loading pixels forever.
    let allUnavailable = !state.hasContributingData && state.hasData
    let canShowEmptyTotal = !state.hasData
    let aggregate = state.hasContributingData || canShowEmptyTotal ? state.aggregateToday : nil
    let currencyCode = state.aggregateCurrencyCode
    // Rotating format → the current (0%-filtered) rotation entry, or total-only when none qualify —
    // never a fallback to an unfiltered "0%" provider. Pinned/static → the pure resolver.
    let limit = MenuBarLabelRenderer.pillLimit(
      for: displayFormat, rotatableLimits: rotatableLimits,
      rotationIndex: limitRotationIndex, providerLimits: providerLimits)
    menuBarDisplayPresentation.update(format: displayFormat, limit: limit)
    if let aggregate {
      stopLoadingDots()
      let pillText = MenuBarLabelRenderer.compactStatusTitle(
        aggregateToday: aggregate,
        limit: limit,
        displayFormat: displayFormat,
        currencyCode: currencyCode)
      applyPillTitle(pillText, attention: attentionState)
      PerformanceInstrumentation.shared.markFirstNumberAvailable()
    } else if allUnavailable {
      stopLoadingDots()
      applyPillTitle("—", attention: .normal)
    } else {
      startLoadingDots()
    }

    // VoiceOver reads the live figures from the accessibility VALUE (the label/help are static).
    let accessibilityValue = MenuBarLabelRenderer.accessibilityValue(
      aggregateToday: aggregate,
      includesNotional: state.aggregateIncludesNotional,
      limit: limit,
      currencyCode: currencyCode,
      allProvidersUnavailable: allUnavailable)
    statusItem.button?.setAccessibilityValue(
      accessibilityValue)
    statusItem.button?.toolTip = MenuBarLabelRenderer.tooltip(
      aggregateToday: aggregate,
      windowTotal: aggregate == nil ? nil : state.aggregateWeek,
      windowDays: state.selectedDays,
      costBasis: state.aggregateCostProvenance.menuBarTooltipCostBasis,
      providerLimits: providerLimits,
      freshnessText: DashboardFreshness.evaluate(refreshStatus: state.refreshStatus, now: Date())
        .footerText,
      currencyCode: currencyCode,
      allProvidersUnavailable: allUnavailable)
  }

  /// Runs the rotation timer only when it can actually do something: a rotating format AND more than
  /// one provider with a live limit. Otherwise it stops (a pinned or single-provider format is static).
  private func syncLimitRotationTimer() {
    guard rotatableLimits.count > 1 else { stopLimitRotationTimer(); return }
    guard limitRotationTimer == nil else { return }  // already rotating
    let timer = Timer(timeInterval: Self.limitRotationInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.advanceLimitRotation() }
    }
    timer.tolerance = 0.5
    RunLoop.main.add(timer, forMode: .common)
    limitRotationTimer = timer
  }

  private func stopLimitRotationTimer() {
    limitRotationTimer?.invalidate()
    limitRotationTimer = nil
  }

  private func advanceLimitRotation() {
    guard rotatableLimits.count > 1 else { return }
    limitRotationIndex = (limitRotationIndex + 1) % rotatableLimits.count
    let state = dashboard.state
    // A rotation tick redraws ONLY the pill — never republishes the widget or re-evaluates the 80%
    // alert (those belong to `updateFromDashboard`).
    renderStatus(
      state: state,
      displayFormat: effectiveDisplayFormat(),
      providerLimits: providerLimitSummaries(from: state))
  }

  private func providerLimitSummaries(from state: DashboardState) -> [MenuBarProviderLimitSummary] {
    state.rows.compactMap { row in
      guard row.usedPct != nil || row.weeklyUsedPct != nil || row.estimatedSharePct != nil else {
        return nil
      }
      return MenuBarProviderLimitSummary(
        id: row.id,
        // Short menu-bar name ("Claude", not "Claude Code") so the pill and tooltip match.
        name: ProviderDescriptor.shortName(forName: row.name),
        primaryUsedPct: row.usedPct,
        primaryWindowMinutes: row.windowMinutes5h,
        secondaryUsedPct: row.weeklyUsedPct,
        secondaryWindowMinutes: row.windowMinutesWeekly,
        isOfficial: row.usageOfficial,
        planLabel: row.planLabel,
        estimatedUsedPct: row.usedPct == nil && row.weeklyUsedPct == nil ? row.estimatedSharePct : nil,
        estimatedTokenCount: row.usedPct == nil && row.weeklyUsedPct == nil
          ? row.todayUsage.total : nil,
        additionalLines: row.cursorPlan?.menuBarPoolLines(meters: row.menuBarPlanMeters()) ?? [])
    }
  }

  /// Draws today's total as a light, rounded "card" (mark + figure) and hands it to the status
  /// button as a single resolution-independent image, so the pill stays crisp at any display scale.
  private func applyPillTitle(
    _ text: String,
    attention: MenuBarAttentionState = .normal
  ) {
    guard let button = statusItem.button else { return }
    button.attributedTitle = NSAttributedString(string: "")
    let image = MenuBarPillRenderer.pillImage(
      text: text,
      attention: attention,
      mark: markImage,
      ink: pillInk,
      fill: pillFill,
      borderNormal: pillBorder,
      borderWarning: pillWarningBorder,
      borderCritical: pillCriticalBorder,
      thickness: NSStatusBar.system.thickness)
    statusItem.length = image.size.width
    button.image = image
    button.imagePosition = .imageOnly
    // NSStatusBarButton is hosted out-of-process by Control Center. Assigning a new same-role image
    // does not always invalidate that remote backing view, so the dashboard can hold the fresh
    // provider percentage while the visible menu-bar bitmap keeps the previous value until a click.
    // Force the AppKit view to commit every completed refresh to the hosted status item.
    button.needsDisplay = true
    button.displayIfNeeded()
  }

  private func startLoadingDots() {
    guard loadingDotsTimer == nil else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      renderLoadingPixels(reduceMotion: true)
      return
    }
    updateLoadingDots()
    // Install on the main run loop in .common mode (like syncLimitRotationTimer) so the cold-launch
    // loading animation keeps ticking while a status-item menu or modal is tracking the run loop.
    // Timer.scheduledTimer runs in .default mode only and would freeze the animation during tracking.
    let timer = Timer(timeInterval: 0.085, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.updateLoadingDots() }
    }
    timer.tolerance = 0.02
    RunLoop.main.add(timer, forMode: .common)
    loadingDotsTimer = timer
  }

  private func stopLoadingDots() {
    loadingDotsTimer?.invalidate()
    loadingDotsTimer = nil
    loadingPixelStep = 0
  }

  private func updateLoadingDots() {
    loadingPixelStep = (loadingPixelStep + 1) % (loadingPixelCols * loadingPixelRows + 1)
    renderLoadingPixels()
  }

  /// Hands the loading grid (drawn by `MenuBarPillRenderer.loadingPixelImage`) to the status button.
  /// Reduced-motion renders the FULL grid once instead of animating.
  private func renderLoadingPixels(reduceMotion: Bool = false) {
    guard let button = statusItem.button else { return }
    let filled = reduceMotion ? loadingPixelCols * loadingPixelRows : loadingPixelStep
    let image = MenuBarPillRenderer.loadingPixelImage(
      filled: filled,
      cols: loadingPixelCols,
      rows: loadingPixelRows,
      mark: markImage,
      thickness: NSStatusBar.system.thickness)
    statusItem.length = image.size.width
    button.image = image
    button.imagePosition = .imageOnly
  }

}

/// Pure decision for a plain (non-modifier) status-item click, factored out so the toggle rule is
/// unit-testable without a live `NSWindow`/`NSApp`.
///
/// The dashboard is dismissed (toggled closed) only when it is on-screen, not miniaturized, and the
/// surface the user is looking at: JP is the active app, OR no other app's window covers it.
///
/// [Regression guard] Two single signals have each shipped a toggle bug:
/// - `isVisible` alone is TRUE for a window BURIED behind another app, so a click closed an invisible
///   window and a second click was needed to reveal it.
/// - `appActive` alone broke the close half on macOS 27: a status-item click no longer makes an
///   app active through `activate(ignoringOtherApps:)`, so `NSApp.isActive` stayed false with the
///   dashboard in front and every click re-revealed instead of closing.
/// The occlusion check (`coveredByOtherApp`) does not depend on activation, so it decides both cases.
enum StatusItemClickDecision {
  static func shouldDismiss(
    isVisible: Bool,
    isMiniaturized: Bool,
    appActive: Bool,
    coveredByOtherApp: Bool
  ) -> Bool {
    isVisible && !isMiniaturized && (appActive || !coveredByOtherApp)
  }

  /// One on-screen window stacked above the dashboard, as `CGWindowListCopyWindowInfo` reports it.
  struct WindowAbove: Equatable {
    let ownerPID: pid_t
    let layer: Int
    let alpha: Double
    let bounds: CGRect

    init(ownerPID: pid_t, layer: Int, alpha: Double = 1, bounds: CGRect) {
      self.ownerPID = ownerPID
      self.layer = layer
      self.alpha = alpha
      self.bounds = bounds
    }

    init?(info: [String: Any]) {
      guard
        let pid = info[kCGWindowOwnerPID as String] as? Int,
        let layer = info[kCGWindowLayer as String] as? Int,
        let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
      else { return nil }
      self.init(
        ownerPID: pid_t(pid), layer: layer,
        alpha: info[kCGWindowAlpha as String] as? Double ?? 1, bounds: bounds)
    }
  }

  /// True when a visible, normal-level (layer 0) window of ANOTHER app overlaps `frame`. Menu bar,
  /// Dock, status items, and overlays sit on higher layers and never count; JP's own child windows
  /// (Advanced Analytics tray, settings) never count either. Coordinates are Quartz global
  /// (top-left origin), matching `kCGWindowBounds`.
  static func isCovered(frame: CGRect, by windowsAbove: [WindowAbove], ownPID: pid_t) -> Bool {
    windowsAbove.contains { other in
      guard other.ownerPID != ownPID, other.layer == 0, other.alpha > 0 else { return false }
      let overlap = other.bounds.intersection(frame)
      return overlap.width > 1 && overlap.height > 1
    }
  }
}

extension NSRect {
  /// This AppKit screen rect (bottom-left origin on the primary display) in Quartz global
  /// coordinates (top-left origin), the space `CGWindowListCopyWindowInfo` reports bounds in.
  var cgQuartzRect: CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
  }
}

enum StatusPillMetrics {
  struct Layout {
    let imageSize: NSSize
    let pillRect: NSRect
    let markRect: NSRect
    let textOriginX: CGFloat
  }

  static let markSize: CGFloat = 24
  static let markLeadingInset: CGFloat = -10
  static let markTextGap: CGFloat = 5
  static let textTrailingInset: CGFloat = 5
  /// Left bleed the overhanging mark needs: it sits `markLeadingInset` outside the pill, so the
  /// image must start that far left. Sized to land the mark's left edge exactly at x=0.
  static let leadingBleed: CGFloat = -markLeadingInset
  /// Right bleed is only enough to keep the 1pt pill stroke off the image edge — no empty gray tail
  /// (which the status-item highlight would otherwise fill on click).
  static let trailingBleed: CGFloat = 1
  static let verticalInset: CGFloat = 1.25
  static let cornerRadius: CGFloat = 7
  static var markClipRadius: CGFloat { markSize / 2 }

  static func layout(textWidth: CGFloat, statusBarThickness: CGFloat) -> Layout {
    let pillHeight = statusBarThickness - verticalInset * 2
    let pillWidth = markLeadingInset + markSize + markTextGap + textWidth + textTrailingInset
    let pillRect = NSRect(
      x: leadingBleed, y: verticalInset, width: pillWidth, height: pillHeight)
    let markRect = NSRect(
      x: pillRect.minX + markLeadingInset,
      y: (statusBarThickness - markSize) / 2,
      width: markSize,
      height: markSize)
    let imageSize = NSSize(width: leadingBleed + pillWidth + trailingBleed, height: statusBarThickness)
    // The mark now draws full-size (feathered edge, no art inset), so its visible trailing edge is
    // `markRect.maxX`. Placing the text `markTextGap` past that makes the text's LEFT whitespace equal
    // its RIGHT whitespace (`textTrailingInset`) — keep `markTextGap == textTrailingInset`. Guard:
    // `StatusPillMetricsTests.testTextHasEqualWhitespaceOnBothSides`.
    return Layout(
      imageSize: imageSize,
      pillRect: pillRect,
      markRect: markRect,
      textOriginX: markRect.maxX + markTextGap)
  }

  /// Sizes the pill TIGHT to the measured text — no fixed over-wide slot, so there is never a blank
  /// tail to the right of the total (the recurring regression). Width stability across refreshes comes
  /// from the monospaced-digit pill font (`JPAppFont.statusPillFont`): a given string always measures
  /// the same, so an unchanged value never churns width. The width intentionally follows the content
  /// when the value's digit count changes, when the display format changes, and when the limit pill
  /// rotates to a different provider — all deliberate, not churn.
  static func statusItemLayout(
    measuredTextWidth: CGFloat,
    statusBarThickness: CGFloat
  ) -> Layout {
    layout(textWidth: measuredTextWidth, statusBarThickness: statusBarThickness)
  }

  static func statusItemLength(for layout: Layout) -> CGFloat {
    layout.imageSize.width
  }
}

enum DashboardWindowSizing {
  /// The frame a layout switch should land on, or nil while the width has not changed yet (a
  /// height-only resize must not consume the anchor). Keeps the pre-switch top and trailing edges.
  static func frameAfterLayoutSwitch(
    anchor: NSRect, resizedFrame: NSRect, visibleFrame: NSRect?
  ) -> NSRect? {
    guard abs(resizedFrame.width - anchor.width) > 0.5 else { return nil }
    return framePreservingTopTrailingEdges(
      currentFrame: anchor, targetFrameSize: resizedFrame.size, visibleFrame: visibleFrame)
  }

  /// Content changes the height; a layout switch changes the width. Keeping the TRAILING edge keeps
  /// the chrome's trailing controls, including the layout toggle, under the pointer after a switch.
  /// It also keeps the card under a right-side status item.
  static func framePreservingTopTrailingEdges(
    currentFrame: NSRect, targetFrameSize: NSSize, visibleFrame: NSRect? = nil
  ) -> NSRect {
    var frame = NSRect(
      x: currentFrame.maxX - targetFrameSize.width,
      y: currentFrame.maxY - targetFrameSize.height,
      width: targetFrameSize.width,
      height: targetFrameSize.height)
    if let visibleFrame {
      // A taller selected detail must not push the footer below the display.
      // Keep the user's position whenever the complete card still fits there.
      if frame.width <= visibleFrame.width {
        frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
      }
      if frame.height <= visibleFrame.height {
        frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
      } else {
        frame.origin.y = visibleFrame.maxY - frame.height
      }
    }
    return frame
  }
}
