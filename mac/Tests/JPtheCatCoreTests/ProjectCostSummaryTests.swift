import Foundation
import XCTest

@testable import JPtheCatCore

/// `UsageIndex.projectCostSummaries` — the analytics warehouse's "by project" slice. Verifies the
/// per-project bucketing (cost + every token type), the most-expensive-first ordering, the nil/empty
/// project → `(unattributed)` fold, and the window clamp.
final class ProjectCostSummaryTests: XCTestCase {
	private func utc() -> Calendar {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}
	private let iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()
	private func tempDBPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-proj-\(UUID().uuidString).sqlite").path
	}
	private func event(
		_ msg: String, _ req: String, _ ts: String, output: Int, project: String?,
		model: String = "claude-opus-4-8", provider: ProviderID = .claude
	) -> UsageEvent {
		UsageEvent(
			messageId: msg, requestId: req, provider: provider, model: model,
			timestamp: iso.date(from: ts)!, usage: TokenUsage(input: 100, output: output), project: project)
	}

	func testBucketsByProjectMostExpensiveFirstWithCorrectTokenSums() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let ts = "2026-06-30T10:00:00.000Z"
		// alpha: 2 events (more output → higher cost); beta: 1 event.
		try index.ingest([
			event("m1", "r1", ts, output: 500, project: "/Users/x/alpha"),
			event("m2", "r2", ts, output: 500, project: "/Users/x/alpha"),
			event("m3", "r3", ts, output: 100, project: "/Users/x/beta"),
		])

		let rows = try index.projectCostSummaries(providers: [.claude], days: 7, now: now, calendar: utc())
		XCTAssertEqual(rows.map(\.project), ["/Users/x/alpha", "/Users/x/beta"])  // cost-desc
		XCTAssertEqual(rows[0].eventCount, 2)
		XCTAssertEqual(rows[0].inputTokens, 200)  // 2 × 100
		XCTAssertEqual(rows[0].outputTokens, 1000)  // 2 × 500
		XCTAssertEqual(rows[1].eventCount, 1)
		XCTAssertEqual(rows[1].outputTokens, 100)
		XCTAssertGreaterThan(rows[0].cost, rows[1].cost)
	}

	func testNilOrEmptyProjectFoldsIntoUnattributed() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		let ts = "2026-06-30T10:00:00.000Z"
		try index.ingest([
			event("m1", "r1", ts, output: 100, project: nil),
			event("m2", "r2", ts, output: 100, project: ""),
		])

		let rows = try index.projectCostSummaries(providers: [.claude], days: 7, now: now, calendar: utc())
		XCTAssertEqual(rows.count, 1)
		XCTAssertEqual(rows[0].project, ProjectCostSummary.unattributed)
		XCTAssertEqual(rows[0].eventCount, 2)
	}

	func testWindowClampExcludesEventsOutsideTheDays() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		try index.ingest([
			event("in", "in", "2026-06-30T10:00:00.000Z", output: 100, project: "/p"),  // today
			event("out", "out", "2026-06-01T10:00:00.000Z", output: 100, project: "/p"),  // 29 days ago
		])

		let sevenDay = try index.projectCostSummaries(providers: [.claude], days: 7, now: now, calendar: utc())
		XCTAssertEqual(sevenDay.first?.eventCount, 1)  // only today's event
		let ninetyDay = try index.projectCostSummaries(providers: [.claude], days: 90, now: now, calendar: utc())
		XCTAssertEqual(ninetyDay.first?.eventCount, 2)  // both
	}

	func testNoProvidersReturnsEmpty() throws {
		let index = try UsageIndex(path: tempDBPath())
		let now = iso.date(from: "2026-06-30T12:00:00.000Z")!
		try index.ingest([event("m", "r", "2026-06-30T10:00:00.000Z", output: 100, project: "/p")])
		XCTAssertTrue(try index.projectCostSummaries(providers: [], days: 7, now: now, calendar: utc()).isEmpty)
	}

	/// The in-memory `bucketed(events:)` (CLI non-indexed path) matches the index query's shape/rule:
	/// per-project sums, unattributed fold, most-expensive-first ordering.
	func testBucketedMatchesTheIndexShapeAndOrdering() {
		let ts = "2026-06-30T10:00:00.000Z"
		let rows = ProjectCostSummary.bucketed(
			events: [
				event("m1", "r1", ts, output: 500, project: "alpha"),  // highest cost
				event("m2", "r2", ts, output: 200, project: "beta"),  // middle
				event("m3", "r3", ts, output: 100, project: nil),  // lowest → (unattributed)
			],
			calculator: CostCalculator())
		XCTAssertEqual(rows.map(\.project), ["alpha", "beta", ProjectCostSummary.unattributed])  // cost-desc
		XCTAssertEqual(rows[0].outputTokens, 500)
		XCTAssertEqual(rows.last?.project, ProjectCostSummary.unattributed)
	}
}
