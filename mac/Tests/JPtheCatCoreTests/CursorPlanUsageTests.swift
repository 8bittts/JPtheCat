import Foundation
import XCTest

@testable import JPtheCatCore

/// Cursor's official plan meters. Fixtures are the REAL response shapes Cursor's dashboard API
/// returned for a team seat (numbers kept; identifiers dropped).
final class CursorPlanUsageTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_790_260_000)  // 2026-09-24

	private let teamPeriod = Data("""
		{"billingCycleStart":"1789851452000","billingCycleEnd":"1792443452000",
		 "planUsage":{"totalSpend":1177,"includedSpend":1177,"remaining":823,"limit":2000,
		  "autoPercentUsed":5.604761904761904,"apiPercentUsed":0,"totalPercentUsed":4.707999999999999},
		 "spendLimitUsage":{"pooledUsed":0,"limitType":"team"},"enabled":true}
		""".utf8)
	private let teamGrokBot = Data("""
		{"currentPeriodStart":"2026-09-20T19:30:26.728Z","nextResetTimestampUtc":"2026-09-27T19:30:26.728Z",
		 "usagePercent":0.187949,"hasAvailableUsage":true,"hasNonZeroIncludedLimit":true,
		 "grokPlanLabel":"Grok Bot Plan","isTeamSeat":true,"cursorPlanName":"Team"}
		""".utf8)
	private let teamPlanInfo = Data("""
		{"planInfo":{"planName":"Team","includedAmountCents":2000,"price":"$40/mo","billingCycleEnd":"1792443452000"}}
		""".utf8)

	// MARK: Decode

	func testTeamSeatDecodesAllThreeOfficialMetersWithTheirOwnResets() throws {
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: teamGrokBot, planInfo: teamPlanInfo, fetchedAt: now))
		XCTAssertEqual(usage.meters.map(\.key), ["cursor_models", "other_models", "grok_bot_weekly"])
		XCTAssertEqual(usage.meters.map(\.label), ["Cursor Models", "Other Models", "Weekly included usage"])
		XCTAssertEqual(usage.meters[0].usedPercent, 5.6048, accuracy: 0.001)
		XCTAssertEqual(usage.meters[1].usedPercent, 0)
		XCTAssertEqual(usage.meters[2].usedPercent, 0.1879, accuracy: 0.001)
		XCTAssertEqual(usage.meters[0].resetsAt?.timeIntervalSince1970, 1_792_443_452)
		XCTAssertEqual(usage.meters[2].resetsAt?.timeIntervalSince1970 ?? 0, 1_790_537_426.728, accuracy: 0.01)
		XCTAssertEqual(usage.planName, "Team")
		XCTAssertTrue(usage.isTeam)
		XCTAssertEqual(usage.planLabel, "Grok Bot Plan")
	}

	func testQuotaGroupsNameCursorAndGrokBotSeparately() throws {
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: teamGrokBot, planInfo: teamPlanInfo, fetchedAt: now))
		let groups = usage.quotaGroups(meters: usage.meters)
		XCTAssertEqual(groups.map(\.title), ["Cursor · Team seat", "Grok Bot Plan · included usage"])
		XCTAssertEqual(groups[0].meters.map(\.label), ["Cursor Models", "Other Models"])
		XCTAssertEqual(groups[1].meters.map(\.label), ["Weekly included usage"])
		XCTAssertEqual(usage.menuBarPoolLines(meters: usage.meters), [
			"Cursor · Team seat: Cursor Models 6% · Other Models 0%",
			"Grok Bot Plan · included usage: Weekly included usage 0%",
		])
	}

	func testDetailHeaderNeverRepeatsTheProviderName() {
		func header(_ label: String?, plan: String? = nil, team: Bool = false) -> String {
			CursorPlanUsage(planName: plan, isTeam: team, meters: [], fetchedAt: now, reportedPlanLabel: label)
				.detailHeader(providerName: "Grok")
		}
		XCTAssertEqual(header("Grok Bot Plan"), "Grok Bot Plan · included usage")
		XCTAssertEqual(header("grok bot plan"), "grok bot plan · included usage")
		XCTAssertEqual(header(nil, plan: "Team", team: true), "Grok Team seat · included usage")
		XCTAssertEqual(header(nil, plan: "Pro"), "Grok Pro plan · included usage")
		XCTAssertEqual(header(nil), "Grok included usage")
	}

	func testPersonalPlanIsNotLabelledATeam() throws {
		let period = Data("""
			{"billingCycleEnd":"1792443452000","planUsage":{"autoPercentUsed":41,"apiPercentUsed":12},
			 "spendLimitUsage":{"individualUsed":0,"limitType":"user"}}
			""".utf8)
		let info = Data(#"{"planInfo":{"planName":"Pro","includedAmountCents":2000}}"#.utf8)
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: period, grokBot: nil, planInfo: info, fetchedAt: now))
		XCTAssertFalse(usage.isTeam)
		XCTAssertEqual(usage.planLabel, "Pro plan")
		XCTAssertEqual(usage.meters.map(\.usedPercent), [41, 12])
	}

	/// An account without Grok Bot access gets NO Grok Bot meter — never a fabricated 0%.
	func testNoGrokBotAccessMeansNoGrokBotMeter() throws {
		let noAccess = Data(#"{"usagePercent":0,"hasNonZeroIncludedLimit":false}"#.utf8)
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: noAccess, planInfo: nil, fetchedAt: now))
		XCTAssertEqual(usage.meters.map(\.key), ["cursor_models", "other_models"])
		// Plan name falls back to nothing rather than a guess when both sources are absent.
		XCTAssertNil(usage.planName)
		XCTAssertNil(usage.planLabel)
	}

	func testNoPlanUsageMeansNoReading() {
		let empty = Data(#"{"billingCycleEnd":"1792443452000","enabled":false}"#.utf8)
		XCTAssertEqual(CursorPlanUsage.decode(
			currentPeriod: empty, grokBot: teamGrokBot, planInfo: teamPlanInfo, fetchedAt: now)?.meters.map(\.key), [CursorPlanMeter.grokBotKey])
		XCTAssertNil(CursorPlanUsage.decode(
			currentPeriod: Data("not json".utf8), grokBot: nil, planInfo: nil, fetchedAt: now))
	}

	func testOlderPlanWithOnlyATotalShowsOneIncludedUsageMeter() throws {
		let period = Data(#"{"billingCycleEnd":"1792443452000","planUsage":{"totalPercentUsed":63}}"#.utf8)
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: period, grokBot: nil, planInfo: nil, fetchedAt: now))
		XCTAssertEqual(usage.meters.map(\.label), ["Included usage"])
		XCTAssertEqual(usage.meters.first?.usedPercent, 63)
	}

	/// Same freshness rule as every official window: a meter past its reset is dropped, never shown.
	func testExpiredMetersAreDroppedAndAllExpiredMeansNil() throws {
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: teamGrokBot, planInfo: teamPlanInfo, fetchedAt: now))
		let afterGrokReset = Date(timeIntervalSince1970: 1_790_600_000)
		XCTAssertEqual(usage.current(at: afterGrokReset)?.meters.map(\.key), ["cursor_models", "other_models"])
		XCTAssertNil(usage.current(at: Date(timeIntervalSince1970: 1_792_443_453)))
	}

	// MARK: Store

	func testStoreRoundTripsOnlyWhileEnabledAndOptOutDeletesTheReading() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-cursor-plan-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: teamGrokBot, planInfo: teamPlanInfo, fetchedAt: now))

		XCTAssertEqual(CursorPlanUsageStore.state(appSupport: dir, detected: false), .unavailable)
		XCTAssertEqual(CursorPlanUsageStore.state(appSupport: dir, detected: true), .installable)
		try CursorPlanUsageStore.enable(appSupport: dir)
		XCTAssertEqual(CursorPlanUsageStore.state(appSupport: dir, detected: false), .active)

		try CursorPlanUsageStore.save(usage, appSupport: dir)
		XCTAssertEqual(CursorPlanUsageStore.load(now: now, appSupport: dir), usage)
		XCTAssertEqual(CursorPlanUsageStore.lastFetchedAt(appSupport: dir), now)

		CursorPlanUsageStore.disable(appSupport: dir)
		XCTAssertNil(CursorPlanUsageStore.load(now: now, appSupport: dir))
		XCTAssertFalse(FileManager.default.fileExists(
			atPath: CursorPlanUsageStore.readingURL(appSupport: dir).path))
	}

	/// The saved reading carries numbers only — the sign-in token must never be persisted by JP.
	func testSavedReadingNeverContainsTheToken() throws {
		let dir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-cursor-plan-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		try CursorPlanUsageStore.enable(appSupport: dir)
		let usage = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: nil, planInfo: nil, fetchedAt: now))
		try CursorPlanUsageStore.save(usage, appSupport: dir)
		let saved = try String(contentsOf: CursorPlanUsageStore.readingURL(appSupport: dir), encoding: .utf8)
		XCTAssertFalse(saved.lowercased().contains("token"))
		XCTAssertFalse(saved.contains("Bearer"))
	}

	// MARK: Sign-in token

	private func jwt(exp: TimeInterval) -> String {
		let payload = try! JSONSerialization.data(withJSONObject: ["exp": exp, "type": "session"])
		let encoded = payload.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
		return "eyJhbGciOiJIUzI1NiJ9.\(encoded).signature"
	}

	private func stateDatabase(token: String?) throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-cursor-state-\(UUID().uuidString).vscdb")
		let db = try SQLiteDatabase(path: url.path)
		try db.execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);")
		try db.execute("INSERT INTO ItemTable VALUES ('composer.composerData', 'chat content must stay unread');")
		if let token {
			let stmt = try db.prepare("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', ?1);")
			stmt.bind(1, token)
			_ = try stmt.step()
		}
		return url
	}

	func testAppDatabaseTokenWinsWhileUnexpired() throws {
		let appToken = jwt(exp: now.timeIntervalSince1970 + 86_400)
		let db = try stateDatabase(token: appToken)
		defer { try? FileManager.default.removeItem(at: db) }
		var keychainRead = false
		let token = CursorAuthToken.load(now: now, stateDatabase: db) {
			keychainRead = true
			return nil
		}
		XCTAssertEqual(token, appToken)
		XCTAssertFalse(keychainRead, "the CLI Keychain item is a fallback, not a second read")
	}

	func testExpiredAppTokenFallsBackToTheCLIToken() throws {
		let db = try stateDatabase(token: jwt(exp: now.timeIntervalSince1970 - 1))
		defer { try? FileManager.default.removeItem(at: db) }
		let cliToken = jwt(exp: now.timeIntervalSince1970 + 3_600)
		XCTAssertEqual(CursorAuthToken.load(now: now, stateDatabase: db) { cliToken }, cliToken)
	}

	func testNoUsableTokenMeansNoFetch() throws {
		let db = try stateDatabase(token: nil)
		defer { try? FileManager.default.removeItem(at: db) }
		let expired = jwt(exp: now.timeIntervalSince1970 - 60)
		XCTAssertNil(CursorAuthToken.load(now: now, stateDatabase: db) { expired })
		XCTAssertNil(CursorAuthToken.load(now: now, stateDatabase: db) { "not-a-jwt" })
		let missing = URL(fileURLWithPath: "/nonexistent/state.vscdb")
		XCTAssertNil(CursorAuthToken.load(now: now, stateDatabase: missing) { nil })
	}

	// MARK: Client

	private final class Recorder: @unchecked Sendable {
		private let lock = NSLock()
		private var storage: [URLRequest] = []
		var requests: [URLRequest] {
			lock.lock(); defer { lock.unlock() }
			return storage
		}
		func append(_ request: URLRequest) {
			lock.lock(); storage.append(request); lock.unlock()
		}
	}

	private static func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
		HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
	}

	/// The only thing sent is the token, as a Bearer header, to Cursor's own API host, with an empty body.
	func testRequestsSendOnlyTheBearerTokenToCursorsOwnHost() throws {
		let request = CursorPlanUsageClient.request("GetCurrentPeriodUsage", token: "abc")
		XCTAssertEqual(request.httpMethod, "POST")
		XCTAssertEqual(request.url?.host, "api2.cursor.sh")
		XCTAssertEqual(request.url?.path, "/aiserver.v1.DashboardService/GetCurrentPeriodUsage")
		XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
		XCTAssertEqual(request.httpBody, Data("{}".utf8))
		XCTAssertEqual(request.allHTTPHeaderFields?.keys.sorted(), ["Accept", "Authorization", "Content-Type"])
	}

	func testFetchKeepsPlanMetersWhenGrokBotEndpointFails() async throws {
		let recorder = Recorder()
		let period = teamPeriod
		let client = CursorPlanUsageClient { request in
			recorder.append(request)
			let method = request.url!.lastPathComponent
			if method == "GetCurrentPeriodUsage" { return (period, CursorPlanUsageTests.response(request, 200)) }
			return (Data(), CursorPlanUsageTests.response(request, 404))
		}
		let usage = try await client.fetch(token: "abc", now: now)
		XCTAssertEqual(usage.meters.map(\.key), ["cursor_models", "other_models"])
		XCTAssertEqual(
			Set(recorder.requests.map { $0.url!.lastPathComponent }),
			["GetCurrentPeriodUsage", "GetSandUsageStatus", "GetPlanInfo"])
	}

	/// A dropped Grok Bot request keeps the previous still-current Grok Bot meter instead of blanking it.
	func testFailedGrokBotCallCarriesOverThePreviousCurrentMeter() async throws {
		let previous = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: teamGrokBot, planInfo: teamPlanInfo, fetchedAt: now))
		let period = teamPeriod
		let client = CursorPlanUsageClient { request in
			if request.url!.lastPathComponent == "GetCurrentPeriodUsage" {
				return (period, CursorPlanUsageTests.response(request, 200))
			}
			throw URLError(.timedOut)
		}
		let usage = try await client.fetch(token: "abc", now: now, previous: previous)
		XCTAssertEqual(usage.meters.map(\.key), ["cursor_models", "other_models", "grok_bot_weekly"])
		XCTAssertEqual(usage.planName, "Team")

		// Past the carried meter's own reset, it is NOT carried.
		let late = Date(timeIntervalSince1970: 1_790_600_000)
		let lateUsage = try await client.fetch(token: "abc", now: late, previous: previous)
		XCTAssertEqual(lateUsage.meters.map(\.key), ["cursor_models", "other_models"])
	}

	/// An account that ANSWERS "no Grok Bot access" loses the meter — the carry-over is for failures only.
	func testAnsweredNoAccessIsNotOverriddenByThePreviousMeter() throws {
		let previous = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: teamGrokBot, planInfo: teamPlanInfo, fetchedAt: now))
		let noAccess = Data(#"{"usagePercent":0,"hasNonZeroIncludedLimit":false}"#.utf8)
		let fresh = try XCTUnwrap(CursorPlanUsage.decode(
			currentPeriod: teamPeriod, grokBot: noAccess, planInfo: teamPlanInfo, fetchedAt: now))
		let merged = fresh.carryingOver(from: previous, grokBotFailed: false, planNameFailed: false, now: now)
		XCTAssertEqual(merged.meters.map(\.key), ["cursor_models", "other_models"])
	}

	func testRejectedSignInIsReportedAsUnauthorized() async {
		let client = CursorPlanUsageClient { request in (Data(), CursorPlanUsageTests.response(request, 401)) }
		do {
			_ = try await client.fetch(token: "stale", now: now)
			XCTFail("expected unauthorized")
		} catch {
			XCTAssertEqual(error as? CursorPlanUsageClient.FetchError, .unauthorized)
		}
	}
}
