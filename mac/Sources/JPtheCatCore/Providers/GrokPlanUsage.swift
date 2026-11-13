import Foundation

/// Public identity is Grok; legacy source IDs remain in the warehouse so upgrades never rewrite
/// or discard history. Projection happens after source-scoped reads, not by re-ingesting events.
extension ProviderID {
	public var consolidated: ProviderID {
		switch self { case .cursor, .grokBot: .grok; default: self }
	}

	/// Dashboard, menu-bar, and widget selections only. OpenCode Go is a section of the one
	/// OpenCode row, so a saved Go selection opens that row.
	public static func consolidatedRawID(_ raw: String) -> String {
		if ["cursor", "grok_bot", "grok-bot", "grokbot"].contains(raw) { return "grok" }
		if raw == "opencodego" { return "opencode" }
		return raw
	}
}

/// Which of a provider's independent official pools headlines its bar. A maxed pool tells the user
/// nothing they can act on, so the first pool in display priority that still has room wins. Only when
/// every pool is exhausted does the bar show an exhausted pool, and then the one that frees up soonest
/// (a pool with no reported reset sorts last). Priority, not the largest or smallest percentage,
/// decides among pools with room, so an unrelated fuller pool never displaces the weekly.
public enum PlanPoolHeadline {
	/// A pool whose bar already reads 100% (99.5% rounds there) has no usable room left.
	public static func isExhausted(_ usedPercent: Double) -> Bool { usedPercent >= 99.5 }

	/// Index of the headline pool in `pools`, which must already be in display priority; nil when empty.
	public static func index(of pools: [(usedPercent: Double, resetsAt: Date?)]) -> Int? {
		guard !pools.isEmpty else { return nil }
		if let open = pools.firstIndex(where: { !isExhausted($0.usedPercent) }) { return open }
		return pools.indices.min { left, right in
			switch (pools[left].resetsAt, pools[right].resetsAt) {
			case let (l?, r?): return l < r
			case (_?, nil): return true
			default: return false
			}
		}
	}
}

extension CursorPlanUsage {
	/// Display priority: the weekly included pool, then Cursor Models, All models, combined
	/// included usage, then any other reported pool in its reported order.
	public var prioritizedMeters: [CursorPlanMeter] {
		let order = [CursorPlanMeter.grokBotKey, "cursor_models", "all_models", "included_usage"]
		let ranked = order.compactMap { key in meters.first { $0.key == key } }
		return ranked + meters.filter { !order.contains($0.key) }
	}

	/// The weekly included pool wins while it has room, never the largest percentage across unrelated
	/// pools; a maxed pool yields to the next one with room (`PlanPoolHeadline`). A Cursor-only plan
	/// uses its own billing-cycle meter without calling it weekly or 5-hour.
	public var primaryMeter: CursorPlanMeter? {
		let ordered = prioritizedMeters
		return PlanPoolHeadline.index(of: ordered.map { ($0.usedPercent, $0.resetsAt) }).map { ordered[$0] }
	}
}

/// One opt-in, one cache, and one fetch cadence for the shared dashboard service. Old markers and
/// cached readings are read in place on upgrade, before any asynchronous refresh can run.
public enum GrokPlanUsageStore {
	public static let markerFileName = "grok-plan-usage.enabled"
	public static let readingFileName = "grok-plan-usage.json"
	private static let attemptFileName = "grok-plan-usage.last-attempt"
	private static func directory(_ root: URL?) -> URL { root ?? CursorHookSetup.appSupportDirectory() }
	public static func readingURL(appSupport: URL? = nil) -> URL {
		directory(appSupport).appendingPathComponent(readingFileName)
	}
	public static func isSourcePresent() -> Bool {
		CursorAuthToken.isSourcePresent() || GrokBotAuthToken.isSourcePresent()
	}
	public static func isEnabled(appSupport: URL? = nil) -> Bool {
		FileManager.default.fileExists(atPath: directory(appSupport).appendingPathComponent(markerFileName).path)
			|| CursorPlanUsageStore.isEnabled(appSupport: appSupport)
			|| GrokBotPlanUsageStore.isEnabled(appSupport: appSupport)
	}
	public static func enable(appSupport: URL? = nil) throws {
		let root = directory(appSupport)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		try Data().write(to: root.appendingPathComponent(markerFileName), options: .atomic)
	}
	public static func disable(appSupport: URL? = nil) {
		try? FileManager.default.removeItem(at: directory(appSupport).appendingPathComponent(markerFileName))
		try? FileManager.default.removeItem(at: readingURL(appSupport: appSupport))
		try? FileManager.default.removeItem(at: directory(appSupport).appendingPathComponent(attemptFileName))
		CursorPlanUsageStore.disable(appSupport: appSupport)
		GrokBotPlanUsageStore.disable(appSupport: appSupport)
	}
	public static func save(_ usage: CursorPlanUsage, appSupport: URL? = nil) throws {
		let root = directory(appSupport)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		try encoder.encode(usage).write(to: readingURL(appSupport: appSupport), options: .atomic)
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: readingURL(appSupport: appSupport).path)
	}
	public static func load(now: Date = Date(), appSupport: URL? = nil) -> CursorPlanUsage? {
		guard isEnabled(appSupport: appSupport) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		if let data = try? Data(contentsOf: readingURL(appSupport: appSupport)),
			let usage = try? decoder.decode(CursorPlanUsage.self, from: data) {
			// A new unified cache is authoritative, including an expired/empty answer. Do not
			// resurrect older legacy pools after a successful API response removed an entitlement.
			return usage.current(at: now)
		}
		return legacyUsage(
			cursor: CursorPlanUsageStore.load(now: now, appSupport: appSupport),
			bot: GrokBotPlanUsageStore.load(now: now, appSupport: appSupport))?.current(at: now)
	}
	/// Persist attempts before networking so failed sign-ins cannot bypass the shared cadence on relaunch.
	public static func recordAttempt(at date: Date, appSupport: URL? = nil) throws {
		let root = directory(appSupport)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let url = root.appendingPathComponent(attemptFileName)
		try Data(String(date.timeIntervalSince1970).utf8).write(to: url, options: .atomic)
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
	}
	public static func lastAttemptAt(appSupport: URL? = nil) -> Date? {
		let url = directory(appSupport).appendingPathComponent(attemptFileName)
		let saved = (try? String(contentsOf: url, encoding: .utf8)).flatMap(Double.init)
		let attempt = saved.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
		return [attempt, lastFetchedAt(appSupport: appSupport)].compactMap { $0 }.max()
	}
	public static func lastFetchedAt(appSupport: URL? = nil) -> Date? {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		if let data = try? Data(contentsOf: readingURL(appSupport: appSupport)),
			let usage = try? decoder.decode(CursorPlanUsage.self, from: data) { return usage.fetchedAt }
		return CursorPlanUsageStore.lastFetchedAt(appSupport: appSupport)
			?? GrokBotPlanUsageStore.lastFetchedAt(appSupport: appSupport)
	}

	/// The row's official weekly. A current Grok subscription hook (X Premium+ / SuperGrok) is a
	/// different plan from Grok Bot's sand weekly, so the hook wins when it is current. Sand weekly
	/// is that official weekly only when no hook weekly exists. Cursor billing-cycle never becomes it.
	public static func officialSnapshot(plan: CursorPlanUsage?, hook: RateLimitSnapshot?, now: Date = Date()) -> RateLimitSnapshot? {
		if let hook = hook?.current(at: now), hook.secondary?.windowMinutes == 10080 { return hook }
		if let plan = plan?.current(at: now),
			let weekly = plan.meters.first(where: { $0.key == CursorPlanMeter.grokBotKey }) {
			return RateLimitSnapshot(primary: nil, secondary: RateLimitWindow(usedPercent: weekly.usedPercent,
				windowMinutes: 10080, resetsAt: weekly.resetsAt), planType: plan.planLabel, capturedAt: plan.fetchedAt)
		}
		return hook?.current(at: now)
	}

	/// One display priority shared by CLI/automation/analytics. A billing-cycle pool never
	/// masquerades as weekly headroom: it keeps its own key and label when it headlines.
	public static func primaryMeter(plan: CursorPlanUsage?, fallback: RateLimitSnapshot? = nil,
		now: Date = Date()) -> CursorPlanMeter? {
		let plan = plan?.current(at: now)
		guard let snapshot = officialSnapshot(plan: plan, hook: fallback, now: now),
			let weekly = snapshot.secondary, weekly.windowMinutes == 10080
		else { return plan?.primaryMeter }
		let official: CursorPlanMeter
		if let sand = plan?.meters.first(where: { $0.key == CursorPlanMeter.grokBotKey }),
			sameReading(sand.usedPercent, weekly.usedPercent, sand.resetsAt, weekly.resetsAt) {
			official = sand
		} else {
			official = CursorPlanMeter(key: CursorPlanMeter.grokBotKey, label: snapshot.planType ?? "Weekly included usage",
				usedPercent: weekly.usedPercent, resetsAt: weekly.resetsAt)
		}
		// The official weekly leads; a maxed weekly yields to another of the account's pools with room.
		let others = (plan?.prioritizedMeters ?? []).filter {
			!sameReading($0.usedPercent, official.usedPercent, $0.resetsAt, official.resetsAt)
		}
		let pools = [official] + others
		return PlanPoolHeadline.index(of: pools.map { ($0.usedPercent, $0.resetsAt) }).map { pools[$0] }
	}

	public static func rateLimits(now: Date = Date(), fallback: RateLimitSnapshot? = nil) -> RateLimitSnapshot? {
		officialSnapshot(plan: load(now: now), hook: fallback, now: now)
	}

	/// True when two official readings are the same pool, not two plans that happen to share a key.
	public static func sameReading(_ left: Double, _ right: Double, _ leftReset: Date?, _ rightReset: Date?) -> Bool {
		guard abs(left - right) < 0.05 else { return false }
		switch (leftReset, rightReset) {
		case (nil, nil): return true
		case let (left?, right?): return abs(left.timeIntervalSince(right)) < 1
		default: return false
		}
	}

	public static func legacyUsage(cursor: CursorPlanUsage?, bot: GrokBotPlanUsage?) -> CursorPlanUsage? {
		// Caches predate account IDs: never splice one app's monthly pools into the other's
		// weekly pool. Prefer the complete Cursor cache, otherwise the standalone Bot cache.
		if let cursor { return cursor }
		guard let bot else { return nil }
		return CursorPlanUsage(planName: bot.planName, isTeam: bot.isTeam,
			meters: bot.weekly.map { [$0] } ?? [], fetchedAt: bot.fetchedAt, reportedPlanLabel: bot.planLabel)
	}
}

/// Uses only the three existing DashboardService methods; never refreshes or logs a credential.
/// Alternate sign-ins are fallback candidates, never a license to merge different accounts' pools.
public struct GrokPlanUsageClient: Sendable {
	private let client: CursorPlanUsageClient
	public init(transport: CursorPlanUsageClient.Transport? = nil) {
		client = CursorPlanUsageClient(transport: transport)
	}
	public typealias TokenLoader = @Sendable () -> String?
	public func fetch(tokens: [String], now: Date = Date(), previous: CursorPlanUsage? = nil) async throws -> CursorPlanUsage {
		try await fetch(tokenLoaders: tokens.map { token in { token } }, now: now, previous: previous)
	}
	public func fetch(tokenLoaders: [TokenLoader], now: Date = Date(), previous: CursorPlanUsage? = nil) async throws -> CursorPlanUsage {
		var best: CursorPlanUsage?
		var seen = Set<String>()
		for loadToken in tokenLoaders {
			guard let token = loadToken(), !token.isEmpty, seen.insert(token).inserted else { continue }
			guard let usage = try? await client.fetch(token: token, now: now, allowEmptyEntitlement: true) else { continue }
			if usage.meters.count > (best?.meters.count ?? -1) { best = usage }
			if usage.meters.contains(where: { $0.key == CursorPlanMeter.grokBotKey }) { return usage }
		}
		if let best { return best }
		// On transient failure keep current cached data; never fabricate a post-reset zero.
		if let previous = previous?.current(at: now) { return previous }
		throw CursorPlanUsageClient.FetchError.noToken
	}
}
