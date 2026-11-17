import Foundation
import XCTest

@testable import JPtheCatApp

/// The support report goes through the user's own mail app; JP has no support endpoint and sends no
/// email itself (the website's report route was removed with every owner email).
final class SupportReportClientTests: XCTestCase {
  func testMailtoAddressesSupportWithSubjectAndFullBody() throws {
    let url = try XCTUnwrap(
      SupportReportClient.mailtoURL(
        contactEmail: "me@example.com", message: "The gauge looks wrong", report: "JP the Cat support report\nLine 2"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.scheme, "mailto")
    XCTAssertEqual(components.path, "support@jpthecat.com")
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    XCTAssertEqual(items["subject"], "JP the Cat support report")
    let body = try XCTUnwrap(items["body"])
    XCTAssertTrue(body.hasPrefix("The gauge looks wrong"), body)
    XCTAssertTrue(body.contains("Reply to: me@example.com"), body)
    XCTAssertTrue(body.contains("JP the Cat support report\nLine 2"), body)
  }

  func testBlankNoteAndEmailAreOmitted() throws {
    let url = try XCTUnwrap(SupportReportClient.mailtoURL(contactEmail: " ", message: nil, report: "Report"))
    let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
    XCTAssertEqual(body?.hasPrefix("Report"), true)
    XCTAssertEqual(body?.contains("Reply to:"), false)
  }

  @MainActor
  func testSendOpensTheMailAppAndReportsTheOutcome() async {
    var opened: [URL] = []
    let sent = await SupportReportClient.send(contactEmail: nil, message: "hi", report: "Report") {
      opened.append($0)
      return true
    }
    XCTAssertEqual(sent, .sent)
    XCTAssertEqual(opened.first?.scheme, "mailto")

    let failed = await SupportReportClient.send(contactEmail: nil, message: nil, report: "Report") { _ in false }
    XCTAssertEqual(failed, .failed)
  }

  @MainActor
  func testImplausibleReplyAddressNeverOpensTheMailApp() async {
    var openCount = 0
    let result = await SupportReportClient.send(contactEmail: "not-an-email", message: nil, report: "Report") { _ in
      openCount += 1
      return true
    }
    XCTAssertEqual(result, .invalidEmail)
    XCTAssertEqual(openCount, 0)
  }
}
