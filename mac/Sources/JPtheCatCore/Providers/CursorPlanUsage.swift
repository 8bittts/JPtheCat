import Foundation

/// One OFFICIAL usage meter Cursor reports for the signed-in account: a provider-computed percentage
/// with its own reset boundary. Never derived from local tokens.
public struct CursorPlanMeter: Sendable, Equatable, Codable, Identifiable {
	/// Stable JP key: `cursor_models`, `other_models`, or `grok_bot_weekly`.
	public let key: String
	/// Cursor's own dashboard label, e.g. "Cursor Models".
	public let label: String
	/// 0–100, clamped.
	public let usedPercent: Double
	public let resetsAt: Date?
	public var id: String { key }
	public static let grokBotKey = "grok_bot_weekly"

	public init(key: String, label: String, usedPercent: Double, resetsAt: Date?) {
		self.key = key
		self.label = label
		self.usedPercent = min(100, max(0, usedPercent))
		self.resetsAt = resetsAt
	}

	/// Same freshness rule as every official window: shown only while its reset is still ahead.
	public func isCurrent(at now: Date) -> Bool {
		guard let resetsAt else { return true }
		return resetsAt > now
	}
}

/// Official shared Grok / Cursor / Grok Bot plan pools for the signed-in account.
/// The legacy type name is retained for persisted cache compatibility.
///
/// Sourced ONLY from Cursor's own usage API after the user opts in (Settings -> Live data). Cursor
/// computes every percentage; JP never derives one from local tokens and never fabricates a plan.
public struct CursorPlanUsage: Sendable, Equatable, Codable {
	/// Cursor's plan name, e.g. "Pro", "Ultra", or "Team". Nil when Cursor did not report one.
	public let planName: String?
	public let reportedPlanLabel: String?
	/// True when Cursor reports a team-scoped limit (a team seat) rather than a personal plan.
	public let isTeam: Bool
	public let meters: [CursorPlanMeter]
	public let fetchedAt: Date

	public init(planName: String?, isTeam: Bool, meters: [CursorPlanMeter], fetchedAt: Date, reportedPlanLabel: String? = nil) {
		self.reportedPlanLabel = reportedPlanLabel
		self.planName = planName
		self.isTeam = isTeam
		self.meters = meters
		self.fetchedAt = fetchedAt
	}

	/// Drops meters whose reset boundary has passed; nil when no current meter remains.
	public func current(at now: Date = Date()) -> CursorPlanUsage? {
		let live = meters.filter { $0.isCurrent(at: now) }
		guard !live.isEmpty else { return nil }
		return CursorPlanUsage(planName: planName, isTeam: isTeam, meters: live, fetchedAt: fetchedAt, reportedPlanLabel: reportedPlanLabel)
	}

	/// Keeps the previous reading's still-current Grok Bot meter and plan name when THIS fetch could
	/// not load them. Never carries a meter past its own reset, and never overrides a fresh answer.
	func carryingOver(
		from previous: CursorPlanUsage?, grokBotFailed: Bool, planNameFailed: Bool, now: Date
	) -> CursorPlanUsage {
		guard let previous else { return self }
		var meters = self.meters
		if grokBotFailed, !meters.contains(where: { $0.key == CursorPlanMeter.grokBotKey }),
			let carried = previous.meters.first(where: { $0.key == CursorPlanMeter.grokBotKey }),
			carried.isCurrent(at: now)
		{
			meters.append(carried)
		}
		let name = planNameFailed ? (planName ?? previous.planName) : planName
		return CursorPlanUsage(planName: name, isTeam: isTeam, meters: meters, fetchedAt: fetchedAt, reportedPlanLabel: reportedPlanLabel)
	}

	/// "Team seat" / "Pro plan" style label for the detail header; nil without a plan name.
	public var planLabel: String? {
		if let reportedPlanLabel, !reportedPlanLabel.isEmpty { return reportedPlanLabel }
		guard let planName, !planName.isEmpty else { return nil }
		return isTeam ? "\(planName) seat" : "\(planName) plan"
	}

	/// Cursor billing-cycle meters. Named from Cursor's plan, never from the Grok Bot plan label.
	public var cursorQuotaTitle: String {
		guard let planName, !planName.isEmpty else { return "Cursor included usage" }
		return isTeam ? "Cursor · \(planName) seat" : "Cursor · \(planName) plan"
	}

	/// One header per product. Bars under a header keep Cursor's own pool labels.
	public struct QuotaGroup: Identifiable, Equatable, Sendable {
		public let title: String
		public let meters: [CursorPlanMeter]
		public var id: String { title }
	}

	public func quotaGroups(meters: [CursorPlanMeter]) -> [QuotaGroup] {
		let cursorKeys: Set<String> = ["cursor_models", "other_models", "included_usage"]
		var groups: [QuotaGroup] = []
		let cursor = meters.filter { cursorKeys.contains($0.key) }
		if !cursor.isEmpty { groups.append(QuotaGroup(title: cursorQuotaTitle, meters: cursor)) }
		let bot = meters.filter { $0.key == CursorPlanMeter.grokBotKey }
		if !bot.isEmpty { groups.append(QuotaGroup(title: detailHeader(providerName: "Grok Bot"), meters: bot)) }
		let rest = meters.filter { !cursorKeys.contains($0.key) && $0.key != CursorPlanMeter.grokBotKey }
		if !rest.isEmpty { groups.append(QuotaGroup(title: detailHeader(providerName: "Grok"), meters: rest)) }
		return groups
	}

	/// Menu-bar tooltip lines for the pools that are not the row's single official weekly.
	public func menuBarPoolLines(meters: [CursorPlanMeter]) -> [String] {
		quotaGroups(meters: meters).map { group in
			let parts = group.meters.map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }
			return "\(group.title): \(parts.joined(separator: " · "))"
		}
	}

	/// Detail header. A plan label that already names the provider ("Grok Bot Plan") is not
	/// prefixed again, so the header never reads "Grok Grok Bot Plan".
	public func detailHeader(providerName: String) -> String {
		guard let planLabel else { return "\(providerName) included usage" }
		let named = planLabel.range(of: providerName, options: [.caseInsensitive, .anchored]) != nil
		return "\(named ? planLabel : "\(providerName) \(planLabel)") · included usage"
	}

	// MARK: Decoding Cursor's dashboard responses

	/// Builds the reading from Cursor's three dashboard responses (JSON bodies of
	/// `GetCurrentPeriodUsage`, `GetSandUsageStatus`, `GetPlanInfo`). Pure and unit-tested.
	///
	/// - `currentPeriod` supplies monthly pools; `{}` is valid for a weekly-only entitlement.
	/// - `grokBot` supplies the optional shared weekly pool only with a non-zero included limit.
	/// - `planInfo` is optional and only supplies the plan name.
	public static func decode(
		currentPeriod: Data, grokBot: Data?, planInfo: Data?, fetchedAt: Date
	) -> CursorPlanUsage? {
		guard let period = jsonObject(currentPeriod) else { return nil }
		var meters = planMeters(period)
		if let grokBot, let meter = grokBotMeter(jsonObject(grokBot)) { meters.append(meter) }
		guard !meters.isEmpty else { return nil }
		let limitType = (period["spendLimitUsage"] as? [String: Any])?["limitType"] as? String
		let sand = grokBot.flatMap(jsonObject)
		let planName = (jsonObject(planInfo)?["planInfo"] as? [String: Any])?["planName"] as? String
			?? sand?["cursorPlanName"] as? String
		let isTeam = limitType == "team" || (sand?["isTeamSeat"] as? Bool ?? false)
		return CursorPlanUsage(
			planName: planName.flatMap { $0.isEmpty ? nil : $0 }, isTeam: isTeam, meters: meters,
			fetchedAt: fetchedAt, reportedPlanLabel: sand?["grokPlanLabel"] as? String)
	}

	/// "Cursor Models" (auto + Composer + Cursor Grok) and "Other Models" (named API models). Both
	/// share the billing cycle's end as their reset. A field Cursor omits yields no meter.
	static func planMeters(_ period: [String: Any]) -> [CursorPlanMeter] {
		guard let usage = period["planUsage"] as? [String: Any] else { return [] }
		let resetsAt = epochMillis(period["billingCycleEnd"])
		var meters: [CursorPlanMeter] = []
		if let auto = JSONNumber.double(usage["autoPercentUsed"]) {
			meters.append(CursorPlanMeter(
				key: "cursor_models", label: "Cursor Models", usedPercent: auto, resetsAt: resetsAt))
		}
		if let api = JSONNumber.double(usage["apiPercentUsed"]) {
			meters.append(CursorPlanMeter(
				key: "other_models", label: "Other Models", usedPercent: api, resetsAt: resetsAt))
		}
		// Older plans report one combined percentage only; show it rather than nothing.
		if meters.isEmpty, let total = JSONNumber.double(usage["totalPercentUsed"]) {
			meters.append(CursorPlanMeter(
				key: "included_usage", label: "Included usage", usedPercent: total, resetsAt: resetsAt))
		}
		return meters
	}

	/// Grok Bot's weekly meter. Present only when Cursor reports a non-zero included limit and a
	/// percentage — an account without Grok Bot access gets no meter.
	public static func grokBotMeter(_ sand: [String: Any]?) -> CursorPlanMeter? {
		guard let sand, sand["hasNonZeroIncludedLimit"] as? Bool == true,
			let used = JSONNumber.double(sand["usagePercent"])
		else { return nil }
		return CursorPlanMeter(
			key: CursorPlanMeter.grokBotKey, label: "Weekly included usage", usedPercent: used,
			resetsAt: isoDate(sand["nextResetTimestampUtc"]))
	}

	private static func jsonObject(_ data: Data?) -> [String: Any]? {
		guard let data else { return nil }
		return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
	}

	/// Cursor encodes int64 epoch milliseconds as JSON strings (proto3 JSON); accept numbers too.
	static func epochMillis(_ raw: Any?) -> Date? {
		let millis = (raw as? String).flatMap(Double.init) ?? JSONNumber.double(raw)
		guard let millis, millis > 0 else { return nil }
		return Date(timeIntervalSince1970: millis / 1000)
	}

	static func isoDate(_ raw: Any?) -> Date? {
		guard let string = raw as? String else { return nil }
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatter.date(from: string) { return date }
		formatter.formatOptions = [.withInternetDateTime]
		return formatter.date(from: string)
	}
}

/// Opt-in state and the last reading on disk.
///
/// The opt-in marker and the reading live under JP's own Application Support directory. The reading
/// holds only Cursor's percentages, reset times, and plan name — never the sign-in token.
public enum CursorPlanUsageStore {
	public static let markerFileName = "cursor-plan-usage.enabled"
	public static let readingFileName = "cursor-plan-usage.json"

	public enum State: Equatable, Sendable {
		case active
		case installable
		case unavailable
	}

	public static func markerURL(appSupport: URL? = nil) -> URL {
		(appSupport ?? CursorHookSetup.appSupportDirectory()).appendingPathComponent(markerFileName)
	}

	public static func readingURL(appSupport: URL? = nil) -> URL {
		(appSupport ?? CursorHookSetup.appSupportDirectory()).appendingPathComponent(readingFileName)
	}

	/// Whether the user opted in. Pure file check; performs no network, Keychain, or Cursor read.
	public static func isEnabled(appSupport: URL? = nil) -> Bool {
		FileManager.default.fileExists(atPath: markerURL(appSupport: appSupport).path)
	}

	/// `.unavailable` when no Cursor sign-in source exists on this Mac, so the Live Data row stays
	/// hidden until Cursor is present.
	public static func state(appSupport: URL? = nil, detected: Bool? = nil) -> State {
		if isEnabled(appSupport: appSupport) { return .active }
		return (detected ?? CursorAuthToken.isSourcePresent()) ? .installable : .unavailable
	}

	public static func enable(appSupport: URL? = nil) throws {
		let marker = markerURL(appSupport: appSupport)
		try FileManager.default.createDirectory(
			at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data().write(to: marker, options: [.atomic])
	}

	/// Turns the feature off and deletes the saved reading so no stale meter survives opt-out.
	public static func disable(appSupport: URL? = nil) {
		try? FileManager.default.removeItem(at: markerURL(appSupport: appSupport))
		try? FileManager.default.removeItem(at: readingURL(appSupport: appSupport))
	}

	public static func save(_ usage: CursorPlanUsage, appSupport: URL? = nil) throws {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		let data = try encoder.encode(usage)
		try data.write(to: readingURL(appSupport: appSupport), options: [.atomic])
		try? FileManager.default.setAttributes(
			[.posixPermissions: 0o600], ofItemAtPath: readingURL(appSupport: appSupport).path)
	}

	/// The saved reading with expired meters removed; nil when the feature is off or nothing is current.
	public static func load(now: Date = Date(), appSupport: URL? = nil) -> CursorPlanUsage? {
		guard isEnabled(appSupport: appSupport),
			let data = try? Data(contentsOf: readingURL(appSupport: appSupport))
		else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		return (try? decoder.decode(CursorPlanUsage.self, from: data))?.current(at: now)
	}

	/// Age of the saved reading, for fetch throttling. Nil when there is none.
	public static func lastFetchedAt(appSupport: URL? = nil) -> Date? {
		guard let data = try? Data(contentsOf: readingURL(appSupport: appSupport)) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		return (try? decoder.decode(CursorPlanUsage.self, from: data))?.fetchedAt
	}
}
