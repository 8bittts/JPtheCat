import Foundation
import XCTest

@testable import JPtheCatCore

final class CodexCreditsTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_791_000_000)

	private func stage(_ limits: [[String: Any]]) throws -> (URL, URL) {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("jp-credits-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let file = root.appendingPathComponent("rollout-2026-10-02T00-00-00-feedface-0000-0000-0000-000000000099.jsonl")
		let lines = try limits.enumerated().map { offset, limit in
			let record: [String: Any] = [
				"timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(offset))),
				"type": "event_msg",
				"payload": ["type": "token_count", "rate_limits": limit],
			]
			return String(decoding: try JSONSerialization.data(withJSONObject: record), as: UTF8.self)
		}
		try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
		return (root, file)
	}

	func testCreditOnlyAccountSnapshotSurvivesWithoutInventingAQuota() throws {
		let (root, _) = try stage([[
			"limit_id": "codex", "plan_type": "pro",
			"credits": ["has_credits": true, "unlimited": false, "balance": "12345.6789000000"],
		]])
		defer { try? FileManager.default.removeItem(at: root) }
		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))
		XCTAssertNil(snapshot.primary)
		XCTAssertNil(snapshot.secondary)
		XCTAssertEqual(ProviderHeadroom.resolve(from: snapshot, now: now), .unknown)
	}
	private func account(balance: Any = "12345.6789000000", used: Double = 100) -> [String: Any] {
		[
			"limit_id": "codex", "plan_type": "pro",
			"primary": ["used_percent": used, "window_minutes": 10080,
				"resets_at": now.timeIntervalSince1970 + 86400],
			"credits": ["has_credits": true, "unlimited": false, "balance": balance],
		]
	}

	func testExhaustedWeeklyAllowanceRetainsSeparateCreditsAcrossTailAndPersistedPaths() throws {
		let (root, file) = try stage([account()])
		defer { try? FileManager.default.removeItem(at: root) }
		let provider = CodexProvider(root: root)
		let tail = try XCTUnwrap(provider.latestRateLimits(now: now))
		let decoded = provider.decodeFile(file, from: 0, parserState: nil)
		let persisted = try XCTUnwrap(provider.latestRateLimitState(
			now: now, persistedStates: [decoded.parserState]).current)
		XCTAssertEqual(tail, persisted)
		XCTAssertEqual(tail.secondary?.usedPercent, 100)
		XCTAssertNil(tail.primary, "The weekly primary slot must not invent a five-hour limit")
		XCTAssertEqual(tail.credits?.balance, 12345.6789)
		XCTAssertEqual(tail.credits?.displayValue, "12,345.67")
		XCTAssertEqual(tail.credits?.hasCredits, true)
		XCTAssertEqual(tail.capturedAt, now)
		XCTAssertEqual(ProviderHeadroom.resolve(from: tail, now: now).remainingPercent, 0)
	}

	func testLegacyCursorBackfillsCreditsWithoutReindexingTokens() throws {
		let (root, file) = try stage([account()])
		defer { try? FileManager.default.removeItem(at: root) }
		let provider = CodexProvider(root: root)
		let decoded = provider.decodeFile(file, from: 0, parserState: nil)
		var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(decoded.parserState.utf8)) as? [String: Any])
		var stored = try XCTUnwrap(legacy["newestRateLimit"] as? [String: Any])
		stored.removeValue(forKey: "credits")
		stored.removeValue(forKey: "creditDataVersion")
		legacy["newestRateLimit"] = stored
		let raw = String(decoding: try JSONSerialization.data(withJSONObject: legacy), as: UTF8.self)
		let snapshot = try XCTUnwrap(provider.latestRateLimitState(now: now, persistedStates: [raw]).current)
		XCTAssertEqual(snapshot.credits?.balance, 12345.6789)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 100)
		XCTAssertEqual(provider.parserRevision, 3, "Credit metadata must not force a whole-corpus token reindex")
	}

	func testNamedModelPoolCannotReplaceAccountCredits() throws {
		var other = account(balance: "0", used: 0)
		other["limit_id"] = "premium"
		let (root, _) = try stage([account(), other])
		defer { try? FileManager.default.removeItem(at: root) }
		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))
		XCTAssertEqual(snapshot.credits?.balance, 12345.6789)
		XCTAssertEqual(snapshot.capturedAt, now)
	}

	func testNewerAccountReadingWithoutCreditsClearsOldBalance() throws {
		var newer = account(used: 99)
		newer.removeValue(forKey: "credits")
		let (root, _) = try stage([account(), newer])
		defer { try? FileManager.default.removeItem(at: root) }
		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))
		XCTAssertNil(snapshot.credits)
		XCTAssertEqual(snapshot.secondary?.usedPercent, 99)
	}

	func testCreditOnlyReadingDoesNotInheritOlderWindows() throws {
		let newer: [String: Any] = ["limit_id": "codex", "credits": ["balance": "12.5"]]
		let (root, _) = try stage([account(), newer])
		defer { try? FileManager.default.removeItem(at: root) }
		let snapshot = try XCTUnwrap(CodexProvider(root: root).latestRateLimits(now: now))
		XCTAssertNil(snapshot.primary)
		XCTAssertNil(snapshot.secondary)
		XCTAssertEqual(snapshot.credits?.balance, 12.5)
	}

	func testExpiredAllowanceRetainsLastReportedCreditsAndResetHint() throws {
		let (root, _) = try stage([account()])
		defer { try? FileManager.default.removeItem(at: root) }
		let state = CodexProvider(root: root).latestRateLimitState(now: now.addingTimeInterval(86401))
		XCTAssertEqual(state.current?.credits?.balance, 12345.6789)
		XCTAssertNil(state.current?.secondary)
		XCTAssertTrue(state.awaitingReset)
		XCTAssertEqual(state.current?.capturedAt, now)
	}

	func testCreditDecodingDistinguishesZeroMissingUnlimitedAndMalformedValues() throws {
		XCTAssertNil(CodexCreditBalance(json: nil))
		XCTAssertNil(CodexCreditBalance(json: [:]))
		for malformed: Any in [true, -1, "NaN", "Infinity", "-1", "one", NSNull()] {
			XCTAssertNil(CodexCreditBalance(json: ["balance": malformed]), "\(malformed)")
		}
		XCTAssertEqual(CodexCreditBalance(json: ["balance": 0])?.displayValue, "0")
		XCTAssertEqual(CodexCreditBalance(json: ["balance": "0.009"])?.displayValue, "<0.01")
		XCTAssertEqual(CodexCreditBalance(json: ["has_credits": true])?.displayValue, "Available · balance not reported")
		XCTAssertEqual(CodexCreditBalance(json: ["has_credits": false])?.displayValue, "None available")
		XCTAssertEqual(CodexCreditBalance(json: ["unlimited": true])?.displayValue, "Unlimited")
		XCTAssertNil(CodexCreditBalance(json: ["has_credits": 1, "unlimited": "false"]))
	}

	func testAutomationCreditJSONUsesIndependentUnitsAndKeepsCaptureTimestamp() throws {
		let credits = try XCTUnwrap(CodexCreditBalance(json: ["has_credits": true, "balance": "123.45"]))
		let limits = LocalAutomationRateLimits(planType: "pro", primary5h: nil, secondaryWeekly: nil,
			credits: credits, capturedAt: now)
		let encoded = try JSONEncoder().encode(limits)
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
		let wallet = try XCTUnwrap(json["credits"] as? [String: Any])
		XCTAssertEqual(wallet["balance"] as? Double, 123.45)
		XCTAssertEqual(wallet["has_credits"] as? Bool, true)
		XCTAssertNotNil(json["captured_at"])
		XCTAssertNil(json["primary_5h"])
		XCTAssertEqual(try JSONDecoder().decode(LocalAutomationRateLimits.self, from: encoded), limits)
		let old = try JSONDecoder().decode(LocalAutomationRateLimits.self, from: Data("{}".utf8))
		XCTAssertNil(old.credits)
		XCTAssertNil(old.capturedAt)
	}

}
