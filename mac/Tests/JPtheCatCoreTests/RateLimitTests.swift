import Foundation
import XCTest

@testable import JPtheCatCore

final class RateLimitTests: XCTestCase {
	func testWindowIsCurrentUntilResetArrives() {
		let now = Date(timeIntervalSince1970: 1_783_000_000)

		XCTAssertNotNil(
			RateLimitWindow(
				usedPercent: 82, windowMinutes: 300, resetsAt: now.addingTimeInterval(1)
			).current(at: now))
		XCTAssertNil(
			RateLimitWindow(
				usedPercent: 82, windowMinutes: 300, resetsAt: now
			).current(at: now))
		XCTAssertNil(
			RateLimitWindow(
				usedPercent: 82, windowMinutes: 300, resetsAt: now.addingTimeInterval(-1)
			).current(at: now))
		XCTAssertNotNil(
			RateLimitWindow(usedPercent: 82, windowMinutes: 300, resetsAt: nil).current(at: now))
	}

	func testSnapshotDropsExpiredWindowsAndYieldsNilWhenNoneRemain() {
		let now = Date(timeIntervalSince1970: 1_783_000_000)
		let expired = RateLimitWindow(
			usedPercent: 91, windowMinutes: 300, resetsAt: now.addingTimeInterval(-1))
		let current = RateLimitWindow(
			usedPercent: 43, windowMinutes: 10080, resetsAt: now.addingTimeInterval(60))

		let filtered = RateLimitSnapshot(primary: expired, secondary: current, planType: "pro")
			.current(at: now)

		XCTAssertNil(filtered?.primary)
		XCTAssertEqual(filtered?.secondary, current)
		XCTAssertEqual(filtered?.planType, "pro")
		XCTAssertNil(RateLimitSnapshot(primary: expired, secondary: nil, planType: "pro").current(at: now))
	}

	/// Reproduces the "bars reset randomly after a long idle period, then reappear once I use a model"
	/// report: nothing changes the data — only wall-clock passing the reset boundary blanks the gauge,
	/// and the window that just rolled over is flagged so the UI can show a hint instead of vanishing.
	func testAwaitingFreshDataAfterResetDistinguishesRolloverFromNoData() {
		let captured = Date(timeIntervalSince1970: 1_783_000_000)
		let fiveHour = RateLimitWindow(
			usedPercent: 62, windowMinutes: 300, resetsAt: captured.addingTimeInterval(3 * 3600))
		let snapshot = RateLimitSnapshot(primary: fiveHour, secondary: nil, planType: "pro")

		// While current: gauge shows, no hint.
		XCTAssertNotNil(snapshot.current(at: captured)?.primary)
		XCTAssertFalse(snapshot.awaitingFreshDataAfterReset(at: captured))

		// Just past reset with no fresh reading: gauge is blank BUT the rollover is flagged.
		let justAfter = captured.addingTimeInterval(3 * 3600 + 60)
		XCTAssertNil(snapshot.current(at: justAfter))
		XCTAssertTrue(
			snapshot.awaitingFreshDataAfterReset(at: justAfter),
			"a window that just rolled over must flag the hint, not silently disappear")

		// Long past the grace: fall back to a plain blank gauge (no stale 'awaiting' hint).
		let longAfter = captured.addingTimeInterval(3 * 3600 + RateLimitSnapshot.resetHintGrace + 60)
		XCTAssertFalse(snapshot.awaitingFreshDataAfterReset(at: longAfter))

		// A window with no resetsAt (never-expiring) is never a rollover hint.
		let noReset = RateLimitSnapshot(
			primary: RateLimitWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil),
			secondary: nil, planType: "pro")
		XCTAssertFalse(noReset.awaitingFreshDataAfterReset(at: justAfter))

		// The honesty invariant holds: we NEVER fabricate a replacement percentage — the flagged snapshot
		// still yields nil from current(), so no number is shown.
		XCTAssertNil(snapshot.current(at: justAfter)?.primary?.usedPercent)
	}
}
