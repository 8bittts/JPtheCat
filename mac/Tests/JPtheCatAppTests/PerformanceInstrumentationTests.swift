import XCTest

@testable import JPtheCatApp

final class PerformanceInstrumentationTests: XCTestCase {
	func testResourceSnapshotComputesIdleCPUPercentBetweenSamples() {
		let start = PerformanceResourceSnapshot(
			uptimeSeconds: 100,
			residentMemoryBytes: 42 * 1_024 * 1_024,
			totalCPUTimeSeconds: 10
		)
		let end = PerformanceResourceSnapshot(
			uptimeSeconds: 110,
			residentMemoryBytes: 43 * 1_024 * 1_024,
			totalCPUTimeSeconds: 10.25
		)

		XCTAssertEqual(end.residentMemoryMegabytes, 43, accuracy: 0.001)
		XCTAssertEqual(try XCTUnwrap(end.cpuPercent(since: start)), 2.5, accuracy: 0.001)
	}

	func testPhase2PerformanceBudgetsAreEncoded() {
		XCTAssertEqual(PerformanceBudget.coldStartToFirstNumberMilliseconds, 400, accuracy: 0.001)
		XCTAssertEqual(PerformanceBudget.incrementalReloadMilliseconds, 50, accuracy: 0.001)
		XCTAssertEqual(PerformanceBudget.idleResidentMemoryMegabytes, 50, accuracy: 0.001)
		XCTAssertEqual(PerformanceBudget.idleCPUPercent, 1, accuracy: 0.001)
	}
}
