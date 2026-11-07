import XCTest

@testable import JPtheCatApp

final class RefreshScheduleTests: XCTestCase {
  func testActiveVsIdleCadence() {
    let s = RefreshSchedule()
    XCTAssertEqual(s.interval(active: true, burstRemaining: 0), 60)  // dashboard visible → fast
    XCTAssertEqual(s.interval(active: false, burstRemaining: 0), 300)  // hidden → slow
  }

  func testBurstOverridesActivity() {
    let s = RefreshSchedule()
    // A burst runs fast regardless of visibility.
    XCTAssertEqual(s.interval(active: true, burstRemaining: 4), 3)
    XCTAssertEqual(s.interval(active: false, burstRemaining: 1), 3)
  }

  func testBurstEndsAtZeroTicks() {
    let s = RefreshSchedule()
    // Once the burst is exhausted, cadence tracks visibility again.
    XCTAssertEqual(s.interval(active: true, burstRemaining: 0), s.activeInterval)
    XCTAssertEqual(s.interval(active: false, burstRemaining: 0), s.idleInterval)
  }

  func testCustomSchedule() {
    let s = RefreshSchedule(activeInterval: 30, idleInterval: 600, burstInterval: 2, burstTicks: 3)
    XCTAssertEqual(s.interval(active: true, burstRemaining: 0), 30)
    XCTAssertEqual(s.interval(active: false, burstRemaining: 0), 600)
    XCTAssertEqual(s.interval(active: true, burstRemaining: 3), 2)
  }

  func testRefreshCadenceBalancedEqualsShippedDefault() {
    // Balanced is the shipped default: it must equal a bare RefreshSchedule() (60s active / 300s idle),
    // so an unchanged install behaves exactly as before the cadence setting existed.
    XCTAssertEqual(RefreshCadence.defaultCadence, .balanced)
    XCTAssertEqual(RefreshCadence.balanced.schedule, RefreshSchedule())
  }

  func testRefreshCadencePresetsMapToExpectedSchedules() {
    // Each preset overrides ONLY the active knob; idle stays 5× active (the 60→300 ratio); burst is
    // untouched (default 3s / 4 ticks).
    let cases: [(RefreshCadence, TimeInterval, TimeInterval)] = [
      (.live, 30, 150),
      (.balanced, 60, 300),
      (.relaxed, 120, 600),
      (.batterySaver, 300, 1500),
    ]
    for (cadence, active, idle) in cases {
      let schedule = cadence.schedule
      XCTAssertEqual(schedule.interval(active: true, burstRemaining: 0), active, "\(cadence) active")
      XCTAssertEqual(schedule.interval(active: false, burstRemaining: 0), idle, "\(cadence) idle")
      XCTAssertEqual(schedule.interval(active: true, burstRemaining: 4), 3, "\(cadence) keeps burst")
    }
  }

  func testRefreshCadenceNextCyclesThroughAllPresets() {
    // The Settings row taps through the cycle: live → balanced → relaxed → batterySaver → live.
    XCTAssertEqual(RefreshCadence.live.next, .balanced)
    XCTAssertEqual(RefreshCadence.balanced.next, .relaxed)
    XCTAssertEqual(RefreshCadence.relaxed.next, .batterySaver)
    XCTAssertEqual(RefreshCadence.batterySaver.next, .live)
    XCTAssertEqual(RefreshCadence.normalized("nonsense"), .balanced)
    XCTAssertEqual(RefreshCadence.normalized("relaxed"), .relaxed)
  }

  func testFileChangeReindexDeadlineDebouncesButNeverStarves() {
    let first = Date(timeIntervalSince1970: 1_000)
    XCTAssertEqual(
      FileChangeReindexPolicy.deadline(firstChange: first, latestChange: first),
      Date(timeIntervalSince1970: 1_005))
    XCTAssertEqual(
      FileChangeReindexPolicy.deadline(
        firstChange: first, latestChange: Date(timeIntervalSince1970: 1_004)),
      Date(timeIntervalSince1970: 1_009))
    XCTAssertEqual(
      FileChangeReindexPolicy.deadline(
        firstChange: first, latestChange: Date(timeIntervalSince1970: 1_014)),
      Date(timeIntervalSince1970: 1_015),
      "continuous writes must still force one full reindex by the maximum delay")
  }

  /// [Regression guard — refresh storm] The window-only path that `RefreshCoordinator.fileChanged()`
  /// drives must be debounced too. It used to call `onRefresh(false)` on EVERY FSEvents callback, and
  /// with `kFSEventStreamCreateFlagNoDefer` + `latency: 1.0` a live agent session fires that at ~1 Hz —
  /// measured at 43 refreshes/minute against a designed cadence of 1/minute on the signed v1.082 app.
  func testFileChangeWindowRefreshDebouncesButNeverStarves() {
    let first = Date(timeIntervalSince1970: 1_000)
    XCTAssertEqual(
      FileChangeWindowRefreshPolicy.deadline(firstChange: first, latestChange: first),
      Date(timeIntervalSince1970: 1_002))
    XCTAssertEqual(
      FileChangeWindowRefreshPolicy.deadline(
        firstChange: first, latestChange: Date(timeIntervalSince1970: 1_001)),
      Date(timeIntervalSince1970: 1_003),
      "a later write pushes the trailing deadline out")
    XCTAssertEqual(
      FileChangeWindowRefreshPolicy.deadline(
        firstChange: first, latestChange: Date(timeIntervalSince1970: 1_009)),
      Date(timeIntervalSince1970: 1_005),
      "continuous writes must still repaint by the maximum delay")
  }

  /// The window-only debounce must stay STRICTLY tighter than the reindex one: it exists to keep the
  /// menu-bar pill responsive, so it may never be the slower of the two.
  func testWindowRefreshDebounceIsTighterThanTheReindexDebounce() {
    XCTAssertLessThan(FileChangeWindowRefreshPolicy.debounce, FileChangeReindexPolicy.debounce)
    XCTAssertLessThan(
      FileChangeWindowRefreshPolicy.maximumDelay, FileChangeReindexPolicy.maximumDelay)
  }

  /// A reindex recomputes everything a window-only pass would, so popping one must consume a
  /// window-only request queued alongside it — otherwise a redundant full pass fires right after.
  func testPoppingAReindexAlsoConsumesAPendingWindowOnly() {
    var queue = DashboardRefreshQueue()
    queue.request(reindex: false)
    queue.request(reindex: true)
    XCTAssertEqual(queue.popNext(), .windowOnly, "window-only keeps priority for timeframe repaints")
    XCTAssertEqual(queue.popNext(), .reindex)
    XCTAssertEqual(queue.popNext(), .none)

    var reindexFirst = DashboardRefreshQueue()
    reindexFirst.request(reindex: true)
    XCTAssertEqual(reindexFirst.popNext(), .reindex)
    reindexFirst.request(reindex: true)
    reindexFirst.request(reindex: false)
    XCTAssertEqual(reindexFirst.popNext(), .windowOnly)
    XCTAssertEqual(reindexFirst.popNext(), .reindex)
    XCTAssertEqual(
      reindexFirst.popNext(), .none,
      "the reindex must not leave a stale window-only request behind it")
  }
}
