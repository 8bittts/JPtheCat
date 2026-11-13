import Foundation
import XCTest
@testable import JPtheCatCore

final class GrokConsolidationTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)
	private func weekly(_ percent: Double = 30.46) -> CursorPlanMeter {
		CursorPlanMeter(key: CursorPlanMeter.grokBotKey, label: "Weekly included usage", usedPercent: percent,
			resetsAt: now.addingTimeInterval(86400))
	}
	private func temporaryRoot() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	func testAttemptCadenceSurvivesFailedFetchAndRelaunch() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: root) }
		try GrokPlanUsageStore.enable(appSupport: root)
		XCTAssertNil(GrokPlanUsageStore.lastAttemptAt(appSupport: root))
		try GrokPlanUsageStore.recordAttempt(at: now, appSupport: root)
		XCTAssertEqual(GrokPlanUsageStore.lastAttemptAt(appSupport: root), now)
		XCTAssertNil(GrokPlanUsageStore.load(now: now, appSupport: root), "A failed attempt is not a fabricated usage reading")
		GrokPlanUsageStore.disable(appSupport: root)
		XCTAssertNil(GrokPlanUsageStore.lastAttemptAt(appSupport: root))
	}

	func testOnePublicIdentityWithBackwardsCompatibleRawAliases() {
		XCTAssertEqual(ProviderID.cursor.consolidated, .grok)
		XCTAssertEqual(ProviderID.grokBot.consolidated, .grok)
		XCTAssertFalse(ProviderCatalog.all.contains { $0.id == .cursor || $0.id == .grokBot })
		XCTAssertEqual(ProviderCatalog.descriptor(for: .cursor)?.id, .grok)
		for raw in ["cursor", "grok_bot", "grok-bot", "grokbot"] {
			XCTAssertEqual(ProviderID.consolidatedRawID(raw), "grok")
		}
	}

	func testWeeklyWinsOverLargerMonthlyPercentAndMonthlyOnlyIsAnHonestFallback() {
		let monthly = CursorPlanMeter(key: "cursor_models", label: "Cursor Models", usedPercent: 100,
			resetsAt: now.addingTimeInterval(86400))
		let plan = CursorPlanUsage(planName: nil, isTeam: false, meters: [monthly, weekly()], fetchedAt: now)
		XCTAssertEqual(plan.primaryMeter?.key, CursorPlanMeter.grokBotKey)
		let monthlyOnly = CursorPlanUsage(planName: nil, isTeam: false, meters: [monthly], fetchedAt: now)
		XCTAssertEqual(monthlyOnly.primaryMeter?.key, "cursor_models")
	}

	func testHeadlinePoolSkipsAMaxedPoolForThePriorityPoolWithRoom() {
		XCTAssertNil(PlanPoolHeadline.index(of: []))
		XCTAssertEqual(PlanPoolHeadline.index(of: [(100, nil), (37, nil), (10, nil)]), 1, "priority, not the emptiest pool")
		XCTAssertEqual(PlanPoolHeadline.index(of: [(99.6, nil), (64, nil)]), 1, "a bar that already reads 100% has no room")
		XCTAssertEqual(PlanPoolHeadline.index(of: [(99.4, nil), (10, nil)]), 0)
		let maxedSand = weekly(100)
		let cursor = CursorPlanMeter(key: "cursor_models", label: "Cursor Models", usedPercent: 40,
			resetsAt: now.addingTimeInterval(8 * 86400))
		let plan = CursorPlanUsage(planName: nil, isTeam: false, meters: [maxedSand, cursor], fetchedAt: now)
		XCTAssertEqual(plan.primaryMeter?.key, "cursor_models")
	}

	func testEveryPoolMaxedShowsTheExhaustedPoolThatResetsSoonest() {
		let late = CursorPlanMeter(key: "cursor_models", label: "Cursor Models", usedPercent: 100,
			resetsAt: now.addingTimeInterval(8 * 86400))
		let soon = CursorPlanMeter(key: "other_models", label: "Other Models", usedPercent: 100,
			resetsAt: now.addingTimeInterval(3600))
		let undated = CursorPlanMeter(key: "all_models", label: "All models", usedPercent: 100, resetsAt: nil)
		let plan = CursorPlanUsage(planName: nil, isTeam: false, meters: [late, undated, soon], fetchedAt: now)
		XCTAssertEqual(plan.primaryMeter?.key, "other_models")
		XCTAssertEqual(plan.primaryMeter?.usedPercent, 100)
		XCTAssertEqual(PlanPoolHeadline.index(of: [(100, nil), (100, nil)]), 0, "no resets keeps priority order")
	}

	func testSinglePoolHeadlinesUnchangedWhetherOrNotItHasRoom() {
		XCTAssertEqual(CursorPlanUsage(planName: nil, isTeam: false, meters: [weekly(30.46)], fetchedAt: now)
			.primaryMeter?.usedPercent, 30.46)
		XCTAssertEqual(CursorPlanUsage(planName: nil, isTeam: false, meters: [weekly(100)], fetchedAt: now)
			.primaryMeter?.usedPercent, 100)
		let hook = RateLimitSnapshot(primary: nil, secondary: RateLimitWindow(usedPercent: 100,
			windowMinutes: 10080, resetsAt: now.addingTimeInterval(3600)), planType: "X Premium+", capturedAt: now)
		XCTAssertEqual(GrokPlanUsageStore.primaryMeter(plan: nil, fallback: hook, now: now)?.label, "X Premium+")
	}

	func testMaxedSubscriptionWeeklyYieldsToGrokBotWeeklyWithRoom() {
		let allModels = CursorPlanMeter(key: "all_models", label: "All models", usedPercent: 100,
			resetsAt: now.addingTimeInterval(8 * 86400))
		let plan = CursorPlanUsage(planName: "Team", isTeam: true, meters: [allModels, weekly(37.36)], fetchedAt: now,
			reportedPlanLabel: "Grok Bot Plan")
		let hook = RateLimitSnapshot(primary: nil, secondary: RateLimitWindow(usedPercent: 100,
			windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400)), planType: "X Premium+", capturedAt: now)
		XCTAssertEqual(GrokPlanUsageStore.officialSnapshot(plan: plan, hook: hook, now: now)?.secondary?.usedPercent, 100,
			"the official weekly itself is unchanged; only the headline moves")
		let headline = GrokPlanUsageStore.primaryMeter(plan: plan, fallback: hook, now: now)
		XCTAssertEqual(headline?.key, CursorPlanMeter.grokBotKey)
		XCTAssertEqual(headline?.label, "Weekly included usage")
		XCTAssertEqual(headline?.usedPercent ?? -1, 37.36, accuracy: 0.001)
	}

	func testSubscriptionWeeklyStaysDistinctFromGrokBotAndCursor() {
		let reset = now.addingTimeInterval(3 * 86400)
		let sand = weekly(22)
		let cursor = CursorPlanMeter(key: "cursor_models", label: "Cursor Models", usedPercent: 100,
			resetsAt: now.addingTimeInterval(8 * 86400))
		let plan = CursorPlanUsage(planName: "Team", isTeam: true, meters: [cursor, sand], fetchedAt: now,
			reportedPlanLabel: "Grok Bot Plan")
		let hook = RateLimitSnapshot(primary: nil, secondary: RateLimitWindow(usedPercent: 1,
			windowMinutes: 10080, resetsAt: reset), planType: "X Premium+", capturedAt: now)
		let snapshot = GrokPlanUsageStore.officialSnapshot(plan: plan, hook: hook, now: now)
		XCTAssertEqual(snapshot?.planType, "X Premium+")
		XCTAssertEqual(snapshot?.secondary?.usedPercent, 1)
		XCTAssertEqual(GrokPlanUsageStore.primaryMeter(plan: plan, fallback: hook, now: now)?.usedPercent, 1)
		XCTAssertFalse(GrokPlanUsageStore.sameReading(1, sand.usedPercent, reset, sand.resetsAt))
		XCTAssertEqual(plan.quotaGroups(meters: plan.meters).map(\.title), [
			"Cursor · Team seat", "Grok Bot Plan · included usage",
		])
	}

	func testHookWeeklyPrecedesMonthlyWithoutDuplicatingOrInventingAPool() {
		let monthly = CursorPlanMeter(key: "cursor_models", label: "Cursor Models", usedPercent: 99,
			resetsAt: now.addingTimeInterval(86400))
		let plan = CursorPlanUsage(planName: "Pro", isTeam: false, meters: [monthly], fetchedAt: now)
		let hook = RateLimitSnapshot(primary: nil, secondary: RateLimitWindow(usedPercent: 22,
			windowMinutes: 10080, resetsAt: now.addingTimeInterval(3600)), planType: nil, capturedAt: now)
		XCTAssertEqual(GrokPlanUsageStore.primaryMeter(plan: plan, fallback: hook, now: now)?.usedPercent, 22)
		XCTAssertEqual(GrokPlanUsageStore.primaryMeter(plan: plan, fallback: hook, now: now)?.key, CursorPlanMeter.grokBotKey)
		XCTAssertEqual(plan.meters.map(\.key), ["cursor_models"])
	}

	func testLegacyCursorCacheIsVisibleImmediatelyAndNeverSplicedWithAnotherAccountsBotPool() throws {
		let root = try temporaryRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		try CursorPlanUsageStore.enable(appSupport: root)
		try GrokBotPlanUsageStore.enable(appSupport: root)
		let cursor = CursorPlanUsage(planName: "Team", isTeam: true, meters: [weekly()], fetchedAt: now)
		try CursorPlanUsageStore.save(cursor, appSupport: root)
		try GrokBotPlanUsageStore.save(GrokBotPlanUsage(planName: "Other", planLabel: "Other account", isTeam: false,
			weekly: weekly(80), fetchedAt: now.addingTimeInterval(60)), appSupport: root)
		XCTAssertEqual(GrokPlanUsageStore.load(now: now, appSupport: root), cursor)
		XCTAssertFalse(FileManager.default.fileExists(atPath: GrokPlanUsageStore.readingURL(appSupport: root).path))
	}

	func testLegacyBotCacheLoadsWithoutCursorInstallAndOptOutClearsEveryPlanMarker() throws {
		let root = try temporaryRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		try GrokBotPlanUsageStore.enable(appSupport: root)
		try GrokBotPlanUsageStore.save(GrokBotPlanUsage(planName: "Team", planLabel: "Grok Bot Plan", isTeam: true,
			weekly: weekly(), fetchedAt: now), appSupport: root)
		let loaded = try XCTUnwrap(GrokPlanUsageStore.load(now: now, appSupport: root))
		XCTAssertEqual(loaded.primaryMeter?.usedPercent, 30.46)
		XCTAssertEqual(loaded.planLabel, "Grok Bot Plan")
		try GrokPlanUsageStore.enable(appSupport: root)
		try GrokPlanUsageStore.save(loaded, appSupport: root)
		GrokPlanUsageStore.disable(appSupport: root)
		XCTAssertFalse(GrokPlanUsageStore.isEnabled(appSupport: root))
		XCTAssertNil(GrokPlanUsageStore.load(now: now, appSupport: root))
	}

	func testUnifiedEmptyOrExpiredCacheCannotResurrectLegacyEntitlement() throws {
		let root = try temporaryRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		try CursorPlanUsageStore.enable(appSupport: root)
		try CursorPlanUsageStore.save(CursorPlanUsage(planName: "Team", isTeam: true, meters: [weekly()], fetchedAt: now), appSupport: root)
		try GrokPlanUsageStore.save(CursorPlanUsage(planName: nil, isTeam: false, meters: [], fetchedAt: now), appSupport: root)
		XCTAssertNil(GrokPlanUsageStore.load(now: now, appSupport: root))
		XCTAssertEqual(GrokPlanUsageStore.lastFetchedAt(appSupport: root), now)
	}

	func testWeeklyOnlyEntitlementDecodesWithoutMonthlyPlanUsage() throws {
		let sand = Data(#"{"usagePercent":30.46,"hasNonZeroIncludedLimit":true,"nextResetTimestampUtc":"2027-01-16T00:00:00Z","grokPlanLabel":"Included plan"}"#.utf8)
		let plan = try XCTUnwrap(CursorPlanUsage.decode(currentPeriod: Data("{}".utf8), grokBot: sand,
			planInfo: nil, fetchedAt: now))
		XCTAssertEqual(plan.meters.count, 1)
		XCTAssertEqual(plan.planLabel, "Included plan")
		XCTAssertEqual(plan.primaryMeter?.usedPercent, 30.46)
	}

	func testNoNonZeroIncludedLimitNeverInventsWeeklyPool() {
		let sand = Data(#"{"usagePercent":0,"hasNonZeroIncludedLimit":false}"#.utf8)
		XCTAssertNil(CursorPlanUsage.decode(currentPeriod: Data("{}".utf8), grokBot: sand, planInfo: nil, fetchedAt: now))
	}

	func testSharedClientRequestsExactlyThreeEndpointsForACompleteAccount() async throws {
		let log = RequestLog()
		let client = GrokPlanUsageClient(transport: { request in
			await log.record(request.url!.lastPathComponent)
			let method = request.url!.lastPathComponent
			XCTAssertEqual(request.url!.host, "api2.cursor.sh")
			XCTAssertEqual(request.httpBody, Data("{}".utf8))
			let body: String
			switch method {
			case "GetCurrentPeriodUsage": body = #"{"planUsage":{"autoPercentUsed":10}}"#
			case "GetSandUsageStatus": body = #"{"hasNonZeroIncludedLimit":true,"usagePercent":30.46}"#
			case "GetPlanInfo": body = #"{"planInfo":{"planName":"Team"}}"#
			default: XCTFail("Unexpected endpoint"); body = "{}"
			}
			return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		let result = try await client.fetch(tokenLoaders: [{ "fixture-primary" }, {
			XCTFail("A complete account must not load the alternate credential")
			return "fixture-fallback"
		}], now: now)
		XCTAssertEqual(result.primaryMeter?.usedPercent, 30.46)
		let methods = await log.methods
		XCTAssertEqual(Set(methods), ["GetCurrentPeriodUsage", "GetSandUsageStatus", "GetPlanInfo"])
		XCTAssertEqual(methods.count, 3)
	}

	func testExplicitNoEntitlementReplacesPreviousPoolRatherThanResurrectingIt() async throws {
		let client = GrokPlanUsageClient(transport: { request in
			let body = request.url!.lastPathComponent == "GetSandUsageStatus"
				? #"{"hasNonZeroIncludedLimit":false}"# : "{}"
			return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		let previous = CursorPlanUsage(planName: "Team", isTeam: true, meters: [weekly()], fetchedAt: now)
		let result = try await client.fetch(tokens: ["fixture-primary"], now: now, previous: previous)
		XCTAssertTrue(result.meters.isEmpty)
		XCTAssertNil(result.current(at: now))
	}

	func testAlternateTokenFallsBackWithoutMergingDifferentAccounts() async throws {
		let client = GrokPlanUsageClient(transport: { request in
			let first = request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-primary"
			let method = request.url!.lastPathComponent
			let body = first && method == "GetCurrentPeriodUsage" ? #"{"planUsage":{"autoPercentUsed":99}}"#
				: (!first && method == "GetSandUsageStatus" ? #"{"hasNonZeroIncludedLimit":true,"usagePercent":20}"# : "{}")
			return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		let result = try await client.fetch(tokens: ["fixture-primary", "fixture-fallback"], now: now)
		XCTAssertEqual(result.meters.map(\.key), [CursorPlanMeter.grokBotKey])
		XCTAssertEqual(result.primaryMeter?.usedPercent, 20)
	}
}

private actor RequestLog {
	var methods: [String] = []
	func record(_ method: String) { methods.append(method) }
}
