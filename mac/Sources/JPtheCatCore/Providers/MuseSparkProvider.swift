import Foundation

/// Reads Meta Muse Spark usage from OpenCode's local SQLite store
/// (`~/.local/share/opencode/opencode.db`). OpenCode is the harness that runs
/// Muse Spark via the Meta Model API — its `session` table carries a JSON
/// `model` column (`{"id": "muse-spark-1.1", "providerID": "meta", ...}`) and
/// cumulative token counters. The newer `message` table carries per-turn
/// breakdowns (one assistant message = one turn) with the same model shape.
///
/// This row owns Meta's Muse model family: ids containing any of `museFamilyNeedles`
/// (`muse-spark`, `muse-wonder`), on any gateway. Muse Wonder 1.0 joined the row when OpenCode began
/// logging it through Meta's own API, where no gateway row could claim it.
///
/// Cost is NOT taken from the DB's own `cost` column (known upstream undercount) —
/// `UsageEvent` is token-based and priced at read time via `CostCalculator` from
/// `pricing-default.json` (Meta list rates: Spark 1.25/4.25, Wonder 4/20 per MTok).
///
/// Tier: dashboard-visible, notional list-price $, no rate-limit gauge (Meta's API
/// exposes no local quota %), same honesty posture as Grok/Codex.
public struct MuseSparkProvider: UsageProvider {
	public let id: ProviderID = .museSpark
	public let root: URL

	public init(root: URL? = nil) {
		self.root = root ?? OpenCodeStorePaths.defaultRoot()
	}

	public func watchPaths() -> [URL] { [root] }

	/// True only when OpenCode's store actually contains Muse Spark usage — a bare
	/// `opencode.db` (or log) with only other models must NOT surface a Muse Spark row.
	public func isAvailable() -> Bool {
		let db = databaseFile()
		if FileManager.default.fileExists(atPath: db.path) {
			return OpenCodeDetection.current(root: root).museSpark
		}
		let log = legacyLogFile()
		guard FileManager.default.fileExists(atPath: log.path),
			let handle = try? FileHandle(forReadingFrom: log)
		else { return false }
		defer { try? handle.close() }
		// Cheap scan of the first ~256KB of the legacy log for the model id.
		let chunk = try? handle.read(upToCount: 256 * 1024)
		guard let chunk, let text = String(data: chunk, encoding: .utf8) else { return false }
		return text.lowercased().contains("muse-spark")
	}

	public func loadEvents() -> [UsageEvent] {
		let dbFile = databaseFile()
		if FileManager.default.fileExists(atPath: dbFile.path) {
			return Deduplicator.dedupe(MuseSparkProvider.decodeDatabase(fileURL: dbFile))
		}
		return MuseSparkProvider.parseLegacyLog(fileURL: legacyLogFile())
	}

	public func dataFiles() -> [URL] { OpenCodeStorePaths.dataFiles(root: root) }

	func databaseFile() -> URL { OpenCodeStorePaths.databaseFile(root: root) }

	private func legacyLogFile() -> URL { OpenCodeStorePaths.logFile(root: root) }

	// MARK: - Model detection

	/// Meta's Muse text models on the Meta Model API. A new family member joins only by name here, so
	/// an unrelated id that merely contains "muse" never lands on this row.
	public static let museFamilyNeedles = ["muse-spark", "muse-wonder"]

	/// True when the model identifier designates a Meta Muse model (any provider prefix).
	public static func isSparkModelID(_ raw: String?) -> Bool {
		guard let raw, !raw.isEmpty else { return false }
		let lower = raw.lowercased()
		return museFamilyNeedles.contains { lower.contains($0) }
	}

	/// Structured check from decoded model object — used on the DB `model` JSON column.
	public static func isSparkModelObject(id: String?, providerID: String?) -> Bool {
		let idLower = (id ?? "").lowercased()
		if isSparkModelID(idLower) { return true }
		// Provider "meta" + id contains "spark" catches future minor variants.
		if (providerID ?? "").lowercased() == "meta" && idLower.contains("spark") { return true }
		return false
	}

	static func matches(_ ref: OpenCodeModelRef) -> Bool {
		isSparkModelObject(id: ref.modelID, providerID: ref.providerID)
	}

	// MARK: - DB decoding: message granularity first, session fallback

	public static func decodeDatabase(fileURL: URL) -> [UsageEvent] {
		decodeDatabase(fileURL: fileURL, createdAtOrAfterMillis: 0).events
	}

	/// Change-scoped decode through the shared reader (`OpenCodeModelReader.decode`): only assistant
	/// messages created at or after `createdAtOrAfterMillis`, plus the watermark a later call should
	/// resume from.
	///
	/// [Why the bound exists] Muse Spark declares `canTailAppend: false`, so `FileCursor.classify`
	/// returns `.reset` for ANY change to `opencode.db` — and the DB mutates on every message during a
	/// live session. Unbounded, `UsageIndexer.refresh` therefore deleted N rows and re-upserted N rows
	/// every 2 s where N is the LIFETIME message count, so both the write volume and SQLite's
	/// free-page churn grew linearly with total history, forever.
	static func decodeDatabase(fileURL: URL, createdAtOrAfterMillis: Int)
		-> (events: [UsageEvent], watermark: Int)
	{
		guard let store = OpenCodeStore(fileURL: fileURL) else { return ([], createdAtOrAfterMillis) }
		return OpenCodeModelReader.decode(
			store: store, createdAtOrAfterMillis: createdAtOrAfterMillis, provider: .museSpark,
			matches: matches, normalize: normalizedModelID)
	}

	public static func decodeMessagesFromDatabase(fileURL: URL) -> [UsageEvent] {
		guard let store = OpenCodeStore(fileURL: fileURL) else { return [] }
		return OpenCodeModelReader.messages(
			store: store, createdAtOrAfterMillis: 0, provider: .museSpark,
			matches: matches, normalize: normalizedModelID
		).events
	}

	public static func decodeSessionsFromDatabase(fileURL: URL) -> [UsageEvent] {
		guard let store = OpenCodeStore(fileURL: fileURL) else { return [] }
		return OpenCodeModelReader.sessions(
			store: store, provider: .museSpark, matches: matches, normalize: normalizedModelID)
	}

	/// Parse-time normalisation through the same `OpenCodeGateway.normalizedModelID` the gateway and
	/// brand rows use, so one turn always carries one accounting id on every row. A `-contributor` /
	/// `-contributor-free` suffix stays: `PricingTable` prices `muse-spark-1.3-contributor` at its own
	/// row and leaves the free tier unpriced, the same rule every OpenCode-derived row follows.
	public static func normalizedModelID(_ ref: OpenCodeModelRef) -> String {
		OpenCodeGateway.normalizedModelID(ref, fallback: "muse-spark-1.1")
	}

	// MARK: - Legacy log fallback

	/// Routes through `OpenCodeLogReader` so this and `OpenCodeProvider.parseUsage` share ONE traversal
	/// of `opencode.log` — the two used to stream the same file end to end once each per refresh, each
	/// re-running `parseFields` over every line to apply the opposite filter.
	static func parseLegacyLog(fileURL: URL, reader: JSONLStreamReader = JSONLStreamReader()) -> [UsageEvent] {
		OpenCodeLogReader.parse(fileURL: fileURL, reader: reader).museSpark
	}

	static func decode(line: String) -> UsageEvent? {
		decode(fields: OpenCodeProvider.parseFields(line))
	}

	/// Decode from already-parsed logfmt fields, so one traversal can feed both this filter and
	/// `OpenCodeProvider.decode(fields:)` without re-parsing the line.
	static func decode(fields: [String: String]) -> UsageEvent? {
		guard let sessionID = fields["id"] ?? fields["session.id"] else { return nil }
		let rawModel = fields["model"] ?? fields["modelID"]
		guard isSparkModelID(rawModel) else { return nil }
		let usage = TokenUsage(
			input: intField(fields["tokens.input"]),
			output: intField(fields["tokens.output"]) + intField(fields["tokens.reasoning"]),
			cacheCreate5m: intField(fields["tokens.cache.write"]), cacheCreate1h: 0,
			cacheRead: intField(fields["tokens.cache.read"]))
		guard usage.total > 0 else { return nil }
		let project = fields["directory"].map { URL(fileURLWithPath: $0).lastPathComponent }
		return UsageEvent(
			messageId: sessionID, requestId: fields["run"] ?? "opencode-log",
			provider: .museSpark,
			model: normalizedModelID(OpenCodeModelRef(modelID: rawModel, providerID: nil)),
			timestamp: ISOTimestamp.parse(fields["timestamp"]), usage: usage, project: project)
	}

	private static func intField(_ string: String?) -> Int {
		JSONNumber.int(fromString: string)
	}
}

// MARK: - IndexableProvider conformance

extension MuseSparkProvider: IndexableProvider {
	/// Byte offsets mean nothing in a SQLite file, so a changed DB is never tail-appendable.
	public var canTailAppend: Bool { false }
	/// Revision 2 changed the cursor's `offset` meaning from "bytes consumed" to a `$.time.created`
	/// watermark. Revision 3 moved per-turn rows onto the shared reader, which stamps
	/// `requestId: "opencode-db"` (the index key) instead of the session id — the bump forces one
	/// full re-read so no row is left under the old key.
	// Reconcile edits below the creation watermark and repair already-indexed history.
	// Revision 5: also read OpenCode's session-v2 `session_message` table; the old `message` table
	// stopped receiving turns after the migration, and Muse Wonder ids now belong to this row, so
	// history must be re-read once.
	public var parserRevision: Int { 5 }

	/// The DB source resumes from its watermark instead of re-reading (and re-deleting) the full
	/// lifetime message set on every 2 s refresh — see `decodeDatabase(fileURL:createdAtOrAfterMillis:)`.
	/// The legacy log has no such ordering key and keeps the whole-file semantics.
	public var resetPolicy: ResetPolicy {
		dataFiles().first?.pathExtension == "db" ? .watermark : .rereadWhole
	}

	public func decodeFile(_ url: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		guard url.pathExtension == "db" else {
			return IndexedDecodeResult(
				events: MuseSparkProvider.parseLegacyLog(fileURL: url), consumed: FileByteSize.of(url))
		}
		return OpenCodeModelReader.indexed(fileURL: url, from: offset, provider: .museSpark,
			matches: Self.matches, normalize: Self.normalizedModelID)
	}

	public func watermarkTimestamp(_ watermark: Int) -> Date? {
		OpenCodeModelReader.watermarkTimestamp(watermark)
	}
}
