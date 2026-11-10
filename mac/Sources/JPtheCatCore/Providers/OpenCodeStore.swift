import Foundation
import SQLite3

/// Shared plumbing for the ONE local store seven providers read.
///
/// `OpenCodeProvider` (Zen), `OpenCodeGoProvider` (Go), `MuseSparkProvider`, and every
/// `OpenCodeBrandProvider` read `~/.local/share/opencode` — the same `opencode.db` (and, for the two
/// oldest, the same legacy `log/opencode.log` fallback) — and differ ONLY in which assistant rows they
/// claim: a gateway row claims by `providerID`, a brand row by model id. Path resolution, the row
/// projections, the watermark scan, the session fallback, and the existence probe all live here so no
/// provider carries its own copy (four once did, byte-for-byte).

// MARK: - Path resolution

/// The one place `opencode.db` / `log/opencode.log` locations are derived.
///
/// A `root` that already points AT a `.db` or `.log` file is honoured as-is — fixtures and the
/// indexer both hand a concrete file down, and both providers relied on that behaviour.
public enum OpenCodeStorePaths {
	public static func defaultRoot() -> URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".local/share/opencode", isDirectory: true)
	}

	public static func databaseFile(root: URL) -> URL {
		root.pathExtension == "db" ? root : root.appendingPathComponent("opencode.db")
	}

	static func logFile(root: URL) -> URL {
		if root.pathExtension == "log" { return root }
		return root.appendingPathComponent("log", isDirectory: true)
			.appendingPathComponent("opencode.log")
	}

	/// The single active data file for this install: the DB when present (preferred), else the log.
	/// Never both — that would double-source the same sessions.
	static func dataFiles(root: URL) -> [URL] {
		let db = databaseFile(root: root)
		if FileManager.default.fileExists(atPath: db.path) { return [db] }
		let log = logFile(root: root)
		return FileManager.default.fileExists(atPath: log.path) ? [log] : []
	}
}

// MARK: - Gateways

/// The OpenCode gateway `providerID`s JP treats as first-class billing services.
///
/// A row's GATEWAY is the `providerID` OpenCode itself recorded on the assistant message
/// (`opencode` = Zen, `opencode-go` = Go). The model-brand providers (Muse Spark / Nemotron / MiMo /
/// Big Pickle / DeepSeek) own their models regardless of gateway, which is exactly why the gateway
/// rows are `ProviderBasis.gateway`: the same usage is displayed under both, but only the brand rows
/// are aggregated. See `ProviderBasis` and the Provider Expansion note in `_docs/todos.md`.
enum OpenCodeGateway {
	static let zenProviderID = "opencode"
	static let goProviderID = "opencode-go"

	static func isZen(_ providerID: String?) -> Bool { providerID?.lowercased() == zenProviderID }
	static func isGo(_ providerID: String?) -> Bool { providerID?.lowercased() == goProviderID }

	/// The Go-routed models whose published Go list price differs from the SAME model on Zen
	/// (<https://opencode.ai/docs/go/>), keyed by vendor-stripped id with tier suffix included. A
	/// matching non-free id parses to a `-go`-suffixed id so pricing lands on the dedicated Go row;
	/// other ids retain their published model list-price basis.
	static let goDistinctModelIDs: Set<String> = [
		"deepseek-v4-pro", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp"
	]

	/// Grok models whose Zen and Go rate uses an exclusive 200K boundary, unlike direct xAI's
	/// inclusive one; either gateway parses them to a `-opencode` row.
	static let openCodeBoundaryModelIDs: Set<String> = ["grok-4.7", "grok-4.6", "grok-4.5", "grok-build-0.1"]

	/// Zen-routed models whose Zen list price differs from the base row; they parse to a `-zen` row.
	static let zenDistinctModelIDs: Set<String> = ["deepseek-v4.1-flash", "gpt-5-codex", "gpt-5.1-codex", "claude-sonnet-5-5"]

	/// Go-routed ids billed at Go's published 2x peak rate during peak hours (`isPeak`).
	static let goPeakModelIDs: Set<String> = goDistinctModelIDs.union(["deepseek-v4.1-flash"])

	/// Parse-time gateway accounting: preserve free tiers, route distinct rates, and select peak hours.
	/// Drop a `vendor/` prefix, then append `-go`
	/// ONLY when the ref is genuinely Go-routed (`providerID == "opencode-go"`) AND its id (tier
	/// suffix kept) is in `goDistinctModelIDs`. The `-free` tier suffix is never suffixed, so a free
	/// Go turn stays unpriced exactly as on Zen; a nil providerID (session fallback, legacy log)
	/// cannot be Go evidence and keeps the base id. Every id this can return for a routed model must be
	/// an exact `pricing-default.json` row (guard: `OpenCodeGoProviderTests`).
	static func normalizedModelID(_ ref: OpenCodeModelRef, fallback: String) -> String {
		let id = ProviderModelNormalization.strippingVendorPrefix(ref.modelID, fallback: fallback)
		typealias Suffix = ModelIdentity.AccountingSuffix
		if isZen(ref.providerID) || isGo(ref.providerID), openCodeBoundaryModelIDs.contains(id) {
			return id + Suffix.openCode
		}
		if isZen(ref.providerID), zenDistinctModelIDs.contains(id) {
			return id + Suffix.zen
		}
		guard isGo(ref.providerID) else { return id }
		let routed = goDistinctModelIDs.contains(id) ? id + Suffix.go : id
		guard goPeakModelIDs.contains(id), let date = ref.createdAt, isPeak(date) else { return routed }
		return routed + Suffix.peak
	}
	/// OpenCode Go publishes weekday UTC peak windows; request creation selects the notional rate.
	static func isPeak(_ date: Date) -> Bool {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		let weekday = calendar.component(.weekday, from: date)
		let hour = calendar.component(.hour, from: date)
		return (2...6).contains(weekday) && ((1..<4).contains(hour) || (6..<10).contains(hour))
	}

}

// MARK: - Row shapes

/// The (model id, gateway id) pair every OpenCode row carries, in the shape each provider's matcher
/// reads. A `message` row carries both as JSON fields; a `session` row packs them into its `model`
/// column (`OpenCodeModelColumn.parse`).
public struct OpenCodeModelRef: Sendable, Hashable {
	public let modelID: String?
	public let providerID: String?
	public let createdAt: Date?

	public init(modelID: String?, providerID: String?, createdAt: Date? = nil) {
		self.modelID = modelID
		self.providerID = providerID
		self.createdAt = createdAt
	}
}

/// `session.model` stores a JSON object (`{"id": "...", "providerID": "...", "variant": "..."}`);
/// older rows store a plain model string. One parser for every provider that reads the column.
public enum OpenCodeModelColumn {
	public static func parse(_ raw: String?) -> OpenCodeModelRef {
		guard let raw, !raw.isEmpty else { return OpenCodeModelRef(modelID: nil, providerID: nil) }
		if let data = raw.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		{
			return OpenCodeModelRef(
				modelID: object["id"] as? String, providerID: object["providerID"] as? String)
		}
		return OpenCodeModelRef(modelID: raw, providerID: nil)
	}
}

/// One `session` row: a cumulative full-state snapshot across every model the session used.
struct OpenCodeSessionRow {
	let id: String
	/// Raw `model` column — a JSON object (`{"id": …, "providerID": …}`) or a plain string.
	let rawModel: String?
	var model: OpenCodeModelRef { OpenCodeModelColumn.parse(rawModel) }
	let usage: TokenUsage
	let timeCreatedMillis: Int
	let projectID: String?
}

/// One assistant row from `message` or `session_message`: a per-turn breakdown (one assistant
/// message = one turn).
struct OpenCodeMessageRow {
	let sessionID: String
	let messageID: String
	let createdMillis: Int
	let modelID: String?
	let providerID: String?
	let usage: TokenUsage
	var model: OpenCodeModelRef {
		OpenCodeModelRef(modelID: modelID, providerID: providerID,
			createdAt: Date(timeIntervalSince1970: Double(createdMillis) / 1000))
	}
}

// MARK: - Store

/// ONE read-only connection over `opencode.db`, plus the parameterised scans both providers share.
///
/// Read-only and non-creating by construction (`SQLiteDatabase(readOnlyPath:)`): this is another
/// app's database and JP never mutates it, never touches its journal mode, and never reads message
/// CONTENT — every scan below projects identifiers, model ids, timestamps, and token counts only.
final class OpenCodeStore {
	private let db: SQLiteDatabase
	var scanFailed = false

	init?(fileURL: URL) {
		guard let db = try? SQLiteDatabase(readOnlyPath: fileURL.path) else { return nil }
		self.db = db
	}

	// MARK: Message tables

	/// OpenCode 1.x wrote one row per message to `message` (role in `$.role`, model in
	/// `$.modelID` / `$.providerID`). The session-v2 store writes `session_message` instead (role in
	/// the `type` column, model in `$.model.id` / `$.model.providerID`, same `tokens` and `time`
	/// shape), migrates the old rows into it, and stops appending to `message`. Reading `message`
	/// alone silently dropped every turn after the migration, so both are read and an id present in
	/// both resolves to the `session_message` copy, which is the one the current OpenCode updates.
	static let legacyMessageTable = "message"
	static let sessionMessageTable = "session_message"

	/// The subset of `names` that exist as tables. Throws when `sqlite_master` itself cannot be read.
	func existingTables(_ names: [String]) throws -> Set<String> {
		let stmt = try db.prepare("SELECT name FROM sqlite_master WHERE type='table'")
		var found = Set<String>()
		while try stmt.step() {
			if let name = stmt.text(0), names.contains(name) { found.insert(name) }
		}
		return found
	}

	/// One projection over every assistant row, whichever table holds it, with stable column names:
	/// `session_id, id, created, model_id, provider_id, t_input, t_output, t_reasoning, t_cache_read,
	/// t_cache_write`. Nil when neither table exists (a legacy session-only store).
	static func assistantProjection(tables: Set<String>) -> String? {
		let v2 = tables.contains(sessionMessageTable)
		let v1 = tables.contains(legacyMessageTable)
		let sessionMessages = """
			SELECT session_id, id,
			       json_extract(data, '$.time.created') AS created,
			       json_extract(data, '$.model.id') AS model_id,
			       json_extract(data, '$.model.providerID') AS provider_id,
			       json_extract(data, '$.tokens.input') AS t_input,
			       json_extract(data, '$.tokens.output') AS t_output,
			       json_extract(data, '$.tokens.reasoning') AS t_reasoning,
			       json_extract(data, '$.tokens.cache.read') AS t_cache_read,
			       json_extract(data, '$.tokens.cache.write') AS t_cache_write
			FROM session_message
			WHERE type = 'assistant'
			"""
		let legacyMessages = """
			SELECT session_id, id,
			       json_extract(data, '$.time.created') AS created,
			       json_extract(data, '$.modelID') AS model_id,
			       json_extract(data, '$.providerID') AS provider_id,
			       json_extract(data, '$.tokens.input') AS t_input,
			       json_extract(data, '$.tokens.output') AS t_output,
			       json_extract(data, '$.tokens.reasoning') AS t_reasoning,
			       json_extract(data, '$.tokens.cache.read') AS t_cache_read,
			       json_extract(data, '$.tokens.cache.write') AS t_cache_write
			FROM message
			WHERE json_extract(data, '$.role') = 'assistant'
			"""
		switch (v1, v2) {
		case (false, false): return nil
		case (true, false): return legacyMessages
		case (false, true): return sessionMessages
		case (true, true):
			return sessionMessages + "\nUNION ALL\n" + legacyMessages
				+ "  AND id NOT IN (SELECT id FROM session_message)\n"
		}
	}

	/// Rewind only as far as an older message edited since the previous creation watermark.
	/// Concurrent sessions finish out of creation order. Include every role so reclassification
	/// removes the old event too. The read snapshot keeps this bound and its replacement consistent.
	func replacementStart(from: Int) throws -> Int {
		guard from > 0 else { return 0 }
		let tables = try existingTables([Self.legacyMessageTable, Self.sessionMessageTable])
		// Legacy session-only stores replace their full snapshot.
		guard !tables.isEmpty else { return 0 }
		var start = from
		for table in tables.sorted() {
			let stmt = try db.prepare("""
				SELECT min(json_extract(data, '$.time.created')) FROM \(table)
				WHERE time_updated >= ?1 AND json_extract(data, '$.time.created') > 0
				""")
			stmt.bind(1, from)
			if try stmt.step(), stmt.int(0) > 0 { start = min(start, stmt.int(0)) }
		}
		return start
	}

	func readSnapshot<T>(_ body: () throws -> T) throws -> T {
		try db.execute("BEGIN DEFERRED;")
		do {
			let value = try body()
			try db.execute("COMMIT;")
			return value
		} catch {
			try? db.execute("ROLLBACK;")
			throw error
		}
	}

	// MARK: Existence probe

	/// Every distinct (model id, gateway id) pair the store has ever recorded on an assistant message
	/// or a session's `model` column. ONE pass feeds `OpenCodeDetection` for all seven providers;
	/// the old per-provider `LIKE` probes ran fourteen scans per Settings appearance.
	///
	/// A mid-scan `SQLiteError` returns `nil` rather than a partial set: a partial set would read as
	/// "this brand is not installed" and hide a row that has real usage (mac/AGENTS.md [CRITICAL]).
	func distinctModelRefs() -> Set<OpenCodeModelRef>? {
		var refs = Set<OpenCodeModelRef>()
		guard
			let tables = try? existingTables([Self.legacyMessageTable, Self.sessionMessageTable]),
			let projection = Self.assistantProjection(tables: tables),
			let messages = try? db.prepare(
				"SELECT DISTINCT model_id, provider_id FROM (\(projection))")
		else { return nil }
		do {
			while try messages.step() {
				refs.insert(OpenCodeModelRef(modelID: messages.text(0), providerID: messages.text(1)))
			}
		} catch {
			return nil
		}
		guard let sessions = try? db.prepare("SELECT DISTINCT model FROM session") else { return refs }
		do {
			while try sessions.step() {
				refs.insert(OpenCodeModelColumn.parse(sessions.text(0)))
			}
		} catch {
			return nil
		}
		return refs
	}

	// MARK: Scans

	/// Every `session` row, in table order. Throws a mid-scan `SQLiteError.step` rather than
	/// collapsing it into loop-end — a truncated session scan must never read as an authoritative
	/// total (mac/AGENTS.md [CRITICAL]).
	func forEachSession(_ body: (OpenCodeSessionRow) -> Void) throws {
		let stmt = try db.prepare(
			"""
			SELECT id, tokens_input, tokens_output, tokens_reasoning, tokens_cache_read,
			       tokens_cache_write, model, time_created, project_id
			FROM session
			""")
		while try stmt.step() {
			guard let id = stmt.text(0) else { continue }
			body(
				OpenCodeSessionRow(
					id: id,
					rawModel: stmt.text(6),
					usage: TokenUsage(
						input: stmt.int(1), output: stmt.int(2) + stmt.int(3), cacheCreate5m: stmt.int(5),
						cacheCreate1h: 0, cacheRead: stmt.int(4)),
					timeCreatedMillis: stmt.int(7),
					projectID: stmt.text(8)))
		}
	}

	/// Assistant rows from `message` and `session_message` (see `assistantProjection`) whose
	/// `$.time.created` is at or after `createdAtOrAfterMillis`.
	///
	/// The bound is what makes a live-session refresh cheap: `opencode.db` mutates on EVERY message,
	/// so an unbounded decode re-emitted (and the indexer re-deleted and re-upserted) the full lifetime
	/// message set every 2 s, growing linearly with total history forever. `>=` rather than `>` on
	/// purpose — the newest row is the one still being written, so it must stay in range until it
	/// stops changing; the index's keep-max-output upsert makes re-ingesting it idempotent.
	/// A `NULL` `$.time.created` never satisfies the comparison, matching the old decode's
	/// `guard tc != 0` skip.
	func forEachAssistantMessage(
		createdAtOrAfterMillis: Int, _ body: (OpenCodeMessageRow) -> Void
	) throws {
		// Older stores have only session counters. Absence of both message tables permits that
		// fallback; a malformed existing message table does not.
		let tables = try existingTables([Self.legacyMessageTable, Self.sessionMessageTable])
		guard let projection = Self.assistantProjection(tables: tables) else { return }
		guard let stmt = try? db.prepare(
			"""
			SELECT session_id, id, created, model_id, provider_id,
			       t_input, t_output, t_reasoning, t_cache_read, t_cache_write
			FROM (\(projection))
			WHERE created >= ?1
			""")
		else {
			scanFailed = true
			return
		}
		stmt.bind(1, createdAtOrAfterMillis)
		while try stmt.step() {
			let sessionID = stmt.text(0) ?? ""
			let messageID = stmt.text(1) ?? ""
			guard !sessionID.isEmpty, !messageID.isEmpty else { continue }
			body(
				OpenCodeMessageRow(
					sessionID: sessionID,
					messageID: messageID,
					createdMillis: stmt.int(2),
					modelID: stmt.text(3),
					providerID: stmt.text(4),
					usage: TokenUsage(
						input: stmt.int(5), output: stmt.int(6) + stmt.int(7), cacheCreate5m: stmt.int(9),
						cacheCreate1h: 0, cacheRead: stmt.int(8))))
		}
	}

	/// `session.id -> project_id`. A mid-scan `SQLiteError` must never collapse into loop-end: a
	/// partial map would present as complete, so the whole map is dropped instead — project labels
	/// degrade, money does not.
	func projectIDsBySession() -> [String: String] {
		// `session_message` rows reference `session_v2`; legacy `message` rows reference `session`.
		let hasV2 = (try? existingTables(["session_v2"]))?.isEmpty == false
		let sql = hasV2
			? "SELECT id, project_id FROM session UNION ALL SELECT id, project_id FROM session_v2"
			: "SELECT id, project_id FROM session"
		guard let stmt = try? db.prepare(sql) else { return [:] }
		var out: [String: String] = [:]
		do {
			while try stmt.step() {
				if let sid = stmt.text(0), let pid = stmt.text(1) { out[sid] = pid }
			}
		} catch {
			return [:]
		}
		return out
	}

	/// Sum of assistant-message tokens keyed by session id for rows matching the SQL LIKE pattern.
	/// Retained for the shared-store guard tests; no production path peels brands out of a session
	/// total any more (gateway rows deliberately overlap their brands — see `ProviderBasis.gateway`).
	func modelMessageTotals(_ pattern: String) -> [String: TokenUsage] {
		guard let stmt = try? db.prepare(
			"""
			SELECT session_id,
			       coalesce(sum(json_extract(data, '$.tokens.input')), 0),
			       coalesce(sum(json_extract(data, '$.tokens.output')), 0)
			         + coalesce(sum(json_extract(data, '$.tokens.reasoning')), 0),
			       coalesce(sum(json_extract(data, '$.tokens.cache.write')), 0),
			       coalesce(sum(json_extract(data, '$.tokens.cache.read')), 0)
			FROM message
			WHERE json_extract(data, '$.role') = 'assistant'
			  AND lower(coalesce(json_extract(data, '$.modelID'), '')) LIKE ?1
			GROUP BY session_id
			""")
		else { return [:] }
		stmt.bind(1, pattern)
		var out: [String: TokenUsage] = [:]
		do {
			while try stmt.step() {
				guard let sessionID = stmt.text(0), !sessionID.isEmpty else { continue }
				out[sessionID] = TokenUsage(
					input: stmt.int(1), output: stmt.int(2), cacheCreate5m: stmt.int(3), cacheCreate1h: 0,
					cacheRead: stmt.int(4))
			}
		} catch {
			return [:]
		}
		return out
	}
}

// MARK: - Legacy log: one traversal, two filters

/// Both event sets a single `opencode.log` traversal yields. Each side is already deduped.
struct OpenCodeLogParse {
	let opencode: [UsageEvent]
	let museSpark: [UsageEvent]
}

/// Process-wide, thread-safe cache from log path -> the `(size, mtime, ctime)` we last read it at and
/// the events BOTH providers derived from it. The `(size, mtime, ctime)` key is required —
/// `(size, mtime)` alone is unsafe against mtime-preserving rewrites; see `UsageIndexer.swift`. An
/// unreadable state forces a re-read rather than trusting a partial key.
///
/// [Why this exists] On the legacy-log fallback the SAME `opencode.log` was fully streamed TWICE per
/// refresh — once by `OpenCodeProvider.parseUsage` and again by `MuseSparkProvider.parseLegacyLog`,
/// which re-ran `parseFields` over every line a second time to apply the opposite filter.
private final class OpenCodeLogCache: @unchecked Sendable {
	private struct Entry {
		let size: Int
		let mtime: Double
		let ctime: Double
		let parse: OpenCodeLogParse
	}
	private let lock = NSLock()
	private var path: String?
	private var entry: Entry?
	/// Counts real log traversals. A cache hit is not otherwise observable — a correct cache re-reads
	/// whenever the file actually changes — so `OpenCodeLogSharedTraversalTests` reads this counter.
	private(set) var traversalCount = 0

	func recordTraversal() {
		lock.lock()
		traversalCount += 1
		lock.unlock()
	}

	func cached(path: String, state: (size: Int, mtime: Double, ctime: Double)) -> OpenCodeLogParse? {
		lock.lock()
		defer { lock.unlock() }
		guard self.path == path, let entry, entry.size == state.size, entry.mtime == state.mtime,
			entry.ctime == state.ctime
		else { return nil }
		return entry.parse
	}

	/// Holds ONE entry. Both providers read the same single active log per install, so a one-slot
	/// cache is naturally bounded and can never pin a rotated-away path's events forever.
	func store(path: String, state: (size: Int, mtime: Double, ctime: Double), parse: OpenCodeLogParse) {
		lock.lock()
		defer { lock.unlock() }
		self.path = path
		entry = Entry(size: state.size, mtime: state.mtime, ctime: state.ctime, parse: parse)
	}
}

private let openCodeLogCache = OpenCodeLogCache()

enum OpenCodeLogReader {
	/// Number of real log traversals performed process-wide. Guard hook only.
	static var traversalCount: Int { openCodeLogCache.traversalCount }

	/// ONE traversal of `fileURL`, parsing each line's logfmt fields ONCE and applying both providers'
	/// filters to the result. Callers take whichever side they own.
	static func parse(fileURL: URL, reader: JSONLStreamReader = JSONLStreamReader()) -> OpenCodeLogParse {
		let path = fileURL.path
		let state = FileCursor.state(fileURL: fileURL)
		if let state, let hit = openCodeLogCache.cached(path: path, state: state) { return hit }
		openCodeLogCache.recordTraversal()
		var openCode: [UsageEvent] = []
		var museSpark: [UsageEvent] = []
		reader.read(fileURL: fileURL) { data in
			guard let line = String(data: data, encoding: .utf8) else { return }
			let fields = OpenCodeProvider.parseFields(line)
			if let event = OpenCodeProvider.decode(fields: fields) { openCode.append(event) }
			if let event = MuseSparkProvider.decode(fields: fields) { museSpark.append(event) }
		}
		let parse = OpenCodeLogParse(
			opencode: Deduplicator.dedupe(openCode), museSpark: Deduplicator.dedupe(museSpark))
		// Only cache when the full (size, mtime, ctime) key resolved — a partial key would be
		// indistinguishable from a later real change.
		if let state { openCodeLogCache.store(path: path, state: state, parse: parse) }
		return parse
	}
}

/// The ONE decode path every OpenCode-derived provider uses, for direct reads and indexed reads
/// alike: per-turn assistant messages first (with the indexer's watermark), then the cumulative
/// `session` fallback for a pre-1.2.0 store whose `message` table is empty.
///
/// `matches` decides which rows a provider claims — a brand matches on `modelID`, a gateway on
/// `providerID` — and `normalize` is that provider's parse-time model-id normalisation. Every event
/// is stamped `requestId: "opencode-db"` so the index key `(provider, msg_id, req_id)` is the same
/// shape for all seven providers.
enum OpenCodeModelReader {
	/// One indexed path for all seven rows: reconcile late updates and fail without deleting
	/// accepted history or advancing a cursor when the source cannot be read completely.
	static func indexed(
		fileURL: URL, from: Int, provider: ProviderID,
		matches: (OpenCodeModelRef) -> Bool, normalize: (OpenCodeModelRef) -> String
	) -> IndexedDecodeResult {
		let failure = IndexedDecodeResult(events: [], consumed: from, succeeded: false)
		guard let store = OpenCodeStore(fileURL: fileURL) else { return failure }
		do {
			return try store.readSnapshot {
				let start = try store.replacementStart(from: from)
				let scan = decode(store: store, createdAtOrAfterMillis: start, provider: provider,
					matches: matches, normalize: normalize)
				guard !store.scanFailed else { return failure }
				return IndexedDecodeResult(events: scan.events, consumed: max(from, scan.watermark),
					replacementTimestamp: Date(timeIntervalSince1970: Double(start) / 1000))
			}
		} catch {
			return failure
		}
	}

	/// Message-first decode with the cumulative-session fallback.
	///
	/// [Why the fallback is gated on an UNBOUNDED scan] A bounded scan coming back empty only means
	/// "no new turns since the watermark"; only a scan from 0 proves the message table holds nothing
	/// for this provider, which is what licenses switching to session granularity.
	static func decode(
		store: OpenCodeStore, createdAtOrAfterMillis: Int, provider: ProviderID,
		matches: (OpenCodeModelRef) -> Bool, normalize: (OpenCodeModelRef) -> String
	) -> (events: [UsageEvent], watermark: Int) {
		let scan = messages(
			store: store, createdAtOrAfterMillis: createdAtOrAfterMillis, provider: provider,
			matches: matches, normalize: normalize)
		guard !store.scanFailed, scan.events.isEmpty, createdAtOrAfterMillis == 0 else { return scan }
		return (sessions(store: store, provider: provider, matches: matches, normalize: normalize), 0)
	}

	/// Assistant messages at or after the watermark. The returned watermark is `max($.time.created)`
	/// over every row VISITED (not just the matched ones), so a long non-matching tail is never
	/// rescanned forever. A mid-scan `SQLiteError` returns nothing and does NOT advance the watermark
	/// past unread rows — a truncated scan must never read as an authoritative total.
	static func messages(
		store: OpenCodeStore, createdAtOrAfterMillis: Int, provider: ProviderID,
		matches: (OpenCodeModelRef) -> Bool, normalize: (OpenCodeModelRef) -> String
	) -> (events: [UsageEvent], watermark: Int) {
		let projects = store.projectIDsBySession()
		var events: [UsageEvent] = []
		var watermark = createdAtOrAfterMillis
		do {
			try store.forEachAssistantMessage(createdAtOrAfterMillis: createdAtOrAfterMillis) { row in
				guard row.createdMillis > 0 else { return }
				watermark = max(watermark, row.createdMillis)
				guard matches(row.model), row.usage.total > 0 else { return }
				events.append(UsageEvent(
					messageId: row.messageID, requestId: "opencode-db", provider: provider,
					model: normalize(row.model),
					timestamp: Date(timeIntervalSince1970: Double(row.createdMillis) / 1000),
					usage: row.usage, project: projects[row.sessionID]))
			}
		} catch {
			store.scanFailed = true
			return ([], createdAtOrAfterMillis)
		}
		return (Deduplicator.dedupe(events), watermark)
	}

	/// Session-table fallback: one synthetic event per session whose own `model` column matches.
	/// Multi-model sessions are attributed whole to the matcher here because the session row carries
	/// only one model; the per-message path is the accurate one and this is only a degraded fallback.
	static func sessions(
		store: OpenCodeStore, provider: ProviderID,
		matches: (OpenCodeModelRef) -> Bool, normalize: (OpenCodeModelRef) -> String
	) -> [UsageEvent] {
		var events: [UsageEvent] = []
		do {
			try store.forEachSession { row in
				let model = row.model
				guard matches(model), row.usage.total > 0 else { return }
				events.append(
					UsageEvent(
						messageId: row.id, requestId: "opencode-db", provider: provider,
						model: normalize(model),
						timestamp: Date(timeIntervalSince1970: Double(row.timeCreatedMillis) / 1000),
						usage: row.usage, project: row.projectID))
			}
		} catch {
			// A truncated session scan must not read as a complete total (mac/AGENTS.md [CRITICAL]).
			store.scanFailed = true
			return []
		}
		return events
	}

	/// The watermark is `$.time.created` in MILLISECONDS, and `messages` stamps each event with
	/// exactly `Double(createdMillis) / 1000` — so this reproduces the boundary row's stored `ts`
	/// bit-for-bit, and the range-scoped `.reset` delete covers precisely the rows the bounded decode
	/// is about to re-emit. A nonsensical value suppresses the delete rather than widening it.
	static func watermarkTimestamp(_ watermark: Int) -> Date? {
		guard watermark > 0 else { return nil }
		return Date(timeIntervalSince1970: Double(watermark) / 1000)
	}
}

// MARK: - Detection

/// Which OpenCode-derived providers have usage in a store. ONE read-only connection and one distinct
/// scan answer `isAvailable()` for all seven providers, cached against the DB's `(size, mtime, ctime)`
/// INCLUDING its `-wal` sidecar, so the dashboard's 2 s refresh and the Settings window's seven rows
/// share a single probe instead of opening seven connections each.
public struct OpenCodeDetection: Sendable, Equatable {
	public let brands: Set<OpenCodeBrand>
	public let museSpark: Bool
	public let zen: Bool
	public let go: Bool

	public static let none = OpenCodeDetection(brands: [], museSpark: false, zen: false, go: false)

	public init(brands: Set<OpenCodeBrand>, museSpark: Bool, zen: Bool, go: Bool) {
		self.brands = brands
		self.museSpark = museSpark
		self.zen = zen
		self.go = go
	}

	/// Classify a set of (model id, gateway id) pairs. Pure, so a fixture can pin every branch.
	public static func classify(_ refs: some Sequence<OpenCodeModelRef>) -> OpenCodeDetection {
		var brands = Set<OpenCodeBrand>()
		var spark = false
		var zen = false
		var go = false
		for ref in refs {
			for brand in OpenCodeBrand.allCases where brand.matches(modelID: ref.modelID) {
				brands.insert(brand)
			}
			if MuseSparkProvider.isSparkModelObject(id: ref.modelID, providerID: ref.providerID) {
				spark = true
			}
			if OpenCodeGateway.isZen(ref.providerID) { zen = true }
			if OpenCodeGateway.isGo(ref.providerID) { go = true }
		}
		return OpenCodeDetection(brands: brands, museSpark: spark, zen: zen, go: go)
	}

	/// Uncached probe of one store file. `.none` when the file is absent, unopenable, or a scan was
	/// cut short — an unreadable store must hide rows, never show stale ones.
	public static func probe(fileURL: URL) -> OpenCodeDetection {
		guard FileManager.default.fileExists(atPath: fileURL.path),
			let store = OpenCodeStore(fileURL: fileURL),
			let refs = store.distinctModelRefs()
		else { return .none }
		return classify(refs)
	}

	/// Cached probe for the store under `root` (a root that already names the `.db` file is honoured,
	/// as everywhere else in `OpenCodeStorePaths`).
	public static func current(root: URL) -> OpenCodeDetection {
		let db = OpenCodeStorePaths.databaseFile(root: root)
		guard let state = FileCursor.indexedState(fileURL: db) else { return .none }
		if let hit = openCodeDetectionCache.cached(path: db.path, state: state) { return hit }
		let detection = probe(fileURL: db)
		openCodeDetectionCache.store(path: db.path, state: state, detection: detection)
		return detection
	}

	/// Number of real probes performed process-wide. Guard hook only.
	public static var probeCount: Int { openCodeDetectionCache.probeCount }
}

/// One-slot, thread-safe cache: every provider in a process reads the same single store per install,
/// so one entry is naturally bounded (the same shape as `OpenCodeLogCache` above).
private final class OpenCodeDetectionCache: @unchecked Sendable {
	private struct Entry {
		let size: Int
		let mtime: Double
		let ctime: Double
		let detection: OpenCodeDetection
	}
	private let lock = NSLock()
	private var path: String?
	private var entry: Entry?
	private(set) var probeCount = 0

	func cached(path: String, state: (size: Int, mtime: Double, ctime: Double)) -> OpenCodeDetection? {
		lock.lock()
		defer { lock.unlock() }
		guard self.path == path, let entry, entry.size == state.size, entry.mtime == state.mtime,
			entry.ctime == state.ctime
		else { return nil }
		return entry.detection
	}

	func store(path: String, state: (size: Int, mtime: Double, ctime: Double), detection: OpenCodeDetection) {
		lock.lock()
		defer { lock.unlock() }
		probeCount += 1
		self.path = path
		entry = Entry(size: state.size, mtime: state.mtime, ctime: state.ctime, detection: detection)
	}
}

private let openCodeDetectionCache = OpenCodeDetectionCache()
