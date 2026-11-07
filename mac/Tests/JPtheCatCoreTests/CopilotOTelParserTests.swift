import Foundation
import XCTest

@testable import JPtheCatCore

final class CopilotOTelParserTests: XCTestCase {
	// MARK: - Classification

	func testClassifiesChatSpanByOperationName() {
		let record: [String: Any] = [
			"name": "chat completion", "spanId": "s1", "traceId": "t1",
			"attributes": ["gen_ai.operation.name": "chat"],
		]
		XCTAssertEqual(CopilotOTelParser.classify(record), .chatSpan)
	}

	func testClassifiesChatSpanByNamePrefixFallback() {
		let record: [String: Any] = ["name": "chat foo", "spanId": "s1", "attributes": [String: Any]()]
		XCTAssertEqual(CopilotOTelParser.classify(record), .chatSpan)
	}

	func testClassifiesAgentSummarySpan() {
		let record: [String: Any] = [
			"name": "invoke_agent run", "spanId": "s2",
			"attributes": ["gen_ai.operation.name": "invoke_agent"],
		]
		XCTAssertEqual(CopilotOTelParser.classify(record), .agentSummarySpan)
	}

	func testClassifiesInferenceLogByEventName() {
		let record: [String: Any] = [
			"attributes": ["event.name": "gen_ai.client.inference.operation.details"]
		]
		XCTAssertEqual(CopilotOTelParser.classify(record), .inferenceLog)
	}

	func testClassifiesInferenceLogByBodyPrefixFallback() {
		let record: [String: Any] = ["body": "GenAI inference: details here", "attributes": [String: Any]()]
		XCTAssertEqual(CopilotOTelParser.classify(record), .inferenceLog)
	}

	func testClassifiesAgentTurnLog() {
		let record: [String: Any] = [
			"attributes": ["event.name": "copilot_chat.agent.turn"]
		]
		XCTAssertEqual(CopilotOTelParser.classify(record), .agentTurnLog)
	}

	func testUnrecognizedRecordClassifiesAsNil() {
		let record: [String: Any] = ["attributes": ["some.random.key": "value"]]
		XCTAssertNil(CopilotOTelParser.classify(record))
	}

	// MARK: - Token extraction

	func testExtractsTokensNetOfCacheReadFromChatSpan() {
		let record: [String: Any] = [
			"name": "chat", "spanId": "s1", "traceId": "t1", "endTime": [1_783_386_123, 0],
			"attributes": [
				"gen_ai.operation.name": "chat",
				"gen_ai.request.model": "gpt-5.1",
				"gen_ai.conversation.id": "sess-1",
				"gen_ai.usage.input_tokens": 1000,
				"gen_ai.usage.output_tokens": 200,
				"gen_ai.usage.cache_read.input_tokens": 300,
				"gen_ai.usage.cache_write.input_tokens": 50,
			],
		]
		let events = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(events.count, 1)
		let c = events[0]
		XCTAssertEqual(c.usage.input, 700)  // 1000 - 300 cache-read
		XCTAssertEqual(c.usage.output, 200)
		XCTAssertEqual(c.usage.cacheRead, 300)
		XCTAssertEqual(c.usage.cacheCreate5m, 50)
		XCTAssertEqual(c.model, "gpt-5.1")
		XCTAssertEqual(c.sessionID, "sess-1")
	}

	func testReasoningTokensFoldIntoOutput() {
		let record: [String: Any] = [
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 100,
				"gen_ai.usage.reasoning.output_tokens": 40,
			]
		]
		let events = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(events.first?.usage.output, 140)
	}

	func testSkipsRecordWithZeroUsage() {
		let record: [String: Any] = [
			"name": "chat", "attributes": ["gen_ai.operation.name": "chat"]
		]
		XCTAssertTrue(CopilotOTelParser.candidates(from: [record], fallback: .distantPast).isEmpty)
	}

	// MARK: - Session-id priority + trace-context inheritance

	func testSessionIDPrefersHighestPriorityAttribute() {
		let record: [String: Any] = [
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 5,
				"github.copilot.interaction_id": "low-priority",
				"session.id": "high-priority",
			]
		]
		let events = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(events.first?.sessionID, "high-priority")
	}

	func testInheritsModelAndSessionFromTraceContext() {
		let sibling: [String: Any] = [
			"name": "chat", "traceId": "shared-trace",
			"attributes": [
				"gen_ai.operation.name": "chat", "gen_ai.request.model": "claude-sonnet-5",
				"session.id": "inherited-session", "gen_ai.usage.output_tokens": 1,
			],
		]
		let orphan: [String: Any] = [
			"traceId": "shared-trace",
			"attributes": [
				"event.name": "copilot_chat.agent.turn", "gen_ai.usage.output_tokens": 10,
			],
		]
		let candidates = CopilotOTelParser.candidates(from: [sibling, orphan], fallback: .distantPast)
		let turn = candidates.first { $0.kind == .agentTurnLog }
		XCTAssertEqual(turn?.model, "claude-sonnet-5")
		XCTAssertEqual(turn?.sessionID, "inherited-session")
	}

	// MARK: - Dedup priority

	func testChatSpanSuppressesOverlappingInferenceLogOnSameTrace() {
		let chat: [String: Any] = [
			"name": "chat", "spanId": "sp1", "traceId": "t1",
			"attributes": [
				"gen_ai.operation.name": "chat", "gen_ai.usage.output_tokens": 100,
				"session.id": "s1",
			],
		]
		let inference: [String: Any] = [
			"traceId": "t1",
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 100, "session.id": "s1",
			],
		]
		let candidates = CopilotOTelParser.candidates(from: [chat, inference], fallback: .distantPast)
		let deduped = CopilotOTelParser.dedupedCandidates(candidates)
		XCTAssertEqual(deduped.count, 1)
		XCTAssertEqual(deduped.first?.kind, .chatSpan)
	}

	func testAgentSummarySpanSuppressedWhenChatCoversSameTrace() {
		let chat: [String: Any] = [
			"name": "chat", "traceId": "t2",
			"attributes": ["gen_ai.operation.name": "chat", "gen_ai.usage.output_tokens": 5],
		]
		let summary: [String: Any] = [
			"name": "invoke_agent", "traceId": "t2",
			"attributes": ["gen_ai.operation.name": "invoke_agent", "gen_ai.usage.output_tokens": 5],
		]
		let candidates = CopilotOTelParser.candidates(from: [chat, summary], fallback: .distantPast)
		let deduped = CopilotOTelParser.dedupedCandidates(candidates)
		XCTAssertEqual(deduped.count, 1)
		XCTAssertEqual(deduped.first?.kind, .chatSpan)
	}

	func testUncoveredInferenceLogSurvivesDedup() {
		let inference: [String: Any] = [
			"traceId": "solo-trace",
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 42,
			],
		]
		let candidates = CopilotOTelParser.candidates(from: [inference], fallback: .distantPast)
		XCTAssertEqual(CopilotOTelParser.dedupedCandidates(candidates).count, 1)
	}

	// MARK: - Timestamp parsing

	func testParsesArrayFormTimestamp() {
		let record: [String: Any] = [
			"traceId": "tt", "endTime": [1_783_386_123, 500_000_000],
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 1,
			],
		]
		let events = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(events.first?.timestamp.timeIntervalSince1970 ?? 0, 1_783_386_123.5, accuracy: 0.01)
	}

	func testParsesMillisecondScalarTimestamp() {
		let ms = 1_783_386_123_456.0
		let record: [String: Any] = [
			"timestamp": ms,
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 1,
			],
		]
		let events = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(events.first?.timestamp.timeIntervalSince1970 ?? 0, ms / 1000, accuracy: 0.01)
	}

	func testFallsBackToProvidedFallbackTimestamp() {
		let fallback = Date(timeIntervalSince1970: 1_700_000_000)
		let record: [String: Any] = [
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 1,
			]
		]
		let events = CopilotOTelParser.candidates(from: [record], fallback: fallback)
		XCTAssertEqual(events.first?.timestamp, fallback)
	}

	// MARK: - Malformed input fails closed

	func testMalformedLineDecodesToNil() {
		XCTAssertNil(CopilotOTelParser.decode(line: Data("not json".utf8)))
	}

	func testMissingAttributesDoesNotCrash() {
		let record: [String: Any] = ["name": "chat", "attributes": [String: Any]()]
		XCTAssertTrue(CopilotOTelParser.candidates(from: [record], fallback: .distantPast).isEmpty)
	}

	// MARK: - Model normalization

	func testNormalizeModelStripsVendorPrefix() {
		XCTAssertEqual(CopilotOTelParser.normalizeModel("openai/gpt-5.1"), "gpt-5.1")
		XCTAssertEqual(CopilotOTelParser.normalizeModel("claude-sonnet-5"), "claude-sonnet-5")
		XCTAssertEqual(CopilotOTelParser.normalizeModel(""), "copilot")
	}

	// MARK: - parse(fileURL:) end to end

	func testParseFileURLProducesUsageEvents() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-otel-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("export.jsonl")

		let line = """
			{"name":"chat","spanId":"sp1","traceId":"t1","endTime":[1783386123,0],"attributes":{"gen_ai.operation.name":"chat","gen_ai.request.model":"gpt-5.1","session.id":"sess-1","gen_ai.usage.input_tokens":1000,"gen_ai.usage.output_tokens":200}}
			"""
		try (line + "\n").write(to: file, atomically: true, encoding: .utf8)

		let events = CopilotOTelParser.parse(fileURL: file)
		XCTAssertEqual(events.count, 1)
		XCTAssertEqual(events.first?.provider, .copilot)
		XCTAssertEqual(events.first?.model, "gpt-5.1")
		XCTAssertEqual(events.first?.messageId, "sess-1")
	}

	// MARK: - AIU consumption samples (github.copilot.nano_aiu)

	func testExtractsNanoAIUFromChatSpan() {
		let record: [String: Any] = [
			"name": "chat", "spanId": "sp1", "traceId": "t1",
			"attributes": [
				"gen_ai.operation.name": "chat", "gen_ai.usage.output_tokens": 100,
				"github.copilot.nano_aiu": 250_000_000,
			],
		]
		let candidates = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(candidates.first?.aiuNano, 250_000_000)
		let samples = CopilotOTelParser.aiuSamples(from: candidates)
		XCTAssertEqual(samples.count, 1)
		XCTAssertEqual(samples.first?.nano, 250_000_000)
	}

	func testNanoAIUDefaultsToZeroWhenAbsent() {
		let record: [String: Any] = [
			"name": "chat", "spanId": "sp1", "traceId": "t1",
			"attributes": ["gen_ai.operation.name": "chat", "gen_ai.usage.output_tokens": 5],
		]
		let candidates = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(candidates.first?.aiuNano, 0)
		// A zero-AIU turn produces no AIU sample (samples map 1:1 to AIU-consuming requests).
		XCTAssertTrue(CopilotOTelParser.aiuSamples(from: candidates).isEmpty)
	}

	func testAIUSamplesRideDedupNoDoubleCount() {
		// Same trace emits a chatSpan AND an overlapping inferenceLog, both carrying AIU. Only the
		// chatSpan survives dedup, so its AIU is counted exactly once — never summed twice.
		let chat: [String: Any] = [
			"name": "chat", "spanId": "sp1", "traceId": "t1",
			"attributes": [
				"gen_ai.operation.name": "chat", "gen_ai.usage.output_tokens": 100,
				"session.id": "s1", "github.copilot.nano_aiu": 300_000_000,
			],
		]
		let inference: [String: Any] = [
			"traceId": "t1",
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 100, "session.id": "s1",
				"github.copilot.nano_aiu": 300_000_000,
			],
		]
		let candidates = CopilotOTelParser.candidates(from: [chat, inference], fallback: .distantPast)
		let samples = CopilotOTelParser.aiuSamples(from: candidates)
		XCTAssertEqual(samples.count, 1)
		XCTAssertEqual(samples.first?.nano, 300_000_000)
	}

	func testParsesFloatNanoAIU() {
		let record: [String: Any] = [
			"name": "chat", "spanId": "sp1", "traceId": "t1",
			"attributes": [
				"gen_ai.operation.name": "chat", "gen_ai.usage.output_tokens": 1,
				"github.copilot.nano_aiu": 1.25e8,
			],
		]
		let candidates = CopilotOTelParser.candidates(from: [record], fallback: .distantPast)
		XCTAssertEqual(candidates.first?.aiuNano, 125_000_000)
	}
}
