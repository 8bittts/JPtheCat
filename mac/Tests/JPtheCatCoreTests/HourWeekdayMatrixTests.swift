import XCTest

@testable import JPtheCatCore

/// Locks the Rhythm punchcard's pure value type: local-time weekday/hour binning of already-loaded
/// events (the Copilot twin of `UsageIndex.hourWeekdayBins`), per-measure value selection, the
/// element-wise `summed` fold the canvas uses to combine checked providers, and the peak-bin scan the
/// "Busiest: …" callout reads. Deterministic via an explicit UTC gregorian calendar.
final class HourWeekdayMatrixTests: XCTestCase {

	private var utc: Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}

	private let iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private func event(
		_ ts: String, provider: ProviderID = .copilot, model: String = "gpt-5",
		input: Int = 0, output: Int = 0, cacheRead: Int = 0
	) -> UsageEvent {
		UsageEvent(
			messageId: UUID().uuidString, requestId: UUID().uuidString, provider: provider, model: model,
			timestamp: iso.date(from: ts)!,
			usage: TokenUsage(input: input, output: output, cacheRead: cacheRead))
	}

	// MARK: bucketed — local weekday/hour binning

	func testBucketedBinsByLocalWeekdayAndHour() {
		// 2026-07-09 is a Thursday (Calendar weekday 5); 15:30 UTC → hour 15.
		// 2026-07-06 is a Monday (weekday 2); 09:00 UTC → hour 9.
		let events = [
			event("2026-07-09T15:30:00.000Z", input: 100, output: 50),  // Thu 15:00
			event("2026-07-09T15:45:00.000Z", input: 10, output: 5),  // Thu 15:00 (same bin)
			event("2026-07-06T09:00:00.000Z", input: 200, output: 0),  // Mon 09:00
		]
		let matrix = HourWeekdayMatrix.bucketed(events: events, calculator: CostCalculator(), calendar: utc)

		// Thursday 15:00 accumulates BOTH events.
		XCTAssertEqual(matrix.value(weekday: 5, hour: 15, measure: .events), 2)
		XCTAssertEqual(matrix.value(weekday: 5, hour: 15, measure: .tokens), 100 + 50 + 10 + 5)
		// Monday 09:00 has the single event.
		XCTAssertEqual(matrix.value(weekday: 2, hour: 9, measure: .events), 1)
		XCTAssertEqual(matrix.value(weekday: 2, hour: 9, measure: .tokens), 200)
		// An untouched bin is zero.
		XCTAssertEqual(matrix.value(weekday: 1, hour: 0, measure: .events), 0)
		XCTAssertTrue(matrix.value(weekday: 5, hour: 15, measure: .cost) >= 0)
	}

	func testMeasureSelectsEventsTokensOrCost() {
		let matrix = HourWeekdayMatrix.bucketed(
			events: [event("2026-07-09T15:00:00.000Z", input: 100, output: 50, cacheRead: 35)],
			calculator: CostCalculator(), calendar: utc)
		XCTAssertEqual(matrix.value(weekday: 5, hour: 15, measure: .events), 1)
		XCTAssertEqual(
			matrix.value(weekday: 5, hour: 15, measure: .tokens), 185, "tokens = input+output+cacheRead")
	}

	func testPeakReturnsTheBusiestBinForMeasureAndNilWhenEmpty() {
		let events = [
			event("2026-07-06T09:00:00.000Z", output: 10),  // Mon 09:00 — 1 event
			event("2026-07-09T15:00:00.000Z", output: 10),  // Thu 15:00 — 2 events (busiest)
			event("2026-07-09T15:20:00.000Z", output: 10),
		]
		let matrix = HourWeekdayMatrix.bucketed(events: events, calculator: CostCalculator(), calendar: utc)
		let peak = matrix.peak(measure: .events)
		XCTAssertEqual(peak?.weekday, 5)
		XCTAssertEqual(peak?.hour, 15)
		XCTAssertEqual(peak?.value, 2)

		XCTAssertNil(HourWeekdayMatrix.zero.peak(measure: .events), "no activity → no peak")
		XCTAssertTrue(HourWeekdayMatrix.zero.isEmpty(measure: .cost))
		XCTAssertFalse(matrix.isEmpty(measure: .events))
	}

	func testSummedIsElementWise() {
		let a = HourWeekdayMatrix.bucketed(
			events: [event("2026-07-09T15:00:00.000Z", output: 5)], calculator: CostCalculator(), calendar: utc)
		let b = HourWeekdayMatrix.bucketed(
			events: [
				event("2026-07-09T15:10:00.000Z", output: 7),
				event("2026-07-06T09:00:00.000Z", output: 3),
			], calculator: CostCalculator(), calendar: utc)
		let summed = HourWeekdayMatrix.summed([a, b])
		XCTAssertEqual(summed.value(weekday: 5, hour: 15, measure: .events), 2, "Thu 15:00: 1 + 1")
		XCTAssertEqual(summed.value(weekday: 5, hour: 15, measure: .tokens), 12, "5 + 7")
		XCTAssertEqual(summed.value(weekday: 2, hour: 9, measure: .events), 1, "Mon 09:00 from b only")
		XCTAssertEqual(HourWeekdayMatrix.summed([]).isEmpty(measure: .events), true)
	}

	func testOutOfRangeIndicesAreIgnoredNotCrashing() {
		var matrix = HourWeekdayMatrix.zero
		matrix.add(weekday: 0, hour: 0, events: 1, tokens: 1, cost: 1)  // weekday 0 invalid
		matrix.add(weekday: 8, hour: 0, events: 1, tokens: 1, cost: 1)  // weekday 8 invalid
		matrix.add(weekday: 3, hour: 24, events: 1, tokens: 1, cost: 1)  // hour 24 invalid
		XCTAssertTrue(matrix.isEmpty(measure: .events))
		XCTAssertEqual(matrix.cell(weekday: 99, hour: 99).events, 0, "out-of-range read is a zero cell")
	}
}
