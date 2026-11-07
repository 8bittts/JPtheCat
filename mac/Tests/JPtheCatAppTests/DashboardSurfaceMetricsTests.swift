import XCTest

@testable import JPtheCatApp

final class DashboardSurfaceMetricsTests: XCTestCase {
	func testEachLayoutUsesAFixedWidthWithIntrinsicHeight() {
		XCTAssertEqual(DashboardLayout.oneColumn.width, 384, accuracy: 0.001)
		XCTAssertEqual(DashboardLayout.twoColumns.width, 768, accuracy: 0.001)
	}

	func testInitialWindowSizeIsOnlyAStartupFallback() {
		for layout in DashboardLayout.allCases {
			let size = DashboardSurfaceMetrics.initialWindowSize(for: layout)
			XCTAssertEqual(size.width, layout.width, accuracy: 0.001)
			XCTAssertGreaterThan(size.height, 0)
		}
	}
}
