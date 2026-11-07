import XCTest

@testable import JPtheCatCore

/// Pins the Advanced Analytics calendar grain's month blocking: the grid shows WHOLE calendar months
/// (so a 14-day window fills the canvas instead of occupying two ragged week columns), every in-month day
/// outside the window is `.outOfWindow` (recessive — never a "no activity" cell), and padding is `.blank`.
final class CalendarMonthLayoutTests: XCTestCase {
	private var calendar: Calendar {
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = TimeZone(identifier: "UTC")!
		cal.firstWeekday = 1
		return cal
	}

	private func day(_ iso: String) -> Date {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.date(from: iso)!
	}

	private func window(from start: String, count: Int) -> [HeatmapDay] {
		(0..<count).compactMap {
			calendar.date(byAdding: .day, value: $0, to: day(start)).map {
				HeatmapDay(day: $0, value: 1)
			}
		}
	}

	func testAFourteenDayWindowStillRendersTheWholeMonth() {
		let blocks = CalendarMonthLayout.months(days: window(from: "2026-07-15", count: 14), calendar: calendar)
		XCTAssertEqual(blocks.count, 1)
		// July 2026 starts on a Wednesday and has 31 days → 5 week columns once padded.
		XCTAssertEqual(blocks[0].columns.count, 5)
		let slots = blocks[0].columns.flatMap { $0 }
		XCTAssertEqual(slots.filter { if case .day = $0 { return true } else { return false } }.count, 14)
		XCTAssertEqual(
			slots.filter { if case .outOfWindow = $0 { return true } else { return false } }.count, 31 - 14)
	}

	func testAWindowSpanningTwoMonthsProducesTwoBlocksOldestFirst() {
		let blocks = CalendarMonthLayout.months(days: window(from: "2026-06-25", count: 20), calendar: calendar)
		XCTAssertEqual(blocks.count, 2)
		XCTAssertTrue(blocks[0].monthStart < blocks[1].monthStart)
		for block in blocks {
			XCTAssertTrue(block.columns.allSatisfy { $0.count == 7 }, "every column is a full weekday run")
		}
	}

	func testEveryDayLandsOnItsRealWeekdayRow() {
		let blocks = CalendarMonthLayout.months(days: window(from: "2026-07-01", count: 31), calendar: calendar)
		for column in blocks[0].columns {
			for (row, slot) in column.enumerated() {
				guard case .day(let hit) = slot else { continue }
				let weekday = calendar.component(.weekday, from: hit.day)
				XCTAssertEqual((weekday - calendar.firstWeekday + 7) % 7, row)
			}
		}
	}

	func testNoDaysProducesNoBlocks() {
		XCTAssertTrue(CalendarMonthLayout.months(days: [], calendar: calendar).isEmpty)
	}
}
