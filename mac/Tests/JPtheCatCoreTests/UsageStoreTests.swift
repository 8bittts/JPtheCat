import Foundation
import XCTest

@testable import JPtheCatCore

final class UsageStoreTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}
	private func ev(
		_ ts: Date, model: String = "claude-opus-4-8", output: Int = 1000, id: String = UUID().uuidString
	) -> UsageEvent {
		UsageEvent(
			messageId: id, requestId: id, provider: .claude, model: model, timestamp: ts,
			usage: TokenUsage(output: output))
	}

	func testTodayAndSevenDayBoundariesAreInclusive() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
		let sod = cal.startOfDay(for: now)
		let events = [
			ev(sod), // exactly midnight -> today (inclusive)
			ev(cal.date(byAdding: .hour, value: -1, to: sod)!), // yesterday 23:00 -> in 7d, not today
			ev(cal.date(byAdding: .day, value: -6, to: sod)!), // day-6 midnight -> in 7d (inclusive)
			ev(cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: -6, to: sod)!)!),
		]
		let r = UsageStore().rollup(events, now: now, calendar: cal)
		XCTAssertEqual(r.today.eventCount, 1)
		XCTAssertEqual(r.last7d.eventCount, 3) // [today-6 .. now], both ends inclusive
	}

	func testWindowBucketSpansSelectedDays() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
		let sod = cal.startOfDay(for: now)
		// One event today, one 10 days ago (inside a 14-day window, outside a 7-day one).
		let events = [ev(sod), ev(cal.date(byAdding: .day, value: -10, to: sod)!)]

		let sevenDay = UsageStore().rollup(events, days: 7, now: now, calendar: cal)
		XCTAssertEqual(sevenDay.last7d.eventCount, 1)
		XCTAssertEqual(sevenDay.windowDays, 7)

		let fourteenDay = UsageStore().rollup(events, days: 14, now: now, calendar: cal)
		XCTAssertEqual(fourteenDay.last7d.eventCount, 2)  // the day-10 event is now in-window
		XCTAssertEqual(fourteenDay.windowDays, 14)
		XCTAssertEqual(fourteenDay.today.eventCount, 1)  // today bucket is unaffected by the window
	}

	func testDefaultWindowIsSevenDays() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
		let r = UsageStore().rollup([ev(cal.startOfDay(for: now))], now: now, calendar: cal)
		XCTAssertEqual(r.windowDays, 7)
	}

	func testFutureEventsAreExcludedFromTodayAndSevenDays() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
		let future = cal.date(byAdding: .hour, value: 1, to: now)!

		let r = UsageStore().rollup([ev(now), ev(future)], now: now, calendar: cal)

		XCTAssertEqual(r.today.eventCount, 1)
		XCTAssertEqual(r.last7d.eventCount, 1)
	}

	func testCostSumsAndPerModelBreakdown() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
		let sod = cal.startOfDay(for: now)
		let events = [
			UsageEvent(
				messageId: "a", requestId: "a", provider: .claude, model: "claude-opus-4-8",
				timestamp: sod, usage: TokenUsage(output: 1_000_000)), // $25
			UsageEvent(
				messageId: "b", requestId: "b", provider: .claude, model: "claude-haiku-4-5",
				timestamp: sod, usage: TokenUsage(output: 1_000_000)), // $5
		]
		let r = UsageStore().rollup(events, now: now, calendar: cal)
		XCTAssertEqual(r.today.cost, 30.0, accuracy: 1e-9)
		XCTAssertEqual(r.byModel7d["claude-opus-4-8"]?.cost ?? -1, 25.0, accuracy: 1e-9)
	}

	func testUnpricedModelRecordedNotBilled() {
		let cal = utc()
		let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
		let sod = cal.startOfDay(for: now)
		let e = UsageEvent(
			messageId: "z", requestId: "z", provider: .claude, model: "gpt-imaginary", timestamp: sod,
			usage: TokenUsage(input: 999))
		let r = UsageStore().rollup([e], now: now, calendar: cal)
		XCTAssertEqual(r.today.cost, 0)
		XCTAssertTrue(r.today.unpricedModels.contains("gpt-imaginary"))
	}
}
