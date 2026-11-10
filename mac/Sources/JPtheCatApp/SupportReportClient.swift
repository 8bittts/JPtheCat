import Foundation

enum SupportReportSendResult: Sendable, Equatable {
  case sent
  case invalidEmail
  case failed
}

enum SupportReportClient {
  static let endpoint = URL(string: "https://jpthecat.com/api/support-report")!

  struct RequestBody: Encodable {
    let contactEmail: String?
    let message: String?
    let report: String
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
      case contactEmail = "contact_email"
      case message
      case report
      case appVersion = "app_version"
    }
  }

  static func send(contactEmail: String?, message: String?, report: String) async -> SupportReportSendResult {
    let email = contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = message?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let email, !email.isEmpty, !isPlausibleEmail(email) {
      return .invalidEmail
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("JPtheCat/\(appVersion ?? "unknown")", forHTTPHeaderField: "User-Agent")
    let body = RequestBody(
      contactEmail: email?.isEmpty == false ? email : nil,
      message: note?.isEmpty == false ? note : nil,
      report: report,
      appVersion: appVersion)
    guard let encoded = try? JSONEncoder().encode(body) else { return .failed }
    request.httpBody = encoded

    guard let (_, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse
    else { return .failed }
    return (200..<300).contains(http.statusCode) ? .sent : .failed
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
