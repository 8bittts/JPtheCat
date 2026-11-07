import Foundation
import XCTest

@testable import JPtheCatApp

/// [Regression guard — 120 fps rendered to nobody] macOS does NOT throttle
/// `TimelineView(.animation)` when a window is covered. A probe measured 360 frames / 3 s = 120 fps
/// while the dashboard window was 100% occluded, and the same 120 fps while miniaturized;
/// `.animation(paused: true)` measured 0 frames and 0.000 s CPU. On the real app that was 7-14% of a
/// core burned continuously in the app's DEFAULT steady state (the dashboard opens on every
/// Dock-visible launch and the reveal path raises a buried window rather than closing it).
final class DashboardMotionGateTests: XCTestCase {
  func testPausesOnlyWhenAnObservedOcclusionSaysNothingIsVisible() {
    XCTAssertTrue(
      DashboardMotionGate.shouldPauseMotion(hasObservedOcclusion: true, occlusionVisible: false))
    XCTAssertFalse(
      DashboardMotionGate.shouldPauseMotion(hasObservedOcclusion: true, occlusionVisible: true))
  }

  /// THE load-bearing property. Outside a real `NSApplication.run()` event loop, `occlusionState`
  /// reads permanently non-visible and delivers ZERO notifications — the same launch-mode hazard that
  /// bites bundle identity, Sparkle and activation policy. If the gate ever trusted `occlusionState`
  /// before a notification arrived, every animation would freeze under `swift run JPtheCat`.
  /// "No notification ever" must be able to mean only one thing: never pause.
  func testFailsOpenUntilARealOcclusionNotificationHasArrived() {
    XCTAssertFalse(
      DashboardMotionGate.shouldPauseMotion(hasObservedOcclusion: false, occlusionVisible: false),
      "an unobserved occlusion state must NEVER pause motion — it fails open by construction")
    XCTAssertFalse(
      DashboardMotionGate.shouldPauseMotion(hasObservedOcclusion: false, occlusionVisible: true))
  }

  /// The gate deliberately takes no `isVisible`/`isMiniaturized` input. A miniaturized window reports
  /// `isVisible == false`, so an `isVisible` guard would make the miniaturized branch unreachable —
  /// while a miniaturized window was measured still running a full 120 fps. `occlusionState` already
  /// reports non-visible when miniaturized, so it covers that case on its own.
  func testMiniaturizedIsCoveredByOcclusionAloneWithNoSeparateFlag() {
    // A miniaturized window delivers a notification with `.visible` absent — identical to "covered",
    // which is exactly why one input suffices.
    XCTAssertTrue(
      DashboardMotionGate.shouldPauseMotion(hasObservedOcclusion: true, occlusionVisible: false))
  }

  @MainActor
  func testChromeStateDefaultsToRunningMotion() {
    XCTAssertFalse(
      DashboardChromeState().motionPaused,
      "the shared default must animate; pausing is only ever opted into by a delivered notification")
  }
}

/// Source-level guard. An assertion that merely looks for a `paused:` argument is satisfied by a
/// hardcoded `.animation(paused: false)` — which is precisely an ungated timeline. These assert the
/// argument is the ENVIRONMENT FLAG, and that no bare `TimelineView(.animation)` sneaks back in.
final class DashboardMotionGateSourceGuardTests: XCTestCase {
  /// [NOTE] This suite's own `#filePath`-rooted walker is what `AppSourceScanner` was generalised from;
  /// the private copies are gone so there is exactly one scanner for every source-text guard.
  /// Scans EVERY app source, not a hardcoded file list: splitting `DashboardView.swift` or adding a
  /// new animated surface would otherwise reduce this guard to zero assertions while still passing.
  func testEveryAnimationTimelineIsGatedOnTheEnvironmentFlag() throws {
    var matched = 0
    for (file, text) in try AppSourceScanner.files().map({ ($0.name, $0.text) }) {
      let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      for (index, line) in lines.enumerated() where line.contains("TimelineView(.animation") {
        // Skip doc-comment mentions; only real call sites matter.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
        matched += 1
        XCTAssertTrue(
          line.contains("TimelineView(.animation(paused: motionPaused))"),
          """
          \(file):\(index + 1) has an animation timeline that is not gated on the environment flag.
          A bare `TimelineView(.animation)` — or a hardcoded `paused: false` — burns a full display \
          link while the window is completely hidden. Use `.animation(paused: motionPaused)` and \
          declare `@Environment(\\.jpMotionPaused) private var motionPaused`.
          Offending line: \(trimmed)
          """)
      }
    }
    XCTAssertGreaterThan(
      matched, 0,
      "scan found no TimelineView(.animation) call sites — the guard would pass vacuously")
  }

  /// The periodic freshness timeline is intentionally NOT gated: it ticks at 1 Hz (negligible) and
  /// `PeriodicTimelineSchedule` has no `paused:` parameter. Pinned so nobody "fixes" it.
  func testThePeriodicFreshnessTimelineIsDeliberatelyLeftAlone() throws {
    XCTAssertTrue(
      try AppSourceScanner.typeSurface("DashboardView").contains(
        "TimelineView(.periodic(from: .now, by: 1))"),
      "the 1 Hz freshness timeline is deliberately ungated — PeriodicTimelineSchedule has no paused:")
  }

  /// The flag has to actually reach the leaves, or every `paused: motionPaused` above reads a
  /// permanent `false` from the environment default.
  func testTheDashboardInjectsTheFlagIntoTheEnvironment() throws {
    XCTAssertTrue(
      try AppSourceScanner.typeSurface("DashboardView").contains(
        ".environment(\\.jpMotionPaused, chrome?.motionPaused ?? false)"),
      "DashboardView must publish the gate into the environment for its animated leaves")
  }

  /// The observer is the ONLY writer of `motionPaused`. An eager `window.occlusionState` read at
  /// construction would freeze motion in raw `swift run` mode, where the state reads permanently
  /// non-visible and no notification ever arrives.
  func testOcclusionIsObservedViaNotificationRatherThanReadEagerly() throws {
    let text = try AppSourceScanner.source(named: "StatusBarController.swift")
    XCTAssertTrue(text.contains("NSWindow.didChangeOcclusionStateNotification"))
    XCTAssertTrue(text.contains("hasObservedOcclusion: true"))
    // Count CODE reads only — the surrounding doc comments legitimately name the API repeatedly.
    let codeReads = text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.hasPrefix("//") && $0.contains("occlusionState") }
    XCTAssertEqual(
      codeReads.count, 1,
      """
      occlusionState must be read ONLY inside the notification handler — never eagerly. Outside a \
      real NSApplication.run() loop it reports permanently non-visible, so an eager read freezes \
      every animation in raw `swift run` mode. Found: \(codeReads)
      """)
  }
}
