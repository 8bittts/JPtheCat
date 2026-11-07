import Foundation
import XCTest

@testable import JPtheCatCore

/// [CRITICAL] `CopilotOTelParser` stopped materializing every decoded record into a `[[String: Any]]`
/// before classifying, and now folds trace contexts in and keeps only classify-accepted records during
/// a SINGLE streaming pass. That is a memory fix, so it must be behaviour-IDENTICAL rather than an
/// approximation: `collectTraceContexts` is first-writer-wins for `model` and strict-greater for
/// session priority, and `candidate(...)`'s dedup-key fallbacks embed the record's index in the WHOLE
/// file — all three are preserved only if the streaming pass accumulates in the same file order over
/// the same record set.
///
/// This runs the OLD shape (decode everything, then `candidates(from:fallback:)`) and the NEW shape
/// (`candidates(fileURL:)`) over the same realistic fixture and asserts identical candidate arrays.
final class CopilotProviderStreamingParityTests: XCTestCase {
	private func tempDirectory() throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-parity-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	/// Every field a `Candidate` carries, so a drift in any one of them fails the comparison.
	private func descriptor(_ candidate: CopilotOTelParser.Candidate) -> String {
		let usage = candidate.usage
		return [
			"\(candidate.kind)", candidate.traceID ?? "-", candidate.responseID ?? "-", candidate.model,
			candidate.sessionID, "\(candidate.timestamp.timeIntervalSince1970)",
			"\(usage.input)/\(usage.output)/\(usage.cacheCreate5m)/\(usage.cacheCreate1h)/\(usage.cacheRead)",
			candidate.dedupKey, "\(candidate.aiuNano)",
		].joined(separator: "|")
	}

	/// A file shaped like a real OTel export: overwhelmingly `"type":"metric"` noise (98.8% of a real
	/// 14,198-line file), model/session attributes arriving on records that are NOT themselves
	/// candidates, later records trying to overwrite an already-set model, a higher-priority session id
	/// arriving after a lower-priority one, and candidates with no trace/span id so their dedup key
	/// falls back to the whole-file index.
	private func fixtureLines() -> [String] {
		var lines: [String] = []
		func add(_ object: [String: Any]) {
			lines.append(
				String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self))
		}

		for trace in 0..<6 {
			let traceID = "trace-\(trace)"
			// Noise first: metric lines that nonetheless carry trace attributes the candidates inherit.
			for metric in 0..<40 {
				add([
					"type": "metric", "name": "copilot.metric.\(metric)", "traceId": traceID,
					"attributes": ["gen_ai.request.model": "metric-model-\(trace)-\(metric)"],
				])
			}
			// A LOWER-priority session id lands before the higher-priority one.
			add([
				"type": "metric", "name": "m", "traceId": traceID,
				"attributes": ["gen_ai.response.id": "resp-low-\(trace)"],
			])
			add([
				"type": "metric", "name": "m", "traceId": traceID,
				"attributes": ["gen_ai.conversation.id": "conv-\(trace)"],
			])
			// …and a later attempt to overwrite the already-set model must lose (first-writer-wins).
			add([
				"type": "metric", "name": "m", "traceId": traceID,
				"attributes": ["gen_ai.response.model": "late-model-\(trace)"],
			])
			add([
				"type": "span", "name": "chat gpt", "traceId": traceID, "spanId": "span-chat-\(trace)",
				"endTime": [1_785_000_000 + trace, 500_000_000],
				"attributes": [
					"gen_ai.operation.name": "chat", "gen_ai.usage.input_tokens": 1_200 + trace,
					"gen_ai.usage.output_tokens": 80 + trace,
					"gen_ai.usage.cache_read.input_tokens": 300,
					"gen_ai.usage.cache_write.input_tokens": 40,
					"github.copilot.nano_aiu": 1_500_000_000,
				],
			])
			add([
				"body": "GenAI inference: done", "traceId": traceID, "spanId": "span-log-\(trace)",
				"timestamp": 1_785_000_100_000 + trace,
				"attributes": [
					"event.name": "gen_ai.client.inference.operation.details",
					"gen_ai.usage.input_tokens": 20, "gen_ai.usage.reasoning.output_tokens": 9,
					"gen_ai.response.id": "resp-\(trace)",
				],
			])
			// No traceId and no spanId → dedup key falls back to the WHOLE-FILE index.
			add([
				"body": "copilot_chat.agent.turn", "timestamp": 1_785_000_200_000 + trace,
				"attributes": [
					"event.name": "copilot_chat.agent.turn", "gen_ai.usage.output_tokens": 11,
					"gen_ai.request.model": "orphan-model",
				],
			])
			// A record that decodes but classifies to nil, so the index gap is real.
			add(["type": "metric", "name": "tail", "traceId": traceID])
		}
		return lines
	}

	func testStreamingPassProducesIdenticalCandidatesToMaterializingEveryRecord() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("otel.jsonl")
		let lines = fixtureLines()
		try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
		XCTAssertGreaterThan(lines.count, 250, "fixture must be big enough to be realistic")

		// OLD shape: decode every line into one array, then classify.
		var records: [[String: Any]] = []
		JSONLStreamReader().read(fileURL: file) { data in
			if let record = CopilotOTelParser.decode(line: data) { records.append(record) }
		}
		XCTAssertEqual(records.count, lines.count)
		let fallback =
			((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date)
			?? .distantPast
		let old = CopilotOTelParser.candidates(from: records, fallback: fallback)

		// NEW shape: one streaming pass, contexts folded from every record, only survivors retained.
		let new = CopilotOTelParser.candidates(fileURL: file)

		XCTAssertFalse(old.isEmpty, "fixture produced no candidates — the comparison would be vacuous")
		XCTAssertEqual(old.map(descriptor), new.map(descriptor))
		// The inherited values the streaming pass could most plausibly get wrong, asserted directly.
		let chat = try XCTUnwrap(new.first { $0.kind == .chatSpan })
		XCTAssertEqual(chat.sessionID, "conv-0", "highest-priority session attr must win")
		// The trace-less agent turn's dedup key embeds its WHOLE-FILE index. Its position among the
		// RETAINED records is 2; if the streaming pass ever renumbered from the kept array instead, this
		// would read `idx-2` and silently collide across files.
		let agentTurn = try XCTUnwrap(new.first { $0.kind == .agentTurnLog })
		let index = Int(try XCTUnwrap(agentTurn.dedupKey.split(separator: ":").last))
		XCTAssertGreaterThan(
			try XCTUnwrap(index), 40, "dedup key must carry the whole-file index, not the kept index")
	}

	func testStreamingPassMatchesOnTheOffsetEntryPointToo() throws {
		let root = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("otel.jsonl")
		let lines = fixtureLines()
		try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

		// `Deduplicator` reduces through a dictionary, so compare as sorted sets — the guarantee is the
		// same EVENTS, not a stable emission order.
		func descriptors(_ events: [UsageEvent]) -> [String] {
			events.map { "\($0.messageId)|\($0.requestId)|\($0.model)|\($0.usage.total)" }.sorted()
		}
		let whole = CopilotOTelParser.parse(fileURL: file)
		let fromZero = CopilotOTelParser.parse(fileURL: file, from: 0)
		XCTAssertFalse(whole.isEmpty)
		XCTAssertEqual(descriptors(whole), descriptors(fromZero.events))
		XCTAssertEqual(
			fromZero.consumed,
			(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue)
	}

	/// The streaming pass keeps only classify-accepted records, so its retained set must be a tiny
	/// fraction of the file — that ratio IS the memory fix.
	func testOnlyClassifyAcceptedRecordsAreRetained() throws {
		var streamed = CopilotOTelParser.StreamedRecords()
		let lines = fixtureLines()
		var total = 0
		for line in lines {
			guard let record = CopilotOTelParser.decode(line: Data(line.utf8)) else { continue }
			total += 1
			streamed.absorb(record)
		}
		let kept = CopilotOTelParser.candidates(from: streamed, fallback: .distantPast).count
		XCTAssertEqual(kept, 18, "3 candidates per trace x 6 traces")
		XCTAssertLessThan(
			Double(kept) / Double(total), 0.10,
			"the point of the streaming pass is that the survivors are a small fraction of the file")
	}
}
