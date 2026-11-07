import XCTest

@testable import JPtheCatApp

/// Locks the shared radar-ping curve so the aggregate-selector `PulseDot` and the hero `SparkChart`
/// end dot — which AGENTS.md requires to "read as one system" — can never drift apart. Both call
/// sites now derive the ring from `RadarPing`, and these asserts pin its magic numbers.
final class RadarPingTests: XCTestCase {
	func testCycleIsAOnePointFourSecondSawtooth() {
		XCTAssertEqual(RadarPing.period, 1.4, accuracy: 1e-9)
		// 0→1 ramp within a cycle, wrapping at the period.
		XCTAssertEqual(RadarPing.phase(at: 0), 0, accuracy: 1e-9)
		XCTAssertEqual(RadarPing.phase(at: 0.7), 0.5, accuracy: 1e-9)
		XCTAssertEqual(RadarPing.phase(at: 1.4), 0, accuracy: 1e-9, "wraps at the period")
		XCTAssertEqual(RadarPing.phase(at: 2.1), 0.5, accuracy: 1e-9, "wraps across cycles")
	}

	func testScaleExpandsOneToTwoPointFourEaseOut() {
		XCTAssertEqual(RadarPing.scale(0), 1.0, accuracy: 1e-9)
		XCTAssertEqual(RadarPing.scale(1), 2.4, accuracy: 1e-9)
		// Ease-out: more than half the growth is reached by the cycle midpoint.
		XCTAssertGreaterThan(RadarPing.scale(0.5), 1 + (2.4 - 1) / 2)
	}

	func testOpacityFadesFourTenthsToZero() {
		XCTAssertEqual(RadarPing.opacity(0), 0.4, accuracy: 1e-9)
		XCTAssertEqual(RadarPing.opacity(1), 0.0, accuracy: 1e-9)
		XCTAssertEqual(RadarPing.opacity(0.5), 0.2, accuracy: 1e-9)
	}
}
