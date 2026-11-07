import Foundation
import XCTest
import SwiftUI

@testable import JPtheCatApp
@testable import JPtheCatCore

/// Muse Spark has no official quota % — menu-bar rotation must still admit it via `estimatedSharePct`.
final class DashboardViewModelMuseSparkEstimateTests: XCTestCase {
	private func stageDatabase(
		messages: [(sessionID: String, messageID: String, modelID: String, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int)]
	) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-muse-estimate-\(UUID().uuidString)", isDirectory: true)
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
				"providerID": "meta",
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

	@MainActor
	func testDerivedProvidersShareDashboardProjectionAndDisableCleanly() throws {
		let stamp = Int(Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000)
		let models = ["nemotron-3-ultra-free", "mimo-v2.5-free", "big-pickle", "deepseek-v4-flash-free"]
		let root = try stageDatabase(messages: models.enumerated().map { i, model in
			(sessionID: "shared", messageID: "m-\(i)", modelID: model,
			 tokens: (1000, 200, 10, 50, 0), timeCreatedMillis: stamp)
		})
		defer { try? FileManager.default.removeItem(at: root) }
		func build(index: UsageIndex?, enabled: Bool) -> DashboardViewModel.RefreshBuild {
			DashboardViewModel.buildRefreshResult(
				reindex: true, days: 14, calculator: CostCalculator(pricing: .bundledDefault()),
				claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
				copilot: CopilotProvider(), museSpark: MuseSparkProvider(root: root),
				brands: OpenCodeBrand.allCases.map { OpenCodeBrandProvider(brand: $0, root: root) },
				openCodeZen: OpenCodeProvider(root: root), openCodeGo: OpenCodeGoProvider(root: root),
				index: index, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
				copilotEnabled: false, museSparkEnabled: false,
				enabledBrands: enabled ? Set(OpenCodeBrand.allCases) : [],
				openCodeZenEnabled: false, openCodeGoEnabled: false,
				previousRows: [], hadPreviousRefresh: false)
		}
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		let direct = build(index: nil, enabled: true)
		let indexed = build(index: index, enabled: true)
		XCTAssertEqual(Set(indexed.rows.map(\.id)), ["nemotron", "mimo", "big_pickle", "deepseek"])
		XCTAssertEqual(indexed.aggregateWeek, direct.aggregateWeek, accuracy: 0.000001)
		for row in indexed.rows {
			XCTAssertEqual(row.weekEvents, 1)
			XCTAssertEqual(row.weekUsage.total, 1260)
			XCTAssertTrue(row.notional)
			XCTAssertNil(row.usedPct)
			XCTAssertNil(row.weeklyUsedPct)
			XCTAssertEqual(row.series, direct.rows.first { $0.id == row.id }?.series)
		}
		for result in [direct, indexed] {
			let pickle = try XCTUnwrap(result.rows.first { $0.id == "big_pickle" })
			XCTAssertTrue(pickle.usesTokenDisplay)
			XCTAssertFalse(pickle.isFullyUnpriced, "Free is a known zero price, not missing pricing")
			XCTAssertEqual(pickle.week, 0)
			XCTAssertEqual(pickle.tokenSeries.count, 14)
			XCTAssertEqual(pickle.tokenSeries.reduce(0, +), 1260)
			let state = DashboardState(rows: [pickle], selectedId: pickle.id, selectedDays: 14)
			XCTAssertEqual(state.selectedBasisLabel, "LOCAL TOKENS · TODAY")
			XCTAssertEqual(state.selectorMeterDescription(pickle), "Local token activity, last 14 days — quota unavailable")
			if ProcessInfo.processInfo.environment["JP_RENDER"] != nil {
				let renderer = ImageRenderer(content: ProviderDetail(row: pickle, days: 14)
					.frame(width: 384).background(JP.card))
				renderer.scale = 2
				let image = try XCTUnwrap(renderer.nsImage)
				let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
				let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
				try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("jpc-big-pickle-detail.png"))
				print("Rendered Big Pickle detail to \(NSTemporaryDirectory())jpc-big-pickle-detail.png")
			}
		}
		XCTAssertTrue(build(index: index, enabled: false).rows.isEmpty)
	}

	@MainActor
	func testMiMoV26ProPricesThroughDirectAndIndexedDashboard() throws {
		let stamp = Int(Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000)
		let root = try stageDatabase(messages: [("mimo-session", "mimo-turn", "mimo-v2.6-pro", (1_000_000, 100_000, 0, 0, 0), stamp)])
		defer { try? FileManager.default.removeItem(at: root) }
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		for currentIndex in [nil, index] as [UsageIndex?] {
			let result = DashboardViewModel.buildRefreshResult(
				reindex: true, days: 14, calculator: CostCalculator(),
				claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
				copilot: CopilotProvider(), museSpark: MuseSparkProvider(root: root),
				brands: OpenCodeBrand.allCases.map { OpenCodeBrandProvider(brand: $0, root: root) },
				openCodeZen: OpenCodeProvider(root: root), openCodeGo: OpenCodeGoProvider(root: root),
				index: currentIndex, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
				copilotEnabled: false, museSparkEnabled: false,
				enabledBrands: Set(OpenCodeBrand.allCases), openCodeZenEnabled: false, openCodeGoEnabled: false,
				previousRows: [], hadPreviousRefresh: false)
			let row = try XCTUnwrap(result.rows.first { $0.id == "mimo" })
			XCTAssertEqual(row.week, 0.522, accuracy: 0.000001)
			XCTAssertEqual(row.weekEvents, 1)
			XCTAssertTrue(row.unpricedModels.isEmpty)
			XCTAssertFalse(row.usesTokenDisplay)
			XCTAssertEqual(row.byModel7d.first?.model, "mimo-v2.6-pro")
			if ProcessInfo.processInfo.environment["JP_RENDER"] != nil {
				let renderer = ImageRenderer(content: ProviderDetail(row: row, days: 14).frame(width: 384).background(JP.card))
				renderer.scale = 2
				let image = try XCTUnwrap(renderer.nsImage)
				let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
				let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
				try png.write(to: URL(fileURLWithPath: "/tmp/jp-mimo-priced-detail.png"))
				print("Rendered priced MiMo V2.6 Pro dashboard to /tmp/jp-mimo-priced-detail.png")
			}
		}
	}

	func testMuseSparkProducesEstimatedShareForMenuBarRotation() throws {
		let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
		let threeDaysAgoMillis = Int(threeDaysAgo.timeIntervalSince1970 * 1000)
		let todayMillis = Int(Date().timeIntervalSince1970 * 1000)
		let root = try stageDatabase(messages: [
			(sessionID: "ses_1", messageID: "msg_today", modelID: "muse-spark-1.1",
			 tokens: (10_000, 500, 0, 0, 0), timeCreatedMillis: todayMillis),
			(sessionID: "ses_1", messageID: "msg_earlier", modelID: "muse-spark-1.1",
			 tokens: (30_000, 1_000, 0, 0, 0), timeCreatedMillis: threeDaysAgoMillis),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let build = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
			copilot: CopilotProvider(), museSpark: MuseSparkProvider(root: root),
			openCodeZen: OpenCodeProvider(root: root), openCodeGo: OpenCodeGoProvider(root: root),
			index: nil, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
			copilotEnabled: false, museSparkEnabled: true,
			openCodeZenEnabled: false, openCodeGoEnabled: false,
			previousRows: [], hadPreviousRefresh: false)

		guard let row = build.rows.first(where: { $0.id == "muse_spark" }) else {
			return XCTFail("expected a Muse Spark row")
		}
		XCTAssertNil(row.usedPct, "Muse Spark exposes no official 5-hour quota")
		XCTAssertNil(row.weeklyUsedPct, "Muse Spark exposes no official weekly quota")
		XCTAssertFalse(row.usageOfficial)
		XCTAssertNotNil(row.estimatedSharePct, "menu-bar rotation requires a self-relative estimate")
		XCTAssertGreaterThan(row.estimatedSharePct ?? 0, 0)
		XCTAssertLessThanOrEqual(row.estimatedSharePct ?? 0, 100)
		XCTAssertEqual(row.sourceScopeNote, MuseSparkScope.baseNote)
	}

	func testMuseSparkFallsBackToEventSeriesWhenIndexSeriesMissing() throws {
		let todayMillis = Int(Date().timeIntervalSince1970 * 1000)
		let root = try stageDatabase(messages: [
			(sessionID: "ses_1", messageID: "msg_today", modelID: "muse-spark-1.1",
			 tokens: (10_000, 500, 0, 0, 0), timeCreatedMillis: todayMillis),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let build = DashboardViewModel.buildRefreshResult(
			reindex: false, days: 14,
			calculator: CostCalculator(pricing: .bundledDefault()),
			claude: ClaudeProvider(), codex: CodexProvider(), grok: GrokProvider(),
			copilot: CopilotProvider(), museSpark: MuseSparkProvider(root: root),
			openCodeZen: OpenCodeProvider(root: root), openCodeGo: OpenCodeGoProvider(root: root),
			index: nil, claudeEnabled: false, codexEnabled: false, grokEnabled: false,
			copilotEnabled: false, museSparkEnabled: true,
			openCodeZenEnabled: false, openCodeGoEnabled: false,
			previousRows: [], hadPreviousRefresh: false)

		guard let row = build.rows.first(where: { $0.id == "muse_spark" }) else {
			return XCTFail("expected a Muse Spark row")
		}
		XCTAssertEqual(row.series.count, 14, "hero chart needs a full window series")
		XCTAssertGreaterThan(row.series.reduce(0, +), 0, "priced activity must chart, not a dead flat line")
		XCTAssertGreaterThan(row.week, 0)
		if let line = row.byModel7d.first, let cost = line.cost {
			XCTAssertGreaterThan(cost, 0)
		} else {
			XCTFail("expected a priced model line")
		}
	}
}