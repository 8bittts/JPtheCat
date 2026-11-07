import Foundation

/// Process-wide, thread-safe cache from OTel file path -> the (size, mtime, ctime) we last read it at
/// and the parsed pre-dedup `[Candidate]`, so the same file isn't re-opened and re-JSON-decoded by every
/// consumer on every refresh. The `(size, mtime, ctime)` key is required — `(size, mtime)` alone is
/// unsafe against mtime-preserving rewrites; see `UsageIndexer.swift`. Because ctime is in the key
/// this needs no "recently written files bypass the cache" escape hatch. An unreadable ctime forces a
/// re-read rather than trusting a partial key.
///
/// [Why this exists] `~/.copilot/otel/otel.jsonl` was fully decoded THREE times per refresh — once by
/// `loadEvents()` for the dashboard row, once by `windowAIU()` -> `aiuSamples()`, and a third time by
/// `DashboardWidgetPublisher.makeWindows`. On a real 9.6 MB / 14,198-line file each pass moved physical
/// footprint by ~46 MB, and 98.8% of the decoded records are `"type":"metric"` lines that `classify()`
/// throws away. Caching the ~169 surviving candidates costs well under 100 KB.
private final class CopilotCandidateCache: @unchecked Sendable {
	private struct Entry {
		let size: Int
		let mtime: Double
		let ctime: Double
		let candidates: [CopilotOTelParser.Candidate]
	}
	private let lock = NSLock()
	private var entries: [String: Entry] = [:]
	/// Counts real file traversals. The whole point of this cache is "one decode per changed file per
	/// refresh", and that is only observable as a count — a behavioural test can't distinguish a cache
	/// hit from a re-read, because a correct cache re-reads whenever the file actually changes.
	/// `CopilotProviderTests.testLoadEventsAndAIUSamplesShareOneFileTraversal` reads this.
	private(set) var traversalCount = 0

	func recordTraversal() {
		lock.lock()
		traversalCount += 1
		lock.unlock()
	}

	func cached(path: String, size: Int, mtime: Double, ctime: Double)
		-> [CopilotOTelParser.Candidate]?
	{
		lock.lock()
		defer { lock.unlock() }
		guard let entry = entries[path], entry.size == size, entry.mtime == mtime, entry.ctime == ctime
		else { return nil }
		return entry.candidates
	}

	func store(
		path: String, size: Int, mtime: Double, ctime: Double,
		candidates: [CopilotOTelParser.Candidate]
	) {
		lock.lock()
		defer { lock.unlock() }
		entries[path] = Entry(size: size, mtime: mtime, ctime: ctime, candidates: candidates)
	}

	/// Keeps the cache bounded by the current on-disk file count. Only ever removes entries for absent
	/// files, so it can never surface stale data — worst case a re-read on a path that reappears.
	func retainOnly(livePaths: Set<String>) {
		lock.lock()
		defer { lock.unlock() }
		guard entries.count > livePaths.count else { return }
		entries = entries.filter { livePaths.contains($0.key) }
	}
}

private let copilotCandidateCache = CopilotCandidateCache()

/// Reads GitHub Copilot CLI usage from its OpenTelemetry JSONL export
/// (`~/.copilot/otel/*.jsonl`). This is **opt-in only** — Copilot CLI does not enable the OTel
/// file exporter by default; the user must set `COPILOT_OTEL_FILE_EXPORTER_PATH=<path>` before a session starts
/// (`CopilotOtelSetup` installs this with explicit consent, mirroring `StatuslineCapture`). Cost/
/// token tracking only: Copilot's own `/usage` command is unreliable near its quota cap and around
/// context compaction, so no rate-limit gauge is derived here — that would require a trustworthy
/// local %, which does not exist. Audit-only pending live promotion, same posture as Gemini/OpenCode.
public struct CopilotProvider: UsageProvider {
	public let id: ProviderID = .copilot
	public let root: URL
	private let reader = JSONLStreamReader()

	public init(root: URL? = nil) {
		self.root =
			root
			?? FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".copilot/otel", isDirectory: true)
	}

	/// Number of real OTel file decodes performed process-wide. Guard hook only — see
	/// `CopilotCandidateCache.traversalCount`.
	static var candidateTraversalCount: Int { copilotCandidateCache.traversalCount }

	public func watchPaths() -> [URL] { [root] }

	public func isAvailable() -> Bool { !otelFiles().isEmpty }

	public func loadEvents() -> [UsageEvent] {
		var dedup = Deduplicator()
		for file in otelFiles() {
			// Per-file dedup first (what `CopilotOTelParser.parse(fileURL:)` did), then the cross-file
			// dedup below — BOTH reductions are load-bearing and must stay separate from `aiuSamples()`,
			// which combines candidates across files and dedups exactly once.
			for event in CopilotOTelParser.events(fromDeduping: cachedCandidates(for: file)) {
				dedup.add(event)
			}
		}
		return dedup.events
	}

	/// Deduped per-request AIU consumption samples across every OTel file. Candidates are combined
	/// across files and deduped ONCE, so a turn that appears in two files (or as both a chatSpan and
	/// an inferenceLog) contributes its AIU exactly once. Raw consumption counts only — never dollars,
	/// never a quota %.
	func aiuSamples() -> [CopilotOTelParser.AIUSample] {
		let all = otelFiles().flatMap { cachedCandidates(for: $0) }
		return CopilotOTelParser.aiuSamples(from: all)
	}

	/// One file traversal shared by every consumer. Returns the same pre-dedup `[Candidate]` that
	/// `CopilotOTelParser.candidates(fileURL:)` produces — each caller still applies its OWN dedup
	/// reduction, so collapsing the traversal cannot change either result.
	private func cachedCandidates(for file: URL) -> [CopilotOTelParser.Candidate] {
		let path = file.path
		let attributes = try? FileManager.default.attributesOfItem(atPath: path)
		let size = (attributes?[.size] as? NSNumber)?.intValue
		let mtime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970
		let ctime = FileCursor.changeTime(fileURL: file)
		if let size, let mtime, let ctime,
			let hit = copilotCandidateCache.cached(path: path, size: size, mtime: mtime, ctime: ctime)
		{
			return hit
		}
		copilotCandidateCache.recordTraversal()
		let fresh = CopilotOTelParser.candidates(fileURL: file, reader: reader)
		// Only cache when the full (size, mtime, ctime) key resolved. A partial key would be
		// indistinguishable from a later real change.
		if let size, let mtime, let ctime {
			copilotCandidateCache.store(
				path: path, size: size, mtime: mtime, ctime: ctime, candidates: fresh)
		}
		return fresh
	}

	/// Total AIU consumed (in whole AIU, nano ÷ 1e9) over the trailing `days` window ending at `now`,
	/// or nil when no local AIU signal exists. Consumption only — do NOT render as `$` or `%`, and do
	/// NOT derive headroom from it (Copilot exposes no local quota ceiling).
	public func windowAIU(days: Int, now: Date = Date(), calendar: Calendar = .current) -> Double? {
		guard days > 0 else { return nil }
		let samples = aiuSamples()
		guard !samples.isEmpty else { return nil }
		guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
		else { return nil }
		let nano = samples.filter { $0.timestamp >= start && $0.timestamp <= now }.reduce(0) { $0 + $1.nano }
		return Double(nano) / 1_000_000_000
	}

	/// The `otel` directory's own `.jsonl` files, flat (NOT recursive) — matches ccusage's
	/// `collect_files_with_extension(&default_dir, "jsonl", ...)`, which does not walk subdirectories.
	public func otelFiles() -> [URL] {
		guard
			let entries = try? FileManager.default.contentsOfDirectory(
				at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		else { return [] }
		let files = entries.filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
		// Keep the candidate cache bounded by the live file count (short-circuits on the common
		// nothing-to-drop case), so a rotated-away OTel file can't pin its candidates forever.
		copilotCandidateCache.retainOnly(livePaths: Set(files.map(\.path)))
		return files
	}
}
