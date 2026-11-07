import Foundation

/// Reads Claude Code usage from `~/.claude/projects/*/*.jsonl`. Usage lives at `message.usage`
/// (NOT top-level); we take assistant lines with usage that are not API-error messages.
///
/// Decoding uses `JSONSerialization` + tolerant field access (rather than strict `Codable`) so a
/// single odd field never drops an otherwise-valid line — the cost total must not silently lose
/// events.
public struct ClaudeProvider: UsageProvider {
	public let id: ProviderID = .claude
	public let root: URL
	private let reader = JSONLStreamReader()

	public init(root: URL? = nil) {
		self.root =
			root
			?? FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".claude/projects", isDirectory: true)
	}

	public func watchPaths() -> [URL] { [root] }

	public func isAvailable() -> Bool { FileManager.default.fileExists(atPath: root.path) }

	/// Claude's OFFICIAL 5h/weekly windows, when the opt-in statusline capture has written them
	/// (`ClaudeRateLimitStore`). Nil when the capture isn't installed or is stale — we then show no
	/// gauge rather than a reconstructed estimate (token counts can't reproduce Claude's real %).
	public func latestRateLimits() -> RateLimitSnapshot? { ClaudeRateLimitStore.load() }

	/// Flags a just-rolled-over 5h/weekly window so the dashboard shows an "awaiting fresh data" hint
	/// rather than a silently blank gauge (the "bars reset randomly" report). False until the opt-in
	/// capture is installed and fresh.
	public func latestRateLimitAwaitingReset(now: Date) -> Bool {
		ClaudeRateLimitStore.awaitingResetHint(now: now)
	}

	public func loadEvents() -> [UsageEvent] {
		var dedup = Deduplicator()
		for file in jsonlFiles() {
			// Bound transient memory to one file's worth of parsed objects over a GB-scale corpus.
			autoreleasepool {
				reader.read(fileURL: file) { data in
					if let event = ClaudeProvider.decode(line: data) { dedup.add(event) }
				}
			}
		}
		return dedup.events
	}

	func jsonlFiles() -> [URL] {
		guard
			let enumerator = FileManager.default.enumerator(
				at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		else { return [] }
		var out: [URL] = []
		for case let url as URL in enumerator where url.pathExtension == "jsonl" { out.append(url) }
		return out
	}

	// MARK: - Line decoding

	static func decode(line data: Data) -> UsageEvent? {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			object["type"] as? String == "assistant",
			object["isApiErrorMessage"] as? Bool != true,
			let message = object["message"] as? [String: Any],
			let usage = message["usage"] as? [String: Any], !usage.isEmpty,
			let messageId = message["id"] as? String, !messageId.isEmpty,
			let requestId = object["requestId"] as? String, !requestId.isEmpty,
			let model = message["model"] as? String, !model.isEmpty
		else { return nil }

		let create5m: Int
		let create1h: Int
		if let cache = usage["cache_creation"] as? [String: Any] {
			create5m = JSONNumber.int(cache["ephemeral_5m_input_tokens"])
			create1h = JSONNumber.int(cache["ephemeral_1h_input_tokens"])
		} else {
			// Older logs without the split: bill all cache-creation at the 5m rate.
			create5m = JSONNumber.int(usage["cache_creation_input_tokens"])
			create1h = 0
		}

		let tokens = TokenUsage(
			input: JSONNumber.int(usage["input_tokens"]),
			output: JSONNumber.int(usage["output_tokens"]),
			cacheCreate5m: create5m,
			cacheCreate1h: create1h,
			cacheRead: JSONNumber.int(usage["cache_read_input_tokens"])
		)

		let timestamp = ISOTimestamp.parse(object["timestamp"] as? String)
		let project = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
		// Fast mode bills every token category at a premium. `usage.speed` reports the speed that ran
		// (a fast request Opus 4.6 served at standard speed says "standard"), so it alone selects the
		// rate; an id with no fast row stays unpriced rather than billed at the standard rate.
		let isFastMode = usage["speed"] as? String == "fast"
		var accountingModel = isFastMode ? ModelIdentity.fastModeID(model) : model
		// US-only inference multiplies every rate, fast mode included. Only Claude 4.6 and later accept
		// it, so the field alone selects the premium.
		if usage["inference_geo"] as? String == "us" {
			accountingModel = ModelIdentity.usInferenceID(accountingModel)
		}

		return UsageEvent(
			messageId: messageId,
			requestId: requestId,
			provider: .claude,
			model: accountingModel,
			timestamp: timestamp,
			usage: tokens,
			project: project
		)
	}
}
