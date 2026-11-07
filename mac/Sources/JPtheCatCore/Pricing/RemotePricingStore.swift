import Foundation

/// The middle layer of the three-layer pricing resolution (bundled → **remote ETag override** →
/// unpriced). Model prices drift (a provider cuts rates, a new snapshot ships); rather than force an
/// app update for every table change, JP conditionally fetches a small `pricing-v1.json` published
/// alongside the Sparkle appcast (`https://jpthecat.com/stable/pricing-v1.json`) and overlays it on the
/// bundled defaults.
///
/// Contract, in priority order — the store is **fail-closed** at every step:
///  1. `resolvedTable()` is synchronous and never touches the network: bundled defaults with any
///     previously-cached remote override merged on top (remote wins per-model, bundled fills gaps).
///     Used to seed `DashboardViewModel` at launch so pricing is correct before the first byte of
///     network I/O.
///  2. `refresh()` is an async **conditional GET** using the stored `ETag`. `304 Not Modified` →
///     returns `nil` (cache already current). `200` with a valid, non-empty table → persists it and
///     returns the freshly-merged table for a mid-session hot-swap. Any failure — network error,
///     non-2xx, malformed/empty body — returns `nil`, leaving the last good cache (or bundled)
///     untouched. Pricing must never regress to `$0` because a fetch hiccuped.
///
/// Cost is read-time (`UsageIndex` caches tokens, not dollars), so a returned table flows through
/// `DashboardViewModel.updatePricing(_:)` and re-derives every figure from already-indexed tokens
/// with no disk re-scan.
public final class RemotePricingStore: Sendable {
	/// Older tables can restore Sonnet 5.5's stale cache price over the corrected bundled row.
	static let minimumPricingRevision = 2
	private let fetcher: PricingFetcher
	private let cacheURL: URL?  // verbatim copy of the last accepted remote `{models:…}` body
	private let etagURL: URL?  // the ETag that body was served with, for the next conditional GET

	/// Sibling of the Sparkle appcast; Vercel serves `web/public/stable/*` statically.
	public static let defaultRemoteURL = URL(string: "https://jpthecat.com/stable/pricing-v1.json")!

	/// Production initializer: real URLSession fetcher + App Support cache.
	public convenience init(url: URL = RemotePricingStore.defaultRemoteURL) {
		self.init(
			fetcher: URLSessionPricingFetcher(url: url),
			cacheURL: RemotePricingStore.defaultCacheURL(),
			etagURL: RemotePricingStore.defaultETagURL())
	}

	/// Testable initializer: inject a scripted fetcher and temp cache locations.
	public init(fetcher: PricingFetcher, cacheURL: URL?, etagURL: URL?) {
		self.fetcher = fetcher
		self.cacheURL = cacheURL
		self.etagURL = etagURL
	}

	/// Synchronous best-known table — bundled defaults with any cached remote override merged on top.
	/// Never hits the network; safe to call at launch to seed the cost engine.
	public func resolvedTable() -> PricingTable {
		let bundled = PricingTable.bundledDefault()
		guard let remote = cachedRemoteTable() else { return bundled }
		return bundled.merging(remote)
	}

	/// Conditional GET. Returns a freshly-merged table ONLY when the server sent a new, valid, non-empty
	/// table; `nil` on `304`, network error, non-2xx, or a malformed/empty body (cache left intact).
	public func refresh() async -> PricingTable? {
		let result: PricingFetchResult
		do {
			result = try await fetcher.fetch(etag: storedETag())
		} catch {
			return nil  // fail-closed: keep the last good cache (or bundled)
		}
		switch result {
		case .notModified:
			return nil  // server confirmed our cache is current
		case let .updated(data, etag):
			guard let remote = Self.decodeTable(data) else { return nil }  // malformed/empty → keep cache
			persist(body: data, etag: etag)
			return PricingTable.bundledDefault().merging(remote)
		}
	}

	// MARK: - Cache I/O (fail-closed everywhere; a torn write just forces the next GET to be full)

	private func cachedRemoteTable() -> PricingTable? {
		guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
		return Self.decodeTable(data)
	}

	private func storedETag() -> String? {
		guard cachedRemoteTable() != nil,
			let etagURL, let data = try? Data(contentsOf: etagURL) else { return nil }
		let tag = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
		return tag.isEmpty ? nil : tag
	}

	/// Body first (atomic), then the ETag sidecar. If the ETag write loses, the next launch simply sends
	/// no `If-None-Match` and re-fetches — wasteful but correct, never a mismatched pair.
	private func persist(body: Data, etag: String?) {
		guard let cacheURL else { return }
		try? FileManager.default.createDirectory(
			at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		guard (try? body.write(to: cacheURL, options: .atomic)) != nil else { return }
		guard let etagURL else { return }
		if let etag, !etag.isEmpty {
			try? Data(etag.utf8).write(to: etagURL, options: .atomic)
		} else {
			try? FileManager.default.removeItem(at: etagURL)  // no ETag ⇒ next GET is unconditional
		}
	}

	/// A remote body must decode to `{models:{…}}` with at least one entry. An empty table is rejected so
	/// a truncated or wrong file can never wipe every price to unpriced. An optional `aliases` map is
	/// accepted only when it has no `PricingTable.aliasDefects` against the merged rows; one dangling or
	/// dead alias rejects the body. An optional `rate_multipliers` map must pass
	/// `PricingTable.rateMultipliersAreSound` the same way.
	static func decodeTable(_ data: Data) -> PricingTable? {
		struct File: Decodable {
			let pricing_revision: Int?
			let models: [String: ModelPrice]
			let aliases: [String: String]?
			let rate_multipliers: [String: Double]?
		}
		guard let file = try? JSONDecoder().decode(File.self, from: data), !file.models.isEmpty,
			(file.pricing_revision ?? 0) >= minimumPricingRevision else {
			return nil
		}
		guard file.models.values.allSatisfy({ ($0.contextTierThreshold ?? 200_000) > 0
			&& ($0.contextTierThreshold ?? 200_000) < 10_000_000 }) else { return nil }
		let aliases = file.aliases ?? [:]
		let rows = PricingTable.bundledDefault().knownModels.union(file.models.keys)
		guard PricingTable.aliasDefects(aliases, rows: rows).isEmpty else { return nil }
		let multipliers = file.rate_multipliers ?? [:]
		guard PricingTable.rateMultipliersAreSound(multipliers) else { return nil }
		return PricingTable(models: file.models, aliases: aliases, rateMultipliers: multipliers)
	}

	// MARK: - Default locations (mirror ClaudeRateLimitStore's App Support convention)

	private static func appSupportDir() -> URL? {
		try? FileManager.default.url(
			for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
			.appendingPathComponent("JPtheCat", isDirectory: true)
	}

	static func defaultCacheURL() -> URL? {
		appSupportDir()?.appendingPathComponent("pricing-remote.json")
	}

	static func defaultETagURL() -> URL? {
		appSupportDir()?.appendingPathComponent("pricing-remote.etag")
	}
}

/// When a running app re-checks the hosted table: at launch, then once per `interval` on the existing
/// refresh cadence. A menu-bar app runs for weeks, so a launch-only check left a running app on stale
/// prices — a model priced in the feed stayed "unpriced" until the user relaunched. A clock that moved
/// backwards also counts as due, so the check can never stall.
public enum RemotePricingRefreshPolicy {
	public static let interval: TimeInterval = 24 * 60 * 60

	public static func isDue(lastAttempt: Date?, now: Date) -> Bool {
		guard let lastAttempt else { return true }
		return now < lastAttempt || now.timeIntervalSince(lastAttempt) >= interval
	}
}

/// The one network primitive the store needs, abstracted so tests can script `200`/`304`/error without
/// a live server. Conforms to `Sendable` so the store stays `Sendable`.
public protocol PricingFetcher: Sendable {
	/// Conditional GET with an optional prior `ETag` (sent as `If-None-Match`).
	func fetch(etag: String?) async throws -> PricingFetchResult
}

public enum PricingFetchResult: Sendable {
	case notModified  // HTTP 304
	case updated(data: Data, etag: String?)  // HTTP 2xx body + response ETag (if any)
}

public enum RemotePricingError: Error, Sendable {
	case http(status: Int)
}

/// Real fetcher. Does its own ETag caching, so it bypasses URLSession's local cache to avoid a
/// double-caching layer that could mask a `304`.
public struct URLSessionPricingFetcher: PricingFetcher {
	private let url: URL
	private let session: URLSession

	public init(url: URL, session: URLSession = .shared) {
		self.url = url
		self.session = session
	}

	public func fetch(etag: String?) async throws -> PricingFetchResult {
		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 15
		if let etag, !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

		let (data, response) = try await session.data(for: request)
		guard let http = response as? HTTPURLResponse else {
			return .updated(data: data, etag: nil)  // non-HTTP (e.g. file URL in a test) — treat as fresh
		}
		if http.statusCode == 304 { return .notModified }
		guard (200..<300).contains(http.statusCode) else {
			throw RemotePricingError.http(status: http.statusCode)
		}
		return .updated(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
	}
}
