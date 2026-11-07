import Foundation
import XCTest

@testable import JPtheCatCore

/// Tests for MiMo, Nemotron, Big Pickle, and DeepSeek — the four `OpenCodeBrand` rows one
/// `OpenCodeBrandProvider` serves by filtering `opencode.db` on model id.
final class OpenCodeDerivedProviderTests: XCTestCase {
	private func stageDatabase(
		messages: [(sessionID: String, messageID: String, modelID: String, providerID: String, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int)],
		sessions: [(id: String, model: String?, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int, projectID: String?)] = []
	) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-oc-derived-\(UUID().uuidString)", isDirectory: true)
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

	func testDirectAndIndexedMessagesAgreeForEveryDerivedProvider() throws {
		let models = ["nemotron-3-ultra-free", "mimo-v2.5-free", "big-pickle", "deepseek-v4-flash-free"]
		let (root, file) = try stageDatabase(messages: models.enumerated().map { i, model in
			(sessionID: "shared", messageID: "msg-\(i)", modelID: model,
			 providerID: "opencode", tokens: (100, 20, 5, 10, 0), timeCreatedMillis: 1_784_000_000_000 + i)
		})
		defer { try? FileManager.default.removeItem(at: root) }
		let providers: [any IndexableProvider] = [OpenCodeBrandProvider(brand: .nemotron, root: root), OpenCodeBrandProvider(brand: .mimo, root: root),
			OpenCodeBrandProvider(brand: .bigPickle, root: root), OpenCodeBrandProvider(brand: .deepseek, root: root)]
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		for provider in providers {
			let direct = provider.loadEvents()
			let decoded = provider.decodeFile(file, from: 0, parserState: nil).events
			XCTAssertEqual(direct.count, 1, provider.id.rawValue)
			XCTAssertEqual(direct.map(\.usage.total), decoded.map(\.usage.total))
			_ = try UsageIndexer(index: index).refresh(provider)
		}
		for provider in providers {
			XCTAssertEqual(index.eventCount(provider: provider.id), 1)
			XCTAssertEqual(try UsageIndexer(index: index).refresh(provider).filesSkipped, 1)
		}
		let source = try SQLiteDatabase(path: file.path)
		try source.execute("""
			INSERT INTO message
			SELECT id || '-new', session_id, time_created + 1000, time_updated + 1000,
			json_set(data, '$.time.created', time_created + 1000) FROM message;
			""")
		for provider in providers {
			XCTAssertEqual(try UsageIndexer(index: index).refresh(provider).filesRead, 1, provider.id.rawValue)
			XCTAssertEqual(index.eventCount(provider: provider.id), 2, provider.id.rawValue)
		}
	}

	func testOlderConcurrentMessageUpdatesReachEveryIndexedRow() throws {
		let (root, file) = try stageDatabase(messages: [
			("old", "old", "deepseek-v4.1-flash", "opencode-go", (100, 10, 0, 0, 0), 1000),
			("new", "new", "deepseek-v4.1-flash", "opencode-go", (100, 10, 0, 0, 0), 2000),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		let providers: [any IndexableProvider] = [
			OpenCodeGoProvider(root: root), OpenCodeBrandProvider(brand: .deepseek, root: root),
			OpenCodeProvider(root: root), MuseSparkProvider(root: root),
		]
		for provider in providers { try UsageIndexer(index: index).refresh(provider) }
		let source = try SQLiteDatabase(path: file.path)
		try source.execute("""
			UPDATE message SET data=json_set(data, '$.tokens.output', 900), time_updated=3000
			WHERE id='old';
			""")
		for provider in providers {
			try UsageIndexer(index: index).refresh(provider)
			let indexed = try index.rollup(provider: provider.id, days: 7, now: Date(timeIntervalSince1970: 10))
			XCTAssertEqual(indexed.last7d.usage.output, provider.loadEvents().reduce(0) { $0 + $1.usage.output }, provider.id.rawValue)
		}
		// A correction can lower usage and move a turn between providers; stale rows must disappear.
		try source.execute("""
			UPDATE message SET data=json_set(data, '$.tokens.output', 3,
			  '$.modelID', 'muse-spark-1.3', '$.providerID', 'opencode'), time_updated=4000
			WHERE id='old';
			""")
		for provider in providers {
			try UsageIndexer(index: index).refresh(provider)
			let indexed = try index.rollup(provider: provider.id, days: 7, now: Date(timeIntervalSince1970: 10))
			XCTAssertEqual(indexed.last7d.usage.output, provider.loadEvents().reduce(0) { $0 + $1.usage.output }, provider.id.rawValue)
		}
	}

	func testFailedRefreshRetainsEventsAndRetriesAfterRepair() throws {
		let (root, file) = try stageDatabase(messages: [
			("session", "message", "deepseek-v4.1-flash", "opencode-go", (100, 10, 0, 0, 0), 1000),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		let provider = OpenCodeGoProvider(root: root)
		try UsageIndexer(index: index).refresh(provider)
		let source = try SQLiteDatabase(path: file.path)
		let original = try source.prepare("SELECT data FROM message LIMIT 1")
		XCTAssertTrue(try original.step())
		let originalData = try XCTUnwrap(original.text(0))
		original.reset()
		try source.execute("UPDATE message SET data='broken json', time_updated=2000;")
		XCTAssertThrowsError(try UsageIndexer(index: index).refresh(provider))
		XCTAssertEqual(index.eventCount(provider: .opencodego), 1)
		let repair = try source.prepare("UPDATE message SET data=json_set(?1, '$.tokens.output', 900), time_updated=3000")
		repair.bind(1, originalData)
		_ = try repair.step()
		try UsageIndexer(index: index).refresh(provider)
		let restored = try index.rollup(provider: .opencodego, days: 7, now: Date(timeIntervalSince1970: 10))
		XCTAssertEqual(restored.last7d.usage.output, 900)
	}

	func testLegacySessionReadFailurePreservesAcceptedIndexAndCursor() throws {
		let (root, file) = try stageDatabase(messages: [], sessions: [
			("session", #"{"id":"mimo-v2.6-pro","providerID":"opencode-go"}"#, (100, 20, 0, 0, 0), 1000, nil)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let index = try UsageIndex(path: root.appendingPathComponent("index.sqlite").path)
		let provider = OpenCodeBrandProvider(brand: .mimo, root: root)
		try UsageIndexer(index: index).refresh(provider)
		let cursor = try XCTUnwrap(index.cursor(for: file.path, provider: .mimo))
		let source = try SQLiteDatabase(path: file.path)
		try source.execute("ALTER TABLE session RENAME COLUMN tokens_output TO unavailable_output")
		XCTAssertTrue(provider.isAvailable())
		XCTAssertThrowsError(try UsageIndexer(index: index).refresh(provider))
		XCTAssertEqual(index.eventCount(provider: .mimo), 1)
		XCTAssertEqual(index.cursor(for: file.path, provider: .mimo)?.mtime, cursor.mtime)
		try source.execute("ALTER TABLE session RENAME COLUMN unavailable_output TO tokens_output; UPDATE session SET tokens_output=900;")
		try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .mimo), 1)
		let rollup = try index.rollup(provider: .mimo, days: 7, now: Date(timeIntervalSince1970: 10))
		XCTAssertEqual(rollup.last7d.usage.output, 900)
	}

	// MARK: - MiMo

	func testMiMoIsAvailableWhenModelPresent() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: 1_783_000_000_000
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(OpenCodeBrandProvider(brand: .mimo, root: root).isAvailable())
	}

	func testMiMoIsUnavailableOnEmptyDatabase() throws {
		let (root, _) = try stageDatabase(messages: [], sessions: [])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertFalse(OpenCodeBrandProvider(brand: .mimo, root: root).isAvailable())
	}

	func testMiMoParsesSessionEvents() throws {
		let (root, _) = try stageDatabase(
			messages: [],
			sessions: [
				(
					id: "ses_mimo",
					model: #"{"id":"mimo-v2.5-free","providerID":"opencode"}"#,
					tokens: (3000, 150, 50, 0, 0), timeCreatedMillis: 1_784_000_000_000,
					projectID: "proj_mimo"
				),
			])
		defer { try? FileManager.default.removeItem(at: root) }
		let events = OpenCodeBrandProvider(brand: .mimo, root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .mimo)
		XCTAssertEqual(event.model, "mimo-v2.5-free")
		XCTAssertEqual(event.usage.input, 3000)
		XCTAssertEqual(event.project, "proj_mimo")
	}

	func testMiMoParsesMessageEventsViaIndexPath() throws {
		let (root, file) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_mimo", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (5000, 200, 100, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
			(
				sessionID: "ses_1", messageID: "msg_other", modelID: "gpt-4o",
				providerID: "opencode", tokens: (1000, 50, 0, 0, 0), timeCreatedMillis: 1_784_000_001_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let result = OpenCodeBrandProvider(brand: .mimo).decodeDatabase(fileURL: file, createdAtOrAfterMillis: 0)
		XCTAssertEqual(result.events.count, 1)
		let event = try XCTUnwrap(result.events.first)
		XCTAssertEqual(event.provider, .mimo)
		XCTAssertEqual(event.messageId, "msg_mimo")
		XCTAssertEqual(event.model, "mimo-v2.5-free")
		XCTAssertEqual(event.usage.input, 5000)
		XCTAssertEqual(event.usage.output, 200 + 100)
	}

	/// [Regression guard] The tier suffix is KEPT at parse time. Stripping it once priced free-tier
	/// turns at the paid list rate on the brand row while the gateway row showed the same turns as
	/// free — the same event read as $0 under Zen and as dollars under MiMo.
	func testMiMoNormalizedModelKeepsFreeSuffix() {
		XCTAssertEqual(
			OpenCodeBrand.mimo.normalizedModelID(OpenCodeModelRef(modelID: "mimo-v2.5-free", providerID: "opencode")),
			"mimo-v2.5-free")
		XCTAssertEqual(
			OpenCodeBrand.mimo.normalizedModelID(OpenCodeModelRef(modelID: "mimo-v2.5", providerID: "opencode")),
			"mimo-v2.5")
		XCTAssertEqual(
			OpenCodeBrand.mimo.normalizedModelID(OpenCodeModelRef(modelID: "vendor/mimo-v2.5-free", providerID: "opencode")),
			"mimo-v2.5-free")
		XCTAssertEqual(
			OpenCodeBrand.mimo.normalizedModelID(OpenCodeModelRef(modelID: nil, providerID: nil)),
			"mimo-v2.5")
	}

	func testMiMoModelDetection() {
		XCTAssertTrue(OpenCodeBrand.mimo.matches(modelID: "mimo-v2.5-free"))
		XCTAssertTrue(OpenCodeBrand.mimo.matches(modelID: "mimo-v2.5"))
		XCTAssertTrue(OpenCodeBrand.mimo.matches(modelID: "vendor/mimo-v2.5-free"))
		XCTAssertFalse(OpenCodeBrand.mimo.matches(modelID: "gpt-4o"))
		XCTAssertFalse(OpenCodeBrand.mimo.matches(modelID: nil))
		XCTAssertFalse(OpenCodeBrand.mimo.matches(modelID: ""))
	}

	/// MiMo is priced for OpenCode Go and unpriced for Zen's free tier. The base id carries a real
	/// per-token rate; only the `-free` suffix stays unpriced so free turns never show a fake $0.
	func testMiMoPricingMatchesTier() {
		let table = PricingTable.bundledDefault()
		XCTAssertNotNil(table.price(for: "mimo-v2.5"))
		XCTAssertNil(table.price(for: "mimo-v2.5-free"))
	}

	func testIndexIngestsMiMoMessages() throws {
		let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: nowMillis
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-mimo-index-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = OpenCodeBrandProvider(brand: .mimo, root: root)
		_ = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .mimo), 1)
		let rollup = try index.rollup(provider: .mimo)
		XCTAssertGreaterThan(rollup.last7d.eventCount, 0)
	}

	// MARK: - Nemotron

	func testNemotronIsAvailableWhenModelPresent() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "nemotron-3-ultra-free",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: 1_783_000_000_000
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(OpenCodeBrandProvider(brand: .nemotron, root: root).isAvailable())
	}

	func testNemotronParsesSessionEvents() throws {
		let (root, _) = try stageDatabase(
			messages: [],
			sessions: [
				(
					id: "ses_nem",
					model: #"{"id":"nemotron-3-ultra-free","providerID":"opencode"}"#,
					tokens: (8000, 400, 200, 0, 0), timeCreatedMillis: 1_784_000_000_000,
					projectID: nil
				),
			])
		defer { try? FileManager.default.removeItem(at: root) }
		let events = OpenCodeBrandProvider(brand: .nemotron, root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .nemotron)
		XCTAssertEqual(event.model, "nemotron-3-ultra-free")
		XCTAssertEqual(event.usage.input, 8000)
	}

	func testNemotronParsesMessageEventsViaIndexPath() throws {
		let (root, file) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_nem", modelID: "nemotron-3-ultra-free",
				providerID: "opencode", tokens: (8000, 400, 200, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let result = OpenCodeBrandProvider(brand: .nemotron).decodeDatabase(fileURL: file, createdAtOrAfterMillis: 0)
		XCTAssertEqual(result.events.count, 1)
		let event = try XCTUnwrap(result.events.first)
		XCTAssertEqual(event.provider, .nemotron)
		XCTAssertEqual(event.model, "nemotron-3-ultra-free")
	}

	func testNemotronNormalizedModelKeepsFreeSuffix() {
		XCTAssertEqual(
			OpenCodeBrand.nemotron.normalizedModelID(OpenCodeModelRef(modelID: "nemotron-3-ultra-free", providerID: "opencode")),
			"nemotron-3-ultra-free")
		XCTAssertEqual(
			OpenCodeBrand.nemotron.normalizedModelID(OpenCodeModelRef(modelID: "nemotron-3-ultra", providerID: "opencode")),
			"nemotron-3-ultra")
	}

	/// Nemotron has NO price row for the same reason as MiMo (Zen free tier only; no first-party rate).
	func testNemotronIsDeliberatelyUnpriced() {
		let table = PricingTable.bundledDefault()
		XCTAssertNil(table.price(for: "nemotron-3-ultra"))
		XCTAssertNil(table.price(for: "nemotron-3-ultra-free"))
		XCTAssertNil(table.price(for: "nemotron-3.5-lightning-free"))
	}

	func testIndexIngestsNemotronMessages() throws {
		let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "nemotron-3-ultra-free",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: nowMillis
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-nemotron-index-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = OpenCodeBrandProvider(brand: .nemotron, root: root)
		_ = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .nemotron), 1)
	}

	// MARK: - Big Pickle

	func testBigPickleIsAvailableWhenModelPresent() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "big-pickle",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: 1_783_000_000_000
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(OpenCodeBrandProvider(brand: .bigPickle, root: root).isAvailable())
	}

	func testBigPickleParsesSessionEvents() throws {
		let (root, _) = try stageDatabase(
			messages: [],
			sessions: [
				(
					id: "ses_bp",
					model: #"{"id":"big-pickle","providerID":"opencode"}"#,
					tokens: (2000, 100, 0, 0, 0), timeCreatedMillis: 1_784_000_000_000,
					projectID: nil
				),
			])
		defer { try? FileManager.default.removeItem(at: root) }
		let events = OpenCodeBrandProvider(brand: .bigPickle, root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .bigPickle)
		XCTAssertEqual(event.model, "big-pickle")
		XCTAssertEqual(event.usage.input, 2000)
	}

	func testBigPickleParsesMessageEventsViaIndexPath() throws {
		let (root, file) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_bp", modelID: "big-pickle",
				providerID: "opencode", tokens: (2000, 100, 0, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let result = OpenCodeBrandProvider(brand: .bigPickle).decodeDatabase(fileURL: file, createdAtOrAfterMillis: 0)
		XCTAssertEqual(result.events.count, 1)
		let event = try XCTUnwrap(result.events.first)
		XCTAssertEqual(event.provider, .bigPickle)
		XCTAssertEqual(event.model, "big-pickle")
	}

	func testBigPicklePricingTableCoversModel() throws {
		let table = PricingTable.bundledDefault()
		XCTAssertNotNil(table.price(for: "big-pickle"))
	}

	func testBigPickleNormalizedModelKeepsFreeSuffix() {
		XCTAssertEqual(
			OpenCodeBrand.bigPickle.normalizedModelID(OpenCodeModelRef(modelID: "big-pickle-free", providerID: "opencode")),
			"big-pickle-free")
		XCTAssertEqual(
			OpenCodeBrand.bigPickle.normalizedModelID(OpenCodeModelRef(modelID: "big-pickle", providerID: "opencode")),
			"big-pickle")
	}

	func testIndexIngestsBigPickleMessages() throws {
		let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "big-pickle",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: nowMillis
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-bigpickle-index-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = OpenCodeBrandProvider(brand: .bigPickle, root: root)
		_ = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .bigPickle), 1)
	}

	// MARK: - DeepSeek

	func testDeepSeekIsAvailableWhenModelPresent() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "deepseek-v4-flash-free",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: 1_783_000_000_000
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(OpenCodeBrandProvider(brand: .deepseek, root: root).isAvailable())
	}

	func testDeepSeekParsesSessionEvents() throws {
		let (root, _) = try stageDatabase(
			messages: [],
			sessions: [
				(
					id: "ses_ds",
					model: #"{"id":"deepseek-v4-flash-free","providerID":"opencode"}"#,
					tokens: (3000, 150, 50, 0, 0), timeCreatedMillis: 1_784_000_000_000,
					projectID: nil
				),
			])
		defer { try? FileManager.default.removeItem(at: root) }
		let events = OpenCodeBrandProvider(brand: .deepseek, root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .deepseek)
		XCTAssertEqual(event.model, "deepseek-v4-flash-free")
		XCTAssertEqual(event.usage.input, 3000)
		XCTAssertEqual(event.usage.output, 150 + 50)
	}

	func testDeepSeekParsesMessageEventsViaIndexPath() throws {
		let (root, file) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_ds", modelID: "deepseek-v4-flash-free",
				providerID: "opencode", tokens: (3000, 150, 50, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let result = OpenCodeBrandProvider(brand: .deepseek).decodeDatabase(fileURL: file, createdAtOrAfterMillis: 0)
		XCTAssertEqual(result.events.count, 1)
		let event = try XCTUnwrap(result.events.first)
		XCTAssertEqual(event.provider, .deepseek)
		XCTAssertEqual(event.model, "deepseek-v4-flash-free")
		XCTAssertEqual(event.usage.input, 3000)
		XCTAssertEqual(event.usage.output, 150 + 50)
	}

	func testDeepSeekNormalizedModelKeepsFreeSuffix() {
		XCTAssertEqual(
			OpenCodeBrand.deepseek.normalizedModelID(OpenCodeModelRef(modelID: "deepseek-v4-flash-free", providerID: "opencode")),
			"deepseek-v4-flash-free")
		XCTAssertEqual(
			OpenCodeBrand.deepseek.normalizedModelID(OpenCodeModelRef(modelID: "deepseek-v4-flash", providerID: "opencode")),
			"deepseek-v4-flash")
	}

	/// [Regression guard] A Go-routed DeepSeek V4 turn suffices to the dedicated `-go` row on the brand
	/// side too, so brand and gateway rows price the same turn at the same Go list rate. Zen-routed
	/// turns and ids outside the differing set stay on the base (Zen) row.
	func testDeepSeekBrandGoRoutedSuffixesToGoRow() {
		let go = { (id: String?) in OpenCodeModelRef(modelID: id, providerID: "opencode-go") }
		XCTAssertEqual(OpenCodeBrand.deepseek.normalizedModelID(go("deepseek-v4-flash")), "deepseek-v4-flash-go")
		XCTAssertEqual(OpenCodeBrand.deepseek.normalizedModelID(go("deepseek-v4-pro")), "deepseek-v4-pro-go")
		XCTAssertEqual(
			OpenCodeBrand.deepseek.normalizedModelID(go("deepseek-v4-flash-free")), "deepseek-v4-flash-free")
		XCTAssertEqual(OpenCodeBrand.deepseek.normalizedModelID(go("deepseek-v4.1-flash")), "deepseek-v4.1-flash")
		XCTAssertEqual(
			OpenCodeBrand.deepseek.normalizedModelID(
				OpenCodeModelRef(modelID: "deepseek-v4-flash", providerID: "opencode")),
			"deepseek-v4-flash")
	}

	/// DeepSeek's paid ids carry the OpenCode Zen list rate; the free tier stays unpriced on THIS row
	/// exactly as on the gateway row (one rule, `ModelIdentity.isFreeTier`).
	func testDeepSeekPricingCoversPaidIdsAndLeavesFreeTierUnpriced() throws {
		let table = PricingTable.bundledDefault()
		let flash = try XCTUnwrap(table.price(for: "deepseek-v4-flash"))
		XCTAssertEqual(flash.inputCostPerToken, 0.14e-6, accuracy: 1e-15)
		XCTAssertEqual(flash.outputCostPerToken, 0.28e-6, accuracy: 1e-15)
		XCTAssertEqual(flash.cacheReadInputTokenCost ?? -1, 0.028e-6, accuracy: 1e-15)
		let pro = try XCTUnwrap(table.price(for: "deepseek-v4-pro"))
		XCTAssertEqual(pro.inputCostPerToken, 1.74e-6, accuracy: 1e-15)
		XCTAssertEqual(pro.outputCostPerToken, 3.48e-6, accuracy: 1e-15)
		// Go-routed ids price on the dedicated Go row at the Go list rate, distinct from the Zen base.
		let flashGo = try XCTUnwrap(table.price(for: "deepseek-v4-flash-go"))
		XCTAssertEqual(flashGo.inputCostPerToken, 0.15e-6, accuracy: 1e-15)
		XCTAssertEqual(flashGo.outputCostPerToken, 0.6e-6, accuracy: 1e-15)
		let proGo = try XCTUnwrap(table.price(for: "deepseek-v4-pro-go"))
		XCTAssertEqual(proGo.inputCostPerToken, 0.66e-6, accuracy: 1e-15)
		XCTAssertEqual(proGo.outputCostPerToken, 1.98e-6, accuracy: 1e-15)
		XCTAssertNotNil(table.price(for: "deepseek-v4-flash-vision-exp"))
		XCTAssertNotNil(table.price(for: "deepseek-v4.1-flash"))
		XCTAssertNil(table.price(for: "deepseek-v4-flash-free"))
		XCTAssertNil(table.price(for: "deepseek-v4.1-flash-free"))
	}

	func testIndexIngestsDeepSeekMessages() throws {
		let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_1", modelID: "deepseek-v4-flash-free",
				providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: nowMillis
			)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-deepseek-index-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = OpenCodeBrandProvider(brand: .deepseek, root: root)
		_ = try UsageIndexer(index: index).refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .deepseek), 1)
	}

	// MARK: - Cross-provider isolation

	func testMultipleProvidersInSameDatabaseDoNotCrossContaminate() throws {
		let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
		let (root, _) = try stageDatabase(
			messages: [
				(
					sessionID: "ses_1", messageID: "msg_mimo", modelID: "mimo-v2.5-free",
					providerID: "opencode", tokens: (100, 20, 0, 0, 0), timeCreatedMillis: nowMillis
				),
				(
					sessionID: "ses_2", messageID: "msg_nem", modelID: "nemotron-3-ultra-free",
					providerID: "opencode", tokens: (200, 30, 0, 0, 0), timeCreatedMillis: nowMillis
				),
				(
					sessionID: "ses_3", messageID: "msg_ds", modelID: "deepseek-v4-flash-free",
					providerID: "opencode", tokens: (300, 40, 0, 0, 0), timeCreatedMillis: nowMillis
				),
				(
					sessionID: "ses_4", messageID: "msg_bp", modelID: "big-pickle",
					providerID: "opencode", tokens: (400, 50, 0, 0, 0), timeCreatedMillis: nowMillis
				),
			],
			sessions: [
				(
					id: "ses_1",
					model: #"{"id":"mimo-v2.5-free","providerID":"opencode"}"#,
					tokens: (100, 20, 0, 0, 0), timeCreatedMillis: nowMillis, projectID: nil
				),
				(
					id: "ses_2",
					model: #"{"id":"nemotron-3-ultra-free","providerID":"opencode"}"#,
					tokens: (200, 30, 0, 0, 0), timeCreatedMillis: nowMillis, projectID: nil
				),
				(
					id: "ses_3",
					model: #"{"id":"deepseek-v4-flash-free","providerID":"opencode"}"#,
					tokens: (300, 40, 0, 0, 0), timeCreatedMillis: nowMillis, projectID: nil
				),
				(
					id: "ses_4",
					model: #"{"id":"big-pickle","providerID":"opencode"}"#,
					tokens: (400, 50, 0, 0, 0), timeCreatedMillis: nowMillis, projectID: nil
				),
			])

		defer { try? FileManager.default.removeItem(at: root) }

		// Session path (loadEvents)
		let mimoEvents = OpenCodeBrandProvider(brand: .mimo, root: root).loadEvents()
		let nemotronEvents = OpenCodeBrandProvider(brand: .nemotron, root: root).loadEvents()
		let deepseekEvents = OpenCodeBrandProvider(brand: .deepseek, root: root).loadEvents()
		let bigPickleEvents = OpenCodeBrandProvider(brand: .bigPickle, root: root).loadEvents()

		XCTAssertEqual(mimoEvents.count, 1)
		XCTAssertEqual(nemotronEvents.count, 1)
		XCTAssertEqual(deepseekEvents.count, 1)
		XCTAssertEqual(bigPickleEvents.count, 1)

		XCTAssertEqual(mimoEvents.first?.provider, .mimo)
		XCTAssertEqual(nemotronEvents.first?.provider, .nemotron)
		XCTAssertEqual(deepseekEvents.first?.provider, .deepseek)
		XCTAssertEqual(bigPickleEvents.first?.provider, .bigPickle)

		// Message path (indexer)
		let mimoResult = OpenCodeBrandProvider(brand: .mimo).decodeDatabase(fileURL: root.appendingPathComponent("opencode.db"), createdAtOrAfterMillis: 0)
		let nemotronResult = OpenCodeBrandProvider(brand: .nemotron).decodeDatabase(fileURL: root.appendingPathComponent("opencode.db"), createdAtOrAfterMillis: 0)
		let deepseekResult = OpenCodeBrandProvider(brand: .deepseek).decodeDatabase(fileURL: root.appendingPathComponent("opencode.db"), createdAtOrAfterMillis: 0)
		let bigPickleResult = OpenCodeBrandProvider(brand: .bigPickle).decodeDatabase(fileURL: root.appendingPathComponent("opencode.db"), createdAtOrAfterMillis: 0)

		XCTAssertEqual(mimoResult.events.count, 1)
		XCTAssertEqual(nemotronResult.events.count, 1)
		XCTAssertEqual(deepseekResult.events.count, 1)
		XCTAssertEqual(bigPickleResult.events.count, 1)
	}

	// MARK: - One rule for every OpenCode-derived row

	/// The brand row and the gateway row must price the SAME free turn identically: both unpriced.
	func testBrandAndGatewayAgreeThatFreeTierIsUnpriced() throws {
		let (root, file) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_free", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (5000, 200, 0, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let calculator = CostCalculator(pricing: .bundledDefault())
		let brand = try XCTUnwrap(OpenCodeBrandProvider(brand: .mimo, root: root).loadEvents().first)
		let zen = try XCTUnwrap(OpenCodeProvider.decodeDatabase(fileURL: file).first)
		XCTAssertEqual(brand.model, zen.model)
		XCTAssertNil(calculator.cost(model: brand.model, usage: brand.usage))
		XCTAssertNil(calculator.cost(model: zen.model, usage: zen.usage))
	}

	/// Every OpenCode-derived row stamps the same index request id, so the `(provider, msg_id,
	/// req_id)` key has one shape across brands, gateways, and Muse Spark.
	func testEveryOpenCodeRowSharesTheIndexRequestID() throws {
		let (root, file) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "msg_ds", modelID: "deepseek-v4.1-flash",
				providerID: "opencode-go", tokens: (100, 10, 0, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
			(
				sessionID: "ses_1", messageID: "msg_spark", modelID: "muse-spark-1.3",
				providerID: "opencode", tokens: (100, 10, 0, 0, 0), timeCreatedMillis: 1_784_000_001_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let brand = OpenCodeBrandProvider(brand: .deepseek, root: root).loadEvents()
		let go = OpenCodeGoProvider(root: root).loadEvents()
		let zen = OpenCodeProvider.decodeDatabase(fileURL: file)
		let spark = MuseSparkProvider(root: root).loadEvents()
		for event in brand + go + zen + spark {
			XCTAssertEqual(event.requestId, "opencode-db", event.provider.rawValue)
		}
		XCTAssertEqual(brand.count, 1)
		XCTAssertEqual(go.count, 1)
		XCTAssertEqual(zen.count, 1)
		XCTAssertEqual(spark.count, 1)
	}

	/// The catalog's local-accounting set is derived from `OpenCodeBrand`, and every brand is
	/// notional (aggregable) but NOT marketed live.
	func testLocalAccountingSetIsTheBrandTable() {
		XCTAssertEqual(ProviderCatalog.localAccountingIDs, [.mimo, .nemotron, .deepseek, .bigPickle])
		for brand in OpenCodeBrand.allCases {
			XCTAssertEqual(ProviderBasis.of(brand.id), .notional, brand.rawValue)
			XCTAssertNotEqual(ProviderCatalog.descriptor(for: brand.id)?.support, .live, brand.rawValue)
			XCTAssertEqual(brand.displayName, ProviderCatalog.descriptor(for: brand.id)?.shortName)
		}
		XCTAssertTrue(ProviderCatalog.aggregateIDs.isSuperset(of: ProviderCatalog.localAccountingIDs))
		XCTAssertTrue(ProviderCatalog.aggregateIDs.contains(.claude))
		XCTAssertFalse(ProviderCatalog.aggregateIDs.contains(.opencode))
	}

	// MARK: - Detection

	/// One probe classifies every OpenCode-derived row from the store's distinct model refs.
	func testDetectionClassifiesEveryRowFromOneProbe() throws {
		let (root, file) = try stageDatabase(
			messages: [
				(
					sessionID: "ses_1", messageID: "m1", modelID: "mimo-v2.5-free",
					providerID: "opencode", tokens: (1, 1, 0, 0, 0), timeCreatedMillis: 1_784_000_000_000
				),
				(
					sessionID: "ses_1", messageID: "m2", modelID: "deepseek-v4.1-flash",
					providerID: "opencode-go", tokens: (1, 1, 0, 0, 0), timeCreatedMillis: 1_784_000_000_001
				),
			],
			sessions: [
				(
					id: "ses_old", model: #"{"id":"muse-spark-1.1","providerID":"meta"}"#,
					tokens: (1, 1, 0, 0, 0), timeCreatedMillis: 1_784_000_000_000, projectID: nil
				),
			])
		defer { try? FileManager.default.removeItem(at: root) }
		let detection = OpenCodeDetection.probe(fileURL: file)
		XCTAssertEqual(detection.brands, [.mimo, .deepseek])
		XCTAssertTrue(detection.museSpark)
		XCTAssertTrue(detection.zen)
		XCTAssertTrue(detection.go)
		XCTAssertTrue(OpenCodeBrandProvider(brand: .mimo, root: root).isAvailable())
		XCTAssertFalse(OpenCodeBrandProvider(brand: .nemotron, root: root).isAvailable())
		XCTAssertTrue(OpenCodeProvider(root: root).isAvailable())
		XCTAssertTrue(OpenCodeGoProvider(root: root).isAvailable())
		XCTAssertTrue(MuseSparkProvider(root: root).isAvailable())
	}

	func testDetectionIsEmptyForAMissingOrEmptyStore() throws {
		XCTAssertEqual(
			OpenCodeDetection.current(root: URL(fileURLWithPath: "/nonexistent/jp-\(UUID().uuidString)")),
			.none)
		let (root, file) = try stageDatabase(messages: [], sessions: [])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertEqual(OpenCodeDetection.probe(fileURL: file), .none)
		XCTAssertFalse(OpenCodeBrandProvider(brand: .mimo, root: root).isAvailable())
		XCTAssertFalse(OpenCodeGoProvider(root: root).isAvailable())
	}

	/// The cached probe re-reads only when the store's `(size, mtime, ctime)` — including its `-wal`
	/// sidecar — changes, so seven `isAvailable()` calls per refresh cost one scan.
	func testDetectionIsCachedAcrossProvidersUntilTheStoreChanges() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_1", messageID: "m1", modelID: "big-pickle",
				providerID: "opencode", tokens: (1, 1, 0, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let before = OpenCodeDetection.probeCount
		_ = OpenCodeDetection.current(root: root)
		let afterFirst = OpenCodeDetection.probeCount
		XCTAssertEqual(afterFirst, before + 1)
		for brand in OpenCodeBrand.allCases {
			_ = OpenCodeBrandProvider(brand: brand, root: root).isAvailable()
		}
		_ = OpenCodeProvider(root: root).isAvailable()
		_ = OpenCodeGoProvider(root: root).isAvailable()
		_ = MuseSparkProvider(root: root).isAvailable()
		XCTAssertEqual(OpenCodeDetection.probeCount, afterFirst, "same store state must not re-probe")
	}
}
