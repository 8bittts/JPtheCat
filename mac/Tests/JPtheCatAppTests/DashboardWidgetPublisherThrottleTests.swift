import Foundation
import XCTest

@testable import JPtheCatApp

/// [Regression guard — 90-day scan on every refresh completion] `DashboardWidgetPublisher.publish`
/// assembled a full `WidgetSnapshot` on EVERY `onDidUpdate` — which fires on every refresh completion
/// AND every provider-row click. Profiling the signed v1.082 app attributed ~29% of a saturated
/// background core to that path. The existing `hasSameContent` dedup in `finishPublishing` only skipped
/// the WRITE; by then the expensive assembly had already run.
///
/// WidgetKit budgets reloads at roughly 40-70/day and the snapshot's own `staleAfter` is +30 min, so a
/// spacing floor costs no freshness the OS could have consumed.
@MainActor
final class DashboardWidgetPublisherThrottleTests: XCTestCase {
  // `setUp`/`tearDown` override NONISOLATED XCTestCase methods, so the class-level `@MainActor` does
  // not reach them; XCTest runs them on the main thread, which `assumeIsolated` states explicitly.
  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated { DashboardWidgetPublisher.resetPublishThrottleForTesting() }
  }

  override func tearDown() {
    MainActor.assumeIsolated { DashboardWidgetPublisher.resetPublishThrottleForTesting() }
    super.tearDown()
  }

  /// The first publish after launch must NEVER be throttled — `SettingsBackView`'s support report reads
  /// `WidgetSnapshotStore().readIfAvailable()?.access`, so an app that never published once would have
  /// nothing to report.
  func testFirstPublishAfterLaunchIsNeverThrottled() {
    let start = Date(timeIntervalSince1970: 1_783_386_123)
    XCTAssertTrue(DashboardWidgetPublisher.shouldAssembleSnapshot(force: false, now: start))
  }

  func testSecondPublishInsideTheFloorSkipsSnapshotAssembly() {
    let start = Date(timeIntervalSince1970: 1_783_386_123)
    XCTAssertTrue(DashboardWidgetPublisher.shouldAssembleSnapshot(force: false, now: start))
    DashboardWidgetPublisher.clearPublishInFlightForTesting()

    XCTAssertFalse(
      DashboardWidgetPublisher.shouldAssembleSnapshot(
        force: false, now: start.addingTimeInterval(1)),
      "a refresh one second later must not re-run the 90-day scan")
    XCTAssertFalse(
      DashboardWidgetPublisher.shouldAssembleSnapshot(
        force: false, now: start.addingTimeInterval(299)),
      "still inside the 5-minute floor")
    XCTAssertTrue(
      DashboardWidgetPublisher.shouldAssembleSnapshot(
        force: false, now: start.addingTimeInterval(300)),
      "the floor must elapse, not latch off")
  }

  /// A forced publish (a settings or theme change) must reach a placed widget at once, not up to
  /// five minutes late.
  func testForcePublishBypassesTheFloor() {
    let start = Date(timeIntervalSince1970: 1_783_386_123)
    XCTAssertTrue(DashboardWidgetPublisher.shouldAssembleSnapshot(force: false, now: start))
    DashboardWidgetPublisher.clearPublishInFlightForTesting()

    XCTAssertTrue(
      DashboardWidgetPublisher.shouldAssembleSnapshot(
        force: true, now: start.addingTimeInterval(1)),
      "a forced publish must go out immediately")
  }

  /// The post-open burst runs 4 ticks 3s apart, and `publish` hops to a DETACHED task — without an
  /// in-flight guard those would stack concurrent 90-day scans over the same index.
  func testConcurrentPublishesDoNotStackDetachedScans() {
    let start = Date(timeIntervalSince1970: 1_783_386_123)
    XCTAssertTrue(DashboardWidgetPublisher.shouldAssembleSnapshot(force: false, now: start))
    // No `clearPublishInFlightForTesting()` here: the first assembly is still running.
    XCTAssertFalse(
      DashboardWidgetPublisher.shouldAssembleSnapshot(
        force: false, now: start.addingTimeInterval(600)),
      "a publish already in flight must suppress a second one even past the spacing floor")
  }

  /// Placed widgets showed "$0.00" for up to five minutes after every launch: an empty pre-refresh
  /// snapshot went out first and the spacing floor then skipped the first real one.
  func testNoDataSnapshotIsPublishedBeforeTheFirstRefreshFinishes() throws {
    let done = Date(timeIntervalSince1970: 1_783_386_123)
    XCTAssertFalse(DashboardWidgetPublisher.hasPublishableData(.idle(lastRefresh: nil)))
    XCTAssertFalse(DashboardWidgetPublisher.hasPublishableData(.refreshing(lastRefresh: nil)))
    XCTAssertTrue(DashboardWidgetPublisher.hasPublishableData(.idle(lastRefresh: done)))
    XCTAssertTrue(DashboardWidgetPublisher.hasPublishableData(.refreshing(lastRefresh: done)))
    XCTAssertTrue(
      DashboardWidgetPublisher.hasPublishableData(.failed(message: "x", lastRefresh: nil)),
      "a failed first refresh still publishes its error")

    // The gate must run before the throttle, or a skipped publish would still start the floor.
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JPtheCatApp/DashboardWidgetPublisher.swift"),
      encoding: .utf8)
    let gate = try XCTUnwrap(source.range(of: "guard hasPublishableData("))
    let throttle = try XCTUnwrap(source.range(of: "guard shouldAssembleSnapshot("))
    XCTAssertLessThan(gate.lowerBound, throttle.lowerBound)
  }

  /// Placing a widget clears the floor so brand-new widget instances aren't stuck on older numbers.
  func testInvalidatingTheThrottleAllowsAnImmediateRepublish() {
    let start = Date(timeIntervalSince1970: 1_783_386_123)
    XCTAssertTrue(DashboardWidgetPublisher.shouldAssembleSnapshot(force: false, now: start))
    DashboardWidgetPublisher.clearPublishInFlightForTesting()
    XCTAssertFalse(
      DashboardWidgetPublisher.shouldAssembleSnapshot(
        force: false, now: start.addingTimeInterval(5)))

    DashboardWidgetPublisher.invalidatePublishThrottle()
    XCTAssertTrue(
      DashboardWidgetPublisher.shouldAssembleSnapshot(
        force: false, now: start.addingTimeInterval(6)),
      "opening the widget gallery must let the next refresh publish fresh numbers")
  }
}
