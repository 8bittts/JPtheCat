import Foundation

/// The model brands JP tracks out of OpenCode's local store as their OWN dashboard rows.
///
/// Each brand claims the assistant messages whose model id contains its `needle`, regardless of
/// which OpenCode gateway (Zen, Go, or a direct vendor key) served the turn. The gateway rows
/// (`OpenCodeProvider` = Zen, `OpenCodeGoProvider` = Go) display the same turns again under the
/// gateway, but only the brand rows are summed — see `ProviderBasis.gateway`.
///
/// Muse Spark is NOT in this enum: it predates it, is marketed live, carries the legacy-log fallback
/// and a scope disclosure, and lives in `MuseSparkProvider`. Everything the two share is in
/// `OpenCodeStore` / `OpenCodeModelReader`.
///
/// Tier: dashboard-visible, aggregable (`ProviderBasis.notional`), catalog `.localRoadmap` — local
/// accounting only, never a marketing claim. `ProviderCatalog.localAccountingIDs` is derived from this
/// enum so the CLI, the dashboard, and the catalog cannot disagree about the set.
public enum OpenCodeBrand: String, CaseIterable, Sendable {
	case mimo
	case nemotron
	case deepseek
	case bigPickle

	public var id: ProviderID {
		switch self {
		case .mimo: .mimo
		case .nemotron: .nemotron
		case .deepseek: .deepseek
		case .bigPickle: .bigPickle
		}
	}

	/// Lower-cased substring that identifies the brand inside an OpenCode model id.
	public var needle: String {
		switch self {
		case .mimo: "mimo"
		case .nemotron: "nemotron"
		case .deepseek: "deepseek"
		case .bigPickle: "big-pickle"
		}
	}

	/// Model id recorded when a matching row carries no usable id at all.
	public var fallbackModel: String {
		switch self {
		case .mimo: "mimo-v2.5"
		case .nemotron: "nemotron-3-ultra"
		case .deepseek: "deepseek-v4-flash"
		case .bigPickle: "big-pickle"
		}
	}

	/// Dashboard / settings row title. Mirrors `ProviderCatalog` `shortName`.
	public var displayName: String {
		ProviderCatalog.descriptor(for: id)?.shortName ?? rawValue
	}

	/// True when `modelID` belongs to this brand (any vendor prefix, any tier suffix).
	public func matches(modelID: String?) -> Bool {
		guard let modelID, !modelID.isEmpty else { return false }
		return modelID.lowercased().contains(needle)
	}

	/// Parse-time normalisation: drop a `vendor/` prefix, keep everything else — INCLUDING a
	/// `-free` / `-contributor-free` tier suffix. The suffix is what lets `ModelIdentity.isFreeTier`
	/// leave a free turn unpriced on this row exactly as it does on the gateway row; stripping it here
	/// once priced free-tier usage at the paid list rate and summed it into the dollar total. A
	/// Go-routed DeepSeek V4 turn gets a `-go` suffix through `OpenCodeGateway.normalizedModelID` so
	/// the brand row prices it at the same Go list price as the gateway row — the two rows always
	/// agree per turn.
	public func normalizedModelID(_ ref: OpenCodeModelRef) -> String {
		OpenCodeGateway.normalizedModelID(ref, fallback: fallbackModel)
	}
}

/// One `UsageProvider` per `OpenCodeBrand`, reading OpenCode's local SQLite store
/// (`~/.local/share/opencode/opencode.db`). Cost is never taken from the DB's own `cost` column —
/// `UsageEvent` is token-based and priced at read time from `pricing-default.json`, so a brand whose
/// only local usage is a free tier shows tokens (`ProviderRow.isFullyUnpriced`), not a dead `$0.00`.
public struct OpenCodeBrandProvider: UsageProvider {
	public let brand: OpenCodeBrand
	public let root: URL

	public var id: ProviderID { brand.id }

	public init(brand: OpenCodeBrand, root: URL? = nil) {
		self.brand = brand
		self.root = root ?? OpenCodeStorePaths.defaultRoot()
	}

	public func watchPaths() -> [URL] { [root] }

	/// True only when OpenCode's store actually contains this brand's usage. One cached probe serves
	/// every OpenCode-derived provider (`OpenCodeDetection`), so seven rows cost one scan.
	public func isAvailable() -> Bool {
		OpenCodeDetection.current(root: root).brands.contains(brand)
	}

	public func loadEvents() -> [UsageEvent] {
		let dbFile = databaseFile()
		guard FileManager.default.fileExists(atPath: dbFile.path) else { return [] }
		return Deduplicator.dedupe(decodeDatabase(fileURL: dbFile))
	}

	public func dataFiles() -> [URL] { OpenCodeStorePaths.dataFiles(root: root) }

	func databaseFile() -> URL { OpenCodeStorePaths.databaseFile(root: root) }

	// MARK: - DB decoding

	public func decodeDatabase(fileURL: URL) -> [UsageEvent] {
		decodeDatabase(fileURL: fileURL, createdAtOrAfterMillis: 0).events
	}

	public func decodeDatabase(
		fileURL: URL, createdAtOrAfterMillis: Int
	) -> (events: [UsageEvent], watermark: Int) {
		guard let store = OpenCodeStore(fileURL: fileURL) else { return ([], createdAtOrAfterMillis) }
		return OpenCodeModelReader.decode(
			store: store, createdAtOrAfterMillis: createdAtOrAfterMillis, provider: id,
			matches: { brand.matches(modelID: $0.modelID) }, normalize: brand.normalizedModelID)
	}
}

// MARK: - IndexableProvider conformance

extension OpenCodeBrandProvider: IndexableProvider {
	/// Byte offsets mean nothing in a SQLite file, so a changed DB is never tail-appendable.
	public var canTailAppend: Bool { false }
	/// Revision 4: free-tier suffixes are no longer stripped at parse time, so every indexed row's
	/// model id (and therefore its price) must be re-derived once.
	// Reconcile edits below the creation watermark and repair already-indexed history.
	// Revision 6: also read OpenCode's session-v2 `session_message` table; the old `message` table
	// stopped receiving turns after the migration, so post-migration history must be re-read once.
	public var parserRevision: Int { 6 }

	public var resetPolicy: ResetPolicy {
		dataFiles().first?.pathExtension == "db" ? .watermark : .rereadWhole
	}

	public func decodeFile(_ url: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		guard url.pathExtension == "db" else {
			return IndexedDecodeResult(events: [], consumed: FileByteSize.of(url))
		}
		return OpenCodeModelReader.indexed(fileURL: url, from: offset, provider: id,
			matches: { brand.matches(modelID: $0.modelID) }, normalize: brand.normalizedModelID)
	}

	public func watermarkTimestamp(_ watermark: Int) -> Date? {
		OpenCodeModelReader.watermarkTimestamp(watermark)
	}
}
