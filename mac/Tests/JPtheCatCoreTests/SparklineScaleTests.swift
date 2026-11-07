import XCTest
@testable import JPtheCatCore

/// Regression guard for the dashboard hero sparkline scaling contract — the model for every future
/// provider. Locks in per-provider auto-range with a min-anchored baseline so a low/steady provider
/// (e.g. Codex) never collapses flat under a bigger provider's peak.
final class SparklineScaleTests: XCTestCase {
	private func assertClose(_ a: Double, _ b: Double, _ msg: String = "", accuracy: Double = 1e-9) {
		XCTAssertEqual(a, b, accuracy: accuracy, msg)
	}

	// The baseline is the series MINIMUM (never zero): the lowest point sits at 0, the peak at 1, so a
	// series' full amplitude is used regardless of its absolute spend level.
	func testMinAnchoredBaselineUsesFullRange() {
		let f = SparklineScale.fractions([10, 20, 30])
		assertClose(f.min() ?? -1, 0, "series minimum must sit on the baseline (0)")
		assertClose(f.max() ?? -1, 1, "series peak must reach the top (1)")
	}

	// The core "feel real" property: two providers with wildly different absolute spend but the SAME
	// relative shape must produce IDENTICAL normalized charts. A low provider is never flattened by a
	// high one because scaling is per-series, not a shared cross-provider max.
	func testScaleIsPerProviderNotShared() {
		let bigProvider = SparklineScale.fractions([100, 200, 150, 300])
		let smallProvider = SparklineScale.fractions([1, 2, 1.5, 3])
		XCTAssertEqual(bigProvider.count, smallProvider.count)
		for (a, b) in zip(bigProvider, smallProvider) { assertClose(a, b, "same shape → same chart") }
	}

	// A low/steady provider with real day-to-day variation must show meaningful vertical spread — the
	// exact regression that motivated this (Codex reading flat). Guard: peak-to-trough spread ≥ 0.5.
	func testLowSteadyProviderShowsVariation() {
		let codexLike = [8.0, 12, 9, 11, 10, 13, 9.5]
		let f = SparklineScale.fractions(codexLike)
		let spread = (f.max() ?? 0) - (f.min() ?? 0)
		XCTAssertGreaterThanOrEqual(spread, 0.5, "a varying low/steady provider must not read flat")
	}

	// Headroom floor: a series whose variation is a tiny fraction of its peak must STAY near-flat — we
	// do not amplify trivial noise into a full-height jagged line. Variation ~1% of peak with a 15%
	// floor should read as at most ~1/15 of full height.
	func testHeadroomFloorKeepsTrivialNoiseFlat() {
		let almostFlat = [100.0, 100.5, 99.8, 100.2, 100.1]
		let f = SparklineScale.fractions(almostFlat)
		let spread = (f.max() ?? 0) - (f.min() ?? 0)
		XCTAssertLessThan(spread, 0.10, "trivial noise must not be amplified to full height")
	}

	// A single dominant spike legitimately compresses the rest — the tail IS flat relative to the
	// spike. The spike hits the top; the low tail clusters near the bottom.
	func testDominantSpikeCompressesTailHonestly() {
		let f = SparklineScale.fractions([50, 4, 4.2, 3.8, 4.1])
		assertClose(f.first ?? -1, 1, "the spike is the series peak")
		for tail in f.dropFirst() { XCTAssertLessThan(tail, 0.05, "tail sits near baseline under the spike") }
	}

	// Degenerate inputs never crash and never divide by zero.
	func testDegenerateInputs() {
		XCTAssertEqual(SparklineScale.fractions([]), [])
		let flat = SparklineScale.fractions([5, 5, 5])
		XCTAssertEqual(flat, [0, 0, 0], "a perfectly flat series parks on the baseline, no NaN")
		let zeros = SparklineScale.fractions([0, 0])
		for v in zeros { XCTAssertFalse(v.isNaN, "all-zero series must not produce NaN") }
	}

	func testChartPointsPeakAboveTroughForRisingSeries() {
		let values = [1.0, 2.0, 4.0, 3.0]
		for height: CGFloat in [5, 16, 18] {
			let points = SparklineScale.chartPoints(values: values, in: CGSize(width: 100, height: height))
			XCTAssertEqual(points.count, values.count)
			let trough = points[0]
			let peak = points[2]
			XCTAssertLessThan(peak.y, trough.y, "peak must sit above trough (smaller y) at height \(height)")
			XCTAssertLessThan(points[3].y, points[1].y)
		}
	}
}
