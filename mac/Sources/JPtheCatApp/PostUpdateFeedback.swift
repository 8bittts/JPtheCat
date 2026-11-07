import Foundation
import JPtheCatCore

/// Decides whether the post-update feedback prompt should appear, and builds the minimal report body
/// that goes with it.
///
/// The prompt is the one moment JP asks for anything: the first time the dashboard opens after the
/// app's version changes, it offers a plain text box and sends whatever the user writes to
/// `support@JPtheCat.com` through the SAME `SupportReportClient` path the Settings support report
/// uses. There is no rating, no star gate, and no telemetry — an unsent prompt produces no network
/// call at all.
///
/// `decide` is pure so the whole show/suppress matrix is testable without a window, defaults suite,
/// or bundle. Everything it needs is passed in.
enum PostUpdateFeedbackGate {
  struct Inputs {
    /// The version recorded the last time this gate ran. `nil` on a fresh install (or on the first
    /// launch after this feature ships, which is deliberately treated the same way).
    var lastPromptedVersion: String?
    /// `CFBundleShortVersionString` of the running app.
    var currentVersion: String
    /// Set once the user picks "Don't ask again"; suppresses the prompt for every future version.
    var optedOut: Bool
    /// First-run onboarding must finish before JP asks for anything.
    var onboardingCompleted: Bool
  }

  enum Decision: Equatable {
    /// Show the prompt, then record `currentVersion` as prompted.
    case prompt
    /// Do not show, but still record `currentVersion` so the NEXT update is the first real prompt.
    /// This is the fresh-install path: a brand-new user has nothing to say about an update yet.
    case recordOnly
    /// Do nothing at all — already prompted for this version, opted out, or still onboarding.
    case skip
  }

  static func decide(_ inputs: Inputs) -> Decision {
    guard !inputs.currentVersion.isEmpty else { return .skip }
    // Never interrupt first-run onboarding, and never record over it either: the version gets
    // recorded on the first dashboard open AFTER onboarding finishes.
    guard inputs.onboardingCompleted else { return .skip }
    guard let lastPromptedVersion = inputs.lastPromptedVersion else { return .recordOnly }
    guard lastPromptedVersion != inputs.currentVersion else { return .skip }
    // Opting out is checked LAST so the version still records for an opted-out user — flipping the
    // opt-out back off must not immediately re-prompt for an update they already installed.
    return inputs.optedOut ? .recordOnly : .prompt
  }
}

/// The resolved prompt, held as one piece of `DashboardView` state so the sheet can never render with
/// a version and a report that disagree.
struct PostUpdateFeedbackPresentation: Equatable {
  let version: String
  let report: String
}

/// The body attached to a post-update feedback send.
///
/// Deliberately NOT `SupportReport`: that report carries provider rows and dollar figures, which
/// nobody expects to travel with a one-line "the menu bar is too
/// wide". This carries the two facts needed to act on a report — which build, which macOS — and the
/// sheet says so in plain words above the Send button. The `JP the Cat support report` first line is
/// the contract the `/api/support-report` route validates on.
enum PostUpdateFeedbackReport {
  static func make(
    appVersion: String,
    buildNumber: String,
    previousVersion: String?,
    macOSVersion: String,
    generatedAt: Date = Date()
  ) -> String {
    [
      "JP the Cat support report",
      "Kind: post-update feedback",
      "Generated: \(LocalAutomationSnapshotEncoder.string(from: generatedAt))",
      "App: \(appVersion) (\(buildNumber))",
      "Updated from: \(previousVersion ?? "unknown")",
      "macOS: \(macOSVersion)",
      "",
      "Privacy: this report carries no usage data, no costs, no provider list, no device "
        + "identifiers, and no request text, code, conversation logs, token payloads, secrets, or file paths.",
    ].joined(separator: "\n")
  }
}
