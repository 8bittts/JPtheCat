import Foundation
import XCTest

@testable import JPtheCatCore

final class GrokBotPlanUsageTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_790_260_000)

	private let sand = Data("""
		{"currentPeriodStart":"2026-09-20T19:30:26.728Z","nextResetTimestampUtc":"2026-09-27T19:30:26.728Z",
		 "usagePercent":42.5,"hasAvailableUsage":true,"hasNonZeroIncludedLimit":true,
		 "grokPlanLabel":"Grok Bot Plan","isTeamSeat":false,"cursorPlanName":"Pro"}
		""".utf8)

	func testDecodesWeeklyMeterAndPlanLabel() throws {
		let usage = try XCTUnwrap(GrokBotPlanUsage.decode(sand: sand, planInfo: nil, fetchedAt: now))
		XCTAssertEqual(usage.planName, "Pro")
		XCTAssertEqual(usage.planLabel, "Grok Bot Plan")
		XCTAssertFalse(usage.isTeam)
		let weekly = try XCTUnwrap(usage.weekly)
		XCTAssertEqual(weekly.usedPercent, 42.5, accuracy: 0.001)
		XCTAssertEqual(weekly.label, "Weekly included usage")
	}

	func testNoIncludedLimitMeansNoReading() {
		let noAccess = Data(#"{"usagePercent":0,"hasNonZeroIncludedLimit":false}"#.utf8)
		XCTAssertNil(GrokBotPlanUsage.decode(sand: noAccess, planInfo: nil, fetchedAt: now))
	}

	func testStoreRoundTripsWhileEnabled() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-grok-bot-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let usage = try XCTUnwrap(GrokBotPlanUsage.decode(sand: sand, planInfo: nil, fetchedAt: now))
		try GrokBotPlanUsageStore.enable(appSupport: dir)
		try GrokBotPlanUsageStore.save(usage, appSupport: dir)
		let raw = try String(contentsOf: GrokBotPlanUsageStore.readingURL(appSupport: dir), encoding: .utf8)
		XCTAssertFalse(raw.contains("Bearer"), "plan usage cache must never store tokens")
		XCTAssertFalse(raw.lowercased().contains("refresh"), "plan usage cache must never store refresh material")
		XCTAssertEqual(GrokBotPlanUsageStore.load(now: now, appSupport: dir), usage)
		GrokBotPlanUsageStore.disable(appSupport: dir)
		XCTAssertNil(GrokBotPlanUsageStore.load(now: now, appSupport: dir))
	}
}
