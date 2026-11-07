import Foundation

/// Reads Gemini CLI usage from `~/.gemini/tmp/<projectHash>/chats/session-*.json`.
///
/// Correctness model (verified against real local sessions on this machine):
///  - Each session file is a SINGLE JSON document (not JSONL) rewritten in place on every turn, so
///    we read it whole with `JSONSerialization` and set `canTailAppend = false` — the `.reset`
///    whole-file re-read path in `UsageIndexer`/`FileCursor` covers Gemini verbatim (like Codex).
///    The idempotent keep-max-output upsert makes re-reads safe; unchanged files are skipped by the
///    cursor fingerprint, so steady-state cost is near zero.
///  - Per-message tokens (assistant turns, `type == "gemini"`): the invariant
///    `total == input + output + thoughts + tool` holds with zero mismatches, and `cached ⊆ input`
///    always. So the honest per-turn mapping onto `TokenUsage` is:
///      input     = max(0, input - cached) + tool   // uncached prompt + tool context, at input rate
///      cacheRead = cached                           // Gemini's `cached` is a cache READ, not a write
///      output    = output + thoughts                // Gemini bills thinking/reasoning as output
///    Gemini exposes no cache-CREATION split, so `cacheCreate5m/1h` stay 0.
///  - Dedup identity is content-stable: `messageId` = the per-message UUID `id`, `requestId` =
///    the top-level `sessionId`. Stable across whole-file re-serializations, so the
///    `UNIQUE(provider, msg_id, req_id)` keep-max upsert makes every re-read net-new-only.
///
/// STRICT allowlist (three gates): `pathExtension == "json"`, `lastPathComponent` begins with
/// `session-`, and the parent directory is named `chats`. This excludes `logs.json` (prompts only,
/// no tokens), `oauth_creds.json`, `installation_id`, and the `bin/` tools by construction.
public struct GeminiProvider: UsageProvider {
	public let id: ProviderID = .gemini
	public let root: URL

	public init(root: URL? = nil) {
		self.root =
			root
			?? FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".gemini/tmp", isDirectory: true)
	}

	public func watchPaths() -> [URL] { [root] }

	public func isAvailable() -> Bool { FileManager.default.fileExists(atPath: root.path) }

	public func loadEvents() -> [UsageEvent] {
		var dedup = Deduplicator()
		for file in sessionFiles() {
			// Bound transient memory to one file's worth of parsed objects over a large corpus.
			autoreleasepool {
				for event in GeminiProvider.parseUsage(fileURL: file) { dedup.add(event) }
			}
		}
		return dedup.events
	}

	/// STRICT allowlist: `.json` + `session-` prefix + parent dir named `chats`.
	func sessionFiles() -> [URL] {
		guard
			let enumerator = FileManager.default.enumerator(
				at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		else { return [] }
		var out: [URL] = []
		for case let url as URL in enumerator
		where url.pathExtension == "json"
			&& url.lastPathComponent.hasPrefix("session-")
			&& url.deletingLastPathComponent().lastPathComponent == "chats" {
			out.append(url)
		}
		return out
	}

	// MARK: - Parsing

	private static func date(_ any: Any?) -> Date {
		ISOTimestamp.parse(any as? String)
	}

	/// Parse ONE whole session file into UsageEvents. Never streams lines — a re-serialized JSON
	/// object has no stable line boundaries. On malformed/truncated JSON (a transient mid-write),
	/// returns `[]` and leaves prior index rows intact; the next refresh re-reads the now-complete
	/// file.
	static func parseUsage(fileURL: URL) -> [UsageEvent] {
		guard let data = try? Data(contentsOf: fileURL),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let sessionId = object["sessionId"] as? String, !sessionId.isEmpty,
			let messages = object["messages"] as? [[String: Any]]
		else { return [] }

		var out: [UsageEvent] = []
		var seen = Set<String>()  // within-file dedupe by message id (keep first)

		for message in messages {
			guard message["type"] as? String == "gemini",
				let tokens = message["tokens"] as? [String: Any],
				let msgId = message["id"] as? String, !msgId.isEmpty,
				!seen.contains(msgId)
			else { continue }
			seen.insert(msgId)

			let input = JSONNumber.int(tokens["input"])
			let output = JSONNumber.int(tokens["output"])
			let cached = JSONNumber.int(tokens["cached"])
			let thoughts = JSONNumber.int(tokens["thoughts"])
			let tool = JSONNumber.int(tokens["tool"])

			// `cached ⊆ input` (clamp defends the invariant); `tool` is request context at input rate.
			let usage = TokenUsage(
				input: max(0, input - cached) + tool,
				output: output + thoughts,  // thinking is billed as output
				cacheCreate5m: 0,  // Gemini exposes no cache-creation split
				cacheCreate1h: 0,
				cacheRead: cached
			)
			if usage.total == 0 { continue }  // empty / aborted turn -> emit nothing

			let model = (message["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "gemini"

			out.append(
				UsageEvent(
					messageId: msgId,  // per-message UUID, stable across re-serializations
					requestId: sessionId,  // scopes the UUID to its session
					provider: .gemini,
					model: model,  // RAW string; pricing normalizes at lookup (like Codex)
					timestamp: GeminiProvider.date(message["timestamp"]),
					usage: usage,
					project: nil))  // session files carry only a hashed dir, not a project name
		}
		return out
	}
}
