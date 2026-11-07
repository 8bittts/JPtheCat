import Foundation

/// Process-wide, thread-safe cache from the capture file's path to the `(size, mtime, ctime)` we last
/// read it at and the deduped events it decoded to. The `(size, mtime, ctime)` key is required —
/// `(size, mtime)` alone is unsafe against mtime-preserving rewrites; see `UsageIndexer.swift`. An
/// unreadable state forces a re-read rather than trusting a partial key.
///
/// [Why this exists] `loadEvents()` re-read `cursor-usage.jsonl` from offset 0 on EVERY call —
/// JSON-parsing every line ever captured plus three base64 decodes per line — and
/// `DashboardViewModel` calls it on every refresh build (60 s poll plus every FSEvents burst, 2 s
/// floor) with `DashboardWidgetPublisher` calling it again per publish. A refresh where the file did
/// not change now costs one `stat(2)`.
///
/// One slot, not a dictionary: a `CursorProvider` reads exactly ONE file, so a single entry is
/// naturally bounded and can never pin a stale path's events forever.
private final class CursorEventCache: @unchecked Sendable {
	private struct Entry {
		let path: String
		let size: Int
		let mtime: Double
		let ctime: Double
		let events: [UsageEvent]
	}
	private let lock = NSLock()
	private var entry: Entry?
	/// Counts real file traversals. A cache hit is not otherwise observable — a correct cache re-reads
	/// whenever the file actually changes — so `CursorProviderTests` reads this counter.
	private(set) var traversalCount = 0

	func recordTraversal() {
		lock.lock()
		traversalCount += 1
		lock.unlock()
	}

	func cached(path: String, state: (size: Int, mtime: Double, ctime: Double)) -> [UsageEvent]? {
		lock.lock()
		defer { lock.unlock() }
		guard let entry, entry.path == path, entry.size == state.size, entry.mtime == state.mtime,
			entry.ctime == state.ctime
		else { return nil }
		return entry.events
	}

	func store(path: String, state: (size: Int, mtime: Double, ctime: Double), events: [UsageEvent]) {
		lock.lock()
		defer { lock.unlock() }
		entry = Entry(
			path: path, size: state.size, mtime: state.mtime, ctime: state.ctime, events: events)
	}
}

private let cursorEventCache = CursorEventCache()

/// Reads the usage-only JSONL written by JP's opt-in Cursor CLI `stop` hook.
///
/// Cursor's private chat databases contain conversation content and are not a stable usage ledger.
/// This provider therefore reads exactly one app-owned capture file containing identifiers, model,
/// timestamp, and token counts—never prompts, responses, tool data, paths, or credentials.
public struct CursorProvider: UsageProvider {
	public let id: ProviderID = .cursor
	public let root: URL
	private let reader = JSONLStreamReader()

	public init(root: URL? = nil) {
		self.root = root ?? CursorHookSetup.captureURL()
	}

	/// Number of real capture-file decodes performed process-wide. Guard hook only — see
	/// `CursorEventCache.traversalCount`.
	static var decodeTraversalCount: Int { cursorEventCache.traversalCount }

	public func watchPaths() -> [URL] { [root.deletingLastPathComponent()] }
	public func isAvailable() -> Bool { FileManager.default.fileExists(atPath: root.path) }
	public func loadEvents() -> [UsageEvent] {
		let path = root.path
		// ONE `stat(2)` for all three fields — the whole cost of an unchanged refresh.
		let state = FileCursor.state(fileURL: root)
		if let state, let hit = cursorEventCache.cached(path: path, state: state) { return hit }
		cursorEventCache.recordTraversal()
		var dedup = Deduplicator()
		_ = reader.read(fileURL: root, from: 0) { line in
			if let event = Self.decode(line: line) { dedup.add(event) }
		}
		let events = dedup.events
		// Only cache when the full (size, mtime, ctime) key resolved — a partial key would be
		// indistinguishable from a later real change.
		if let state { cursorEventCache.store(path: path, state: state, events: events) }
		return events
	}

	static func decode(line: Data) -> UsageEvent? {
		guard
			let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
			let generationID = decodedString("generation_id", in: object), !generationID.isEmpty,
			let capturedAt = JSONNumber.double(object["captured_at"]), capturedAt > 0
		else { return nil }

		let conversationID =
			decodedString("conversation_id", in: object).flatMap { $0.isEmpty ? nil : $0 }
			?? "unknown-conversation"
		let model =
			decodedString("model", in: object).flatMap { $0.isEmpty ? nil : $0 }
			?? "cursor"
		let rawInput = JSONNumber.int(object["input_tokens"])
		let output = JSONNumber.int(object["output_tokens"])
		let cacheRead = JSONNumber.int(object["cache_read_tokens"])
		let cacheWrite = JSONNumber.int(object["cache_write_tokens"])
		guard rawInput >= 0, output >= 0, cacheRead >= 0, cacheWrite >= 0 else { return nil }

		// Cursor's hook receives the raw input count. Match Cursor's own stream-JSON normalization:
		// cached reads/writes are subsets of input, so remove them from uncached input exactly once.
		let usage = TokenUsage(
			input: max(0, rawInput - cacheRead - cacheWrite),
			output: output,
			cacheCreate5m: cacheWrite,
			cacheCreate1h: 0,
			cacheRead: cacheRead)
		guard usage.total > 0 else { return nil }

		return UsageEvent(
			messageId: generationID,
			requestId: conversationID,
			provider: .cursor,
			model: model,
			timestamp: Date(timeIntervalSince1970: capturedAt),
			usage: usage)
	}

	private static func decodedString(_ key: String, in object: [String: Any]) -> String? {
		if let value = object[key] as? String { return value }
		guard let encoded = object["\(key)_b64"] as? String,
			let data = Data(base64Encoded: encoded)
		else { return nil }
		return String(data: data, encoding: .utf8)
	}
}
