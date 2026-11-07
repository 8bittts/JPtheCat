import Foundation
import XCTest

@testable import JPtheCatCore

final class CopilotProviderTests: XCTestCase {
	private func stage(_ lines: [String]) throws -> (root: URL, file: URL) {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let file = root.appendingPathComponent("export.jsonl")
		try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
		return (root, file)
	}

	private func chatLine(
		session: String, model: String = "gpt-5.1", input: Int = 1000, output: Int = 200,
		traceID: String? = nil, spanID: String? = nil
	) -> String {
		let attrs: [String: Any] = [
			"gen_ai.operation.name": "chat", "gen_ai.request.model": model, "session.id": session,
			"gen_ai.usage.input_tokens": input, "gen_ai.usage.output_tokens": output,
		]
		var record: [String: Any] = ["name": "chat", "attributes": attrs, "endTime": [1_783_386_123, 0]]
		if let traceID { record["traceId"] = traceID }
		if let spanID { record["spanId"] = spanID }
		let data = try! JSONSerialization.data(withJSONObject: record)
		return String(decoding: data, as: UTF8.self)
	}

	private func aiuChatLine(session: String, aiuNano: Int, at date: Date, traceID: String) -> String {
		let record: [String: Any] = [
			"name": "chat", "traceId": traceID, "spanId": "sp-\(traceID)",
			"endTime": [date.timeIntervalSince1970, 0],
			"attributes": [
				"gen_ai.operation.name": "chat", "gen_ai.request.model": "gpt-5.1", "session.id": session,
				"gen_ai.usage.output_tokens": 100, "github.copilot.nano_aiu": aiuNano,
			],
		]
		let data = try! JSONSerialization.data(withJSONObject: record)
		return String(decoding: data, as: UTF8.self)
	}

	// MARK: - AIU consumption windowing

	func testWindowAIUSumsInsideWindowAndConvertsNanoToAIU() throws {
		let now = Date(timeIntervalSince1970: 1_783_386_123)
		let inside = now.addingTimeInterval(-3600)
		let outside = now.addingTimeInterval(-10 * 86400)  // 10 days ago — outside a 7-day window
		let (root, _) = try stage([
			aiuChatLine(session: "s1", aiuNano: 250_000_000, at: inside, traceID: "t1"),
			aiuChatLine(session: "s2", aiuNano: 500_000_000, at: now, traceID: "t2"),
			aiuChatLine(session: "s3", aiuNano: 900_000_000, at: outside, traceID: "t3"),
		])
		defer { try? FileManager.default.removeItem(at: root) }

		let provider = CopilotProvider(root: root)
		let aiu = try XCTUnwrap(provider.windowAIU(days: 7, now: now))
		XCTAssertEqual(aiu, 0.75, accuracy: 1e-9)  // (250M + 500M) nano = 0.75 AIU; 10-day-old sample excluded
	}

	func testWindowAIUReturnsNilWhenNoLocalAIUSignal() throws {
		let (root, _) = try stage([chatLine(session: "s1", traceID: "t1", spanID: "sp1")])
		defer { try? FileManager.default.removeItem(at: root) }
		// Tokens present but zero nano_aiu → no AIU samples → nil (never a fabricated 0 consumption).
		XCTAssertNil(CopilotProvider(root: root).windowAIU(days: 7))
	}

	// MARK: - Availability

	func testIsAvailableRequiresAtLeastOneJSONLFile() throws {
		let (root, _) = try stage([chatLine(session: "s1")])
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertTrue(CopilotProvider(root: root).isAvailable())
		XCTAssertFalse(CopilotProvider(root: root.appendingPathComponent("missing")).isAvailable())
	}

	func testIsAvailableFalseWhenDirectoryEmpty() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-copilot-empty-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		XCTAssertFalse(CopilotProvider(root: root).isAvailable())
	}

	// MARK: - Multiple flat files (NOT recursive)

	func testReadsAllFlatJSONLFilesButNotSubdirectories() throws {
		let (root, _) = try stage([chatLine(session: "s1", traceID: "t1", spanID: "sp1")])
		try chatLine(session: "s2", traceID: "t2", spanID: "sp2").write(
			to: root.appendingPathComponent("export-2.jsonl"), atomically: true, encoding: .utf8)
		let subdir = root.appendingPathComponent("nested", isDirectory: true)
		try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
		try chatLine(session: "s3", traceID: "t3", spanID: "sp3").write(
			to: subdir.appendingPathComponent("export-3.jsonl"), atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: root) }

		let provider = CopilotProvider(root: root)
		XCTAssertEqual(provider.otelFiles().count, 2, "flat glob only — must not recurse into subdirectories")
		let events = provider.loadEvents()
		XCTAssertEqual(Set(events.map(\.messageId)), ["s1", "s2"])
	}

	// MARK: - Token mapping

	func testLoadEventsMapsTokensAndModel() throws {
		let (root, _) = try stage([chatLine(session: "sess-1", model: "gpt-5.1", input: 1000, output: 200)])
		defer { try? FileManager.default.removeItem(at: root) }

		let events = CopilotProvider(root: root).loadEvents()
		XCTAssertEqual(events.count, 1)
		let event = try XCTUnwrap(events.first)
		XCTAssertEqual(event.provider, .copilot)
		XCTAssertEqual(event.messageId, "sess-1")
		XCTAssertEqual(event.model, "gpt-5.1")
		XCTAssertEqual(event.usage.input, 1000)
		XCTAssertEqual(event.usage.output, 200)
	}

	// MARK: - Index integration (whole-file re-read, net-new-only)
	//
	// [Regression guard] Copilot's dedup-priority logic (ChatSpan suppresses an overlapping
	// InferenceLog/AgentTurnLog/AgentSummarySpan sharing its trace) only works when the full
	// candidate set for a request is considered together — this is exactly why `canTailAppend` is
	// `false`, matching Gemini/Codex, NOT `true` like Claude's append-only JSONL. Do not flip it back.

	func testIndexIngestReReadsWholeFileAndIsIdempotent() throws {
		let (root, file) = try stage([chatLine(session: "s1", traceID: "t1", spanID: "sp1")])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-copilot-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = CopilotProvider(root: root)
		let indexer = UsageIndexer(index: index)

		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .copilot), 1)

		let unchanged = try indexer.refresh(provider)
		XCTAssertEqual(unchanged.filesSkipped, 1)
		XCTAssertEqual(index.eventCount(provider: .copilot), 1)

		let appended = chatLine(session: "s2", traceID: "t2", spanID: "sp2")
		let handle = try FileHandle(forWritingTo: file)
		try handle.seekToEnd()
		try handle.write(contentsOf: Data((appended + "\n").utf8))
		try handle.close()

		let stats = try indexer.refresh(provider)
		XCTAssertEqual(stats.filesRead, 1)
		XCTAssertEqual(index.eventCount(provider: .copilot), 2)
	}

	/// The defect this guards: a ChatSpan ingested in one refresh, then its correlated InferenceLog
	/// for the SAME trace appended and ingested in a LATER refresh, must still dedup to one event —
	/// not double-count. This only holds because `canTailAppend == false` forces a full re-read (and
	/// re-dedup) of the whole file on every change, never an isolated incremental batch.
	func testChatSpanAndInferenceLogAcrossSeparateRefreshesStillDedup() throws {
		let chat: [String: Any] = [
			"name": "chat", "spanId": "sp1", "traceId": "t1",
			"attributes": [
				"gen_ai.operation.name": "chat", "gen_ai.usage.output_tokens": 100, "session.id": "s1",
			],
		]
		let (root, file) = try stage([
			String(decoding: try JSONSerialization.data(withJSONObject: chat), as: UTF8.self)
		])
		defer { try? FileManager.default.removeItem(at: root) }
		let dbPath = NSTemporaryDirectory() + "jpc-copilot-\(UUID().uuidString).sqlite"
		defer { try? FileManager.default.removeItem(atPath: dbPath) }

		let index = try UsageIndex(path: dbPath)
		let provider = CopilotProvider(root: root)
		let indexer = UsageIndexer(index: index)
		_ = try indexer.refresh(provider)
		XCTAssertEqual(index.eventCount(provider: .copilot), 1)

		let inference: [String: Any] = [
			"traceId": "t1",
			"attributes": [
				"event.name": "gen_ai.client.inference.operation.details",
				"gen_ai.usage.output_tokens": 100, "session.id": "s1",
			],
		]
		let handle = try FileHandle(forWritingTo: file)
		try handle.seekToEnd()
		try handle.write(
			contentsOf: Data(
				(String(decoding: try JSONSerialization.data(withJSONObject: inference), as: UTF8.self) + "\n")
					.utf8))
		try handle.close()
		_ = try indexer.refresh(provider)

		XCTAssertEqual(
			index.eventCount(provider: .copilot), 1,
			"the InferenceLog must be suppressed by the earlier ChatSpan on the same trace, never double-counted")
	}

	// MARK: - Shared file traversal (candidate cache)

	/// [Regression guard — 3x full parse per refresh] `loadEvents()` and `aiuSamples()` each used to
	/// fully re-read and re-JSON-decode every OTel file, and `DashboardWidgetPublisher.makeWindows`
	/// added a third pass. On a real 9.6 MB / 14,198-line `otel.jsonl` each pass moved physical
	/// footprint by ~46 MB. They now share one cached traversal — this proves the file is opened once.
	func testLoadEventsAndAIUSamplesShareOneFileTraversal() throws {
		let now = Date(timeIntervalSince1970: 1_783_386_123)
		let staged = try stage([
			aiuChatLine(session: "s1", aiuNano: 2_000_000_000, at: now, traceID: "t1")
		])
		let provider = CopilotProvider(root: staged.root)

		let before = CopilotProvider.candidateTraversalCount
		// Exactly the three consumers that ran per refresh: the dashboard row, the AIU window, and the
		// widget publisher's own `loadEvents()`. The file never changes, so ONE decode must serve all.
		XCTAssertEqual(provider.loadEvents().count, 1)
		XCTAssertEqual(provider.windowAIU(days: 7, now: now) ?? 0, 2.0, accuracy: 0.0001)
		XCTAssertEqual(CopilotProvider(root: staged.root).loadEvents().count, 1)

		XCTAssertEqual(
			CopilotProvider.candidateTraversalCount - before, 1,
			"an unchanged OTel file must be decoded ONCE per refresh, not once per consumer")
	}

	/// [Correctness guard — the v1.013-v1.015 precedent] A cache keyed on `(size, mtime)` ALONE shipped
	/// a real correctness regression: mtime-preserving tools (`rsync --times`, `cp -p`, `touch -r`)
	/// rewrite content silently. The key must include `ctime`, which userspace cannot forge.
	func testCandidateCacheInvalidatesOnSameSizeSameMtimeRewrite() throws {
		let now = Date(timeIntervalSince1970: 1_783_386_123)
		let first = aiuChatLine(session: "s1", aiuNano: 1_000_000_000, at: now, traceID: "t1")
		let staged = try stage([first])
		let provider = CopilotProvider(root: staged.root)
		XCTAssertEqual(provider.windowAIU(days: 7, now: now) ?? 0, 1.0, accuracy: 0.0001)

		let originalMtime = try XCTUnwrap(
			(try FileManager.default.attributesOfItem(atPath: staged.file.path))[.modificationDate]
				as? Date)

		// Rewrite with DIFFERENT content padded to the SAME byte length, then restore the old mtime —
		// exactly what a mtime-preserving copy does. Only ctime moves.
		var replacement = aiuChatLine(session: "s2", aiuNano: 5_000_000_000, at: now, traceID: "t2")
		let targetBytes = first.utf8.count
		while replacement.utf8.count < targetBytes { replacement += " " }
		XCTAssertGreaterThanOrEqual(replacement.utf8.count, targetBytes)
		try (replacement + "\n").write(to: staged.file, atomically: false, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.modificationDate: originalMtime], ofItemAtPath: staged.file.path)

		XCTAssertEqual(
			provider.windowAIU(days: 7, now: now) ?? 0, 5.0, accuracy: 0.0001,
			"a mtime-preserving rewrite still bumps ctime and MUST force a re-read")
	}
}
