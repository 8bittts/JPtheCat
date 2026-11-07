import Foundation

/// Reads **OpenCode Go** usage from OpenCode's local SQLite store
/// (`~/.local/share/opencode/opencode.db`).
///
/// Go is the $10/month OpenCode Zen subscription. OpenCode records its gateway as `opencode-go` on
/// every assistant message it routes there, so this provider claims exactly those rows — the same
/// store `OpenCodeProvider` (Zen) and the model-brand providers read, filtered by GATEWAY instead of
/// by model.
///
/// Cost basis is `ProviderBasis.gateway`: Go's dollars are real usage that ALSO appears under the
/// model-brand row that owns each model (e.g. DeepSeek), so Go is displayed but never summed into the
/// aggregate. Go's official documented caps (per `OpenCodeGoLimits`) are applied against locally
/// recorded cost. OpenCode publishes NO local reset boundary — the windows are 5-hour / weekly /
/// monthly dollar ceilings — so JP shows measured usage-versus-cap and never a fabricated reset
/// countdown.
public struct OpenCodeGoProvider: UsageProvider {
	public let id: ProviderID = .opencodego
	public let root: URL

	public init(root: URL? = nil) {
		self.root = root ?? OpenCodeStorePaths.defaultRoot()
	}

	public func watchPaths() -> [URL] { [root] }

	/// True only when OpenCode's store actually carries Go-routed usage (shared cached probe).
	public func isAvailable() -> Bool {
		OpenCodeDetection.current(root: root).go
	}

	public func loadEvents() -> [UsageEvent] {
		let dbFile = databaseFile()
		guard FileManager.default.fileExists(atPath: dbFile.path) else { return [] }
		return Deduplicator.dedupe(Self.decodeDatabase(fileURL: dbFile))
	}

	public func dataFiles() -> [URL] { OpenCodeStorePaths.dataFiles(root: root) }

	func databaseFile() -> URL { OpenCodeStorePaths.databaseFile(root: root) }

	// MARK: - DB decoding

	public static func decodeDatabase(fileURL: URL) -> [UsageEvent] {
		decodeDatabase(fileURL: fileURL, createdAtOrAfterMillis: 0).events
	}

	public static func decodeDatabase(
		fileURL: URL, createdAtOrAfterMillis: Int
	) -> (events: [UsageEvent], watermark: Int) {
		guard let store = OpenCodeStore(fileURL: fileURL) else { return ([], createdAtOrAfterMillis) }
		return OpenCodeModelReader.decode(
			store: store, createdAtOrAfterMillis: createdAtOrAfterMillis, provider: .opencodego,
			matches: { OpenCodeGateway.isGo($0.providerID) }, normalize: normalizedModelID)
	}

	/// Go-routed turns created at or after `since` — the bounded read the dashboard's measured
	/// usage-vs-cap windows need (the longest window is 30 days), instead of decoding the lifetime
	/// message set on every refresh.
	public func recentEvents(since: Date) -> [UsageEvent] {
		let dbFile = databaseFile()
		guard FileManager.default.fileExists(atPath: dbFile.path),
			let store = OpenCodeStore(fileURL: dbFile)
		else { return [] }
		let bound = max(1, Int(since.timeIntervalSince1970 * 1000))
		return OpenCodeModelReader.messages(
			store: store, createdAtOrAfterMillis: bound, provider: .opencodego,
			matches: { OpenCodeGateway.isGo($0.providerID) }, normalize: Self.normalizedModelID
		).events
	}

	/// Parse-time normalisation keeps any tier suffix (one rule for every OpenCode-derived row — see
	/// `OpenCodeBrand.normalizedModelID`) and appends `-go` to the few DeepSeek V4 models whose Go
	/// list price differs from Zen's so their usage prices on the dedicated Go row; only the
	/// published-cap lookup strips the `-go` and `-free` markers.
	public static func normalizedModelID(_ ref: OpenCodeModelRef) -> String {
		OpenCodeGateway.normalizedModelID(ref, fallback: "opencode-go")
	}
}

// MARK: - IndexableProvider conformance

extension OpenCodeGoProvider: IndexableProvider {
	// The DB is re-queried whole every refresh (like the other OpenCode-derived providers); it is not
	// an append-only log, so tailing is never safe here.
	public var canTailAppend: Bool { false }
	/// Revision 2: tier suffixes are no longer stripped at parse time.
	// Reconcile edits below the creation watermark and repair already-indexed history.
	// Revision 4: also read OpenCode's session-v2 `session_message` table; the old `message` table
	// stopped receiving turns after the migration, so post-migration history must be re-read once.
	public var parserRevision: Int { 4 }

	public var resetPolicy: ResetPolicy {
		dataFiles().first?.pathExtension == "db" ? .watermark : .rereadWhole
	}

	public func decodeFile(_ url: URL, from offset: Int, parserState _: String?) -> IndexedDecodeResult {
		guard url.pathExtension == "db" else {
			return IndexedDecodeResult(events: [], consumed: FileByteSize.of(url))
		}
		return OpenCodeModelReader.indexed(fileURL: url, from: offset, provider: .opencodego,
			matches: { OpenCodeGateway.isGo($0.providerID) }, normalize: Self.normalizedModelID)
	}

	public func watermarkTimestamp(_ watermark: Int) -> Date? {
		OpenCodeModelReader.watermarkTimestamp(watermark)
	}
}

// MARK: - Official usage caps

/// OpenCode Go's officially documented usage ceilings, from <https://opencode.ai/docs/go/>.
///
/// Go is a $10/month subscription metered in DOLLAR-EQUIVALENT usage, not tokens: each model has its
/// own monthly limit, and the shorter windows are fixed fractions of it — 5-hour = 20% of the
/// monthly limit, weekly = 50%, monthly = 100%.
///
/// These are the provider's PUBLISHED caps applied to JP's locally recorded cost. OpenCode writes no
/// window/reset state to disk (its `account`/`credential` tables are empty and its `event` table
/// carries only message/session events), so this is measured usage against a documented ceiling —
/// never a provider-reported remaining percentage, and never a reset countdown.
public enum OpenCodeGoLimits {
	public static let fiveHourFraction = 0.20
	public static let weeklyFraction = 0.50
	public static let monthlyFraction = 1.0

	/// The nominal window lengths, matching the rest of the app (Codex 300 / 10080).
	public static let fiveHourMinutes = 300
	public static let weeklyMinutes = 10080
	/// Go's longest window is the monthly limit itself. OpenCode's own console draws the same three
	/// bars, so the trailing window is a nominal 30 days.
	public static let monthlyMinutes = 43200

	/// Base monthly cap in USD for a Go model id, or nil when the model is not (yet) in the published
	/// table — in which case JP shows its measured usage with no cap fraction rather than inventing
	/// one. A currently-running promotion multiplies the base (see `promotions`).
	public static func monthlyCapUSD(for modelID: String, now: Date = Date()) -> Double? {
		monthlyCapUSD(for: modelID, now: now, promotions: promotions)
	}

	static func monthlyCapUSD(for modelID: String, now: Date, promotions: [String: Promotion]) -> Double? {
		// Caps are per published model: the gateway route, peak window, and free tier share one cap.
		let key = ModelIdentity.modelKey(modelID, aliases: [:])
		guard let base = baseMonthlyCapUSD(for: key) else { return nil }
		return base * promotionMultiplier(promotions[key], now: now)
	}

	private static func baseMonthlyCapUSD(for key: String) -> Double? {
		switch key {
		case "glm-5.3-flash", "glm-5.2", "glm-5.1", "kimi-k2.7-code", "kimi-k2.6", "longcat-2.0",
			"mimo-v2.5", "mimo-v2.6-flash", "minimax-m3", "minimax-m2.7", "minimax-m2.5", "muse-spark-1.3-contributor",
			"muse-spark-1.2-contributor", "qwen3.7-plus", "qwen3.6-plus", "hy3":
			return 60
		case "deepseek-v4.1-flash":
			return 100
		case "glm-5.3", "kimi-k3", "mimo-v2.5-pro", "mimo-v2.6-pro", "qwen3.8-max", "deepseek-v4-pro",
			"deepseek-v4-flash-vision-exp", "grok-4.6", "grok-4.7", "gpt-6-luna", "gpt-5.6-luna", "claude-haiku-5-5", "kimi-k3.1-pro", "step-5-preview":
			return 15
		case "qwen3.8-flash", "qwen3.7-max", "deepseek-v4-flash", "hy4-preview", "space-bunny", "gemini-4-argon":
			return 30
		case "minimax-m3.1-flash":
			return 20
		default:
			return nil
		}
	}

	/// A dated promotional multiplier from the published table. The END DATE is stored so the cap
	/// reverts by itself instead of silently drifting.
	struct Promotion {
		let multiplier: Double
		/// Exclusive midnight UTC after the published final day.
		let endsAt: DateComponents
	}

	/// Promotions currently published on opencode.ai/docs/go. None as of the 2026-10-30 audit: the
	/// DeepSeek V4.1 Flash limit that earlier ran as a dated 4x window is now listed at $100 with no end.
	static let promotions: [String: Promotion] = [:]

	private static var utcCalendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		return calendar
	}

	private static func promotionMultiplier(_ promo: Promotion?, now: Date) -> Double {
		guard let promo, let end = utcCalendar.date(from: promo.endsAt) else { return 1 }
		return now < end ? promo.multiplier : 1
	}

	/// The cap in USD for `modelID` over the given window, or nil when the model has no published cap.
	public static func capUSD(for modelID: String, windowMinutes: Int, now: Date = Date()) -> Double? {
		guard let monthly = monthlyCapUSD(for: modelID, now: now) else { return nil }
		switch windowMinutes {
		case fiveHourMinutes: return monthly * fiveHourFraction
		case weeklyMinutes: return monthly * weeklyFraction
		case monthlyMinutes: return monthly * monthlyFraction
		default: return nil
		}
	}

	/// Locally measured cost for one model over the trailing `windowMinutes`, as a 0–100 used-percent
	/// of that model's documented cap. Nil when the model has no cap or the cap is non-positive.
	public static func usedPercent(
		cost: Double, modelID: String, windowMinutes: Int, now: Date = Date()
	) -> Double? {
		guard let cap = capUSD(for: modelID, windowMinutes: windowMinutes, now: now), cap > 0 else {
			return nil
		}
		return min(100, max(0, cost / cap * 100))
	}

	/// Go's three measured usage-vs-cap windows in the provider's own order — 5-hour, weekly, monthly.
	/// Each is the TIGHTEST model in that window (the one nearest its cap; the binding constraint), or
	/// absent when no model in the window carries BOTH a published cap and a JP price.
	///
	/// Every returned window has `resetsAt: nil` on purpose: OpenCode publishes the caps but writes no
	/// window boundary to disk, so a countdown here would be invented. A window with no measurable
	/// model is dropped rather than reported as 0%, and an empty result means "nothing measurable yet".
	///
	/// [Regression guard] A capped model JP cannot price (no `pricing-default.json` row, or a free-tier
	/// id) contributes NOTHING — it is skipped, never counted as $0. Counting it as $0 once produced a
	/// fabricated "0% of 5h" bar for every GLM / Kimi / Qwen user (`OpenCodeGoProviderTests`).
	public static func measuredWindows(
		events: [UsageEvent], calculator: CostCalculator, now: Date = Date()
	) -> [RateLimitWindow] {
		func tightest(windowMinutes: Int, seconds: TimeInterval) -> RateLimitWindow? {
			let cutoff = now.addingTimeInterval(-seconds)
			var perModel: [String: Double] = [:]
			for event in events where event.timestamp >= cutoff && event.timestamp <= now {
				guard let cost = calculator.cost(model: event.model, usage: event.usage) else { continue }
				perModel[ModelIdentity.presentationID(event.model), default: 0] += cost
			}
			var best: Double?
			for (model, cost) in perModel {
				guard
					let pct = usedPercent(
						cost: cost, modelID: model, windowMinutes: windowMinutes, now: now)
				else { continue }
				best = max(best ?? 0, pct)
			}
			guard let used = best else { return nil }
			return RateLimitWindow(usedPercent: used, windowMinutes: windowMinutes, resetsAt: nil)
		}
		return [
			tightest(windowMinutes: fiveHourMinutes, seconds: 5 * 3600),
			tightest(windowMinutes: weeklyMinutes, seconds: 7 * 24 * 3600),
			tightest(windowMinutes: monthlyMinutes, seconds: 30 * 24 * 3600),
		].compactMap { $0 }
	}
}
