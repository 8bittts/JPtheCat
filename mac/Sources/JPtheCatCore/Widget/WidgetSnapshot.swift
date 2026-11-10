import Foundation

public enum JPWidgetContract {
	public static let kind = "JPtheCatWidget"
}

/// Legacy snapshot field: JP is free, so the app always writes `.premium`. The other cases stay only so
/// snapshots written by older (paid-era) builds still decode; nothing gates on them any more.
public enum WidgetAccessState: String, Codable, Equatable, Sendable {
	case premium
	case trialActive
	case locked
}

public enum WidgetCostBasis: String, Codable, Equatable, Sendable {
	case realSpend
	case notionalListPrice
	case realAndNotionalListPrice

	public var shortLabel: String {
		switch self {
		case .realSpend: return "real spend"
		case .notionalListPrice: return "notional"
		case .realAndNotionalListPrice: return "incl notional"
		}
	}

}

public enum WidgetValueMetric: String, Codable, Equatable, Sendable {
  case dollars
  case tokens
  case percent
}

public struct WidgetProviderSnapshot: Codable, Equatable, Identifiable, Sendable {
	public let id: String
	public let name: String
	public let tintHex: String
	public let today: Double
	public let window: Double
	public let currencyCode: String
  public let metric: WidgetValueMetric
	public let basis: WidgetCostBasis
	public let usedPercent: Double?
	/// Carried in the App-Group contract (and the publisher writes it) but intentionally UNrendered by the
	/// widget today — the bare gauge bar shows only the 5h `usedPercent`; keep the field for forward-compat
	/// (a future weekly-gauge surface / the app) so a dead-code sweep does not strip it and bump the schema.
	public let weeklyUsedPercent: Double?
	public let usageOfficial: Bool
	public let series: [Double]

	public init(
		id: String,
		name: String,
		tintHex: String,
		today: Double,
		window: Double,
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
    metric: WidgetValueMetric = .dollars,
		basis: WidgetCostBasis,
		usedPercent: Double?,
		weeklyUsedPercent: Double?,
		usageOfficial: Bool,
		series: [Double]
	) {
		self.id = id
		self.name = name
		self.tintHex = tintHex
		self.today = today
		self.window = window
		self.currencyCode = currencyCode
    self.metric = metric
		self.basis = basis
		self.usedPercent = usedPercent
		self.weeklyUsedPercent = weeklyUsedPercent
		self.usageOfficial = usageOfficial
		self.series = series
	}
}

extension WidgetProviderSnapshot {
	/// The basis word a token row carries: `gateway` for the OpenCode Zen and Go rollups, `estimate` for
	/// unpriced estimates (Copilot, Cursor). Read from `ProviderBasis`, the one owner of badge words, so the
	/// widget says what the dashboard says.
	public var tokenBasisLabel: String {
		switch ProviderBasis.of(rawID: id) {
		case .gateway: ProviderBasis.gateway.badge
		case .officialPlan: ProviderBasis.officialPlan.badge
		default: ProviderBasis.estimate.badge
		}
	}
}

/// One provider's figures for a single non-selected window, keyed into
/// `WidgetWindowSnapshot.providerWindows` by provider id. Everything else about a provider
/// (today total, rate-limit %, tint, basis, currency) is NOT window-dependent and stays on
/// `WidgetProviderSnapshot` itself.
public struct WidgetProviderWindow: Codable, Equatable, Sendable {
	public let window: Double
	public let series: [Double]

	public init(window: Double, series: [Double]) {
		self.window = window
		self.series = series
	}
}

/// One full window's worth of aggregate + per-provider figures (7/14/30/90 days), computed in a
/// single indexed scan by `UsageIndex.multiWindowSummaries`. `WidgetSnapshot.windows` carries one
/// of these per supported day-count so each widget instance can pick its own via
/// `selectingWindow(days:)` instead of always mirroring the in-app dashboard's chosen timeframe.
public struct WidgetWindowSnapshot: Codable, Equatable, Sendable {
	public let days: Int
	public let totalWindow: Double
	public let series: [Double]
	public let providerWindows: [String: WidgetProviderWindow]

  public init(
    days: Int, totalWindow: Double, series: [Double],
    providerWindows: [String: WidgetProviderWindow]
  ) {
		self.days = days
		self.totalWindow = totalWindow
		self.series = series
		self.providerWindows = providerWindows
	}
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
	// v2 adds `availabilityNotice` so an all-sources-unavailable snapshot can disclose the exclusion rather
	// than presenting a bare "$0.00" total. v3 adds `windows`, a per-day-count side-channel carrying every
	// supported timeframe's aggregate + per-provider figures so each placed widget instance can select its
	// own via `selectingWindow(days:)` instead of always mirroring the in-app dashboard's currently-selected
	// window. The persisted App Group file survives app updates, so bumping this makes an older build
	// reject the newer file (falling back to the placeholder) instead of structurally mis-decoding it.
  public static let schemaVersion = 4

	public let schemaVersion: Int
	public let generatedAt: Date
	public let access: WidgetAccessState
	public let title: String
	public let totalToday: Double
	public let totalWindow: Double
	public let currencyCode: String
  public let metric: WidgetValueMetric
	public let windowDays: Int
	public let basis: WidgetCostBasis
	public let series: [Double]
	public let providers: [WidgetProviderSnapshot]
	public let staleAfter: Date
	public let errorMessage: String?
	/// Aggregate availability disclosure (e.g. "Codex unavailable; aggregate excludes it …"). Non-nil only
	/// for the All-providers face; dropped when the widget is focused on a single provider.
	public let availabilityNotice: String?
	/// Every supported timeframe's data, keyed by day-count (7/14/30/90). The singular fields above always
	/// mirror `windows[windowDays]` (the "currently selected" window) so existing render code needs no
	/// change; `selectingWindow(days:)` is the only place that reads this dictionary.
	public let windows: [Int: WidgetWindowSnapshot]

	public init(
		schemaVersion: Int = Self.schemaVersion,
		generatedAt: Date,
		access: WidgetAccessState,
		title: String,
		totalToday: Double,
		totalWindow: Double,
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
    metric: WidgetValueMetric = .dollars,
		windowDays: Int,
		basis: WidgetCostBasis,
		series: [Double],
		providers: [WidgetProviderSnapshot],
		staleAfter: Date,
		errorMessage: String?,
		availabilityNotice: String? = nil,
		windows: [Int: WidgetWindowSnapshot] = [:]
	) {
		self.schemaVersion = schemaVersion
		self.generatedAt = generatedAt
		self.access = access
		self.title = title
		self.totalToday = totalToday
		self.totalWindow = totalWindow
		self.currencyCode = currencyCode
    self.metric = metric
		self.windowDays = windowDays
		self.basis = basis
		self.series = series
		self.providers = providers
		self.staleAfter = staleAfter
		self.errorMessage = errorMessage
		self.availabilityNotice = availabilityNotice
		self.windows = windows
	}

	/// True whenever the readable dollar total blends in Codex notional list-price (mixed real+notional)
	/// or is wholly notional — the cases AGENTS.md rule (b) requires the widget to disclose visibly AND
	/// in the accessibility value. Only pure `.realSpend` needs no notional marker. This intentionally
	/// replaces the earlier inverted `basis != .realAndNotionalListPrice` helper, which hid the
	/// disclosure exactly when Codex notional was included.
	public var disclosesNotionalBasis: Bool { metric != .percent && basis != .realSpend }

	public var primaryValueCaption: String { metric == .percent ? "included usage" : "today" }

	public func heroAccessibilitySummary(amount: String) -> String {
		if metric == .percent { return "\(title), official plan usage, \(amount) used" }
		return "\(title), today \(amount), \(basis.shortLabel), last \(windowDays) days"
	}

	/// The single availability/error line the widget surfaces — a hard `errorMessage` (refresh failed)
	/// takes precedence over the softer `availabilityNotice` (a source excluded from the aggregate). One
	/// source of truth for the visual footer/caption AND the VoiceOver summary, so a screen-reader user
	/// never hears a bare "$0.00" total without the disclosure the sighted faces already show.
	public var disclosureNotice: String? { errorMessage ?? availabilityNotice }

	/// The snapshot is past the freshness horizon the publisher stamped (`staleAfter`). Widgets are
	/// glanceable timeline snapshots that keep re-reading the same file when the app isn't running, so
	/// the UI must degrade (show a stale marker) rather than present hours-old numbers as live.
	public func isStale(now: Date = Date()) -> Bool { now >= staleAfter }

	/// Content equality that ignores the two always-moving timestamps (`generatedAt`, `staleAfter`) so
	/// the publisher can skip redundant App Group writes + `WidgetCenter` reloads when nothing the user
	/// would see has changed — WidgetKit budgets reloads, and rewriting an identical file every refresh
	/// tick wastes I/O and can get legitimate updates throttled.
	/// Two dollar figures are "the same" for republish-suppression at cent granularity. The grouped
	/// window scan sums `Double`s in SQLite `GROUP BY` order, so a value can differ from a prior run in
	/// the ~1e-9 tail while displaying identically ($X.XX); an exact `==` would spuriously re-publish +
	/// reload (WidgetKit budgets reloads). Cent-rounding compares what the user actually sees. This must
	/// cover EVERY money surface — top-level AND the nested per-provider / per-window figures — or the
	/// suppression is only half-applied (a nested `today`/`window`/`series` drift still trips exact `==`).
	private static func sameCents(_ a: Double, _ b: Double) -> Bool {
		(a * 100).rounded() == (b * 100).rounded()
	}
	private static func sameCents(_ a: [Double], _ b: [Double]) -> Bool {
		a.count == b.count && zip(a, b).allSatisfy { sameCents($0, $1) }
	}
	private static func sameContent(_ a: WidgetProviderSnapshot, _ b: WidgetProviderSnapshot) -> Bool {
		a.id == b.id && a.name == b.name && a.tintHex == b.tintHex && a.currencyCode == b.currencyCode
			&& a.metric == b.metric && a.basis == b.basis && a.usedPercent == b.usedPercent
			&& a.weeklyUsedPercent == b.weeklyUsedPercent && a.usageOfficial == b.usageOfficial
			&& sameCents(a.today, b.today) && sameCents(a.window, b.window) && sameCents(a.series, b.series)
	}
	private static func sameContent(_ a: WidgetProviderWindow, _ b: WidgetProviderWindow) -> Bool {
		sameCents(a.window, b.window) && sameCents(a.series, b.series)
	}
	private static func sameContent(_ a: WidgetWindowSnapshot, _ b: WidgetWindowSnapshot) -> Bool {
		a.days == b.days && sameCents(a.totalWindow, b.totalWindow) && sameCents(a.series, b.series)
			&& a.providerWindows.count == b.providerWindows.count
			&& a.providerWindows.allSatisfy { key, value in
				b.providerWindows[key].map { sameContent(value, $0) } ?? false
			}
	}

	public func hasSameContent(as other: WidgetSnapshot) -> Bool {
		schemaVersion == other.schemaVersion
			&& access == other.access
			&& title == other.title
			&& Self.sameCents(totalToday, other.totalToday)
			&& Self.sameCents(totalWindow, other.totalWindow)
			&& currencyCode == other.currencyCode
      && metric == other.metric
			&& windowDays == other.windowDays
			&& basis == other.basis
			&& Self.sameCents(series, other.series)
			&& providers.count == other.providers.count
			&& zip(providers, other.providers).allSatisfy { Self.sameContent($0, $1) }
			&& errorMessage == other.errorMessage
			&& availabilityNotice == other.availabilityNotice
			&& windows.count == other.windows.count
			&& windows.allSatisfy { key, value in
				other.windows[key].map { Self.sameContent(value, $0) } ?? false
			}
	}

	public func focused(providerID: String?) -> WidgetSnapshot {
		guard
			let providerID,
			providerID != "all",
			let provider = providers.first(where: { $0.id == ProviderID.consolidatedRawID(providerID) })
		else {
			return self
		}
		return WidgetSnapshot(
			generatedAt: generatedAt,
			access: access,
			title: provider.name,
			totalToday: provider.today,
			totalWindow: provider.window,
			currencyCode: provider.currencyCode,
      metric: provider.metric,
			windowDays: windowDays,
			basis: provider.basis,
			series: provider.series,
			providers: [provider],
			staleAfter: staleAfter,
			errorMessage: errorMessage,
			// The notice is an aggregate concern; a single-provider face doesn't carry it.
			availabilityNotice: nil,
			windows: windows)
	}

	/// Returns a copy with the singular "currently selected" fields (`windowDays`/`totalWindow`/`series`
	/// and every provider's `window`/`series`) replaced from `windows[days]`. No-ops (returns `self`
	/// unchanged) when that day-count isn't present — e.g. an older snapshot written before this window
	/// was requested, or a widget configured with a day-count the publisher doesn't currently populate.
	/// Every OTHER `WidgetProviderSnapshot` field (today, rate-limit %, tint, basis, currency) is NOT
	/// window-dependent and is copied through unchanged. Call this BEFORE `focused(providerID:)` so the
	/// provider-narrowing step picks up the already-window-selected per-provider figures.
	public func selectingWindow(days: Int) -> WidgetSnapshot {
		guard let selected = windows[days] else { return self }
		let updatedProviders = providers.map { provider -> WidgetProviderSnapshot in
      guard provider.metric != .percent, let providerWindow = selected.providerWindows[provider.id] else {
        return provider
      }
			return WidgetProviderSnapshot(
				id: provider.id,
				name: provider.name,
				tintHex: provider.tintHex,
				today: provider.today,
				window: providerWindow.window,
				currencyCode: provider.currencyCode,
        metric: provider.metric,
				basis: provider.basis,
				usedPercent: provider.usedPercent,
				weeklyUsedPercent: provider.weeklyUsedPercent,
				usageOfficial: provider.usageOfficial,
				series: providerWindow.series)
		}
		return WidgetSnapshot(
			generatedAt: generatedAt,
			access: access,
			title: title,
			totalToday: totalToday,
			totalWindow: selected.totalWindow,
			currencyCode: currencyCode,
      metric: metric,
			windowDays: selected.days,
			basis: basis,
			series: selected.series,
			providers: updatedProviders,
			staleAfter: staleAfter,
			errorMessage: errorMessage,
			availabilityNotice: availabilityNotice,
			windows: windows)
	}

}

public enum WidgetSnapshotStoreError: Error, Equatable {
	/// The on-disk snapshot was written by a build with a different schema. The App Group file persists
	/// across app updates, so a version bump must reject (not structurally mis-decode) an old file and
	/// fall back to the placeholder rather than render misinterpreted figures.
	case unsupportedSchemaVersion(found: Int, expected: Int)
}

public struct WidgetSnapshotStore {
	public static let appGroupID = "GRNGR33Z8A.com.8bittts.jpthecat"
	public static let fileName = "widget-snapshot.json"

	private let rootURL: URL
	private let fileManager: FileManager
	private let encoder: JSONEncoder
	private let decoder: JSONDecoder

	public init(
		rootURL: URL = WidgetSnapshotStore.defaultRootURL(),
		fileManager: FileManager = .default
	) {
		self.rootURL = rootURL
		self.fileManager = fileManager
		encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
	}

	public var snapshotURL: URL {
		rootURL.appendingPathComponent(Self.fileName, isDirectory: false)
	}

	public func write(_ snapshot: WidgetSnapshot) throws {
		try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
		let data = try encoder.encode(snapshot)
		try data.write(to: snapshotURL, options: [.atomic])
	}

	public func read() throws -> WidgetSnapshot {
		let data = try Data(contentsOf: snapshotURL)
		let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
		guard decoded.schemaVersion == WidgetSnapshot.schemaVersion else {
			throw WidgetSnapshotStoreError.unsupportedSchemaVersion(
        found: decoded.schemaVersion, expected: WidgetSnapshot.schemaVersion
      )
		}
		return decoded
	}

	public func readIfAvailable() -> WidgetSnapshot? {
		try? read()
	}

	/// Whether the shared App Group container resolved. The main app is NOT sandboxed, which is exactly
	/// the case where `containerURL(forSecurityApplicationGroupIdentifier:)` can return nil (dropped
	/// app-groups entitlement / unsigned); the publisher uses this to log instead of silently writing to
	/// the App Support fallback the sandboxed widget can't read.
	public static func resolvedRootIsAppGroup(fileManager: FileManager = .default) -> Bool {
		fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
	}

	public static func defaultRootURL(fileManager: FileManager = .default) -> URL {
    if let groupURL = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupID)
    {
			return groupURL.appendingPathComponent("Widget", isDirectory: true)
		}
    let appSupport =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
			.first ?? fileManager.temporaryDirectory
    return
      appSupport
			.appendingPathComponent("JPtheCat", isDirectory: true)
			.appendingPathComponent("Widget", isDirectory: true)
	}
}
