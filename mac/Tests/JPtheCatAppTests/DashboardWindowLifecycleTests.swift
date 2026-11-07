import XCTest

final class DashboardWindowLifecycleTests: XCTestCase {
	func testClosingDashboardReleasesHostingTreeSoContinuousTimelinesStop() throws {
		let source = try String(
			contentsOf: repoRoot()
				.appendingPathComponent("mac/Sources/JPtheCatApp/StatusBarController.swift"),
			encoding: .utf8)

		XCTAssertTrue(source.contains("window.onClose = { [weak self, weak window] in"))
		XCTAssertTrue(source.contains("window.contentViewController = nil"))
		XCTAssertTrue(source.contains("self.dashboardHost = nil"))
		XCTAssertTrue(source.contains("self.dashboardWindow = nil"))
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
