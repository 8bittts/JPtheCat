import Foundation

/// Reads **OpenCode Zen** usage — every assistant message OpenCode itself recorded with
/// `providerID == "opencode"` — from OpenCode's local SQLite store
/// (`~/.local/share/opencode/opencode.db`, shipped v1.2.0+). Pre-1.2.0 installs (or a DB the current
/// user can't open) fall back to the legacy append-only `log/opencode.log` text log, which emits one
/// synthetic event per session snapshot. The DB's own `cost` column is never ingested (it undercounts
/// cache-read pricing upstream — anomalyco/opencode#28494): `UsageEvent` is token-based and priced at
/// read time, so Zen's free-tier ids stay unpriced and the row shows tokens.
///
/// Zen is a live `ProviderBasis.gateway` row: displayed with real figures, never summed into the
/// aggregate, because the same turns are counted under their model-brand rows.
public struct OpenCodeProvider: UsageProvider {
	public let id: ProviderID = .opencode
	public let root: URL
	private let reader = JSONLStreamReader()

	public init(root: URL? = nil) {
		self.root = root ?? OpenCodeStorePaths.defaultRoot()
	}

	public func watchPaths() -> [URL] { [root] }

	/// The DB path answers through the shared cached probe (`OpenCodeDetection`); a legacy log-only
	/// install is available whenever the log exists.
	public func isAvailable() -> Bool {
		if FileManager.default.fileExists(atPath: databaseFile().path) {
			return OpenCodeDetection.current(root: root).zen
		}
		return !dataFiles().isEmpty
	}

	public func loadEvents() -> [UsageEvent] {
		let dbFile = databaseFile()
		if FileManager.default.fileExists(atPath: dbFile.path) {
			return Deduplicator.dedupe(OpenCodeProvider.decodeDatabase(fileURL: dbFile))
		}
		var dedup = Deduplicator()
		for event in OpenCodeProvider.parseUsage(fileURL: logFile(), reader: reader) {
			dedup.add(event)
		}
		return dedup.events
	}

	/// The single active data file for this install: the DB when present (preferred), else the log.
	/// Never both — that would double-source the same sessions.
	public func dataFiles() -> [URL] { OpenCodeStorePaths.dataFiles(root: root) }

	func databaseFile() -> URL { OpenCodeStorePaths.databaseFile(root: root) }

	private func logFile() -> URL { OpenCodeStorePaths.logFile(root: root) }

	// MARK: - Parsing

	private static func date(_ string: String?) -> Date {
		ISOTimestamp.parse(string)
	}

	private static func int(_ string: String?) -> Int {
		JSONNumber.int(fromString: string)
	}

	private static func value(_ fields: [String: String], _ key: String) -> String? {
		guard let raw = fields[key], raw != "undefined", raw != "\"\"" else { return nil }
		return raw
	}

	/// Whole-file parse of the legacy log. `OpenCodeLogParse` shares one traversal between OpenCode and
	/// Muse Spark — do not reintroduce a second independent scan.
	static func parseUsage(fileURL: URL, reader: JSONLStreamReader = JSONLStreamReader()) -> [UsageEvent] {
		OpenCodeLogReader.parse(fileURL: fileURL, reader: reader).opencode
	}

	/// Incremental tail from a byte offset (the indexer's append path). Deliberately NOT routed through
	/// the shared whole-file traversal: it reads only the new bytes, so there is nothing to share.
	static func parseUsage(fileURL: URL, from offset: Int, reader: JSONLStreamReader = JSONLStreamReader())
		-> (events: [UsageEvent], consumed: Int)
	{
		var events: [UsageEvent] = []
		let consumed = reader.read(fileURL: fileURL, from: offset) { data in
			guard let line = String(data: data, encoding: .utf8),
				let event = decode(line: line)
			else { return }
			events.append(event)
		}
		return (Deduplicator.dedupe(events), consumed)
	}

	static func decode(line: String) -> UsageEvent? {
		decode(fields: parseFields(line))
	}

	/// Decode from already-parsed logfmt fields, so one traversal can feed both this filter and
	/// `MuseSparkProvider.decode(fields:)` without re-parsing the line.
	static func decode(fields: [String: String]) -> UsageEvent? {
		guard let sessionID = value(fields, "id") ?? value(fields, "session.id") else { return nil }

		let usage = TokenUsage(
			input: int(fields["tokens.input"]),
			output: int(fields["tokens.output"]) + int(fields["tokens.reasoning"]),
			cacheCreate5m: int(fields["tokens.cache.write"]),
			cacheCreate1h: 0,
			cacheRead: int(fields["tokens.cache.read"])
		)
		guard usage.total > 0 else { return nil }

		let rawModel = value(fields, "model") ?? value(fields, "modelID")
		// Exclude muse-spark — owned by MuseSparkProvider.
		if (rawModel ?? "").lowercased().contains("muse-spark") { return nil }
		let model = normalizeModel(OpenCodeModelRef(modelID: rawModel, providerID: nil))
		let project =
			value(fields, "directory")
			.map { URL(fileURLWithPath: $0).lastPathComponent }

		return UsageEvent(
			messageId: sessionID,
			requestId: value(fields, "run") ?? "opencode-log",
			provider: .opencode,
			model: model,
			timestamp: date(value(fields, "timestamp")),
			usage: usage,
			project: project
		)
	}

	/// Parse OpenCode's logfmt-like `key=value` records. Values may be quoted and contain spaces.
	///
	/// Scans `line.utf8` with integer indices rather than `Array(line)`. A `[Character]` copy costs 16
	/// bytes PER GRAPHEME, so a 1 KB log line materialized ~16 KB of transient storage before a single
	/// field was read, on every line of a fully-streamed `opencode.log` — and quoted values were then
	/// rebuilt one `Character` append at a time. Every delimiter this parser knows (` `, `=`, `"`, `\`)
	/// is ASCII, and UTF-8 never encodes an ASCII byte inside a multi-byte sequence, so byte-wise
	/// scanning splits at exactly the same places; keys and unquoted values are now sliced straight out
	/// of the source buffer, and only a quoted value that actually contains an escape is rebuilt.
	///
	/// [NOTE] Quoting, escaping, and malformed-input handling are pinned byte-for-byte by
	/// `OpenCodeLogfmtParsingTests`: an escape takes the NEXT byte literally, an unterminated quote runs
	/// to end of line, a trailing lone backslash stays literal, and a token with no `=` is skipped
	/// without consuming the following field.
	static func parseFields(_ line: String) -> [String: String] {
		var line = line
		return line.withUTF8 { bytes -> [String: String] in
			let space = UInt8(ascii: " ")
			let equals = UInt8(ascii: "=")
			let quote = UInt8(ascii: "\"")
			let backslash = UInt8(ascii: "\\")
			let count = bytes.count
			var fields: [String: String] = [:]
			var i = 0

			func slice(_ range: Range<Int>) -> String {
				range.isEmpty
					? "" : String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
			}

			while i < count {
				while i < count, bytes[i] == space { i += 1 }
				let keyStart = i
				while i < count, bytes[i] != equals, bytes[i] != space { i += 1 }
				guard i < count, bytes[i] == equals else {
					while i < count, bytes[i] != space { i += 1 }
					continue
				}
				let key = slice(keyStart..<i)
				i += 1

				let value: String
				if i < count, bytes[i] == quote {
					i += 1
					let valueStart = i
					var hasEscape = false
					while i < count {
						if bytes[i] == backslash, i + 1 < count {
							hasEscape = true
							i += 2
							continue
						}
						if bytes[i] == quote { break }
						i += 1
					}
					let valueEnd = min(i, count)
					if hasEscape {
						var out: [UInt8] = []
						out.reserveCapacity(valueEnd - valueStart)
						var j = valueStart
						while j < valueEnd {
							if bytes[j] == backslash, j + 1 < count {
								out.append(bytes[j + 1])
								j += 2
								continue
							}
							out.append(bytes[j])
							j += 1
						}
						value = String(decoding: out, as: UTF8.self)
					} else {
						value = slice(valueStart..<valueEnd)
					}
					if i < count, bytes[i] == quote { i += 1 }
				} else {
					let valueStart = i
					while i < count, bytes[i] != space { i += 1 }
					value = slice(valueStart..<i)
				}
				if !key.isEmpty { fields[key] = value }
			}

			return fields
		}
	}

	static func normalizeModel(_ ref: OpenCodeModelRef) -> String {
		OpenCodeGateway.normalizedModelID(ref, fallback: "opencode")
	}

	// MARK: - SQLite (opencode.db)

	/// OpenCode **Zen** owns every assistant message whose own `providerID` is `opencode` — INCLUDING
	/// models that also appear under a model-brand row (mimo / nemotron / big-pickle / muse-spark /
	/// deepseek). That overlap is deliberate: Zen is a `ProviderBasis.gateway` rollup, so the same
	/// usage is displayed under both the gateway and its model brand but summed only once (under the
	/// brand, which stays aggregable). Never "peel" the brands back out here — doing so would turn the
	/// gateway into a residual and break the `ProviderBasis.gateway` contract.
	///
	/// Every DB row shares the stable request id `"opencode-db"` (distinct from the log fallback's
	/// `"opencode-log"`) so DB- and log-sourced rows for the same session id never collide across a
	/// migration window. The `-wal` sidecar is part of the indexer's change signal
	/// (`FileCursor.indexedState`), so an uncheckpointed commit still triggers a refresh.
	public static func decodeDatabase(fileURL: URL) -> [UsageEvent] {
		decodeDatabase(fileURL: fileURL, createdAtOrAfterMillis: 0).events
	}

	/// Change-scoped decode (see `OpenCodeModelReader.decode`): the indexer resumes from the
	/// `$.time.created` watermark instead of re-deleting and re-upserting every Zen row on each
	/// `opencode.db` mutation during a live session.
	public static func decodeDatabase(
		fileURL: URL, createdAtOrAfterMillis: Int
	) -> (events: [UsageEvent], watermark: Int) {
		guard let store = OpenCodeStore(fileURL: fileURL) else { return ([], createdAtOrAfterMillis) }
		return OpenCodeModelReader.decode(
			store: store, createdAtOrAfterMillis: createdAtOrAfterMillis, provider: .opencode,
			matches: { OpenCodeGateway.isZen($0.providerID) }, normalize: normalizeModel)
	}
}

// MARK: - IndexableProvider conformance

extension OpenCodeProvider: IndexableProvider {
	/// Only the legacy log is append-only and line-independent; a SQLite file is never tailed.
	public var canTailAppend: Bool { dataFiles().first?.pathExtension != "db" }
	/// Revision 2: the cursor's `offset` field changed meaning for the DB source, from "bytes consumed"
	/// to "`$.time.created` watermark" (the same migration Muse Spark made at its revision 2). The
	/// bump forces one full, scoped re-read so a byte count is never mistaken for a timestamp.
	// Reconcile edits below the creation watermark and repair already-indexed history.
	// Revision 4: retain Zen Sonnet 5.5 cache rates after the direct Anthropic price cut.
	// Revision 5: also read OpenCode's session-v2 `session_message` table; the old `message` table
	// stopped receiving turns after the migration, so post-migration history must be re-read once.
	public var parserRevision: Int { 5 }

	public var resetPolicy: ResetPolicy {
		dataFiles().first?.pathExtension == "db" ? .watermark : .rereadWhole
	}

	public func decodeFile(_ url: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		guard url.pathExtension == "db" else {
			let parsed = OpenCodeProvider.parseUsage(
				fileURL: url, from: offset, reader: JSONLStreamReader())
			return IndexedDecodeResult(events: parsed.events, consumed: parsed.consumed)
		}
		return OpenCodeModelReader.indexed(fileURL: url, from: offset, provider: .opencode,
			matches: { OpenCodeGateway.isZen($0.providerID) }, normalize: Self.normalizeModel)
	}

	public func watermarkTimestamp(_ watermark: Int) -> Date? {
		OpenCodeModelReader.watermarkTimestamp(watermark)
	}
}
