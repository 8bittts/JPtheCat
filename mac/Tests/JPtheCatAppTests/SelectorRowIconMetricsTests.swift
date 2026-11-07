import XCTest

@testable import JPtheCatApp

final class SelectorRowIconMetricsTests: XCTestCase {
	func testSelectorRowsUseOneCanonicalIconBox() {
		XCTEqualMetrics(SelectorRowIconMetrics.allProviders, SelectorRowIconMetrics.provider)
		XCTAssertEqual(SelectorRowIconMetrics.provider.containerSize, 18, accuracy: 0.001)
		XCTAssertEqual(SelectorRowIconMetrics.provider.imageSize, 16, accuracy: 0.001)
	}

	func testAllProvidersUsesBareJPMark() {
		XCTAssertFalse(SelectorRowIconMetrics.allProviders.drawsBackground)
		XCTAssertFalse(SelectorRowIconMetrics.allProviders.drawsOutline)
	}

	func testProviderRowsKeepSwatchTreatment() {
		XCTAssertTrue(SelectorRowIconMetrics.provider.drawsBackground)
		XCTAssertTrue(SelectorRowIconMetrics.provider.drawsOutline)
	}

	private func XCTEqualMetrics(
		_ lhs: SelectorRowIconMetrics,
		_ rhs: SelectorRowIconMetrics,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		XCTAssertEqual(lhs.containerSize, rhs.containerSize, accuracy: 0.001, file: file, line: line)
		XCTAssertEqual(lhs.imageSize, rhs.imageSize, accuracy: 0.001, file: file, line: line)
	}
}
