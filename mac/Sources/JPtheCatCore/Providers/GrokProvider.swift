import Foundation

/// Reads Grok Build CLI usage from `~/.grok/sessions/<encoded-cwd>/<session-id>/updates.jsonl`.
///
/// Correctness model (verified against real local sessions, Grok Build 0.2.99+):
///  - Grok writes every conversation under `GROK_HOME` (default `~/.grok`). Each session directory
///    holds an append-only ACP update stream `updates.jsonl`. The authoritative per-turn token
///    accounting lives on `sessionUpdate == "turn_completed"` rows under `update.usage`.
///  - `usage` carries `inputTokens`, `outputTokens`, `cachedReadTokens`, `reasoningTokens`, and a
///    per-model map `modelUsage`. The invariant `cachedReadTokens ⊆ inputTokens` holds on real
///    sessions; reasoning tokens are billed as output (xAI list prices have no separate reasoning
///    tier). Honest `TokenUsage` mapping:
///      input     = max(0, inputTokens − cachedReadTokens)
///      cacheRead = cachedReadTokens
///      output    = outputTokens + reasoningTokens
///      cacheCreate5m/1h = 0  (Grok exposes no cache-write split)
///  - When `modelUsage` has multiple models, one `UsageEvent` is emitted per model entry so pricing
///    can apply the correct list rate; otherwise a single event uses the only model key, or `"grok"`.
///  - Dedup identity: `messageId` = `<_meta.eventId>-<model>` (eventId is unique per completed turn;
///    the model suffix is ALWAYS applied — never conditioned on the model count — so a re-logged turn
///    can never change its own identity), `requestId` = `prompt_id`. Both are stable across re-reads,
///    so the index keep-max upsert is safe with `canTailAppend = true` (each JSONL line is
///    independently correct). A turn with no `modelUsage` map falls back to `messageId` = eventId.
///  - SuperGrok / X Premium+ subscription dollars are NOT real spend — list-price notional only
///    (same honesty rule as Codex). Official weekly SuperGrok % is NOT in session logs — it only
///    appears when the user opts into `GrokRateLimitCapture` (scrapes Grok's local billing log line
///    into `grok-rate-limits.json`). Without opt-in, no gauge (never invent a % from tokens).
///  - `turn_completed` is written only when a turn ends. Mid-turn billed tokens live on
///    `~/.grok/logs/unified.jsonl` `shell.turn.inference_done` (prompt / cached / completion /
///    reasoning). Overlay = sum(rounds) − sum(`turn_completed`) per session; `_meta.totalTokens`
///    on ACP chunks is context occupancy and is never billed. See `GrokInProgressUsage.swift`.
///
/// STRICT allowlist: index only files named `updates.jsonl` under the sessions tree. The mid-turn
/// overlay additionally reads `logs/unified.jsonl` lines whose `msg` is `shell.turn.inference_done`
/// (sid + numeric ctx only) and `summary.json` `current_model_id`. Never reads `chat_history.jsonl`
/// (prompts), `auth.json`, or `memtrace/`.
public struct GrokProvider: UsageProvider {
	public let id: ProviderID = .grok
	/// Grok home root (`~/.grok` or `$GROK_HOME`). Sessions live at `<root>/sessions/`.
	public let root: URL
	/// Nil in production (the real Application Support capture). Tests that build dashboard rows
	/// pass a temp file so the developer's own Grok capture never leaks into fixtures.
	let rateLimitStoreURL: URL?
	private let reader = JSONLStreamReader()

	public init(root: URL? = nil) {
		self.init(root: root, rateLimitStoreURL: nil)
	}

	init(root: URL?, rateLimitStoreURL: URL?) {
		self.rateLimitStoreURL = rateLimitStoreURL
		if let root {
			self.root = root
		} else if let home = ProcessInfo.processInfo.environment["GROK_HOME"], !home.isEmpty {
			self.root = URL(fileURLWithPath: home, isDirectory: true)
		} else {
			self.root =
				FileManager.default.homeDirectoryForCurrentUser
				.appendingPathComponent(".grok", isDirectory: true)
		}
	}

	public var sessionsRoot: URL {
		root.appendingPathComponent("sessions", isDirectory: true)
	}

	public func watchPaths() -> [URL] {
		[sessionsRoot, root.appendingPathComponent("logs", isDirectory: true)]
	}

	/// True as soon as ONE `updates.jsonl` exists — short-circuits on the first hit rather than
	/// enumerating and sorting the whole sessions tree (the availability check runs on every refresh;
	/// building the full sorted list just to test emptiness was needless per-refresh work, unlike the
	/// O(1) `fileExists` checks the other live providers use).
	public func isAvailable() -> Bool {
		guard
			let enumerator = FileManager.default.enumerator(
				at: sessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		else { return false }
		for case let url as URL in enumerator where url.lastPathComponent == "updates.jsonl" {
			return true
		}
		return false
	}

	/// Official SuperGrok / weekly credit % when the opt-in capture has a fresh reading.
	/// Nil until Settings → Live data → "Enable Grok live limits" has been installed and Grok has
	/// written a billing log line. Never a token-based estimate.
	public func latestRateLimits() -> RateLimitSnapshot? {
		latestRateLimits(now: Date(), storeURL: nil, logURL: nil)
	}

	/// Testable seam behind `latestRateLimits()`. `storeURL`/`logURL` are injectable ONLY for tests —
	/// production always passes `nil` so the real `~/.grok` log + Application Support store are used and
	/// never touched from XCTest (same hygiene rule as `GrokRateLimitStore.load(url:)`).
	func latestRateLimits(now: Date, storeURL: URL?, logURL: URL?) -> RateLimitSnapshot? {
		let storeURL = storeURL ?? rateLimitStoreURL
		// When the capture is installed, re-scrape the log on each read so the dashboard stays current
		// even if a Grok hook hasn't fired since the last billing fetch (JP open, Grok idle).
		if GrokRateLimitCapture.isInstalled(grokHome: root) {
			_ = GrokRateLimitCapture.refreshFromLogs(grokHome: root, logURL: logURL, outputURL: storeURL, now: now)
		}
		return GrokRateLimitStore.load(now: now, url: storeURL)
	}

	/// Flags a just-rolled-over weekly window so the dashboard shows an "awaiting fresh data" hint rather
	/// than a silently blank gauge. Refreshes from the log first (same as `latestRateLimits`) so a fresh
	/// billing line is seen before deciding.
	public func latestRateLimitAwaitingReset(now: Date) -> Bool {
		latestRateLimitAwaitingReset(now: now, storeURL: nil, logURL: nil)
	}

	func latestRateLimitAwaitingReset(now: Date, storeURL: URL?, logURL: URL?) -> Bool {
		let storeURL = storeURL ?? rateLimitStoreURL
		if GrokRateLimitCapture.isInstalled(grokHome: root) {
			_ = GrokRateLimitCapture.refreshFromLogs(grokHome: root, logURL: logURL, outputURL: storeURL, now: now)
		}
		return GrokRateLimitStore.awaitingResetHint(now: now, url: storeURL)
	}

	public func loadEvents() -> [UsageEvent] {
		var dedup = Deduplicator()
		var completedBySid: [String: TokenUsage] = [:]
		let roundsBySid = GrokRequestRounds.bySession(logURL: unifiedLogURL)
		for file in updatesFiles() {
			autoreleasepool {
				let sid = file.deletingLastPathComponent().lastPathComponent
				let parsed = GrokProvider.parseUsage(
					fileURL: file, reader: reader, sessionRounds: roundsBySid[sid] ?? [])
				var sum = TokenUsage()
				for event in parsed {
					dedup.add(event)
					sum += event.usage
				}
				completedBySid[sid, default: TokenUsage()] += sum
			}
		}
		for event in inProgressEvents(completedBySid: completedBySid) {
			dedup.add(event)
		}
		return dedup.events
	}

	/// All `updates.jsonl` files under the sessions tree (recursive). Sorted for stable iteration.
	public func updatesFiles() -> [URL] {
		guard
			let enumerator = FileManager.default.enumerator(
				at: sessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		else { return [] }
		var out: [URL] = []
		for case let url as URL in enumerator where url.lastPathComponent == "updates.jsonl" {
			out.append(url)
		}
		return out.sorted { $0.path < $1.path }
	}

	// MARK: - Detection (Settings row gate)

	/// True when Grok Build is actually present on this Mac — an executable `grok` on common install
	/// paths, or a real sessions tree with at least one `updates.jsonl`. A bare `~/.grok` leftover
	/// after uninstall is NOT enough (same pitfall as Copilot's bare `~/.copilot` directory).
	///
	/// When `home` is supplied (tests / custom `GROK_HOME` fixtures), detection is scoped to THAT
	/// root only — never the live system install paths — so a clean fixture cannot false-positive
	/// because `/opt/homebrew/bin/grok` exists on the host.
	public static func isGrokBuildDetected(home: URL? = nil) -> Bool {
		let fm = FileManager.default
		let explicitHome = home
		let grokHome =
			explicitHome
			?? (ProcessInfo.processInfo.environment["GROK_HOME"].flatMap {
				$0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
			})
			?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)

		// Bundled CLI: `<home>/bin/grok` (install script default).
		let bundled = grokHome.appendingPathComponent("bin/grok")
		if fm.isExecutableFile(atPath: bundled.path) { return true }

		// System install dirs only when probing the real machine (no explicit fixture home).
		if explicitHome == nil {
			let candidates = [
				"/opt/homebrew/bin/grok",
				"/usr/local/bin/grok",
				fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/grok").path,
			]
			if candidates.contains(where: { fm.isExecutableFile(atPath: $0) }) { return true }
		}

		// Real usage footprint: at least one updates.jsonl under sessions/.
		return GrokProvider(root: grokHome).isAvailable()
	}

	// MARK: - Parsing

	/// Parse one `updates.jsonl` into de-duplicated usage events. `project` is recovered from the
	/// URL-encoded cwd folder name when present (`~/.grok/sessions/<encoded-cwd>/<id>/updates.jsonl`).
	static func parseUsage(
		fileURL: URL, reader: JSONLStreamReader = JSONLStreamReader(),
		sessionRounds: [GrokInferenceRound] = []
	) -> [UsageEvent] {
		let project = projectName(fromUpdatesFile: fileURL)
		var events: [UsageEvent] = []
		reader.read(fileURL: fileURL) { data in
			if let decoded = decode(line: data, project: project, sessionRounds: sessionRounds) {
				events.append(contentsOf: decoded)
			}
		}
		return Deduplicator.dedupe(events)
	}

	/// Decode a single JSONL line. Returns zero or more events: one per model in `modelUsage`, or one per
	/// request when `sessionRounds` reconcile exactly with a single-model turn (`GrokRequestRounds`).
	static func decode(
		line: Data, project: String?, sessionRounds: [GrokInferenceRound] = []
	) -> [UsageEvent]? {
		guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
			let params = object["params"] as? [String: Any],
			let update = params["update"] as? [String: Any],
			update["sessionUpdate"] as? String == "turn_completed",
			let usage = update["usage"] as? [String: Any]
		else { return nil }

		let promptId = (update["prompt_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
		let meta = object["_meta"] as? [String: Any]
		let eventId = (meta?["eventId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
		let messageBase = eventId ?? promptId
		guard let messageBase, !messageBase.isEmpty else { return nil }

		let timestamp = decodeTimestamp(object: object, meta: meta)
		let sessionId = params["sessionId"] as? String

		// Prefer the per-model breakdown when present so each model is priced independently.
		if let modelUsage = usage["modelUsage"] as? [String: Any], !modelUsage.isEmpty {
			// One request per event when this turn's retained requests reconcile exactly, so xAI's
			// per-request context premium is decided per request rather than on the turn total.
			if modelUsage.count == 1, let (model, raw) = modelUsage.first,
				let entry = raw as? [String: Any], let tokens = tokenUsage(from: entry),
				let requests = GrokRequestRounds.rounds(
					forTurn: tokens, completedAt: timestamp, in: sessionRounds)
			{
				let modelName = model.isEmpty ? "grok" : model
				return requests.enumerated().map { index, request in
					UsageEvent(
						messageId: "\(messageBase)-\(modelName)-r\(index)",
						requestId: promptId ?? sessionId ?? messageBase,
						provider: .grok,
						model: modelName,
						timestamp: request.timestamp,
						usage: request.usage,
						project: project)
				}
			}
			var out: [UsageEvent] = []
			for (model, raw) in modelUsage {
				guard let entry = raw as? [String: Any] else { continue }
				guard let tokens = tokenUsage(from: entry), tokens.total > 0 else { continue }
				let modelName = model.isEmpty ? "grok" : model
				// ALWAYS suffix the model — never key the suffix on `modelUsage.count`. Keying on the
				// entry count meant the same turn re-logged with a different number of model entries (or
				// a zero-token entry appearing/disappearing) produced a DIFFERENT dedup identity for the
				// count==1 case, letting the keep-max upsert double-count it. A count-independent
				// `<base>-<model>` identity is stable across any re-read. (parserRevision bumped so the
				// index re-reads Grok files once under the new key.)
				let messageId = "\(messageBase)-\(modelName)"
				out.append(
					UsageEvent(
						messageId: messageId,
						requestId: promptId ?? sessionId ?? messageBase,
						provider: .grok,
						model: modelName,
						timestamp: timestamp,
						usage: tokens,
						project: project))
			}
			return out.isEmpty ? nil : out
		}

		guard let tokens = tokenUsage(from: usage), tokens.total > 0 else { return nil }
		return [
			UsageEvent(
				messageId: messageBase,
				requestId: promptId ?? sessionId ?? messageBase,
				provider: .grok,
				model: "grok",
				timestamp: timestamp,
				usage: tokens,
				project: project)
		]
	}

	/// Maps a Grok usage object onto `TokenUsage`. Accepts either the top-level `usage` bag or one
	/// `modelUsage` entry — field names are the same.
	static func tokenUsage(from usage: [String: Any]) -> TokenUsage? {
		let input = JSONNumber.int(usage["inputTokens"])
		let output = JSONNumber.int(usage["outputTokens"])
		let cached = JSONNumber.int(usage["cachedReadTokens"])
		let reasoning = JSONNumber.int(usage["reasoningTokens"])
		// `cached ⊆ input` (clamp defends the invariant); reasoning is billed as output.
		let tokens = TokenUsage(
			input: max(0, input - cached),
			output: output + reasoning,
			cacheCreate5m: 0,
			cacheCreate1h: 0,
			cacheRead: cached)
		return tokens.total > 0 ? tokens : nil
	}

	static func decodeTimestamp(object: [String: Any], meta: [String: Any]?) -> Date {
		// Prefer the agent wall-clock ms stamp (always present on turn_completed); fall back to the
		// top-level integer second timestamp Grok also writes.
		if let ms = JSONNumber.double(meta?["agentTimestampMs"]), ms > 0 {
			return Date(timeIntervalSince1970: ms / 1000.0)
		}
		if let seconds = JSONNumber.double(object["timestamp"]), seconds > 0 {
			// Values > 1e12 are ms; smaller values are seconds.
			return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000.0 : seconds)
		}
		return .distantPast
	}

	/// `.../sessions/<encoded-cwd>/<session-id>/updates.jsonl` → decoded absolute cwd when possible.
	static func projectName(fromUpdatesFile url: URL) -> String? {
		// updates.jsonl → session-id → encoded-cwd
		let encoded = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
		guard !encoded.isEmpty, encoded != "sessions" else { return nil }
		return encoded.removingPercentEncoding ?? encoded
	}
}

// MARK: - IndexableProvider

extension GrokProvider: IndexableProvider {
	public func dataFiles() -> [URL] { updatesFiles() }
	/// Append-only JSONL; each `turn_completed` line is independently correct (no cross-record
	/// reconciliation), so tailing newly appended bytes is safe.
	public var canTailAppend: Bool { true }
	/// 2: the per-model `messageId` suffix is now always applied (was conditioned on model count) — the
	/// bump forces a one-time clean re-read so no stale count-keyed rows linger. See `decode(...)`.
	/// 3: turns whose retained requests reconcile are re-read as one event per request (`GrokRequestRounds`).
	public var parserRevision: Int { 3 }

	public func decodeFile(_ url: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		let project = GrokProvider.projectName(fromUpdatesFile: url)
		let sessionRounds =
			GrokRequestRounds.bySession(logURL: unifiedLogURL)[url.deletingLastPathComponent().lastPathComponent] ?? []
		var events: [UsageEvent] = []
		let consumed = JSONLStreamReader().read(fileURL: url, from: offset) { data in
			if let decoded = GrokProvider.decode(line: data, project: project, sessionRounds: sessionRounds) {
				events.append(contentsOf: decoded)
			}
		}
		return IndexedDecodeResult(events: events, consumed: consumed)
	}

	public func postRefresh(index: UsageIndex, dataFiles: [URL]) throws {
		try syncInProgressUsage(into: index, sessions: dataFiles)
	}
}
