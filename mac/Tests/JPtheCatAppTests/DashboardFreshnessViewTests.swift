import XCTest

/// [NOTE] Both guards used to read `DashboardView.swift` by literal path, which froze the file: an
/// extraction would have emptied the sizing-key slice and turned its `XCTAssertFalse` trio into a
/// vacuous pass. They now resolve through `AppSourceScanner`, which throws when an anchor is missing.
final class DashboardFreshnessViewTests: XCTestCase {
	func testDashboardFooterUsesTimelineViewForDisplayOnlyFreshness() throws {
		// Scoped to the dashboard face's own surface (declaration plus any extension of it, wherever
		// they live): `Date().timeIntervalSince` is legitimate in `DashboardViewModel`, so a whole-app
		// scan would misfire. `typeSurface` throws if `DashboardView` itself disappears.
		let source = try AppSourceScanner.typeSurface("DashboardView")

		XCTAssertTrue(source.contains("TimelineView(.periodic"))
		XCTAssertTrue(source.contains("DashboardFreshness.evaluate"))
		XCTAssertTrue(source.contains("refreshStatus: model.state.refreshStatus"))
		XCTAssertFalse(source.contains("\"Updated \\(freshness)\""))
		XCTAssertFalse(source.contains("Date().timeIntervalSince"))
	}

	func testFreshnessTickDoesNotDriveSurfaceResizing() throws {
		// The old slice ran from `surfaceSizingKey` all the way down to `footer`, sweeping in ~280
		// incidental lines; the contract this test names is the sizing key itself, so it is now the
		// brace-matched body of exactly that member — and a rename throws rather than emptying it.
		let sizingKeyBody = try AppSourceScanner.member(
			"var surfaceSizingKey: String", of: "DashboardView")

		XCTAssertFalse(sizingKeyBody.contains("refreshStatus"))
		XCTAssertFalse(sizingKeyBody.contains("DashboardFreshness"))
		XCTAssertFalse(sizingKeyBody.contains("TimelineView"))
	}

	// Behavioral coverage of the availability→sizing and availability→accessibility contracts lives in
	// DashboardStateTests (surfaceSizingSignature + chartAccessibilityLabel), which exercise the real
	// pure logic instead of grepping this view's source.
}
