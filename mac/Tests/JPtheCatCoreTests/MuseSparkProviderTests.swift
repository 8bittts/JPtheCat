import Foundation
import XCTest

@testable import JPtheCatCore

final class MuseSparkProviderTests: XCTestCase {
	private func stageDatabase(
		messages: [(sessionID: String, messageID: String, modelID: String, providerID: String, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int)],
		sessions: [(id: String, model: String?, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int, projectID: String?)] = []
	) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-muse-spark-\(UUID().uuidString)", isDirectory: true)
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
		for row in sessions {
			let statement = try db.prepare(
				"""
				INSERT OR REPLACE INTO session
				  (id, project_id, slug, title, cost, tokens_input, tokens_output, tokens_reasoning,
				   tokens_cache_read, tokens_cache_write, model, time_created, time_updated)
				VALUES (?1, ?2, 'slug', 'title', 0, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)
				"""
			)
			statement.bind(1, row.id)
			statement.bind(2, row.projectID)
			statement.bind(3, row.tokens.0)
			statement.bind(4, row.tokens.1)
			statement.bind(5, row.tokens.2)
			statement.bind(6, row.tokens.3)
			statement.bind(7, row.tokens.4)
			statement.bind(8, row.model)
			statement.bind(9, row.timeCreatedMillis)
			_ = try statement.step()
		}
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
		return (root, file)
	}

	func testIsAvailableFalseOnEmptyDatabase() throws {
		let (root, _) = try stageDatabase(messages: [], sessions: [])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertFalse(MuseSparkProvider(root: root).isAvailable())
	}

	func testIsAvailableTrueWhenSparkMessagePresent() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "muse-spark-1.1", providerID: "meta",
				tokens: (100, 20, 5, 0, 0), timeCreatedMillis: 1_783_000_000_000
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(MuseSparkProvider(root: root).isAvailable())
	}

	func testParsesPerMessageSparkEventsAndSkipsOtherModels() throws {
		let (root, _) = try stageDatabase(
			messages: [
				(
					sessionID: "ses_1", messageID: "msg_spark", modelID: "muse-spark-1.1",
					providerID: "meta", tokens: (15779, 82, 262, 0, 0),
					timeCreatedMillis: 1_784_129_182_156
				),
				(
					sessionID: "ses_1", messageID: "msg_other", modelID: "gpt-4o",
					providerID: "opencode", tokens: (16745, 7, 15, 0, 0),
					timeCreatedMillis: 1_784_129_229_432
				),
			],
			sessions: [
				(
					id: "ses_1",
					model: #"{"id":"deepseek-v4-flash-free","providerID":"opencode"}"#,
					tokens: (32524, 89, 277, 0, 0), timeCreatedMillis: 1_784_129_182_129,
					projectID: "proj_y"
				)
			])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = MuseSparkProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .museSpark)
		XCTAssertEqual(event.messageId, "msg_spark")
		// Every OpenCode-derived row stamps the shared index request id (`OpenCodeModelReader`).
		XCTAssertEqual(event.requestId, "opencode-db")
		XCTAssertEqual(event.model, "muse-spark-1.1")
		XCTAssertEqual(event.usage.input, 15_779)
		XCTAssertEqual(event.usage.output, 82 + 262)
		XCTAssertEqual(event.usage.cacheRead, 0)
		XCTAssertEqual(event.project, "proj_y")
	}

	/// Gateway semantics: OpenCode Zen owns ONLY rows routed through `providerID == "opencode"`. A
	/// Meta- or OpenAI-routed session is NOT Zen usage (it belongs to Muse Spark / nobody), so Zen
	/// must never claim it. Muse Spark still surfaces its own spark row from the session fallback.
	func testOpenCodeZenGatewayClaimsOnlyZenRoutedSessions() throws {
		let (root, _) = try stageDatabase(
			messages: [],
			sessions: [
				(
					id: "ses_spark",
					model: #"{"id":"muse-spark-1.1","providerID":"meta"}"#,
					tokens: (100, 10, 0, 0, 0), timeCreatedMillis: 1, projectID: nil
				),
			(
				id: "ses_zen",
				model: #"{"id":"mimo-v2.5-free","providerID":"opencode"}"#,
					tokens: (50, 5, 0, 0, 0), timeCreatedMillis: 2, projectID: nil
				),
			])
		defer { try? FileManager.default.removeItem(at: root) }

		let zen = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(zen.map(\.messageId), ["ses_zen"])
		XCTAssertEqual(zen.first?.provider, .opencode)

		// Session-only spark still surfaces via MuseSpark (message table empty → session fallback).
		let spark = MuseSparkProvider(root: root).loadEvents()
		XCTAssertEqual(spark.map(\.messageId), ["ses_spark"])
		XCTAssertEqual(spark.first?.provider, .museSpark)
	}

	/// Multi-model session: last model is deepseek but cumulative session tokens include an earlier
	/// muse-spark turn. OpenCode must peel the spark portion off so audit doesn't double-count.
	func testOpenCodeSubtractsMuseSparkMessageTokensFromMixedSession() throws {
		let (root, _) = try stageDatabase(
			messages: [
				(
					sessionID: "ses_mixed", messageID: "msg_spark", modelID: "muse-spark-1.1",
					providerID: "meta", tokens: (1000, 100, 50, 0, 0), timeCreatedMillis: 10
				),
				(
					sessionID: "ses_mixed", messageID: "msg_ds", modelID: "gpt-4o",
					providerID: "opencode", tokens: (500, 40, 10, 0, 0), timeCreatedMillis: 20
				),
			],
			sessions: [
				(
					id: "ses_mixed",
					model: #"{"id":"gpt-4o","providerID":"openai"}"#,
					// Cumulative = spark + deepseek
					tokens: (1500, 140, 60, 0, 0), timeCreatedMillis: 10, projectID: nil
				)
			])
		defer { try? FileManager.default.removeItem(at: root) }

		let openCode = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(openCode.count, 1)
		// Remaining after subtract: input 500, output 40+10=50 (session had 140+60=200, spark took 100+50=150)
		XCTAssertEqual(openCode[0].usage.input, 500)
		XCTAssertEqual(openCode[0].usage.output, 50)

		let spark = MuseSparkProvider(root: root).loadEvents()
		XCTAssertEqual(spark.count, 1)
		XCTAssertEqual(spark[0].usage.input, 1000)
		XCTAssertEqual(spark[0].usage.output, 150)
	}

	func testSparkModelDetection() {
		XCTAssertTrue(MuseSparkProvider.isSparkModelID("muse-spark-1.1"))
		XCTAssertTrue(MuseSparkProvider.isSparkModelID("meta/muse-spark-1.1"))
		XCTAssertFalse(MuseSparkProvider.isSparkModelID("deepseek-v4-flash-free"))
		XCTAssertFalse(MuseSparkProvider.isSparkModelID("gpt-5.3-codex-spark"))
		XCTAssertTrue(MuseSparkProvider.isSparkModelObject(id: "muse-spark-1.1", providerID: "meta"))
		XCTAssertFalse(MuseSparkProvider.isSparkModelObject(id: "deepseek", providerID: "opencode"))
		// The row owns Meta's Muse text family, on any gateway, and nothing that merely says "muse".
		XCTAssertTrue(MuseSparkProvider.isSparkModelID("muse-wonder-1.0"))
		XCTAssertTrue(MuseSparkProvider.isSparkModelObject(id: "muse-wonder-1.0", providerID: "meta"))
		XCTAssertTrue(MuseSparkProvider.isSparkModelObject(id: "muse-wonder-1.0", providerID: "opencode"))
		XCTAssertFalse(MuseSparkProvider.isSparkModelID("muse-voice-transcribe-1.0"))
		XCTAssertFalse(MuseSparkProvider.isSparkModelID("amuse-bouche-1"))
	}

	/// OpenCode logged 243 `muse-wonder-1.0` turns through Meta's own API that no row claimed; they now
	/// land on this row, priced at Meta's list rate (4/20, cached 0.20 per MTok).
	func testMuseWonderTurnsLandOnThisRowAtMetaListRates() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_w", messageID: "msg_wonder", modelID: "muse-wonder-1.0", providerID: "meta",
				tokens: (1_000_000, 50_000, 0, 2_000_000, 0), timeCreatedMillis: 1_792_000_000_000
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let provider = MuseSparkProvider(root: root)
		XCTAssertTrue(provider.isAvailable())
		let event = try XCTUnwrap(provider.loadEvents().first)
		XCTAssertEqual(event.model, "muse-wonder-1.0")
		let cost = try XCTUnwrap(CostCalculator().cost(model: event.model, usage: event.usage))
		XCTAssertEqual(cost, 4.0 + 1.0 + 0.4, accuracy: 1e-9)
	}

	func testPricingTableCoversMuseSpark() throws {
		let table = PricingTable.bundledDefault()
		XCTAssertNotNil(table.price(for: "muse-spark-1.1"))
		XCTAssertNotNil(table.price(for: "meta/muse-spark-1.1"))
		let price = try XCTUnwrap(table.price(for: "muse-spark-1.1"))
		XCTAssertEqual(price.inputCostPerToken, 1.25e-6, accuracy: 1e-12)
		XCTAssertEqual(price.outputCostPerToken, 4.25e-6, accuracy: 1e-12)
	}

	func testIndexIngestsSparkMessages() throws {
		// Use a "now" timestamp so the 7-day rollup window includes the event.
		let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "muse-spark-1.1", providerID: "meta",
				tokens: (100, 20, 0, 0, 0), timeCreatedMillis: nowMillis
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-muse-spark-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = MuseSparkProvider(root: root)
		_ = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .museSpark), 1)
		let rollup = try index.rollup(provider: .museSpark)
		XCTAssertGreaterThan(rollup.last7d.eventCount, 0)
	}
}
