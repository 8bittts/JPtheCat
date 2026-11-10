import Foundation
import XCTest

@testable import JPtheCatApp

/// The post-update feedback prompt is the only thing JP ever asks the user for, so the show/suppress
/// matrix is pinned here rather than left to the view. The report body is pinned too: it must carry
/// enough to act on a report and nothing that violates the privacy invariant.
final class PostUpdateFeedbackGateTests: XCTestCase {
  private func inputs(
    last: String?,
    current: String = "1.091",
    optedOut: Bool = false,
    onboarded: Bool = true
  ) -> PostUpdateFeedbackGate.Inputs {
    PostUpdateFeedbackGate.Inputs(
      lastPromptedVersion: last,
      currentVersion: current,
      optedOut: optedOut,
      onboardingCompleted: onboarded)
  }

  func testPromptsOnceWhenTheVersionChanged() {
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: "1.090")), .prompt)
  }

  func testDoesNotPromptTwiceForTheSameVersion() {
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: "1.091")), .skip)
  }

  /// A brand-new install has no update to comment on: record the version silently so the FIRST real
  /// update is the first real prompt.
  func testFreshInstallRecordsWithoutPrompting() {
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: nil)), .recordOnly)
  }

  func testOnboardingSuppressesEverythingIncludingTheRecord() {
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: "1.090", onboarded: false)), .skip)
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: nil, onboarded: false)), .skip)
  }

  /// "Don't ask again" still advances the recorded version. Otherwise turning the opt-out back off
  /// would immediately fire a prompt for an update the user already installed and dismissed.
  func testOptOutRecordsButNeverPrompts() {
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: "1.090", optedOut: true)), .recordOnly)
  }

  /// `swift run` builds have no `CFBundleShortVersionString`; an empty version must never prompt (and
  /// must never record an empty string that would then differ from every real version).
  func testMissingBundleVersionSkips() {
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: "1.090", current: "")), .skip)
  }

  /// A downgrade is still a version change and still worth asking about.
  func testDowngradeAlsoPrompts() {
    XCTAssertEqual(PostUpdateFeedbackGate.decide(inputs(last: "1.092", current: "1.091")), .prompt)
  }
}

final class PostUpdateFeedbackReportTests: XCTestCase {
  private func report() -> String {
    PostUpdateFeedbackReport.make(
      appVersion: "1.091",
      buildNumber: "1091",
      previousVersion: "1.090",
      macOSVersion: "Version 15.2 (Build 24C101)",
      generatedAt: Date(timeIntervalSince1970: 1_760_000_000))
  }

  /// `/api/support-report` rejects a body that does not open with this exact line or runs under 80
  /// characters — the mac and web sides of that contract must not drift.
  func testSatisfiesTheSupportReportEndpointContract() {
    let body = report()
    XCTAssertTrue(body.hasPrefix("JP the Cat support report"))
    XCTAssertGreaterThanOrEqual(body.count, 80)
    XCTAssertLessThanOrEqual(body.count, 20_000)
  }

  func testCarriesTheTwoFactsNeededToActOnAReport() {
    let body = report()
    XCTAssertTrue(body.contains("App: 1.091 (1091)"))
    XCTAssertTrue(body.contains("Updated from: 1.090"))
    XCTAssertTrue(body.contains("macOS: Version 15.2 (Build 24C101)"))
  }

  func testUnknownPreviousVersionIsLabelledNotBlank() {
    let body = PostUpdateFeedbackReport.make(
      appVersion: "1.091",
      buildNumber: "1091",
      previousVersion: nil,
      macOSVersion: "Version 15.2")
    XCTAssertTrue(body.contains("Updated from: unknown"))
  }

  /// The privacy invariant: this body must never grow a device hash, provider list, or dollar figure
  /// the way the full `SupportReport` carries.
  func testCarriesNoIdentifiersUsageOrCosts() {
    let body = report()
    for forbidden in ["Device hash", "License", "Providers:", "$", "Events:", "Window:"] {
      XCTAssertFalse(body.contains(forbidden), "post-update feedback report must not carry \(forbidden)")
    }
  }
}
