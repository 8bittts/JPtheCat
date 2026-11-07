import Foundation

private struct CodexParserState: Codable {
	struct StoredWindow: Codable {
		let usedPercent: Double
		let windowMinutes: Int
		let resetsAt: Date?

		init(_ window: RateLimitWindow) {
			usedPercent = window.usedPercent
			windowMinutes = window.windowMinutes
			resetsAt = window.resetsAt
		}

		var value: RateLimitWindow {
			RateLimitWindow(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: resetsAt)
		}
	}

	struct StoredRateLimit: Codable {
		let timestamp: Date
		let primary: StoredWindow?
		let secondary: StoredWindow?
		let planType: String?
		let credits: CodexCreditBalance?
		let creditDataVersion: Int?

		init(_ value: (Date, RateLimitSnapshot)) {
			timestamp = value.0
			primary = value.1.primary.map(StoredWindow.init)
			secondary = value.1.secondary.map(StoredWindow.init)
			planType = value.1.planType
			credits = value.1.credits
			creditDataVersion = 1
		}

		var value: (Date, RateLimitSnapshot) {
			(timestamp, RateLimitSnapshot(
				primary: primary?.value, secondary: secondary?.value, planType: planType,
				capturedAt: timestamp, credits: credits))
		}
	}

	var currentModel: String?
	var currentProject: String?
	var previousInput: Int?
	var previousCached: Int?
	var previousOutput: Int?
	var emittedInput = 0
	var emittedCached = 0
	var emittedOutput = 0
	var ordinal = 0
	var hasUnattributedEvents = false
	var prefixTailFingerprint = ""
	var newestRateLimit: StoredRateLimit?
	var previousRateLimit: StoredRateLimit?

	static func decode(_ raw: String?) -> CodexParserState? {
		guard let raw, let data = raw.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(CodexParserState.self, from: data)
	}

	var encoded: String {
		guard let data = try? JSONEncoder().encode(self) else { return "" }
		return String(decoding: data, as: UTF8.self)
	}
}

/// Process-wide, thread-safe cache from rollout file path -> the (size, mtime) we last read it at and
/// the parsed result, so `CodexProvider.latestRateLimits` doesn't re-open/re-read a file whose cheap
/// `stat()` hasn't moved since we last parsed it. Shared across all `CodexProvider` value-type copies
/// (and both the app and `jpthecat-cli` within one process) since it's keyed on absolute file path.
private final class RateLimitTailCache: @unchecked Sendable {
	private struct Entry {
		let size: Int
		let mtime: Double
		let ctime: Double
		let result: (Date, RateLimitSnapshot)?
	}
	private let lock = NSLock()
	private var entries: [String: Entry] = [:]

	/// Returns `.some(result)` on a cache hit (including a cached "no rate-limit entry in this file"
	/// miss, `result == nil`), or plain `nil` when there is no usable cache entry for this exact
	/// (path, size, mtime) triple.
	func cached(path: String, size: Int, mtime: Double, ctime: Double) -> (Date, RateLimitSnapshot)?? {
		lock.lock()
		defer { lock.unlock() }
		guard let entry = entries[path], entry.size == size, entry.mtime == mtime, entry.ctime == ctime
		else { return nil }
		return .some(entry.result)
	}

	func store(
		path: String, size: Int, mtime: Double, ctime: Double,
		result: (Date, RateLimitSnapshot)?
	) {
		lock.lock()
		defer { lock.unlock() }
		entries[path] = Entry(size: size, mtime: mtime, ctime: ctime, result: result)
	}

	/// Drops cached entries whose rollout file is no longer live, keeping the cache bounded by the
	/// current on-disk file count instead of growing monotonically with every session file ever seen
	/// this process lifetime (Codex writes one `rollout-<ts>-<uuid>.jsonl` per session and prunes old
	/// ones). Only ever removes entries for absent files, so it can never surface stale/wrong data —
	/// worst case a re-read on a path that reappears.
	func retainOnly(livePaths: Set<String>) {
		lock.lock()
		defer { lock.unlock() }
		guard entries.count > livePaths.count else { return }
		entries = entries.filter { livePaths.contains($0.key) }
	}
}

private let rateLimitTailCache = RateLimitTailCache()

/// Reads OpenAI Codex usage from `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// Correctness model (verified against real local sessions):
///  - Usage lives ONLY in `event_msg` lines whose `payload.type == "token_count"`. The authoritative
///    per-session cumulative is `payload.info.total_token_usage`. We reconcile toward that cumulative
///    so duplicate `token_count` re-reports are skipped, one-component counter wobbles correct prior
///    emitted buckets instead of resetting the whole session, and a whole-footprint drop starts a fresh
///    segment. Unlike summing `last_token_usage`, this never double-counts the re-sent context.
///  - `total_token_usage.input_tokens` INCLUDES `cached_input_tokens`; the uncached remainder is the
///    real new input and the cached part is a cache read. `reasoning_output_tokens` ⊂ `output_tokens`
///    (do not add it separately).
///  - The model is NOT in the `token_count` event — it comes from the most-recent preceding
///    `turn_context.payload.model` (`session_meta.model` is null in older sessions).
///  - Because `plan_type == "pro"` is a subscription, the honest headline is `rate_limits`
///    (`used_percent`), surfaced separately via `latestRateLimits()`.
///
/// Never touches the sibling `logs_2.sqlite` / `state_5.sqlite` / `goals_1.sqlite` / `memories_1.sqlite`
/// (over-counting / cost-irrelevant) or `auth.json` — the strict `rollout-*.jsonl` filename allowlist
/// excludes them by construction.
public struct CodexProvider: UsageProvider {
	public let id: ProviderID = .codex
	public let root: URL
	private let reader: JSONLStreamReader

	public init(root: URL? = nil) {
		self.root =
			root
			?? FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".codex/sessions", isDirectory: true)
		self.reader = JSONLStreamReader()
	}

	init(root: URL, reader: JSONLStreamReader) {
		self.root = root
		self.reader = reader
	}

	public func watchPaths() -> [URL] { [root] }

	public func isAvailable() -> Bool { FileManager.default.fileExists(atPath: root.path) }

	public func loadEvents() -> [UsageEvent] {
		var out: [UsageEvent] = []
		for file in rolloutFiles() {
			// Bound transient memory to one file's parsed objects over a large corpus.
			autoreleasepool {
				out.append(contentsOf: Self.parseUsage(fileURL: file, reader: reader))
			}
		}
		return out
	}

	/// The newest rate-limit snapshot by the event's own timestamp — Codex's honest subscription headline.
	/// Filesystem mtimes can be distorted by copy/restore operations, so mtime is not authoritative.
	/// Codex can turn its 5-hour window off and on, so windows stay scoped to this one atomic snapshot:
	/// normalize by `window_minutes`, show weekly-only when 5-hour is absent, and restore 5-hour as soon
	/// as a newer snapshot contains it again. Never mix an older duration into a newer snapshot.
	/// To keep the menubar path practical, each file is checked from the tail first, with a full-file
	/// fallback only for old/sparse logs whose last snapshot is outside the tail sample.
	public func latestRateLimits() -> RateLimitSnapshot? {
		latestRateLimits(now: Date())
	}

	/// The nominal `window_minutes` durations Codex reports for its 5-hour and weekly limits. A window
	/// with any other duration (Codex has been observed to emit a degenerate `window_minutes:0` line for
	/// whole sessions) is not one we can place, and is ignored rather than guessed at.
	static let fiveHourWindowMinutes = 300
	static let weeklyWindowMinutes = 10_080

	/// Testable clock injection for suppressing windows whose reset boundary has arrived.
	public func latestRateLimits(now: Date) -> RateLimitSnapshot? {
		latestRateLimitState(now: now).current
	}

	/// Resolves BOTH the current-window snapshot and the awaiting-reset hint in ONE walk of the rollout
	/// files.
	///
	/// [Regression guard] Resolves BOTH values in ONE walk. Do not split this back into two walks —
	/// `DashboardViewModel.buildRefreshResult` calls both on every refresh.
	///
	/// The two selection rules are deliberately kept SEPARATE (two independent accumulators over two
	/// different filters), not merged: `current` skips any snapshot with no recognized-and-current
	/// 300/10080 window BEFORE its freshest-wins comparison (that's what keeps a degenerate
	/// `window_minutes:0` line from blanking the gauge), while the awaiting-reset accumulator keeps
	/// expired-but-recognized windows so a just-rolled-over one is still visible to the hint.
	/// `awaitingReset` stays false whenever `current != nil`, preserving the old early return.
	public func latestRateLimitState(now: Date) -> (current: RateLimitSnapshot?, awaitingReset: Bool) {
		latestRateLimitState(now: now, persistedStates: nil)
	}

	/// Uses rate-limit snapshots persisted inside the normal Codex file cursors when an index is
	/// available. The indexer has already visited every rollout, so launch does not need a second
	/// multi-thousand-file tail walk merely to rebuild the gauge.
	public func latestRateLimitState(
		now: Date, persistedStates: [String]?
	) -> (current: RateLimitSnapshot?, awaitingReset: Bool) {
		var best: (timestamp: Date, snapshot: RateLimitSnapshot)?
		var bestIgnoringExpiry: (timestamp: Date, snapshot: RateLimitSnapshot)?
		var newestStored: CodexParserState.StoredRateLimit?
		let persisted = persistedStates?.compactMap { state -> (Date, RateLimitSnapshot)? in
			guard let decoded = CodexParserState.decode(state), let stored = decoded.newestRateLimit
			else { return nil }
			if newestStored == nil || stored.timestamp > newestStored!.timestamp { newestStored = stored }
			let previous = decoded.previousRateLimit?.value
			return Self.isRollingZeroPlaceholder(newest: stored.value, previous: previous)
				? nil : stored.value
		}
		var files = persistedStates == nil ? rolloutFiles() : []
		let entries: [(Date, RateLimitSnapshot)] = persisted ?? files.compactMap { file in
			autoreleasepool(invoking: { Self.cachedRateLimitEntry(for: file, reader: reader) })
		}
		func consider(_ found: (Date, RateLimitSnapshot)) {
			// Normalize THIS atomic snapshot by duration and drop expired windows. A snapshot that carries
			// no recognized-and-current 300/10080 window — e.g. a degenerate `window_minutes:0` line — yields
			// nil and is skipped, so it can't blank the gauge while an OLDER atomic snapshot still holds a
			// current window. Windows are never mixed across snapshots: the winner's primary and secondary
			// both come from the one snapshot that won, so a newer weekly-only snapshot still never inherits
			// an older 5-hour value.
			if let current = Self.normalizedCurrentSnapshot(found.1, at: now),
				best == nil || found.0 > best!.timestamp
					|| (found.0 == best!.timestamp && best!.snapshot.credits == nil && current.credits != nil)
			{
				best = (found.0, current)
			}
			let normalized = Self.normalizedIgnoringExpiry(found.1)
			if normalized.primary != nil || normalized.secondary != nil,
				bestIgnoringExpiry == nil || found.0 > bestIgnoringExpiry!.timestamp
			{
				bestIgnoringExpiry = (found.0, normalized)
			}
		}
		for found in entries { consider(found) }
		// Cursors written before rate-limit persistence have no snapshot. Until active Codex output
		// naturally backfills them, inspect only the newest bounded slice rather than restoring the old
		// unbounded all-history walk. Rollout paths are date/time ordered by Codex itself; 128 files spans
		// far beyond one live quota window on the measured corpus while capping launch I/O absolutely.
		let needsCreditBackfill = newestStored != nil && newestStored?.creditDataVersion == nil
		if persistedStates != nil,
			needsCreditBackfill || (best == nil
				&& bestIgnoringExpiry?.snapshot.awaitingFreshDataAfterReset(at: now) != true)
		{
			files = Array(rolloutFiles().sorted { $0.path > $1.path }.prefix(128))
			for file in files {
				if let found = autoreleasepool(invoking: {
					Self.cachedRateLimitEntry(for: file, reader: reader)
				}) { consider(found) }
			}
		}
		// Evict cache entries for rollout files Codex has since rotated away, so the process-lifetime
		// cache stays bounded by the live file count rather than every file ever observed.
		if !files.isEmpty { rateLimitTailCache.retainOnly(livePaths: Set(files.map(\.path))) }
		// An official window stays on screen until its OWN `resets_at` passes — capture age never hides it.
		// Codex records a window only while a CLI turn runs against that quota pool, so a weekly reading
		// can be hours old while usage continues on Codex web, an IDE extension, or a pool Codex reports
		// no windows for. Suppressing the gauge in that state was measured to be WORSE for the user: the
		// row collapsed to an activity sparkline and lost the 7-day reset countdown, which is real,
		// still-valid information. Keep the bar and the countdown; `capturedAt` stays on the snapshot as
		// diagnostic metadata rather than a display gate.
		let awaitingReset = best?.snapshot.primary == nil && best?.snapshot.secondary == nil
			&& (bestIgnoringExpiry?.snapshot.awaitingFreshDataAfterReset(at: now) ?? false)
		return (best?.snapshot, awaitingReset)
	}

	/// Re-sorts one atomic snapshot's windows by `window_minutes` (not the upstream `primary`/`secondary`
	/// slot name — a weekly-only limit can arrive in the `primary` slot) and drops any window whose reset
	/// boundary has passed. Returns nil when the snapshot has no recognized window that is still current.
	/// One snapshot in, one out — never mixes windows across snapshots.
	private static func normalizedCurrentSnapshot(
		_ snapshot: RateLimitSnapshot, at now: Date
	) -> RateLimitSnapshot? {
		let normalized = normalizedIgnoringExpiry(snapshot)
		// A malformed duration must not become a valid replacement merely by carrying credits.
		if snapshot.primary != nil || snapshot.secondary != nil,
			normalized.primary == nil && normalized.secondary == nil { return nil }
		return normalized.current(at: now)
	}

	/// Re-sorts one atomic snapshot's windows by `window_minutes` WITHOUT dropping expired ones — so a
	/// just-rolled-over window is still visible to the "awaiting fresh data after reset" hint. Never
	/// mixes windows across snapshots.
	private static func normalizedIgnoringExpiry(_ snapshot: RateLimitSnapshot) -> RateLimitSnapshot {
		let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
		return RateLimitSnapshot(
			primary: windows.first { $0.windowMinutes == fiveHourWindowMinutes },
			secondary: windows.first { $0.windowMinutes == weeklyWindowMinutes },
			planType: snapshot.planType, capturedAt: snapshot.capturedAt, credits: snapshot.credits)
	}

	/// True when Codex's newest recognized window has just rolled past its reset boundary and no current
	/// window remains — the gauge is blank because the window reset, not because Codex has no data. Drives
	/// the "awaiting fresh data" hint. Reuses the per-file tail cache, so this is cheap.
	public func latestRateLimitAwaitingReset(now: Date) -> Bool {
		latestRateLimitState(now: now).awaitingReset
	}

	/// [Regression guard] Caches per-file tail results keyed on `(size, mtime, ctime)` so a refresh only
	/// re-reads changed files; re-reading every rollout tail (up to 1MB) unconditionally is the
	/// regression this guards. It does NOT change the cross-file "freshest by internal timestamp"
	/// selection above (still fully re-evaluated every call) — it only skips re-parsing a file whose own
	/// cheap `stat()` says nothing moved. This is a NARROWER, safer claim than trusting mtime for
	/// cross-file recency
	/// (which the doc comment above and `CodexProviderTests
	/// .testLatestRateLimitsUsesNewestTokenCountTimestampAcrossFiles` correctly distrust) — we are only
	/// trusting "this specific file's own state, as we last observed it ourselves, hasn't moved."
	private static func cachedRateLimitEntry(for file: URL, reader: JSONLStreamReader) -> (Date, RateLimitSnapshot)? {
		guard let state = FileCursor.state(fileURL: file) else {
			let tail = latestRateLimitsFromTail(fileURL: file)
			return tail.foundRecord ? tail.value : latestRateLimits(fileURL: file, reader: reader)
		}
		if let cached = rateLimitTailCache.cached(
			path: file.path, size: state.size, mtime: state.mtime, ctime: state.ctime)
		{
			return cached
		}
		let tail = latestRateLimitsFromTail(fileURL: file)
		let result = tail.foundRecord ? tail.value : latestRateLimits(fileURL: file, reader: reader)
		rateLimitTailCache.store(
			path: file.path, size: state.size, mtime: state.mtime, ctime: state.ctime, result: result)
		return result
	}

	/// STRICT allowlist: only `rollout-*.jsonl`. This alone excludes `auth.json`, every `*.sqlite`
	/// (+ their `-wal`/`-shm`), and any other sibling — none of which match.
	func rolloutFiles() -> [URL] {
		guard
			let enumerator = FileManager.default.enumerator(
				at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		else { return [] }
		var out: [URL] = []
		for case let url as URL in enumerator
		where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
			out.append(url)
		}
		return out
	}

	// MARK: - Parsing

	private static func date(_ any: Any?) -> Date {
		ISOTimestamp.parse(any as? String)
	}

	/// The session UUID embedded in `rollout-<timestamp>-<uuid>.jsonl`. We key synthetic event ids on
	/// the FILE uuid, not `session_meta.session_id`, because a resumed/forked session can reuse the
	/// same `session_id` across two files (whose per-file ordinals would then collide).
	static func fileUUID(from filename: String) -> String {
		let pattern =
			"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
		if let range = filename.range(of: pattern, options: .regularExpression) {
			return String(filename[range])
		}
		return (filename as NSString).deletingPathExtension
	}

	static func parseUsage(fileURL: URL, reader: JSONLStreamReader) -> [UsageEvent] {
		parseIndexedUsage(fileURL: fileURL, reader: reader, from: 0, parserState: nil).events
	}

	static func parseIndexedUsage(
		fileURL: URL, reader: JSONLStreamReader, from offset: Int, parserState rawState: String?
	) -> IndexedDecodeResult {
		let uuid = fileUUID(from: fileURL.lastPathComponent)
		let restoredState = CodexParserState.decode(rawState)
		if offset > 0, restoredState == nil {
			return IndexedDecodeResult(events: [], consumed: offset, requiresFullReset: true)
		}
		let isIncremental = offset > 0 && restoredState != nil
		let initial = restoredState ?? CodexParserState()
		if isIncremental,
			initial.prefixTailFingerprint != prefixTailFingerprint(fileURL: fileURL, through: offset)
		{
			return IndexedDecodeResult(events: [], consumed: offset, requiresFullReset: true)
		}
		var out: [UsageEvent] = []
		var currentModel = initial.currentModel
		var currentProject = initial.currentProject
		var previous: (input: Int, cached: Int, output: Int)? = {
			guard let input = initial.previousInput, let cached = initial.previousCached,
				let output = initial.previousOutput
			else { return nil }
			return (input, cached, output)
		}()
		var emitted = (
			input: initial.emittedInput, cached: initial.emittedCached,
			output: initial.emittedOutput)
		var ordinal = initial.ordinal
		var hasUnattributedEvents = initial.hasUnattributedEvents
		var newestRateLimit = initial.newestRateLimit
		var previousRateLimit = initial.previousRateLimit
		var requiresFullReset = false

		enum UsageBucket { case input, cached, output }

		func replacingUsage(_ event: UsageEvent, usage: TokenUsage) -> UsageEvent {
			UsageEvent(
				messageId: event.messageId, requestId: event.requestId, provider: event.provider,
				model: event.model, timestamp: event.timestamp, usage: usage, project: event.project)
		}

		func recordModel(_ model: String) {
			currentModel = model
			// Some resumed/compacted rollout files replay cumulative token snapshots before their first
			// model-bearing turn_context. Once this same file supplies the authoritative model, attach it
			// to those early deltas instead of leaving a permanent "unknown Codex model" omission. Files
			// that never declare a model remain empty/unpriced; no model or price is guessed.
			guard hasUnattributedEvents else { return }
			if isIncremental {
				requiresFullReset = true
				return
			}
			for index in out.indices where out[index].model.isEmpty {
				let event = out[index]
				out[index] = UsageEvent(
					messageId: event.messageId, requestId: event.requestId, provider: event.provider,
					model: model, timestamp: event.timestamp, usage: event.usage, project: event.project)
			}
			hasUnattributedEvents = false
		}

		func reduceEmitted(_ bucket: UsageBucket, by amount: Int) {
			guard !out.isEmpty else { return }
			var remaining = amount
			var index = out.index(before: out.endIndex)
			while remaining > 0, index >= out.startIndex {
				var usage = out[index].usage
				let available: Int
				switch bucket {
				case .input: available = usage.input
				case .cached: available = usage.cacheRead
				case .output: available = usage.output
				}
				let take = min(available, remaining)
				if take > 0 {
					let previousIndex = index == out.startIndex ? nil : out.index(before: index)
					switch bucket {
					case .input: usage.input -= take
					case .cached: usage.cacheRead -= take
					case .output: usage.output -= take
					}
					if usage.total == 0 {
						out.remove(at: index)
					} else {
						out[index] = replacingUsage(out[index], usage: usage)
					}
					remaining -= take
					guard let previousIndex else { break }
					index = previousIndex
				} else {
					if index == out.startIndex { break }
					index = out.index(before: index)
				}
			}
		}

		let consumed = reader.read(fileURL: fileURL, from: offset) { data in
			guard !requiresFullReset else { return }
			if let rateLimit = rateLimitSnapshot(from: data) {
				previousRateLimit = newestRateLimit
				newestRateLimit = CodexParserState.StoredRateLimit(rateLimit)
			}
			guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				let type = object["type"] as? String
			else { return }
			let payload = object["payload"] as? [String: Any]

			switch type {
			case "session_meta":
				if let cwd = payload?["cwd"] as? String {
					currentProject = URL(fileURLWithPath: cwd).lastPathComponent
				}
				if currentModel == nil, let model = payload?["model"] as? String, !model.isEmpty {
					recordModel(model)
				}

			case "turn_context":
				if let cwd = payload?["cwd"] as? String {
					currentProject = URL(fileURLWithPath: cwd).lastPathComponent
				}
				if let model = payload?["model"] as? String, !model.isEmpty {
					recordModel(model)
				} else if
					let settings = (payload?["collaboration_mode"] as? [String: Any])?["settings"]
						as? [String: Any],
					let model = settings["model"] as? String, !model.isEmpty
				{
					recordModel(model)
				}

			case "event_msg":
				guard payload?["type"] as? String == "token_count",
					let info = payload?["info"] as? [String: Any],
					let total = info["total_token_usage"] as? [String: Any]
				else { return }

				let ti = JSONNumber.int(total["input_tokens"])
				let tc = JSONNumber.int(total["cached_input_tokens"])
				let to = JSONNumber.int(total["output_tokens"])

				if let previous {
					let previousSum = previous.input + previous.cached + previous.output
					// Only a LARGE cumulative drop (below half the prior footprint) is a genuine session
					// counter reset that should start a fresh segment. Smaller decreases are counter
					// wobbles/corrections and are reconciled against the cumulative below (reduceEmitted);
					// treating them as resets would ~2x double-count. (No real on-disk session exhibits ANY
					// cumulative decrease — `total_token_usage` is monotonic — so this only guards a
					// hypothetical format change; integer compare avoids float.)
					if (ti + tc + to) * 2 < previousSum {
						emitted = (0, 0, 0)
					}
				}
				previous = (ti, tc, to)

				let targetInput = max(0, ti - tc)
				let targetCached = tc
				let targetOutput = to
				if isIncremental,
					targetInput < emitted.input || targetCached < emitted.cached
						|| targetOutput < emitted.output
				{
					requiresFullReset = true
					return
				}

				if targetInput < emitted.input {
					reduceEmitted(.input, by: emitted.input - targetInput)
					emitted.input = targetInput
				}
				if targetCached < emitted.cached {
					reduceEmitted(.cached, by: emitted.cached - targetCached)
					emitted.cached = targetCached
				}
				if targetOutput < emitted.output {
					reduceEmitted(.output, by: emitted.output - targetOutput)
					emitted.output = targetOutput
				}

				let deltaInput = targetInput - emitted.input
				let deltaCached = targetCached - emitted.cached
				let deltaOutput = targetOutput - emitted.output

				if deltaInput == 0, deltaCached == 0, deltaOutput == 0 { return }

				let usage = TokenUsage(
					input: deltaInput,
					output: deltaOutput,  // reasoning is already inside output
					cacheCreate5m: 0,
					cacheCreate1h: 0,
					cacheRead: deltaCached
				)
				out.append(
					UsageEvent(
						messageId: uuid, requestId: String(ordinal), provider: .codex,
						model: currentModel ?? "", timestamp: date(object["timestamp"]),
						usage: usage, project: currentProject))
				if currentModel == nil { hasUnattributedEvents = true }
				ordinal += 1
				emitted.input += deltaInput
				emitted.cached += deltaCached
				emitted.output += deltaOutput

			default:
				return
			}
		}
		let state = CodexParserState(
			currentModel: currentModel, currentProject: currentProject,
			previousInput: previous?.input, previousCached: previous?.cached,
			previousOutput: previous?.output, emittedInput: emitted.input,
			emittedCached: emitted.cached, emittedOutput: emitted.output, ordinal: ordinal,
			hasUnattributedEvents: hasUnattributedEvents,
			prefixTailFingerprint: prefixTailFingerprint(fileURL: fileURL, through: consumed),
			newestRateLimit: newestRateLimit, previousRateLimit: previousRateLimit)
		return IndexedDecodeResult(
			events: requiresFullReset ? [] : out, consumed: consumed, parserState: state.encoded,
			requiresFullReset: requiresFullReset)
	}

	private static func prefixTailFingerprint(fileURL: URL, through offset: Int) -> String {
		guard offset > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
		defer { try? handle.close() }
		let count = min(4_096, offset)
		do {
			try handle.seek(toOffset: UInt64(offset - count))
			guard let data = try handle.read(upToCount: count), data.count == count else { return "" }
			var hash: UInt64 = 14_695_981_039_346_656_037
			for byte in data {
				hash ^= UInt64(byte)
				hash &*= 1_099_511_628_211
			}
			return "\(offset):\(String(hash, radix: 16))"
		} catch {
			return ""
		}
	}

	static func latestRateLimits(fileURL: URL, reader: JSONLStreamReader) -> (Date, RateLimitSnapshot)? {
		var newest: (Date, RateLimitSnapshot)?
		var previous: (Date, RateLimitSnapshot)?
		reader.read(fileURL: fileURL) { data in
			guard let snapshot = rateLimitSnapshot(from: data) else { return }
			// Files are chronological; retain the final pair so a rolling-zero placeholder can be
			// distinguished from a genuine 0% reading with one fixed reset boundary.
			previous = newest
			newest = snapshot
		}
		guard let newest else { return nil }
		return isRollingZeroPlaceholder(newest: newest, previous: previous) ? nil : newest
	}

	private struct TailRateLimitResult {
		let foundRecord: Bool
		let value: (Date, RateLimitSnapshot)?
	}

	private static func latestRateLimitsFromTail(
		fileURL: URL, maxBytes: UInt64 = 1_048_576
	) -> TailRateLimitResult {
		let matches = JSONLStreamReader.matchingTail(
			fileURL: fileURL, maxBytes: maxBytes, limit: 2
		) {
			rateLimitSnapshot(from: $0)
		}
		guard let newest = matches.first else {
			return TailRateLimitResult(foundRecord: false, value: nil)
		}
		let value = isRollingZeroPlaceholder(newest: newest, previous: matches.dropFirst().first)
			? nil
			: newest
		return TailRateLimitResult(foundRecord: true, value: value)
	}

	/// Some long-running Codex sessions emit a synthetic weekly-looking `0%` whose `resets_at`
	/// advances by exactly the same amount as every token-count timestamp. Concurrent normal sessions
	/// keep reporting the real usage against one fixed reset boundary, so choosing the newest timestamp
	/// makes the synthetic stream repeatedly overwrite the real menu-bar/dashboard value with 0%.
	///
	/// A genuine post-reset 0% keeps one fixed boundary across successive records. Reject only the
	/// narrow moving-boundary signature: weekly-only, zero in both consecutive snapshots, and matching
	/// positive timestamp/reset deltas.
	private static func isRollingZeroPlaceholder(
		newest: (Date, RateLimitSnapshot),
		previous: (Date, RateLimitSnapshot)?
	) -> Bool {
		guard let previous else { return false }
		let latest = normalizedIgnoringExpiry(newest.1)
		let prior = normalizedIgnoringExpiry(previous.1)
		guard latest.primary == nil, prior.primary == nil,
			let latestWeekly = latest.secondary, let priorWeekly = prior.secondary,
			latestWeekly.usedPercent == 0, priorWeekly.usedPercent == 0,
			let latestReset = latestWeekly.resetsAt, let priorReset = priorWeekly.resetsAt
		else { return false }
		let timestampDelta = newest.0.timeIntervalSince(previous.0)
		let resetDelta = latestReset.timeIntervalSince(priorReset)
		return timestampDelta > 0 && abs(timestampDelta - resetDelta) <= 2
	}

	private static func rateLimitSnapshot(from data: Data) -> (Date, RateLimitSnapshot)? {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			object["type"] as? String == "event_msg",
			let payload = object["payload"] as? [String: Any],
			payload["type"] as? String == "token_count",
			let limits = payload["rate_limits"] as? [String: Any],
			isAccountRateLimit(limits),
			let snapshot = snapshot(from: limits)
		else { return nil }
		let capturedAt = date(object["timestamp"])
		return (capturedAt, snapshot.stamped(capturedAt: capturedAt))
	}

	/// Codex can multiplex the account subscription quota and separate model-specific quotas through
	/// the same `rate_limits` field.
	/// The dashboard/menu bar headline is the account quota, whose canonical identifier is `codex`.
	/// Keep accepting identifier-less records written by older Codex versions, but never let a named
	/// model/add-on limit (for example `codex_bengalfox`) win merely because it emitted more recently.
	private static func isAccountRateLimit(_ limits: [String: Any]) -> Bool {
		guard let limitID = limits["limit_id"] as? String else { return true }
		return limitID == "codex"
	}

	static func snapshot(from limits: [String: Any]) -> RateLimitSnapshot? {
		func window(_ key: String) -> RateLimitWindow? {
			guard let raw = limits[key] as? [String: Any],
				let used = JSONNumber.double(raw["used_percent"])
			else { return nil }
			let resets = JSONNumber.double(raw["resets_at"]).map { Date(timeIntervalSince1970: $0) }
			return RateLimitWindow(
				usedPercent: used, windowMinutes: JSONNumber.int(raw["window_minutes"]), resetsAt: resets)
		}
		let primary = window("primary")
		let secondary = window("secondary")
		let credits = CodexCreditBalance(json: limits["credits"])
		if primary == nil, secondary == nil, credits == nil { return nil }
		return RateLimitSnapshot(
			primary: primary, secondary: secondary, planType: limits["plan_type"] as? String,
			credits: credits)
	}
}
