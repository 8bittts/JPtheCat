import Foundation
import XCTest

@testable import JPtheCatCore

/// Tests for OpenCode Go — the $10/month OpenCode Zen subscription, whose rows OpenCode tags with the
/// gateway `providerID == "opencode-go"`.
final class OpenCodeGoProviderTests: XCTestCase {
	func testGatewayGrokContextBoundaryDiffersFromDirectXAI() throws {
		let (root, file) = try stageDatabase(messages: [
			("s", "go", "grok-4.7", "opencode-go", (200_000, 0, 0, 0, 0), 1_000),
			("s", "zen", "grok-4.7", "opencode", (200_000, 0, 0, 0, 0), 2_000),
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let calculator = CostCalculator()
		for event in OpenCodeGoProvider.decodeDatabase(fileURL: file)
			+ OpenCodeProvider.decodeDatabase(fileURL: file) {
			XCTAssertEqual(try XCTUnwrap(calculator.cost(model: event.model, usage: event.usage)), 0.4, accuracy: 0.000001)
			XCTAssertEqual(try XCTUnwrap(calculator.cost(model: event.model, usage: TokenUsage(input: 200_001))), 0.800004, accuracy: 0.000001)
		}
		XCTAssertEqual(try XCTUnwrap(calculator.cost(model: "grok-4.7", usage: TokenUsage(input: 200_000))), 0.8, accuracy: 0.000001)
	}

	private func stageDatabase(
		messages: [(sessionID: String, messageID: String, modelID: String, providerID: String, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int)],
		sessions: [(id: String, model: String?, tokens: (Int, Int, Int, Int, Int), timeCreatedMillis: Int, projectID: String?)] = []
	) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-oc-go-\(UUID().uuidString)", isDirectory: true)
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

	/// The gateway split: Go owns `opencode-go` rows, Zen owns `opencode` rows, and neither claims the
	/// other's. Both see the SAME store; only the gateway predicate differs.
	func testGatewaySplitBetweenZenAndGo() throws {
		let (root, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_go", messageID: "msg_go", modelID: "deepseek-v4.1-flash",
				providerID: "opencode-go", tokens: (1_000, 100, 20, 0, 0), timeCreatedMillis: 1_784_000_000_000
			),
			(
				sessionID: "ses_zen", messageID: "msg_zen", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (500, 50, 0, 0, 0), timeCreatedMillis: 1_784_000_001_000
			),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let go = OpenCodeGoProvider(root: root).loadEvents()
		XCTAssertEqual(go.map(\.messageId), ["msg_go"])
		XCTAssertEqual(go.first?.provider, .opencodego)
		XCTAssertEqual(go.first?.model, "deepseek-v4.1-flash-peak")

		let zen = OpenCodeProvider(root: root).loadEvents()
		XCTAssertEqual(zen.map(\.messageId), ["msg_zen"])
		XCTAssertEqual(zen.first?.provider, .opencode)
	}

	func testIsAvailableRequiresGoRows() throws {
		let (empty, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_zen", messageID: "msg_zen", modelID: "mimo-v2.5-free",
				providerID: "opencode", tokens: (1, 0, 0, 0, 0), timeCreatedMillis: 1
			)
		])
		defer { try? FileManager.default.removeItem(at: empty) }
		XCTAssertFalse(OpenCodeGoProvider(root: empty).isAvailable())

		let (withGo, _) = try stageDatabase(messages: [
			(
				sessionID: "ses_go", messageID: "msg_go", modelID: "deepseek-v4.1-flash",
				providerID: "opencode-go", tokens: (1, 0, 0, 0, 0), timeCreatedMillis: 1
			)
		])
		defer { try? FileManager.default.removeItem(at: withGo) }
		XCTAssertTrue(OpenCodeGoProvider(root: withGo).isAvailable())
	}

	func testMissingStoreIsUnavailableAndReadsNothing() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-oc-go-missing-\(UUID().uuidString)", isDirectory: true)
		XCTAssertFalse(OpenCodeGoProvider(root: root).isAvailable())
		XCTAssertTrue(OpenCodeGoProvider(root: root).loadEvents().isEmpty)
	}

	func testPeakHoursAreUTCWeekdaysAndAgreeAcrossBrandAndGateway() throws {
		let dates = [
			("2026-09-23T00:59:59Z", false), ("2026-09-23T01:00:00Z", true),
			("2026-09-23T03:59:59Z", true), ("2026-09-23T04:00:00Z", false),
			("2026-09-23T06:00:00Z", true), ("2026-09-23T10:00:00Z", false),
			("2026-09-26T02:00:00Z", false),
		]
		for (dateString, peak) in dates {
			let date = try XCTUnwrap(ISO8601DateFormatter().date(from: dateString))
			let (root, _) = try stageDatabase(messages: [
				("session", "turn", "deepseek-v4.1-flash", "opencode-go", (1000, 100, 0, 0, 0), Int(date.timeIntervalSince1970 * 1000)),
			])
			defer { try? FileManager.default.removeItem(at: root) }
			let gateway = try XCTUnwrap(OpenCodeGoProvider(root: root).loadEvents().first)
			let brand = try XCTUnwrap(OpenCodeBrandProvider(brand: .deepseek, root: root).loadEvents().first)
			XCTAssertEqual(gateway.model, peak ? "deepseek-v4.1-flash-peak" : "deepseek-v4.1-flash")
			XCTAssertEqual(brand.model, gateway.model)
			XCTAssertEqual(try XCTUnwrap(CostCalculator().cost(model: gateway.model, usage: gateway.usage)), peak ? 0.00042 : 0.00021, accuracy: 1e-12)
		}
		let zen = OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: "deepseek-v4.1-flash", providerID: "opencode"))
		XCTAssertEqual(zen, "deepseek-v4.1-flash-zen")
	}

	/// Every accounting id the parser can return for a routed model is an EXACT price row. The coverage
	/// audit checks emitted ids only, so a model added to a routing set without its `-opencode`, `-zen`,
	/// `-go`, or `-peak` row would otherwise reach the dashboard as silently unpriced.
	func testEveryRoutedAccountingIDIsAnExactPriceRow() throws {
		let rows = PricingTable.bundledDefault().knownModels
		let peak = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-23T02:00:00Z"))
		let offPeak = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-26T02:00:00Z"))
		let routed = OpenCodeGateway.openCodeBoundaryModelIDs
			.union(OpenCodeGateway.zenDistinctModelIDs)
			.union(OpenCodeGateway.goDistinctModelIDs)
			.union(OpenCodeGateway.goPeakModelIDs)
		var emitted: Set<String> = []
		for model in routed {
			for gateway in ["opencode", "opencode-go"] {
				for date in [peak, offPeak] {
					let ref = OpenCodeModelRef(modelID: "vendor/" + model, providerID: gateway, createdAt: date)
					emitted.insert(OpenCodeGateway.normalizedModelID(ref, fallback: "unused"))
					XCTAssertEqual(MuseSparkProvider.normalizedModelID(ref), OpenCodeGateway.normalizedModelID(ref, fallback: "unused"))
				}
			}
		}
		XCTAssertTrue(emitted.contains("deepseek-v4-pro-go-peak"), "The enumeration lost the peak route.")
		XCTAssertTrue(emitted.contains("grok-4.7-opencode"), "The enumeration lost the boundary route.")
		XCTAssertEqual(emitted.subtracting(rows).sorted(), [])
	}

	/// opencode.ai/docs/go, checked 2026-10-06: Space Bunny is $0.15 in / $0.60 out / $0.03 cached
	/// with a $30 Go cap. Zen serves it only as `space-bunny-free`, which stays unpriced.
	func testGoSpaceBunnyUsesItsPublishedRateWhileTheZenFreeTierStaysUnpriced() throws {
		let calc = CostCalculator()
		let go = OpenCodeGateway.normalizedModelID(
			OpenCodeModelRef(modelID: "opencode-go/space-bunny", providerID: "opencode-go"), fallback: "unused")
		XCTAssertEqual(go, "space-bunny")
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: go, usage: TokenUsage(input: 1_000_000))), 0.15, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: go, usage: TokenUsage(output: 1_000_000))), 0.60, accuracy: 1e-12)
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: go, usage: TokenUsage(cacheRead: 1_000_000))), 0.03, accuracy: 1e-12)
		XCTAssertEqual(OpenCodeGoLimits.capUSD(for: go, windowMinutes: OpenCodeGoLimits.fiveHourMinutes), 6)
		let zen = OpenCodeGateway.normalizedModelID(
			OpenCodeModelRef(modelID: "space-bunny-free", providerID: "opencode"), fallback: "unused")
		XCTAssertEqual(zen, "space-bunny-free")
		XCTAssertNil(calc.cost(model: zen, usage: TokenUsage(input: 1_000_000)))
	}

	func testHistoricalZenCodexRoutesKeepTheirDistinctGatewayRate() throws {
		for model in ["gpt-5-codex", "gpt-5.1-codex"] {
			let id = OpenCodeProvider.normalizeModel(OpenCodeModelRef(modelID: model, providerID: "opencode"))
			XCTAssertEqual(id, model + "-zen")
			XCTAssertEqual(try XCTUnwrap(CostCalculator().cost(model: id, usage: TokenUsage(input: 1_000_000))), 1.07, accuracy: 1e-12)
			XCTAssertEqual(try XCTUnwrap(CostCalculator().cost(model: model, usage: TokenUsage(input: 1_000_000))), 1.25, accuracy: 1e-12)
		}
	}

	/// opencode.ai/docs/go, checked 2026-10-30: DeepSeek V4.1 Flash is listed at $100 with no promotion
	/// or end date, and GPT-6 Luna and Claude Haiku 5.5 carry a $15 cap. Off-peak and peak turns share the one model cap.
	/// opencode.ai/docs/go, checked 2026-10-30: Kimi K3.1 Pro $2 / $10 / cached $0.20 / write $2 ($15 cap),
	/// Step 5 Preview $1 / $2.70 / cached $0.10 ($15), MiniMax M3.1 Flash $0.15 / $0.60 / cached $0.015 ($20),
	/// and Gemini 4 Argon at its billed 50%-off rate $2 / $10 / cached $0.10 ($30).
	func testNewGoModelsUsePublishedRatesAndCaps() throws {
		let calc = CostCalculator()
		let cases: [(String, Double, Double, Double, Double)] = [
			("kimi-k3.1-pro", 2, 10, 0.2, 15),
			("step-5-preview", 1, 2.7, 0.1, 15),
			("minimax-m3.1-flash", 0.15, 0.6, 0.015, 20),
			("gemini-4-argon", 2, 10, 0.1, 30),
		]
		for (model, input, output, cached, cap) in cases {
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(input: 1_000_000))), input, accuracy: 1e-9, model)
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(output: 1_000_000))), output, accuracy: 1e-9, model)
			XCTAssertEqual(try XCTUnwrap(calc.cost(model: model, usage: TokenUsage(cacheRead: 1_000_000))), cached, accuracy: 1e-9, model)
			XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: model), cap, model)
		}
		XCTAssertEqual(try XCTUnwrap(calc.cost(model: "kimi-k3.1-pro", usage: TokenUsage(cacheCreate5m: 1_000_000))), 2, accuracy: 1e-9)
	}

	func testPublishedCapsAndMixedPeakUsageShareOneCap() throws {
		let formatter = ISO8601DateFormatter()
		let now = try XCTUnwrap(formatter.date(from: "2026-09-27T23:59:59Z"))
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4.1-flash", now: now), 100)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4.1-flash", now: Self.afterPromotions), 100)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "mimo-v2.6-pro", now: now), 15)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "grok-4.7-opencode", now: now), 15)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "gpt-6-luna", now: now), 15)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "gpt-5.6-luna", now: now), 15)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "claude-haiku-5-5", now: now), 15)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "space-bunny", now: now), 30)
		let events = [
			event(model: "deepseek-v4.1-flash", usage: TokenUsage(input: 1_000_000), at: now),
			event(model: "deepseek-v4.1-flash-peak", usage: TokenUsage(input: 1_000_000), at: now),
		]
		let windows = OpenCodeGoLimits.measuredWindows(events: events, calculator: CostCalculator(), now: now)
		XCTAssertEqual(try XCTUnwrap(windows.first?.usedPercent), 0.45 / 20 * 100, accuracy: 1e-12)
		XCTAssertTrue(OpenCodeGoLimits.measuredWindows(events: events, calculator: CostCalculator(), now: now.addingTimeInterval(-1)).isEmpty)
		XCTAssertNil(OpenCodeGoLimits.capUSD(for: "deepseek-v4.1-flash", windowMinutes: 42, now: now))
	}

	// MARK: - Official caps

	/// A date safely after every published promotion, so these assert the BASE caps.
	private static let afterPromotions = Calendar(identifier: .gregorian)
		.date(from: DateComponents(year: 2026, month: 10, day: 1))!

	/// 5-hour = 20% of a model's monthly limit, weekly = 50%, monthly = 100%.
	func testWindowCapsAreFractionsOfTheMonthlyLimit() {
		let now = Self.afterPromotions
		XCTAssertEqual(
			OpenCodeGoLimits.capUSD(for: "deepseek-v4-pro", windowMinutes: 300, now: now), 3.0)
		XCTAssertEqual(
			OpenCodeGoLimits.capUSD(for: "deepseek-v4-pro", windowMinutes: 10080, now: now), 7.5)
		XCTAssertEqual(
			OpenCodeGoLimits.capUSD(for: "deepseek-v4-pro", windowMinutes: 43200, now: now), 15.0)
		// A model outside the published table has no cap — never a fabricated one.
		XCTAssertNil(OpenCodeGoLimits.capUSD(for: "not-a-go-model", windowMinutes: 300, now: now))
	}

	/// A dated promotion raises the cap while it runs and reverts on its own afterwards — the cap must
	/// never silently drift. No promotion is published today, so the mechanism runs on a fixture table.
	func testDatedPromotionRaisesTheCapThenReverts() {
		XCTAssertTrue(OpenCodeGoLimits.promotions.isEmpty)
		let promotions = [
			"deepseek-v4-pro": OpenCodeGoLimits.Promotion(
				multiplier: 4, endsAt: DateComponents(year: 2026, month: 9, day: 28)),
		]
		let during = Calendar(identifier: .gregorian)
			.date(from: DateComponents(year: 2026, month: 9, day: 15))!
		let after = Self.afterPromotions
		XCTAssertEqual(
			OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-pro", now: during, promotions: promotions), 60)
		XCTAssertEqual(
			OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-pro-go-peak", now: during, promotions: promotions), 60)
		XCTAssertEqual(
			OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-pro", now: after, promotions: promotions), 15)
		// Only the promoted model moves.
		XCTAssertEqual(
			OpenCodeGoLimits.monthlyCapUSD(for: "kimi-k3", now: during, promotions: promotions), 15)
	}

	func testUsedPercentIsCappedAndNilWithoutACap() {
		let now = Self.afterPromotions
		let used = OpenCodeGoLimits.usedPercent(
			cost: 1.5, modelID: "deepseek-v4-pro", windowMinutes: 300, now: now)
		XCTAssertEqual(used ?? -1, 50, accuracy: 0.001)
		XCTAssertEqual(
			OpenCodeGoLimits.usedPercent(
				cost: 999, modelID: "deepseek-v4-pro", windowMinutes: 300, now: now) ?? -1,
			100, accuracy: 0.001)
		XCTAssertNil(OpenCodeGoLimits.usedPercent(cost: 1, modelID: "unknown", windowMinutes: 300, now: now))
	}

	/// Free-tier ids are unpriced, so the gateway row falls back to tokens rather than a $ figure.
	func testFreeTierModelsAreUnpriced() {
		let table = PricingTable.bundledDefault()
		XCTAssertNil(table.price(for: "mimo-v2.5-free"))
		XCTAssertNil(table.price(for: "muse-spark-1.3-contributor-free"))
		XCTAssertNil(table.price(for: "deepseek-v4-flash-free"))
		XCTAssertNotNil(table.price(for: "deepseek-v4.1-flash"))
	}

	// MARK: - Measured windows

	private func event(
		model: String, usage: TokenUsage, at timestamp: Date
	) -> UsageEvent {
		UsageEvent(
			messageId: "msg-\(model)-\(timestamp.timeIntervalSince1970)", requestId: "r",
			provider: .opencodego, model: model, timestamp: timestamp, usage: usage)
	}

	/// Go's three windows come back in the provider's own order, each measured, and every one is
	/// `resetsAt: nil` — OpenCode publishes the caps but no window boundary, so a countdown here would
	/// be fabricated.
	func testMeasuredWindowsAreOrderedAndCarryNoReset() {
		let now = Self.afterPromotions
		let calculator = CostCalculator(pricing: .bundledDefault())
		let events = [event(model: "deepseek-v4.1-flash", usage: TokenUsage(input: 1_000_000), at: now)]
		let windows = OpenCodeGoLimits.measuredWindows(
			events: events, calculator: calculator, now: now)
		XCTAssertEqual(
			windows.map(\.windowMinutes),
			[
				OpenCodeGoLimits.fiveHourMinutes, OpenCodeGoLimits.weeklyMinutes,
				OpenCodeGoLimits.monthlyMinutes,
			])
		XCTAssertTrue(windows.allSatisfy { $0.resetsAt == nil })
		// One measurable model in every span, so all three bars exist.
		XCTAssertTrue(windows.allSatisfy { $0.usedPercent > 0 })
	}

	/// A model outside the published cap table contributes no window rather than a fabricated 0%, so an
	/// install that has only used uncapped models reports nothing.
	func testMeasuredWindowsDropUncappedModels() {
		let now = Self.afterPromotions
		let calculator = CostCalculator(pricing: .bundledDefault())
		let events = [event(model: "not-a-go-model", usage: TokenUsage(input: 1_000), at: now)]
		XCTAssertTrue(
			OpenCodeGoLimits.measuredWindows(events: events, calculator: calculator, now: now).isEmpty)
	}

	/// [Regression guard] A model Go CAPS but JP cannot PRICE (no pricing row, or a free-tier id) must
	/// contribute nothing — never a $0 that becomes a fabricated "0% of 5h" bar. A free-tier DeepSeek
	/// id is capped after suffix-stripping but deliberately unpriced (`ModelIdentity.isFreeTier`).
	func testMeasuredWindowsDropCappedModelsJPCannotPrice() {
		let now = Self.afterPromotions
		let calculator = CostCalculator(pricing: .bundledDefault())
		XCTAssertNotNil(OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-flash-free", now: now))
		XCTAssertNil(calculator.cost(model: "deepseek-v4-flash-free", usage: TokenUsage(input: 1_000)))
		let unpriced = [
			event(model: "deepseek-v4-flash-free", usage: TokenUsage(input: 1_000_000), at: now),
		]
		XCTAssertTrue(
			OpenCodeGoLimits.measuredWindows(events: unpriced, calculator: calculator, now: now).isEmpty)
		// A priced sibling in the same window is still measured, and the unpriced one adds nothing.
		let mixed = unpriced + [event(model: "deepseek-v4.1-flash", usage: TokenUsage(input: 1_000_000), at: now)]
		let windows = OpenCodeGoLimits.measuredWindows(events: mixed, calculator: calculator, now: now)
		XCTAssertEqual(windows.count, 3)
		let alone = OpenCodeGoLimits.measuredWindows(
			events: [mixed[1]], calculator: calculator, now: now)
		XCTAssertEqual(windows.map(\.usedPercent), alone.map(\.usedPercent))
	}

	/// Go's parse-time normalisation keeps a tier suffix (one rule for every OpenCode row); only the
	/// published-cap lookup strips it.
	func testGoNormalisationKeepsTierSuffixWhileCapLookupStripsIt() {
		XCTAssertEqual(
			OpenCodeGoProvider.normalizedModelID(OpenCodeModelRef(modelID: "zen/deepseek-v4-flash-free", providerID: nil)),
			"deepseek-v4-flash-free")
		XCTAssertEqual(
			OpenCodeGoProvider.normalizedModelID(OpenCodeModelRef(modelID: nil, providerID: nil)), "opencode-go")
		XCTAssertEqual(
			OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-flash-free", now: Self.afterPromotions),
			OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-flash", now: Self.afterPromotions))
	}

	/// A Go-routed DeepSeek V4 turn whose Go list price differs from Zen's gets a parse-time `-go`
	/// suffix so it prices on the dedicated Go row. The vendor prefix strips BEFORE the suffix
	/// decision, ids outside the differing set (including free-tier turns and `deepseek-v4.1-flash`)
	/// keep their id, and a Zen-routed turn never suffixes.
	func testGoRoutedDeepSeekGetsGoSuffix() {
		let go = { (id: String?) in OpenCodeModelRef(modelID: id, providerID: "opencode-go") }
		XCTAssertEqual(OpenCodeGoProvider.normalizedModelID(go("deepseek-v4-flash")), "deepseek-v4-flash-go")
		XCTAssertEqual(OpenCodeGoProvider.normalizedModelID(go("deepseek-v4-pro")), "deepseek-v4-pro-go")
		XCTAssertEqual(
			OpenCodeGoProvider.normalizedModelID(go("vendor/deepseek-v4-flash")), "deepseek-v4-flash-go")
		XCTAssertEqual(OpenCodeGoProvider.normalizedModelID(go("deepseek-v4-flash-free")), "deepseek-v4-flash-free")
		XCTAssertEqual(OpenCodeGoProvider.normalizedModelID(go("deepseek-v4.1-flash")), "deepseek-v4.1-flash")
		XCTAssertEqual(
			OpenCodeGoProvider.normalizedModelID(
				OpenCodeModelRef(modelID: "deepseek-v4-flash", providerID: "opencode")),
			"deepseek-v4-flash")
	}

	/// The published Go caps are keyed by the base id, so each `-go` row resolves back to its base
	/// monthly cap after suffix-stripping (Flash 30, Pro 15, Vision 15).
	func testGoSuffixedRowsResolveToTheirBaseCaps() {
		let now = Self.afterPromotions
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-flash-go", now: now), 30)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-pro-go", now: now), 15)
		XCTAssertEqual(OpenCodeGoLimits.monthlyCapUSD(for: "deepseek-v4-flash-vision-exp-go", now: now), 15)
	}

	/// The `-go` rows carry the Go LIST rates (V4 Flash 0.15/0.60 with a 0.003 cached-read; V4 Pro
	/// 0.66/1.98 with a 0.022 cached-read), distinct from the Zen base rows.
	func testGoSuffixedRowsPriceAtGoRates() throws {
		let table = PricingTable.bundledDefault()
		let flash = try XCTUnwrap(table.price(for: "deepseek-v4-flash-go"))
		XCTAssertEqual(flash.inputCostPerToken, 1.5e-7, accuracy: 1e-15)
		XCTAssertEqual(flash.outputCostPerToken, 6.0e-7, accuracy: 1e-15)
		XCTAssertEqual(flash.cacheReadInputTokenCost ?? -1, 3e-9, accuracy: 1e-15)
		let vision = try XCTUnwrap(table.price(for: "deepseek-v4-flash-vision-exp-go"))
		XCTAssertEqual(vision.inputCostPerToken, 1.5e-7, accuracy: 1e-15)
		XCTAssertEqual(vision.cacheReadInputTokenCost ?? -1, 3e-9, accuracy: 1e-15)
		let pro = try XCTUnwrap(table.price(for: "deepseek-v4-pro-go"))
		XCTAssertEqual(pro.inputCostPerToken, 6.6e-7, accuracy: 1e-15)
		XCTAssertEqual(pro.outputCostPerToken, 1.98e-6, accuracy: 1e-15)
		XCTAssertEqual(pro.cacheReadInputTokenCost ?? -1, 2.2e-8, accuracy: 1e-15)
		XCTAssertNil(table.price(for: "deepseek-v4-flash-free"))
	}

	/// Each window measures its OWN trailing span: an event older than five hours has aged out of the
	/// 5-hour window but still counts toward the weekly and monthly ones.
	func testMeasuredWindowsUseTheirOwnTrailingSpan() {
		let now = Self.afterPromotions
		let calculator = CostCalculator(pricing: .bundledDefault())
		let agedOut = [
			event(
				model: "deepseek-v4.1-flash", usage: TokenUsage(input: 1_000_000),
				at: now.addingTimeInterval(-6 * 3600))
		]
		let windows = OpenCodeGoLimits.measuredWindows(
			events: agedOut, calculator: calculator, now: now)
		XCTAssertNil(windows.first { $0.windowMinutes == OpenCodeGoLimits.fiveHourMinutes })
		XCTAssertNotNil(windows.first { $0.windowMinutes == OpenCodeGoLimits.weeklyMinutes })
		XCTAssertNotNil(windows.first { $0.windowMinutes == OpenCodeGoLimits.monthlyMinutes })
	}
}
