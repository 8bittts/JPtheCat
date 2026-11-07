import Darwin
import Foundation

/// Byte size of `url` from ONE `stat(2)`; `0` when it can't be stat'd.
///
/// [Why this exists] The four-line
/// `((try? FileManager.default.attributesOfItem(atPath:))?[.size] as? NSNumber)?.intValue ?? 0`
/// incantation was repeated at five call sites in this module, and every one of them bridges an
/// 18-entry `NSDictionary` — the exact allocation `FileCursor.state(fileURL:)` was introduced to
/// remove from this file's per-file prologue (see the comment on that call in `refresh`).
enum FileByteSize {
	static func of(_ url: URL) -> Int { FileCursor.state(fileURL: url)?.size ?? 0 }
}

/// How a `.reset` (new / truncated / rotated / rewritten file) is re-read and reconciled.
public enum ResetPolicy: Sendable, Equatable {
	/// Re-read the whole file and REPLACE every event previously indexed from it. The default, and the
	/// only safe choice for a source whose existing records can change in place (Codex telescoping,
	/// Gemini's rewritten session doc, an OpenCode session row's cumulative counters).
	case rereadWhole
	/// Re-read the whole file but KEEP the events already indexed from it. Only for an append-only
	/// source JP ITSELF owns, where a reset can mean nothing but truncation or rotation — never an
	/// in-place rewrite of a record that is still present.
	case rereadWholeRetainingIndexedEvents
	/// Re-read only the records at or after the watermark carried in the cursor's `offset` field, and
	/// keep everything already indexed below it. For a mutating store whose records carry a monotonic
	/// ordering key (Muse Spark's `message.$.time.created`). The first pass, and any pass after a
	/// `parserRevision` bump, still starts from `0` and still replaces the whole file's events.
	case watermark
}

public struct IndexedDecodeResult: Sendable {
	public let events: [UsageEvent]
	public let consumed: Int
	public let parserState: String
	public let requiresFullReset: Bool
	/// A mutable source can rewind the replacement range when an older record changes.
	public let replacementTimestamp: Date?
	public let succeeded: Bool

	public init(
		events: [UsageEvent], consumed: Int, parserState: String = "",
		requiresFullReset: Bool = false, replacementTimestamp: Date? = nil, succeeded: Bool = true
	) {
		self.events = events
		self.consumed = consumed
		self.parserState = parserState
		self.requiresFullReset = requiresFullReset
		self.replacementTimestamp = replacementTimestamp
		self.succeeded = succeeded
	}
}

/// A provider the indexer can ingest incrementally.
public protocol IndexableProvider: UsageProvider {
	/// The (already allowlisted) data files to consider.
	func dataFiles() -> [URL]

	/// True if a grown file can be tailed from the last byte offset (append-only, line-independent
	/// parse — Claude). False for a stateful parse that must re-read a changed file whole (Codex
	/// telescoping); idempotent keep-max-output upsert makes the whole re-read safe.
	var canTailAppend: Bool { get }

	/// Increment when a parser fix must repair rows already indexed from unchanged source files.
	var parserRevision: Int { get }

	/// How a `.reset` on this provider's files is re-read and reconciled. Defaults to `.rereadWhole`.
	var resetPolicy: ResetPolicy { get }

	/// Decode events from one file starting at byte `offset`, returning events, the consumed offset,
	/// and any state needed to resume. Whole-file providers ignore `offset`. Returned events may contain
	/// intra-file duplicates — the index dedupes.
	func decodeFile(_ url: URL, from offset: Int, parserState: String?) -> IndexedDecodeResult

	/// For a `.watermark` provider: the `UsageEvent.timestamp` its cursor watermark corresponds to, so
	/// a `.reset` can delete EXACTLY the range it is about to re-read. The watermark's unit is the
	/// provider's own (Muse Spark's is `$.time.created` in MILLISECONDS, not seconds and not bytes), so
	/// only the provider can express this. `nil` means "cannot be expressed" and suppresses the
	/// range-scoped delete rather than guessing a bound and deleting real history.
	func watermarkTimestamp(_ watermark: Int) -> Date?

	/// Extra ingest after the file walk. Grok uses this for mid-turn `inference_done` overlay rows
	/// that are not independently append-safe with `turn_completed`. Default no-op.
	func postRefresh(index: UsageIndex, dataFiles: [URL]) throws
}

extension IndexableProvider {
	public var resetPolicy: ResetPolicy { .rereadWhole }
	/// Every non-`.watermark` provider replaces or retains whole files, so it never needs this.
	public func watermarkTimestamp(_ watermark: Int) -> Date? { nil }
	public func postRefresh(index: UsageIndex, dataFiles: [URL]) throws {}
}

/// Walks a provider's files and ingests only what changed since the last refresh: unchanged files
/// are skipped (the full-corpus-walk killer), grown append-only files are tailed from their offset,
/// and new/truncated/stateful files are re-read whole. All ingests are idempotent.
public struct UsageIndexer {
	public enum RefreshError: Error { case sourceDecodeFailed(ProviderID) }
	public let index: UsageIndex
	public init(index: UsageIndex) { self.index = index }

	public struct Stats: Sendable, Equatable {
		public var filesRead = 0
		public var filesSkipped = 0
		public var eventsIngested = 0
		/// Files that paid a real `FileCursor.fingerprint` open+read this pass.
		///
		/// [Why this exists] `filesSkipped` is incremented at BOTH the cheap `(size, mtime, ctime)` skip
		/// AND at `.unchanged` — which is only reached AFTER paying a full fingerprint read. So
		/// `filesRead == 0, filesSkipped == 1` reported identically whether the expensive read happened
		/// or not, which made `UsageIndexTests.testColdStartSkipsFingerprintReadViaPersistedCtime` unable
		/// to fail: its name claimed something its assertions could not observe. This counter is the
		/// signal that distinguishes the two, so the cold-start guard is load-bearing.
		public var fingerprintReads = 0
	}

	@discardableResult
	public func refresh(_ provider: some IndexableProvider) throws -> Stats {
		var stats = Stats()
		let files = provider.dataFiles()
		// Resolved ONCE: a provider may compute this from its own `dataFiles()` (Muse Spark picks a
		// different policy for the DB than for the legacy log), so reading it per use would re-stat.
		let resetPolicy = provider.resetPolicy
		let currentPaths = Set(files.map(\.path))
		// [Phase 3 — durable retention beyond provider rotation.] When a provider rotates/prunes its OWN
		// logs, a file we were tracking vanishes from `dataFiles()`. JP is a warehouse: the whole point
		// is to OUTLIVE the provider's own retention, so we KEEP that file's already-indexed events (we
		// do NOT `deleteEvents` here anymore). The (provider, msg_id, req_id) PK excludes the source path
		// (an interned `path_id` today), so a rotated-away file re-appearing can't double-count — proven
		// by `UsageIndexRetentionTests`.
		//
		// We only FORGET the file (drop its cursor + verified-state entry). Crucially the candidate set
		// is `cursorPaths(provider:)` — the cursors we still hold for THIS provider, bounded by the LIVE
		// file count — NOT the events' source paths, which grow without bound as history is retained.
		// Dropping the cursor removes the rotated-away path from this set next refresh, so per-refresh
		// work scales with CURRENT files, never with retained history (the freeze/memory anti-pattern the
		// postmortem burned us on). A path that later re-appears with NEW content still hits `.reset`
		// below (cursor gone -> read whole), which re-ingests it cleanly.
		for stalePath in try index.cursorPaths(provider: provider.id).subtracting(currentPaths) {
			try index.deleteCursor(path: stalePath, provider: provider.id)
		}
		for url in files {
			// ONE `stat(2)` for all three fields. This used to be `attributesOfItem` (a bridged 18-entry
			// NSDictionary) PLUS a separate `changeTime` stat — two syscalls and ~18 boxed Foundation
			// objects per file, ~10,350 times per pass. `FileCursor.state` reproduces the same mtime
			// BIT-FOR-BIT (see its doc — the naive derivation diverges on ~25% of real files), so every
			// already-persisted cursor still matches and no re-fingerprint is forced.
			guard let live = FileCursor.indexedState(fileURL: url) else { continue }
			let size = live.size
			let mtime = live.mtime
			let stored = index.cursor(for: url.path, provider: provider.id)
			let ctime: Double? = live.ctime

			// [Regression guard] (size, mtime) alone is unsafe: mtime-preserving rewrites (`rsync --times`,
			// `cp -p`, `touch -r`) leave both unchanged while bytes change. `ctime` is kernel-bumped and
			// can't be spoofed. Guard: `UsageIndexTests.testSameSizeSameMtimeRewriteIsDetected`. Do not
			// reintroduce a size+mtime-only fast path.
			//
			// Only this provider's persisted cursor proves it has consumed this file state.
			let persistedVerified =
				ctime.map { live in
					guard let stored, stored.ctime > 0 else { return false }
					return stored.size == size && stored.mtime == mtime && stored.ctime == live
						&& stored.parserRevision == provider.parserRevision
				} ?? false
			if persistedVerified {
				stats.filesSkipped += 1
				// One-time provider backfill for a file that ALWAYS skips (so it never rewrites its
				// cursor): without this its cursor keeps provider='' and the retention sweep above could
				// never scope it, leaking the cursor row once the file rotates away. After the first
				// backfill `stored.provider` matches and this is a no-op.
				if stored?.provider != provider.id.rawValue {
					try index.setCursorProvider(path: url.path, provider: provider.id)
				}
				continue
			}

			stats.fingerprintReads += 1
			let fingerprint = FileCursor.indexedFingerprint(fileURL: url)

			let revisionMatchedStored = stored?.parserRevision == provider.parserRevision ? stored : nil
			let change = FileCursor.classify(
				size: size, mtime: mtime, fingerprint: fingerprint, stored: revisionMatchedStored,
				canTailAppend: provider.canTailAppend)

			let from: Int
			switch change {
			case .unchanged:
				stats.filesSkipped += 1
				// Backfill the persisted ctime even on a skip — the file's content is confirmed
				// unchanged (fingerprint matched), so future launches should skip it via the cheap
				// ctime-only fast path above instead of paying for this fingerprint read again.
				if let stored, let ctime {
					try? index.setCursor(
						path: url.path, size: stored.size, mtime: stored.mtime, offset: stored.offset,
						fingerprint: stored.fingerprint, ctime: ctime, provider: provider.id,
						parserRevision: provider.parserRevision, parserState: stored.parserState)
				}
				continue
			case .appended(let offset):
				from = offset
			case .reset:
				// A `.watermark` provider resumes from the monotonic key its LAST accepted decode
				// reached, carried in the cursor's `offset` field. `revisionMatchedStored` (not `stored`)
				// on purpose: a `parserRevision` bump must fall back to a full re-read, which is exactly
				// what makes a change in the field's MEANING safe to ship.
				from = resetPolicy == .watermark ? (revisionMatchedStored?.offset ?? 0) : 0
			}

			// Bound transient memory to one file's worth of parsed objects over a GB-scale corpus —
			// `decodeFile` produces a whole-file `Data` plus per-line `Data`/`JSONSerialization` objects
			// that would otherwise autorelease into the enclosing pool and pile up across every file of a
			// cold-start full-corpus walk (a real first-launch memory-peak driver). Mirrors the identical
			// per-file `autoreleasepool` that `ClaudeProvider`/`CodexProvider`/`GrokProvider` `loadEvents()`
			// already wrap their decode in; the reindex path was the one hot decode loop missing it.
			let ingestedCount = try autoreleasepool { () -> Int in
				var decoded = provider.decodeFile(
					url, from: from, parserState: revisionMatchedStored?.parserState)
				var resetRequired: Bool
				if case .reset = change { resetRequired = true } else { resetRequired = false }
				if decoded.requiresFullReset {
					decoded = provider.decodeFile(url, from: 0, parserState: nil)
					resetRequired = true
				}
				guard decoded.succeeded else { throw RefreshError.sourceDecodeFailed(provider.id) }
			if resetRequired {
				switch Self.resetDeletion(policy: resetPolicy, from: from) {
				case .none:
					break
				case .wholeSourcePath:
					// Scope by provider so shared-source-path providers (OpenCode-derived:
					// MiMo, Nemotron, Big Pickle, DeepSeek) don't delete each other's events.
					try index.deleteEvents(sourcePath: url.path, provider: provider.id)
				case .atOrAfterWatermark:
					// Scope the delete to exactly the range `decodeFile` just re-read. A record edited
					// (or removed) inside that range is therefore genuinely REPLACED, while the retained
					// history below the watermark is untouched. A provider that cannot express its
					// watermark as a timestamp degrades to the previous "delete nothing" behavior.
					if let boundary = decoded.replacementTimestamp ?? provider.watermarkTimestamp(from) {
						try index.deleteEvents(
							sourcePath: url.path, provider: provider.id, timestampAtOrAfter: boundary)
					}
				}
			}
				try index.ingest(decoded.events, sourcePath: url.path)
				try index.setCursor(
					path: url.path, size: size, mtime: mtime, offset: decoded.consumed,
					fingerprint: fingerprint, ctime: ctime ?? 0, provider: provider.id,
					parserRevision: provider.parserRevision, parserState: decoded.parserState)
				return decoded.events.count
			}
			stats.filesRead += 1
			stats.eventsIngested += ingestedCount
		}
		try provider.postRefresh(index: index, dataFiles: files)
		// Foundation's JSON decoder can leave emptied large malloc regions resident after a changed-file
		// pass. Ask Darwin to return those FREE pages only after real decode work; skip-only polls avoid
		// the zone walk entirely. This changes allocator residency, never live objects or indexed data.
		if stats.filesRead > 0 { malloc_zone_pressure_relief(nil, 0) }
		return stats
	}

	/// How much of a file's already-indexed history a `.reset` wipes before re-ingesting.
	public enum ResetDeletion: Sendable, Equatable {
		/// Keep every indexed event for this file.
		case none
		/// Replace the file wholesale: delete every event ever indexed from this source path.
		case wholeSourcePath
		/// Replace only the suffix the re-read actually covers — every event at or after the cursor
		/// watermark. Requires `IndexableProvider.watermarkTimestamp` to express the bound.
		case atOrAfterWatermark
	}

	/// [CRITICAL] `.wholeSourcePath` is the default and stays the answer for every whole-file re-read,
	/// because a stateful source can change records that are still present and a stale row would
	/// otherwise survive forever. The two departures are narrow and each has a proof obligation:
	/// - `.rereadWholeRetainingIndexedEvents` — the source is append-only and JP-owned, so a reset can
	///   only be truncation or rotation. Wiping there would DELETE warehouse history the app itself
	///   just trimmed (`CursorHookSetup`'s hook caps its capture file), which is the opposite of the
	///   durable-retention rule the stale-cursor sweep above implements.
	/// - `.watermark` with `from > 0` — the re-read covers only records at or above the watermark, so
	///   only that RANGE may be replaced; everything below it is retained history the bounded decode
	///   never even looked at, and wiping it is the lifetime-set churn the watermark exists to stop.
	///   `from == 0` is the first pass (or a `parserRevision` bump), which still replaces everything.
	static func resetDeletion(policy: ResetPolicy, from: Int) -> ResetDeletion {
		switch policy {
		case .rereadWhole: return .wholeSourcePath
		case .rereadWholeRetainingIndexedEvents: return .none
		case .watermark: return from == 0 ? .wholeSourcePath : .atOrAfterWatermark
		}
	}

	/// Whether a `.reset` wipes the file's events WHOLESALE — the narrow question the original guard
	/// asked, kept as a derived helper so that guard's intent stays pinned after the range-scoped
	/// `.atOrAfterWatermark` case was split out of it.
	static func resetDeletesIndexedEvents(policy: ResetPolicy, from: Int) -> Bool {
		resetDeletion(policy: policy, from: from) == .wholeSourcePath
	}
}

// MARK: - Provider conformances

extension ClaudeProvider: IndexableProvider {
	public func dataFiles() -> [URL] { jsonlFiles() }
	public var canTailAppend: Bool { true }  // append-only JSONL, each line independent
	/// 2 re-reads indexed turns so fast-mode and US-only inference turns move to their accounting ids.
	public var parserRevision: Int { 2 }

	public func decodeFile(_ url: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		var events: [UsageEvent] = []
		let consumed = JSONLStreamReader().read(fileURL: url, from: offset) { data in
			if let event = ClaudeProvider.decode(line: data) { events.append(event) }
		}
		return IndexedDecodeResult(events: events, consumed: consumed)
	}
}

extension CodexProvider: IndexableProvider {
	public func dataFiles() -> [URL] { rolloutFiles() }
	public var canTailAppend: Bool { true }
	/// 3 persists the cumulative-token state needed to tail a growing rollout safely.
	public var parserRevision: Int { 3 }

	public func decodeFile(
		_ url: URL, from offset: Int, parserState: String?
	) -> IndexedDecodeResult {
		CodexProvider.parseIndexedUsage(
			fileURL: url, reader: JSONLStreamReader(), from: offset, parserState: parserState)
	}
}

extension GeminiProvider: IndexableProvider {
	public func dataFiles() -> [URL] { sessionFiles() }
	public var canTailAppend: Bool { false }  // whole JSON doc rewritten in place -> re-read on change
	public var parserRevision: Int { 1 }

	public func decodeFile(_ url: URL, from _: Int, parserState _: String?) -> IndexedDecodeResult {
		let events = GeminiProvider.parseUsage(fileURL: url)
		return IndexedDecodeResult(events: events, consumed: FileByteSize.of(url))
	}
}

extension CopilotProvider: IndexableProvider {
	public func dataFiles() -> [URL] { otelFiles() }
	// [Regression guard] MUST be false, not true. CopilotOTelParser's dedup-priority logic (ChatSpan
	// suppresses an overlapping InferenceLog/AgentTurnLog/AgentSummarySpan on the same trace) only
	// works when it sees the full candidate set for a request together. A correlated ChatSpan and
	// InferenceLog for the SAME underlying call can land in different append flushes — tailing would
	// dedup each incremental batch in isolation and miss the cross-batch overlap, double-counting
	// tokens (verified: a ChatSpan ingested in one refresh + its InferenceLog appended and ingested in
	// a later refresh produced 2 events instead of 1 before this was fixed to re-read whole).
	public var canTailAppend: Bool { false }
	public var parserRevision: Int { 1 }

	public func decodeFile(_ url: URL, from _: Int, parserState _: String?) -> IndexedDecodeResult {
		let events = CopilotOTelParser.parse(fileURL: url)
		return IndexedDecodeResult(events: events, consumed: FileByteSize.of(url))
	}
}

extension CursorProvider: IndexableProvider {
	public func dataFiles() -> [URL] { isAvailable() ? [root] : [] }
	public var canTailAppend: Bool { true }
	public var parserRevision: Int { 1 }
	// [CRITICAL] The capture file is JP's OWN append-only ledger and its hook now caps it, trimming the
	// oldest lines once it passes `CursorHookSetup.captureMaxBytes`. A trim shrinks the file, which
	// `FileCursor.classify` reports as `.reset` — so the default whole-file replace would DELETE every
	// Cursor event the warehouse had already indexed from the trimmed-away lines, every rotation.
	// Retaining is safe here and only here: a line is never rewritten in place, and the
	// (provider, generation_id, conversation_id) primary key makes a re-ingest idempotent.
	public var resetPolicy: ResetPolicy { .rereadWholeRetainingIndexedEvents }

	public func decodeFile(_ url: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		var events: [UsageEvent] = []
		let consumed = JSONLStreamReader().read(fileURL: url, from: offset) { line in
			if let event = CursorProvider.decode(line: line) { events.append(event) }
		}
		return IndexedDecodeResult(events: events, consumed: consumed)
	}
}
