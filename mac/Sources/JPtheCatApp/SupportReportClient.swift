import AppKit
import Foundation

enum SupportReportSendResult: Sendable, Equatable {
  case sent
  case invalidEmail
  case failed
}

/// Hands a support report to the user's own mail app, addressed to support@JPtheCat.com.
///
/// JP has no support endpoint and sends no email itself: the report travels only if the user sends
/// the message their mail app opens, from their own address.
enum SupportReportClient {
  static let supportAddress = "support@jpthecat.com"
  static let subject = "JP the Cat support report"

  @MainActor
  static func send(
    contactEmail: String?,
    message: String?,
    report: String,
    open: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }
  ) async -> SupportReportSendResult {
    let email = contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let email, !email.isEmpty, !isPlausibleEmail(email) {
      return .invalidEmail
    }
    guard let url = mailtoURL(contactEmail: email, message: message, report: report) else {
      return .failed
    }
    return open(url) ? .sent : .failed
  }

  /// The `mailto:` URL for a report: the user's note first, then the reply address they typed (if
  /// any), then the report with the app version.
  static func mailtoURL(contactEmail: String?, message: String?, report: String) -> URL? {
    let note = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let email = contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var sections: [String] = []
    if !note.isEmpty { sections.append(note) }
    if !email.isEmpty { sections.append("Reply to: \(email)") }
    sections.append(report)
    if let appVersion { sections.append("App version: \(appVersion)") }

    var components = URLComponents()
    components.scheme = "mailto"
    components.path = supportAddress
    components.queryItems = [
      URLQueryItem(name: "subject", value: subject),
      URLQueryItem(name: "body", value: sections.joined(separator: "\n\n")),
    ]
    return components.url
  }

  private static var appVersion: String? {
    guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
      return nil
    }
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    return "\(short) (\(build))"
  }

  private static func isPlausibleEmail(_ value: String) -> Bool {
    guard value.count <= 254 else { return false }
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    return parts.count == 2 && parts[0].isEmpty == false && parts[1].contains(".")
  }
}
