import Foundation
import XCTest

@testable import JPtheCatCore

/// Claude fast mode bills every token category at a premium, and Claude Code logs which speed ran as
/// `message.usage.speed`. Rates: platform.claude.com/docs/en/about-claude/pricing, checked 2026-10-06.
final class ClaudeFastModeTests: XCTestCase {
	private let calc = CostCalculator()

	private func line(model: String, speed: String?, output: Int = 0) -> Data {
		let speedField = speed.map { ",\"speed\":\"\($0)\"" } ?? ""
		return Data(
			("{\"type\":\"assistant\",\"requestId\":\"req\",\"timestamp\":\"2026-10-06T10:00:00.000Z\","
				+ "\"message\":{\"id\":\"msg\",\"model\":\"\(model)\",\"usage\":{\"input_tokens\":1000000,"
				+ "\"output_tokens\":\(output),\"cache_read_input_tokens\":0\(speedField)}}}").utf8)
	}

	func testOnlyAFastSpeedSelectsTheFastModeRow() throws {
		XCTAssertEqual(ClaudeProvider.decode(line: line(model: "claude-opus-5-5", speed: "fast"))?.model, "claude-opus-5-5-fast-mode")
		XCTAssertEqual(ClaudeProvider.decode(line: line(model: "claude-opus-5-5[1m]", speed: "fast"))?.model, "claude-opus-5-5-fast-mode")
		XCTAssertEqual(ClaudeProvider.decode(line: line(model: "claude-opus-5-5", speed: "standard"))?.model, "claude-opus-5-5")
		XCTAssertEqual(ClaudeProvider.decode(line: line(model: "claude-opus-5-5", speed: nil))?.model, "claude-opus-5-5")
	}

	/// Each fast row carries the documented input and output rate with the standard cache multipliers
	/// stacked on top: 5-minute write 1.25x, 1-hour write 2x, read 0.1x (0.05x on Opus 5.5).
	func testFastModeRowsUseDocumentedRatesInEveryBucket() throws {
		let expected: [(String, [Double])] = [
			("claude-opus-5-5", [8, 40, 10, 16, 0.4]),
			("claude-opus-5", [10, 50, 12.5, 20, 1]),
			("claude-opus-4-8", [10, 50, 12.5, 20, 1]),
		]
		let buckets = [
			TokenUsage(input: 1_000_000), TokenUsage(output: 1_000_000), TokenUsage(cacheCreate5m: 1_000_000),
			TokenUsage(cacheCreate1h: 1_000_000), TokenUsage(cacheRead: 1_000_000),
		]
		for (model, rates) in expected {
			let event = try XCTUnwrap(ClaudeProvider.decode(line: line(model: model, speed: "fast")))
			for (usage, rate) in zip(buckets, rates) {
				XCTAssertEqual(try XCTUnwrap(calc.cost(model: event.model, usage: usage), event.model), rate, accuracy: 1e-9, event.model)
				let standard = try XCTUnwrap(calc.cost(model: model, usage: usage))
				XCTAssertEqual(rate, standard * 2, accuracy: 1e-9, "\(model) fast mode is twice its standard rate")
			}
			// Fast mode applies across the full context window, so no 200K tier may reprice it.
			XCTAssertEqual(
				try XCTUnwrap(calc.cost(model: event.model, usage: TokenUsage(input: 1_000_000), forceTier: true)),
				rates[0], accuracy: 1e-9)
		}
	}

	/// A fast id with no documented fast row stays unpriced: billing it at the standard rate is the
	/// silent half-price failure this row set exists to prevent.
	func testFastTurnOnAModelWithoutAFastRowIsUnpricedNotStandard() throws {
		let event = try XCTUnwrap(ClaudeProvider.decode(line: line(model: "claude-opus-6", speed: "fast")))
		XCTAssertEqual(event.model, "claude-opus-6-fast-mode")
		XCTAssertNil(calc.cost(model: event.model, usage: event.usage))
		XCTAssertNil(calc.cost(model: "claude-opus-4-7-fast-mode", usage: event.usage))
	}

	func testFastModeFoldsIntoItsModelForDisplayButNeverMergesRealFastIDs() {
		XCTAssertEqual(ModelIdentity.presentationID("claude-opus-5-5-fast-mode"), "claude-opus-5-5")
		XCTAssertEqual(ModelIdentity.modelKey("claude-opus-5-5-fast-mode"), "claude-opus-5-5")
		XCTAssertEqual(ModelEffort.level(for: "claude-opus-5-5-fast-mode"), ModelEffort.level(for: "claude-opus-5-5"))
		XCTAssertEqual(ModelName.short("claude-opus-5-5-fast-mode"), ModelName.short("claude-opus-5-5"))
		XCTAssertEqual(ModelIdentity.presentationID("grok-composer-2.5-fast"), "grok-composer-2.5-fast")
		XCTAssertEqual(ModelIdentity.presentationID("-fast-mode"), "-fast-mode", "A bare suffix is not a model.")
	}

	/// A turn indexed before fast mode was priced keeps its standard id until the Claude parser
	/// revision changes, which re-reads the unchanged file under the fast-mode id.
	func testParserRevisionBumpRepricesAlreadyIndexedFastTurns() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-fast-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		var content = line(model: "claude-opus-5-5", speed: "fast", output: 1_000_000)
		content.append(Data("\n".utf8))
		try content.write(to: root.appendingPathComponent("a.jsonl"))
		let provider = ClaudeProvider(root: root)
		let file = try XCTUnwrap(provider.jsonlFiles().first)
		let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
		let size = try XCTUnwrap((attrs[.size] as? NSNumber)?.intValue)
		let mtime = try XCTUnwrap((attrs[.modificationDate] as? Date)?.timeIntervalSince1970)
		let ctime = try XCTUnwrap(FileCursor.changeTime(fileURL: file))
		let dbPath = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-fast-\(UUID().uuidString).sqlite").path
		defer { try? FileManager.default.removeItem(atPath: dbPath) }
		let index = try UsageIndex(path: dbPath)
		// What revision 1 stored: the same turn under its standard id.
		let stale = try XCTUnwrap(ClaudeProvider.decode(line: line(model: "claude-opus-5-5", speed: nil, output: 1_000_000)))
		try index.ingest([stale], sourcePath: file.path)
		try index.setCursor(
			path: file.path, size: size, mtime: mtime, offset: size, ctime: ctime, provider: .claude, parserRevision: 1)
		let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z"))
		XCTAssertEqual(try index.rollup(provider: .claude, now: now).today.cost, 24, accuracy: 1e-9)

		let stats = try UsageIndexer(index: index).refresh(provider)

		XCTAssertEqual(stats.filesRead, 1)
		XCTAssertEqual(index.eventCount(provider: .claude), 1)
		let rollup = try index.rollup(provider: .claude, now: now)
		XCTAssertEqual(rollup.today.cost, 48, accuracy: 1e-9)
		XCTAssertEqual(rollup.today.unpricedModels, [])
	}
}
