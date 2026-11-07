import XCTest

@testable import JPtheCatApp

final class DashboardRefreshGateTests: XCTestCase {
	func testTimeframeChangeInvalidatesInFlightRefresh() {
		var gate = DashboardRefreshGate()
		let inFlight = gate.token(days: 14)

		XCTAssertTrue(gate.shouldApply(inFlight, currentDays: 14))

		gate.invalidate()

		XCTAssertFalse(gate.shouldApply(inFlight, currentDays: 30))
		let current = gate.token(days: 30)
		XCTAssertTrue(gate.shouldApply(current, currentDays: 30))
	}

	func testRefreshTokenMustMatchCurrentDaysEvenWithinSameGeneration() {
		let gate = DashboardRefreshGate()
		let token = gate.token(days: 14)

		XCTAssertFalse(gate.shouldApply(token, currentDays: 30))
	}

	func testPendingTimeframeRefreshRunsBeforeQueuedFullReindex() {
		var queue = DashboardRefreshQueue()

		queue.request(reindex: true)
		queue.request(reindex: false)

		XCTAssertEqual(queue.popNext(), .windowOnly)
		XCTAssertEqual(queue.popNext(), .reindex)
		XCTAssertEqual(queue.popNext(), .none)
	}

	func testPendingTimeframeRefreshesCoalesceToOneWindowQuery() {
		var queue = DashboardRefreshQueue()

		queue.request(reindex: false)
		queue.request(reindex: false)

		XCTAssertEqual(queue.popNext(), .windowOnly)
		XCTAssertEqual(queue.popNext(), .none)
	}
}
