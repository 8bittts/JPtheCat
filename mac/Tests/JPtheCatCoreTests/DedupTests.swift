import Foundation
import XCTest

@testable import JPtheCatCore

final class DedupTests: XCTestCase {
	/// Copies the fixture into a temp `.claude/projects`-shaped dir so we exercise the full public
	/// path: enumerate files -> stream -> decode -> dedupe.
	private func fixtureRoot() throws -> URL {
		let url = try XCTUnwrap(
			Bundle.module.url(forResource: "claude-dedup", withExtension: "jsonl"),
			"fixture missing")
		let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-dedup-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		try FileManager.default.copyItem(at: url, to: tmp.appendingPathComponent("session.jsonl"))
		return tmp
	}

	func testDedupeKeepsMaxOutputAndSkipsNoise() throws {
		let root = try fixtureRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let events = ClaudeProvider(root: root).loadEvents()

		// 6 assistant-usage lines (3 reqA + 2 reqB + 1 reqC) -> 3 unique (message.id, requestId).
		XCTAssertEqual(events.count, 3)
		// keep-max-output per key (final streaming snapshot), NOT keep-first.
		XCTAssertEqual(Set(events.map { $0.usage.output }), [120, 30, 200])
		XCTAssertEqual(events.reduce(0) { $0 + $1.usage.output }, 350)
		// user lines and API-error messages are ignored.
		XCTAssertFalse(events.contains { $0.messageId == "msgErr" })
		XCTAssertFalse(events.contains { $0.messageId.isEmpty })
	}

	func testProjectAttributionFromCwd() throws {
		let root = try fixtureRoot()
		defer { try? FileManager.default.removeItem(at: root) }
		let events = ClaudeProvider(root: root).loadEvents()
		XCTAssertTrue(events.allSatisfy { $0.project == "proj" })
	}

	func testGlobalDedupeAcrossCallers() {
		// The same (id, req) logged twice (e.g. a resumed session in another file) collapses to one.
		let a = UsageEvent(
			messageId: "m", requestId: "r", provider: .claude, model: "claude-opus-4-8",
			timestamp: .init(), usage: TokenUsage(output: 40))
		let b = UsageEvent(
			messageId: "m", requestId: "r", provider: .claude, model: "claude-opus-4-8",
			timestamp: .init(), usage: TokenUsage(output: 90))
		let deduped = Deduplicator.dedupe([a, b])
		XCTAssertEqual(deduped.count, 1)
		XCTAssertEqual(deduped.first?.usage.output, 90)
	}
}
