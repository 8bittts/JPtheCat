import XCTest

@testable import JPtheCatApp

final class SelectorRowMeterMetricsTests: XCTestCase {
	func testAllProvidersPulseIsBallOnFullWidthLine() {
		// The ball rides a sparkline line that fills the full meter column — there is deliberately NO
		// fixed pulse-width cap (a prior `pulseWidth = 76` left the line stubbed short on the left).
		XCTAssertGreaterThan(SelectorRowMeterMetrics.dotDiameter, SelectorRowMeterMetrics.dotTrackHeight)
		// The dot has to fit within the pulse frame height with room to spare.
		XCTAssertLessThanOrEqual(SelectorRowMeterMetrics.dotDiameter, SelectorRowMeterMetrics.pulseFrameHeight)
	}
}
