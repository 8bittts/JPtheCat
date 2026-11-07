import AppKit
import Foundation

/// Adaptive cadence policy for `RefreshCoordinator` — pure and unit-tested.
/// Refresh is frequent while the dashboard is visible, slow while idle, and brief
/// after the dashboard opens (a short burst to catch just-written logs).
struct RefreshSchedule: Equatable {
  var activeInterval: TimeInterval = 60
  var idleInterval: TimeInterval = 300
  var burstInterval: TimeInterval = 3
  var burstTicks: Int = 4

  /// Seconds until the next refresh, given the current activity + remaining burst ticks.
  /// Burst wins while it has ticks left; otherwise the interval tracks dashboard visibility.
  func interval(active: Bool, burstRemaining: Int) -> TimeInterval {
    if burstRemaining > 0 { return burstInterval }
    return active ? activeInterval : idleInterval
  }
}

enum FileChangeReindexPolicy {
  static let debounce: TimeInterval = 5
  static let maximumDelay: TimeInterval = 15

  static func deadline(
    firstChange: Date, latestChange: Date,
    debounce: TimeInterval = debounce, maximumDelay: TimeInterval = maximumDelay
  ) -> Date {
    min(latestChange.addingTimeInterval(debounce), firstChange.addingTimeInterval(maximumDelay))
  }
}

/// [Regression guard] The window-only refresh path needs the SAME trailing debounce as reindex — an
/// un-debounced ~1 Hz `FileSystemWatcher` callback makes every tick expensive. `reindex: false` gates
/// ONLY the `UsageIndexer` walk; the window SQL scan, the provider rate-limit sweeps, and the widget
/// publish still run on each one.
///
/// Shorter than the reindex policy on purpose: this path exists to keep the menu-bar pill responsive,
/// so it trades ~2s of freshness (bounded at 5s under a continuous write stream) for ~4x less work.
/// Every user-initiated path — `refreshNow()`, the periodic timer, `burst()`, timeframe changes, and
/// Settings toggles — bypasses this entirely by calling `refresh(reindex:)` directly.
enum FileChangeWindowRefreshPolicy {
  static let debounce: TimeInterval = 2
  static let maximumDelay: TimeInterval = 5

  static func deadline(
    firstChange: Date, latestChange: Date,
    debounce: TimeInterval = debounce, maximumDelay: TimeInterval = maximumDelay
  ) -> Date {
    min(latestChange.addingTimeInterval(debounce), firstChange.addingTimeInterval(maximumDelay))
  }
}

/// User-facing refresh-rate presets (Settings → "Refresh rate"). Each maps to a `RefreshSchedule` by
/// overriding ONLY the active-visibility knob and deriving idle = active × 5 (preserving today's
/// 60 → 300 ratio); the burst ticks and the `FileSystemWatcher` are unchanged, so just-written logs
/// still refresh instantly. `.balanced` is the shipped default and equals a bare `RefreshSchedule()`.
enum RefreshCadence: String, CaseIterable, Sendable {
  case live
  case balanced
  case relaxed
  case batterySaver

  static let defaultCadence: RefreshCadence = .balanced

  /// Active-window (dashboard visible) refresh interval, in seconds.
  var activeInterval: TimeInterval {
    switch self {
    case .live: 30
    case .balanced: 60
    case .relaxed: 120
    case .batterySaver: 300
    }
  }

  /// The concrete schedule this preset drives. Idle is 5× active (the shipped 60 → 300 ratio); burst
  /// stays at the `RefreshSchedule` default so a just-written log still appears promptly.
  var schedule: RefreshSchedule {
    RefreshSchedule(activeInterval: activeInterval, idleInterval: activeInterval * 5)
  }

  var settingsTitle: String {
    switch self {
    case .live: "Live"
    case .balanced: "Balanced"
    case .relaxed: "Relaxed"
    case .batterySaver: "Battery saver"
    }
  }

  var settingsSubtitle: String {
    switch self {
    case .live: "Every 30s when open"
    case .balanced: "Every 60s when open"
    case .relaxed: "Every 2 min when open"
    case .batterySaver: "Every 5 min when open"
    }
  }

  var next: RefreshCadence {
    switch self {
    case .live: .balanced
    case .balanced: .relaxed
    case .relaxed: .batterySaver
    case .batterySaver: .live
    }
  }

  static func normalized(_ rawValue: String?, default fallback: RefreshCadence = defaultCadence) -> RefreshCadence {
    rawValue.flatMap(RefreshCadence.init(rawValue:)) ?? fallback
  }
}

/// Owns the menu-bar refresh *cadence + triggers* — replaces `StatusBarController`'s fixed 60s `Timer`.
///
/// Coalescing, one-in-flight, and off-main provider/index work already live in
/// `DashboardViewModel` (its `busy` / `DashboardRefreshQueue` gate), so this is purely the scheduler: an
/// adaptive timer that runs fast while the dashboard is visible (`activeInterval`), slows
/// down when it's hidden (`idleInterval`), and bursts for a few ticks right after the
/// dashboard opens. The timer is non-repeating and reschedules itself each tick so the
/// interval can change as activity/burst state changes. A `FileSystemWatcher` over the provider
/// log dirs also refreshes the instant a log is written (1s-coalesced), so fresh usage appears
/// without waiting for the next tick.
///
/// All scheduling is main-thread; `onRefresh` triggers `DashboardViewModel.refresh()`, which
/// serializes itself and does the heavy work off-main.
@MainActor
final class RefreshCoordinator {
  private var schedule: RefreshSchedule
  private let watchPaths: [URL]
  private let isActive: () -> Bool
  private let onRefresh: (_ reindex: Bool) -> Void
  private var timer: Timer?
  private var watcher: FileSystemWatcher?
  private var fileReindexTimer: Timer?
  private var firstPendingFileChange: Date?
  private var windowRefreshTimer: Timer?
  private var firstPendingWindowRefresh: Date?
  private var burstRemaining = 0

  init(
    schedule: RefreshSchedule = RefreshSchedule(),
    watchPaths: [URL] = [],
    isActive: @escaping () -> Bool,
    onRefresh: @escaping (_ reindex: Bool) -> Void
  ) {
    self.schedule = schedule
    self.watchPaths = watchPaths
    self.isActive = isActive
    self.onRefresh = onRefresh
  }

  /// Refresh immediately, then start the adaptive cadence and (if any) FSEvents watching.
  func start() {
    fire()
    startWatching()
  }

  /// Watch the provider log dirs so a just-written usage log refreshes immediately, not on the next
  /// timer tick. Degrades silently to timer-only if the dirs don't exist yet or the stream fails.
  private func startWatching() {
    guard watcher == nil, !watchPaths.isEmpty else { return }
    watcher = FileSystemWatcher(paths: watchPaths) { [weak self] in
      Task { @MainActor in self?.fileChanged() }
    }
  }

  /// A provider wrote a log — refresh behind a short trailing debounce (DashboardViewModel
  /// coalesces/serializes the work); the periodic timer keeps its own cadence and overlapping requests
  /// collapse in the refresh owner.
  private func fileChanged() {
    // BOTH paths are debounced. The window-only pass keeps the menu bar live on a 2s/5s deadline; the
    // expensive token-log indexing batches behind the longer 5s/15s one. Calling `onRefresh(false)`
    // straight through here was the refresh storm — see `FileChangeWindowRefreshPolicy`.
    scheduleWindowRefresh()
    scheduleFileReindex()
  }

  private func scheduleWindowRefresh(now: Date = Date()) {
    let first = firstPendingWindowRefresh ?? now
    firstPendingWindowRefresh = first
    let deadline = FileChangeWindowRefreshPolicy.deadline(firstChange: first, latestChange: now)
    windowRefreshTimer?.invalidate()
    let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.fireWindowRefresh() }
    }
    timer.tolerance = 0.5
    RunLoop.main.add(timer, forMode: .common)
    windowRefreshTimer = timer
  }

  private func fireWindowRefresh() {
    windowRefreshTimer?.invalidate()
    windowRefreshTimer = nil
    firstPendingWindowRefresh = nil
    onRefresh(false)
  }

  private func scheduleFileReindex(now: Date = Date()) {
    let first = firstPendingFileChange ?? now
    firstPendingFileChange = first
    let deadline = FileChangeReindexPolicy.deadline(firstChange: first, latestChange: now)
    fileReindexTimer?.invalidate()
    let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.fireFileReindex() }
    }
    timer.tolerance = 0.5
    RunLoop.main.add(timer, forMode: .common)
    fileReindexTimer = timer
  }

  private func fireFileReindex() {
    fileReindexTimer?.invalidate()
    fileReindexTimer = nil
    firstPendingFileChange = nil
    // A reindex is a strict superset of a window-only pass, so drop any still-pending one rather than
    // running a redundant second scan seconds later.
    windowRefreshTimer?.invalidate()
    windowRefreshTimer = nil
    firstPendingWindowRefresh = nil
    onRefresh(true)
  }

  /// Shorten the next few ticks (e.g. right after the dashboard opens) to catch logs written
  /// in the last moment, then settle back to the adaptive cadence. Does not refresh immediately
  /// — the caller (dashboard-open path) already refreshes; this only speeds up what follows.
  func burst() {
    burstRemaining = schedule.burstTicks
    reschedule()
  }

  /// Manual refresh (menu "Refresh" / `⌘R`): refresh now and reset the cadence.
  func refreshNow() { fire() }

  /// Swap the cadence at runtime (Settings → "Refresh rate"). Re-arms the SINGLE existing timer with
  /// the new interval — never a second loop. A no-op when the schedule is unchanged; only reschedules
  /// once `start()` has armed the timer (so this can't kick off refreshes before launch wiring runs).
  func setSchedule(_ newSchedule: RefreshSchedule) {
    guard newSchedule != schedule else { return }
    schedule = newSchedule
    if timer != nil { reschedule() }
  }

  private func fire() {
    onRefresh(true)
    if burstRemaining > 0 { burstRemaining -= 1 }
    reschedule()
  }

  private func reschedule() {
    timer?.invalidate()
    let interval = schedule.interval(active: isActive(), burstRemaining: burstRemaining)
    let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.fire() }
    }
    timer.tolerance = interval * 0.1
    self.timer = timer
  }
}
