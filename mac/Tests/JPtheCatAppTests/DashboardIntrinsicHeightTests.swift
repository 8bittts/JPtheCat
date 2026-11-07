import XCTest

/// [NOTE] This guard is `XCTAssertFalse`-only, so a literal-path read of `DashboardView.swift` was the
/// worst case of the freeze: extracting the detail bay would have left it asserting nothing at all
/// while staying green. The slice is now the brace-matched detail members resolved by
/// `AppSourceScanner`, which THROWS when either anchor is gone.
final class DashboardIntrinsicHeightTests: XCTestCase {
	func testDashboardDoesNotReserveHiddenProviderDetails() throws {
		let detail = try AppSourceScanner.bodies(of: [
			"var detail: some View",
			"var detailBay: some View",
		])

		// Scanned across EVERY app source — a reserver reintroduced in a newly split file is just as bad.
		XCTAssertFalse(
			try AppSourceScanner.joined().contains("detailHeightReservers"),
			"The dashboard must size to the selected detail, not reserve hidden provider panels.")
		XCTAssertTrue(
			detail.contains("ProviderDetail(row: row, days: model.selectedDays)"),
			"anchor check: the detail bay must still render the real provider detail")
		XCTAssertFalse(
			detail.contains("ProviderDetail(row: row, days: model.selectedDays)\n\t\t\t\t.hidden()"),
			"Hidden provider detail copies created the blank tail below the All Providers composition.")
	}
}
