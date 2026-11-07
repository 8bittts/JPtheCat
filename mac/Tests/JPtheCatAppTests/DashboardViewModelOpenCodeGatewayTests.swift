import Foundation
import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

/// OpenCode Zen / Go are `ProviderBasis.gateway` ROLLUPS: they DISPLAY the same usage that also
/// appears under a model-brand row, but must NEVER enter the aggregate `$` total or alerts.
final class DashboardViewModelOpenCodeGatewayTests: XCTestCase {
	private func stageDatabase(
		messages: [(sessionID: String, messageID: String, modelID: String, providerID: String, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int)]
	) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-oc-gateway-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let file = root.appendingPathComponent("opencode.db")
		let db = try SQLiteDatabase(path: file.path)
		try db.execute(
			"""
			CREATE TABLE session (
			  id TEXT PRIMARY KEY, project_id TEXT, slug TEXT, title TEXT,
			  cost REAL NOT NULL DEFAULT 0, tokens_input INTEGER NOT NULL DEFAULT 0,
			  tokens_output INTEGER NOT NULL DEFAULT 0, tokens_reasoning INTEGER NOT NULL DEFAULT 0,
			  tokens_cache_read INTEGER NOT NULL DEFAULT 0, tokens_cache_write INTEGER NOT NULL DEFAULT 0,
			  model TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL
			);
			CREATE TABLE message (
			  id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL,
			  time_updated INTEGER NOT NULL, data TEXT NOT NULL
			);
			"""
		)
		for msg in messages {
			let data: [String: Any] = [
				"role": "assistant",
				"modelID": msg.modelID,
				"providerID": msg.providerID,
				"tokens": [
					"input": msg.tokens.0,
					"output": msg.tokens.1,
					"reasoning": msg.tokens.2,
					"cache": ["read": msg.tokens.3, "write": msg.tokens.4],
				],
				"time": ["created": msg.timeCreatedMillis, "completed": msg.timeCreatedMillis + 1000],
				"finish": "stop",
			]
			let json = try JSONSerialization.data(withJSONObject: data)
			let statement = try db.prepare(
				"""
				INSERT INTO message (id, session_id, time_created, time_updated, data)
				VALUES (?1, ?2, ?3, ?3, ?4)
				"""
			)
			statement.bind(1, msg.messageID)
			statement.bind(2, msg.sessionID)
			statement.bind(3, msg.timeCreatedMillis)
			statement.bind(4, String(decoding: json, as: UTF8.self))
			_ = try statement.step()
		}
		return root
	}

	private func build(root: URL) -> DashboardViewModel.RefreshBuild {
		DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
			copilot: CopilotProvider(), museSpark: MuseSparkProvider(root: root),
			brands: OpenCodeBrand.allCases.map { OpenCodeBrandProvider(brand: $0, root: root) },
			openCodeZen: OpenCodeProvider(root: root), openCodeGo: OpenCodeGoProvider(root: root),
			index: nil, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
			copilotEnabled: false, museSparkEnabled: false,
			enabledBrands: [.mimo, .deepseek], openCodeZenEnabled: true, openCodeGoEnabled: true,
			previousRows: [], hadPreviousRefresh: false)
	}

	func testGatewayRowsAreVisibleButExcludedFromTheAggregate() throws {
		let now = Date()
		let millis = Int(now.timeIntervalSince1970 * 1000)
		let root = try stageDatabase(messages: [
			(
				sessionID: "ses_zen", messageID: "msg_zen", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (1000, 200, 10, 50, 0), timeCreatedMillis: millis
			),
			(
				sessionID: "ses_go", messageID: "msg_go", modelID: "deepseek-v4.1-flash",
				providerID: "opencode-go", tokens: (1000, 200, 10, 50, 0), timeCreatedMillis: millis
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let built = build(root: root)
		let ids = Set(built.rows.map(\.id))
		// One OpenCode row, plus the model-brand rows — gateway usage is shown, never summed twice.
		XCTAssertTrue(ids.isSuperset(of: ["opencode", "mimo", "deepseek"]))
		XCTAssertFalse(ids.contains("opencodego"))
		// A saved Go selection (dashboard, menu bar) opens the one OpenCode row.
		XCTAssertEqual(DashboardViewModel.selectableProviderID("opencodego", rows: built.rows), "opencode")
		XCTAssertEqual(MenuBarDisplayFormat.normalized("limit:opencodego:fiveHour").providerID, "opencode")
		XCTAssertEqual(MenuBarDisplayFormat.normalized("limit:opencodego:fiveHour").window, .fiveHour)

		let openCode = try XCTUnwrap(built.rows.first { $0.id == "opencode" })
		XCTAssertEqual(openCode.name, "OpenCode")
		XCTAssertEqual(openCode.sourceSections.map(\.name), ["Zen", "Go"])
		let zen = try XCTUnwrap(openCode.sourceSections.first { $0.name == "Zen" })
		let go = try XCTUnwrap(openCode.sourceSections.first { $0.name == "Go" })
		// Non-aggregable: never summed, never alerted on. Go's measured meter owns the selector.
		XCTAssertFalse(openCode.isAggregable)
		XCTAssertFalse(openCode.contributesToAggregate)
		XCTAssertFalse(zen.contributesToAggregate)
		XCTAssertFalse(go.contributesToAggregate)
		// Zen's only model is a free tier → unpriced → token display, not a dead $0.00.
		XCTAssertTrue(zen.usesTokenDisplay)
		XCTAssertEqual(zen.week, 0)
		// Go carries measured usage-vs-cap windows (5-hour + weekly + monthly), with no local reset
		// boundary. Measured means NOT official: the percentage drives a quota-shaped meter on the
		// dashboard (badged `measured`) and the menu-bar rotation, but must never light the widget's
		// official-limit capsule or the spoken "N% used" value.
		XCTAssertNotNil(go.usedPct)
		XCTAssertEqual(go.windowMinutes5h, OpenCodeGoLimits.fiveHourMinutes)
		XCTAssertNotNil(go.weeklyUsedPct)
		XCTAssertEqual(go.windowMinutesWeekly, OpenCodeGoLimits.weeklyMinutes)
		XCTAssertNotNil(go.monthlyUsedPct)
		XCTAssertEqual(go.monthlyWindowMinutes, OpenCodeGoLimits.monthlyMinutes)
		XCTAssertNil(go.resetsAt5h, "OpenCode publishes no reset boundary — never fabricate one")
		XCTAssertNil(go.resetsAtWeekly)
		XCTAssertFalse(go.usageOfficial, "a measured gateway window is never official")
		XCTAssertTrue(go.quotaIsMeasured)
		XCTAssertEqual(openCode.usedPct, go.usedPct)
		XCTAssertTrue(openCode.quotaIsMeasured)
		// A gateway's measured window still owns a quota-shaped selector meter, flagged as measured.
		let quota = try XCTUnwrap(openCode.selectorQuota())
		XCTAssertTrue(quota.measured)
		XCTAssertEqual(quota.minutes, OpenCodeGoLimits.fiveHourMinutes)
		// Zen is pay-as-you-go: it publishes no usage window at all, so its section keeps a sparkline.
		XCTAssertNil(zen.selectorQuota())
		XCTAssertNil(zen.monthlyUsedPct)
		XCTAssertFalse(go.usesTokenDisplay)
		// Measured quota owns the selector meter, so the activity sparkline stays suppressed.
		XCTAssertNil(openCode.selectorTrendSeries())
		XCTAssertTrue(zen.usesTokenDisplay)
		XCTAssertEqual(zen.selectorTrendSeries(), zen.tokenSeries)

		// The aggregate is exactly the aggregable brand rows, never the gateways.
		let aggregable = built.rows.filter(\.contributesToAggregate)
		XCTAssertEqual(aggregable.map(\.id).sorted(), ["deepseek", "mimo"])
		XCTAssertEqual(built.aggregateWeek, aggregable.reduce(0.0) { $0 + $1.week }, accuracy: 0.000001)
	}

	func testGatewayRowsDisappearWhenDisabled() throws {
		let millis = Int(Date().timeIntervalSince1970 * 1000)
		let root = try stageDatabase(messages: [
			(
				sessionID: "ses_zen", messageID: "msg_zen", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (10, 1, 0, 0, 0), timeCreatedMillis: millis
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let built = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
			copilot: CopilotProvider(), museSpark: MuseSparkProvider(root: root),
			brands: OpenCodeBrand.allCases.map { OpenCodeBrandProvider(brand: $0, root: root) },
			openCodeZen: OpenCodeProvider(root: root), openCodeGo: OpenCodeGoProvider(root: root),
			index: nil, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
			copilotEnabled: false, museSparkEnabled: false,
			enabledBrands: [], openCodeZenEnabled: false, openCodeGoEnabled: false,
			previousRows: [], hadPreviousRefresh: false)
		// Every provider disabled → both gateway rows are marked disabled (visible but inert), and
		// neither contributes a dollar.
		XCTAssertFalse(built.rows.contains { $0.id == "opencode" || $0.id == "opencodego" })
	}
}
