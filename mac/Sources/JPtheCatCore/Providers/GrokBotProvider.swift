import Foundation

/// Grok Bot does not persist token-metered usage on the Mac (inference runs on the cloud computer).
/// This provider exists for CLI wiring and detection only; `loadEvents()` is always empty.
public struct GrokBotProvider: UsageProvider {
	public let id: ProviderID = .grokBot
	public let root: URL

	public init(root: URL? = nil) {
		self.root = root ?? GrokBotAuthToken.appSupportURL()
	}

	public static func isGrokBotDetected(home: URL? = nil) -> Bool {
		GrokBotAuthToken.isSourcePresent(home: home ?? FileManager.default.homeDirectoryForCurrentUser)
	}

	public func watchPaths() -> [URL] { [root] }
	public func isAvailable() -> Bool {
		FileManager.default.fileExists(
			atPath: root.appendingPathComponent(GrokBotAuthToken.secretsFileName).path)
	}
	public func loadEvents() -> [UsageEvent] { [] }
}

extension GrokBotProvider: IndexableProvider {
	/// No local usage ledger — Grok Bot plan usage is opt-in network only; never index `sand-secrets.json`.
	public func dataFiles() -> [URL] { [] }
	public var canTailAppend: Bool { false }
	public var parserRevision: Int { 1 }

	public func decodeFile(_: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		IndexedDecodeResult(events: [], consumed: offset)
	}
}
