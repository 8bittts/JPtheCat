import Foundation

/// Grok Bot's official weekly included-usage reading for the signed-in account.
///
/// Sourced ONLY from Cursor's dashboard API (`GetSandUsageStatus`, optionally `GetPlanInfo`) after the
/// user opts in, using the Grok Bot app's own sign-in — the same endpoint Cursor uses for its Grok Bot
/// weekly meter, but fetched with the Grok Bot session so the row stands alone from Cursor CLI.
public struct GrokBotPlanUsage: Sendable, Equatable, Codable {
	public let planName: String?
	public let planLabel: String?
	public let isTeam: Bool
	public let weekly: CursorPlanMeter?
	public let fetchedAt: Date

	public init(
		planName: String?, planLabel: String?, isTeam: Bool, weekly: CursorPlanMeter?, fetchedAt: Date
	) {
		self.planName = planName
		self.planLabel = planLabel
		self.isTeam = isTeam
		self.weekly = weekly
		self.fetchedAt = fetchedAt
	}

	public func current(at now: Date = Date()) -> GrokBotPlanUsage? {
		guard let weekly, weekly.isCurrent(at: now) else { return nil }
		return GrokBotPlanUsage(
			planName: planName, planLabel: planLabel, isTeam: isTeam, weekly: weekly, fetchedAt: fetchedAt)
	}

	func carryingOver(from previous: GrokBotPlanUsage?, sandFailed: Bool, now: Date) -> GrokBotPlanUsage {
		guard sandFailed, weekly == nil, let previous, let carried = previous.weekly, carried.isCurrent(at: now)
		else { return self }
		return GrokBotPlanUsage(
			planName: planName ?? previous.planName,
			planLabel: planLabel ?? previous.planLabel,
			isTeam: isTeam,
			weekly: carried,
			fetchedAt: fetchedAt)
	}

	public static func decode(sand: Data, planInfo: Data?, fetchedAt: Date) -> GrokBotPlanUsage? {
		guard let sandObject = jsonObject(sand) else { return nil }
		let weekly = CursorPlanUsage.grokBotMeter(sandObject)
		let planName = (jsonObject(planInfo)?["planInfo"] as? [String: Any])?["planName"] as? String
			?? sandObject["cursorPlanName"] as? String
		let grokLabel = sandObject["grokPlanLabel"] as? String
		let isTeam = sandObject["isTeamSeat"] as? Bool ?? false
		let label = grokLabel.flatMap { $0.isEmpty ? nil : $0 }
			?? planName.flatMap { isTeam ? "\($0) seat" : "\($0) plan" }
		guard weekly != nil || label != nil else { return nil }
		return GrokBotPlanUsage(
			planName: planName.flatMap { $0.isEmpty ? nil : $0 },
			planLabel: label,
			isTeam: isTeam,
			weekly: weekly,
			fetchedAt: fetchedAt)
	}

	private static func jsonObject(_ data: Data?) -> [String: Any]? {
		guard let data else { return nil }
		return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
	}
}

public enum GrokBotPlanUsageStore {
	public static let markerFileName = "grok-bot-plan-usage.enabled"
	public static let readingFileName = "grok-bot-plan-usage.json"

	public enum State: Equatable, Sendable {
		case active
		case installable
		case unavailable
	}

	public static func appSupportDirectory() -> URL {
		CursorHookSetup.appSupportDirectory()
	}

	public static func markerURL(appSupport: URL? = nil) -> URL {
		(appSupport ?? appSupportDirectory()).appendingPathComponent(markerFileName)
	}

	public static func readingURL(appSupport: URL? = nil) -> URL {
		(appSupport ?? appSupportDirectory()).appendingPathComponent(readingFileName)
	}

	public static func isEnabled(appSupport: URL? = nil) -> Bool {
		FileManager.default.fileExists(atPath: markerURL(appSupport: appSupport).path)
	}

	public static func state(appSupport: URL? = nil, detected: Bool? = nil) -> State {
		if isEnabled(appSupport: appSupport) { return .active }
		return (detected ?? GrokBotAuthToken.isSourcePresent()) ? .installable : .unavailable
	}

	public static func enable(appSupport: URL? = nil) throws {
		let marker = markerURL(appSupport: appSupport)
		try FileManager.default.createDirectory(
			at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data().write(to: marker, options: [.atomic])
	}

	public static func disable(appSupport: URL? = nil) {
		try? FileManager.default.removeItem(at: markerURL(appSupport: appSupport))
		try? FileManager.default.removeItem(at: readingURL(appSupport: appSupport))
	}

	public static func save(_ usage: GrokBotPlanUsage, appSupport: URL? = nil) throws {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		let data = try encoder.encode(usage)
		try data.write(to: readingURL(appSupport: appSupport), options: [.atomic])
		try? FileManager.default.setAttributes(
			[.posixPermissions: 0o600], ofItemAtPath: readingURL(appSupport: appSupport).path)
	}

	public static func load(now: Date = Date(), appSupport: URL? = nil) -> GrokBotPlanUsage? {
		guard isEnabled(appSupport: appSupport),
			let data = try? Data(contentsOf: readingURL(appSupport: appSupport))
		else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		return (try? decoder.decode(GrokBotPlanUsage.self, from: data))?.current(at: now)
	}

	public static func lastFetchedAt(appSupport: URL? = nil) -> Date? {
		guard let data = try? Data(contentsOf: readingURL(appSupport: appSupport)) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		return (try? decoder.decode(GrokBotPlanUsage.self, from: data))?.fetchedAt
	}
}
