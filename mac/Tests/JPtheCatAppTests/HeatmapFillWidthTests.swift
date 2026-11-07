import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

/// The Rhythm and Model × Day grains widen their cells to fill the analytics canvas (the Calendar grain
/// already does). Row HEIGHT must never flex — the window is fixed-height with no internal scroll, so a
/// taller row would push the sidebar's Export button off the bottom edge.
// [NOTE] The Advanced Analytics view types these read are `@MainActor`-isolated, so the suite is
// too — a nonisolated read is only a warning today and a hard error under a stricter mode.
@MainActor
final class HeatmapFillWidthTests: XCTestCase {
	/// The real canvas: 960pt window − 252pt sidebar − 1pt rule − 2×22pt padding.
	private let canvasWidth: CGFloat = 663

	func testRhythmRowFillsTheCanvasWidth() {
		let cols = HourWeekdayMatrix.hourCount  // 24
		// Both halves of the layout, never a hardcoded gap — the gap itself tightens on dense grids, so a
		// literal here would silently measure a row the view never draws.
		let layout = LabeledHeatmapGrid.fittedLayout(
			width: canvasWidth, columns: cols, rowLabelWidth: 30)
		let width = layout.cell
		XCTAssertGreaterThan(width, JPAppSpacing.analyticsHeatmapCell, "cells must grow past the square floor")
		let used = 30 + (width + layout.gap) * CGFloat(cols)
		XCTAssertLessThanOrEqual(used, canvasWidth + 0.5, "the row must not overflow the canvas")
		XCTAssertGreaterThan(used, canvasWidth * 0.9, "the row should consume nearly the whole canvas")
	}

	func testModelDayRowFillsTheCanvasWidthWithItsWiderLabelColumn() {
		let layout = LabeledHeatmapGrid.fittedLayout(
			width: canvasWidth, columns: 14, rowLabelWidth: 120)
		let used = 120 + (layout.cell + layout.gap) * 14
		XCTAssertLessThanOrEqual(used, canvasWidth + 0.5)
		XCTAssertGreaterThan(used, canvasWidth * 0.9)
	}

	/// A 90-day Model × Day grid has far more columns than the canvas can give square cells to — square
	/// cells would need 1,740pt of a 663pt canvas — so the row SHRINKS (with a tighter gap) to fit
	/// instead of running off the right edge.
	func testNinetyDayGridShrinksToFitInsteadOfOverflowing() {
		let layout = LabeledHeatmapGrid.fittedLayout(
			width: canvasWidth, columns: 90, rowLabelWidth: 120)
		XCTAssertLessThan(layout.cell, JPAppSpacing.analyticsHeatmapCell)
		XCTAssertGreaterThan(layout.cell, 2, "cells stay visible, not hairlines")
		let used = 120 + (layout.cell + layout.gap) * 90
		XCTAssertLessThanOrEqual(used, canvasWidth + 0.5, "the row must fit the canvas")
	}

	func testDegenerateInputsFallBackToTheSquareCell() {
		XCTAssertEqual(
			LabeledHeatmapGrid.fittedLayout(width: 0, columns: 24, rowLabelWidth: 30).cell,
			JPAppSpacing.analyticsHeatmapCell)
		XCTAssertEqual(
			LabeledHeatmapGrid.fittedLayout(width: canvasWidth, columns: 0, rowLabelWidth: 30).cell,
			JPAppSpacing.analyticsHeatmapCell)
	}
}
