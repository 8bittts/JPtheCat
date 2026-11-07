import Foundation
import XCTest

@testable import JPtheCatCore

/// The honest cross-provider headroom model. The load-bearing invariant: it NEVER fabricates a number
/// for a provider without a live official signal — those resolve to `.unknown`, not `0`/`100`.
final class ProviderHeadroomTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_780_000_000)
	private func future(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
	private func past(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

	private func win(_ used: Double, minutes: Int = 300, resets: Date?) -> RateLimitWindow {
		RateLimitWindow(usedPercent: used, windowMinutes: minutes, resetsAt: resets)
	}

	func testNilSnapshotIsUnknownNeverANumber() {
		let h = ProviderHeadroom.resolve(from: nil, now: now)
		XCTAssertEqual(h, .unknown)
		XCTAssertNil(h.remainingPercent, "unknown must never carry a fabricated number")
		XCTAssertEqual(h.stateToken, "unknown")
	}

	func testOfficialRemainingIsFromTheTightestCurrentWindow() {
		// primary 40% used, weekly 60% used -> weekly is tighter -> remaining 40%.
		let snap = RateLimitSnapshot(
			primary: win(40, minutes: 300, resets: future(60)),
			secondary: win(60, minutes: 10080, resets: future(600)),
			planType: "pro")
		let h = ProviderHeadroom.resolve(from: snap, now: now)
		XCTAssertEqual(h, .official(remainingPercent: 40, windowMinutes: 10080, resetsAt: future(600)))
		XCTAssertEqual(h.remainingPercent, 40)
		XCTAssertEqual(h.stateToken, "official")
	}

	func testSingleWindowOfficial() {
		let snap = RateLimitSnapshot(
			primary: win(25, minutes: 300, resets: future(30)), secondary: nil, planType: "pro")
		XCTAssertEqual(
			ProviderHeadroom.resolve(from: snap, now: now),
			.official(remainingPercent: 75, windowMinutes: 300, resetsAt: future(30)))
	}

	func testRemainingIsClampedIntoZeroToHundred() {
		let over = RateLimitSnapshot(primary: win(140, resets: future(30)), secondary: nil, planType: nil)
		XCTAssertEqual(ProviderHeadroom.resolve(from: over, now: now).remainingPercent, 0)
		let under = RateLimitSnapshot(primary: win(-5, resets: future(30)), secondary: nil, planType: nil)
		XCTAssertEqual(ProviderHeadroom.resolve(from: under, now: now).remainingPercent, 100)
	}

	func testAllWindowsExpiredIsUnknownNotStale() {
		let snap = RateLimitSnapshot(
			primary: win(80, minutes: 300, resets: past(5)),
			secondary: win(50, minutes: 10080, resets: past(1)), planType: "pro")
		XCTAssertEqual(ProviderHeadroom.resolve(from: snap, now: now), .unknown)
	}

	func testFrozenHighClaudeCaptureIsLikelyExhausted() {
		// Claude: 5h window high (>=85) AND capture went quiet (>10m) -> likely exhausted, not a number.
		let snap = RateLimitSnapshot(
			primary: win(92, minutes: 300, resets: future(30)), secondary: nil, planType: nil,
			capturedAt: past(15))
		let h = ProviderHeadroom.resolve(from: snap, now: now)
		XCTAssertEqual(h, .likelyExhausted)
		XCTAssertNil(h.remainingPercent)
		XCTAssertEqual(h.stateToken, "likely_exhausted")
	}

	func testFreshHighClaudeCaptureIsStillOfficial() {
		// High but the capture is FRESH -> we still have a real current figure, so official (8% left).
		let snap = RateLimitSnapshot(
			primary: win(92, minutes: 300, resets: future(30)), secondary: nil, planType: nil,
			capturedAt: past(2))
		XCTAssertEqual(
			ProviderHeadroom.resolve(from: snap, now: now),
			.official(remainingPercent: 8, windowMinutes: 300, resetsAt: future(30)))
	}

	func testEmptySnapshotIsUnknown() {
		let snap = RateLimitSnapshot(primary: nil, secondary: nil, planType: "pro")
		XCTAssertEqual(ProviderHeadroom.resolve(from: snap, now: now), .unknown)
	}
}
