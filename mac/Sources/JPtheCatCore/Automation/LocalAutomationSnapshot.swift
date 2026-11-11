import Foundation

public enum LocalAutomationCostBasis: String, Codable, Equatable, Sendable {
	case realSpend = "real_spend"
	case notionalListPrice = "notional_list_price"
	case realAndNotionalListPrice = "real_and_notional_list_price"
	case tokenEstimate = "token_estimate"
	/// An OpenCode gateway rollup (Zen / Go): real usage that is already counted under a model-brand
	/// provider, so it is listed but excluded from the snapshot's dollar total.
	case gateway = "gateway"
	case officialPlan = "official_plan"

	/// The snapshot vocabulary for Core's one cost-basis table. Every CLI/automation surface derives
	/// its label from `ProviderBasis` through here; a hand-written per-provider switch once labeled
	/// the OpenCode model-brand rows as real spend.
	public init(_ basis: ProviderBasis) {
		switch basis {
		case .real: self = .realSpend
		case .notional: self = .notionalListPrice
		case .estimate: self = .tokenEstimate
		case .gateway: self = .gateway
		case .officialPlan: self = .officialPlan
		}
	}

	public var reportLabel: String {
		switch self {
		case .realSpend: "real spend"
		case .notionalListPrice: "notional list-price"
		case .realAndNotionalListPrice: "incl notional"
		case .tokenEstimate: "token estimate"
		case .gateway: "gateway (not in total)"
		case .officialPlan: "official plan usage"
		}
	}
}

public struct LocalAutomationRateLimitWindow: Codable, Equatable, Sendable {
	public let usedPercent: Double
	public let windowMinutes: Int
	public let resetsAt: Date?
	public let official: Bool

	public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?, official: Bool) {
		self.usedPercent = rounded2(usedPercent)
		self.windowMinutes = windowMinutes
		self.resetsAt = resetsAt
		self.official = official
	}

	private enum CodingKeys: String, CodingKey {
		case usedPercent = "used_percent"
		case windowMinutes = "window_minutes"
		case resetsAt = "resets_at"
		case official
	}
}

public struct LocalAutomationRateLimits: Codable, Equatable, Sendable {
	public let planType: String?
	public let primary5h: LocalAutomationRateLimitWindow?
	public let secondaryWeekly: LocalAutomationRateLimitWindow?
	public let credits: CodexCreditBalance?
	public let capturedAt: Date?

	public init(
		planType: String?,
		primary5h: LocalAutomationRateLimitWindow?,
		secondaryWeekly: LocalAutomationRateLimitWindow?,
		credits: CodexCreditBalance? = nil, capturedAt: Date? = nil
	) {
		self.planType = planType
		self.primary5h = primary5h
		self.secondaryWeekly = secondaryWeekly
		self.credits = credits
		self.capturedAt = capturedAt
	}

	private enum CodingKeys: String, CodingKey {
		case planType = "plan_type"
		case primary5h = "primary_5h"
		case secondaryWeekly = "secondary_weekly"
		case credits
		case capturedAt = "captured_at"
	}
}

/// The serialized subscription-window headroom, separate from any credit balance.
/// `state` is `official` / `likely_exhausted` / `unknown`; the numeric
/// fields are present ONLY for `official` (never fabricated for a provider without a live signal).
public struct LocalAutomationHeadroom: Codable, Equatable, Sendable {
	public let state: String
	public let remainingPercent: Double?
	public let windowMinutes: Int?
	public let resetsAt: Date?

	public init(state: String, remainingPercent: Double? = nil, windowMinutes: Int? = nil, resetsAt: Date? = nil) {
		self.state = state
		self.remainingPercent = remainingPercent.map(rounded2)
		self.windowMinutes = windowMinutes
		self.resetsAt = resetsAt
	}

	public init(_ headroom: ProviderHeadroom) {
		switch headroom {
		case let .official(remaining, minutes, resets):
			self.init(state: "official", remainingPercent: remaining, windowMinutes: minutes, resetsAt: resets)
		case .likelyExhausted:
			self.init(state: "likely_exhausted")
		case .unknown:
			self.init(state: "unknown")
		}
	}

	private enum CodingKeys: String, CodingKey {
		case state
		case remainingPercent = "remaining_percent"
		case windowMinutes = "window_minutes"
		case resetsAt = "resets_at"
	}
}

public struct LocalAutomationProvider: Codable, Equatable, Identifiable, Sendable {
	public let id: String
	public let name: String
	public let currencyCode: String
	public let today: Double
	public let window: Double
	public let costBasis: LocalAutomationCostBasis
	public let valueMetric: WidgetValueMetric
	public let series: [Double]
	public let eventsToday: Int
	public let eventsWindow: Int
	public let unpricedModels: [String]
	public let headroom: LocalAutomationHeadroom
	/// Trailing-window AIU consumption for providers that bill in AIU (Copilot today) — a raw
	/// consumption count, NEVER dollars and NEVER a quota %. `nil` for every provider without a
	/// local AIU signal, and omitted from the JSON entirely when nil (so no consumer sees a fake `0`).
	public let aiuWindow: Double?

	public init(
		id: String,
		name: String,
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
		today: Double,
		window: Double,
		costBasis: LocalAutomationCostBasis,
		valueMetric: WidgetValueMetric = .dollars,
		series: [Double],
		eventsToday: Int,
		eventsWindow: Int,
		unpricedModels: [String],
		headroom: LocalAutomationHeadroom = LocalAutomationHeadroom(.unknown),
		aiuWindow: Double? = nil
	) {
		self.id = id
		self.name = name
		self.currencyCode = currencyCode
		self.today = rounded2(today)
		self.window = rounded2(window)
		self.costBasis = costBasis
		self.valueMetric = valueMetric
		self.series = series.map(rounded2)
		self.eventsToday = eventsToday
		self.eventsWindow = eventsWindow
		self.unpricedModels = unpricedModels.sorted()
		self.headroom = headroom
		self.aiuWindow = aiuWindow.map(rounded2)
	}

	private enum CodingKeys: String, CodingKey {
		case id
		case name
		case currencyCode = "currency_code"
		case today
		case window
		case costBasis = "cost_basis"
		case valueMetric = "value_metric"
		case series
		case eventsToday = "events_today"
		case eventsWindow = "events_window"
		case unpricedModels = "unpriced_models"
		case headroom
		case aiuWindow = "aiu_window"
	}
}

public struct LocalAutomationSnapshot: Codable, Equatable, Sendable {
	public static let schemaVersion = 4

	public let schemaVersion: Int
	public let generatedAt: Date
	public let source: String
	public let windowDays: Int
	public let currencyCode: String
	public let totalToday: Double
	public let totalWindow: Double
	public let costBasis: LocalAutomationCostBasis
	public let valueMetric: WidgetValueMetric
	public let series: [Double]
	public let providers: [LocalAutomationProvider]
	public let rateLimits: [String: LocalAutomationRateLimits]
	public let status: String
	public let notice: String?

	public init(
		schemaVersion: Int = Self.schemaVersion,
		generatedAt: Date,
		source: String,
		windowDays: Int,
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
		totalToday: Double,
		totalWindow: Double,
		costBasis: LocalAutomationCostBasis,
		valueMetric: WidgetValueMetric = .dollars,
		series: [Double],
		providers: [LocalAutomationProvider],
		rateLimits: [String: LocalAutomationRateLimits],
		status: String,
		notice: String?
	) {
		self.schemaVersion = schemaVersion
		self.generatedAt = generatedAt
		self.source = source
		self.windowDays = max(windowDays, 1)
		self.currencyCode = currencyCode
		self.totalToday = rounded2(totalToday)
		self.totalWindow = rounded2(totalWindow)
		self.costBasis = costBasis
		self.valueMetric = valueMetric
		self.series = series.map(rounded2)
		self.providers = providers
		self.rateLimits = rateLimits
		self.status = status
		self.notice = notice
	}

	public func markdownReport() -> String {
		var lines: [String] = [
			"# JP the Cat Local Snapshot",
			"",
			"Generated: \(LocalAutomationSnapshotEncoder.string(from: generatedAt))",
			"Window: \(windowDays)d",
			valueMetric == .tokens
				? "Total today: \(Int(totalToday)) tokens (estimate)"
				: "Total today: \(MoneyFormatter.dollars(totalToday, code: currencyCode)) \(currencyCode) (\(costBasis.reportLabel))",
			valueMetric == .tokens
				? "Total \(windowDays)d: \(Int(totalWindow)) tokens"
				: "Total \(windowDays)d: \(MoneyFormatter.dollars(totalWindow, code: currencyCode)) \(currencyCode)",
			"",
			"## Providers",
		]

		for provider in providers {
			if provider.valueMetric == .percent {
				lines.append("- \(provider.name): official plan usage \(Int(provider.today.rounded()))%")
			} else {
			lines.append(
				provider.valueMetric == .tokens
					? "- \(provider.name): today \(Int(provider.today)) tokens, "
						+ "\(windowDays)d \(Int(provider.window)) tokens, token estimate"
					: "- \(provider.name): today \(MoneyFormatter.dollars(provider.today, code: provider.currencyCode)), "
						+ "\(windowDays)d \(MoneyFormatter.dollars(provider.window, code: provider.currencyCode)), "
						+ provider.costBasis.reportLabel)
			}
			if let limits = rateLimits[provider.id] {
				// A gateway (OpenCode Go) window is measured local cost against the provider's published
				// cap, not a provider-reported number — the same override the menu-bar tooltip applies,
				// so this human-readable report never calls it "official".
				let provenance: (Bool) -> String = { official in
					provider.costBasis == .gateway ? "measured" : (official ? "official" : "estimated")
				}
				if let primary = limits.primary5h {
					lines.append("  - 5h used \(formatPercent(primary.usedPercent)) \(provenance(primary.official))")
				}
				if let weekly = limits.secondaryWeekly {
					lines.append("  - weekly used \(formatPercent(weekly.usedPercent)) \(provenance(weekly.official))")
				}
				if let credits = limits.credits {
					lines.append("  - credits remaining (last reported): \(credits.displayValue); separate from subscription allowance and dollars")
					if let capturedAt = limits.capturedAt {
						lines.append("    reported at: \(ISO8601DateFormatter().string(from: capturedAt))")
					}
				}
			}
			lines.append("  - headroom: \(headroomReportLabel(provider.headroom))")
			if let aiu = provider.aiuWindow {
				lines.append("  - AIU used (\(windowDays)d): \(formatAIU(aiu)) (consumption, not $ or %)")
			}
		}

		if let notice {
			lines += ["", "Notice: \(notice)"]
		}
		return lines.joined(separator: "\n")
	}

	public func hasSameContent(as other: LocalAutomationSnapshot) -> Bool {
		source == other.source
			&& windowDays == other.windowDays
			&& currencyCode == other.currencyCode
			&& totalToday == other.totalToday
			&& totalWindow == other.totalWindow
			&& costBasis == other.costBasis
			&& series == other.series
			&& providers == other.providers
			&& rateLimits == other.rateLimits
			&& status == other.status
			&& notice == other.notice
	}

	private enum CodingKeys: String, CodingKey {
		case schemaVersion = "schema_version"
		case generatedAt = "generated_at"
		case source
		case windowDays = "window_days"
		case currencyCode = "currency_code"
		case totalToday = "total_today"
		case totalWindow = "total_window"
		case costBasis = "cost_basis"
		case valueMetric = "value_metric"
		case series
		case providers
		case rateLimits = "rate_limits"
		case status
		case notice
	}
}

public enum LocalAutomationSnapshotEncoder {
	nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()

	public static func encode(_ snapshot: LocalAutomationSnapshot) throws -> Data {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .custom { date, encoder in
			var container = encoder.singleValueContainer()
			try container.encode(string(from: date))
		}
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(snapshot)
	}

	public static func string(from date: Date) -> String {
		formatter.string(from: date)
	}
}

public struct LocalAutomationSnapshotStore {
	public static let fileName = "latest-snapshot.json"

	private let rootURL: URL
	private let fileManager: FileManager

	public init(
		rootURL: URL = LocalAutomationSnapshotStore.defaultRootURL(),
		fileManager: FileManager = .default
	) {
		self.rootURL = rootURL
		self.fileManager = fileManager
	}

	public var snapshotURL: URL {
		rootURL.appendingPathComponent(Self.fileName, isDirectory: false)
	}

	public func write(_ snapshot: LocalAutomationSnapshot) throws {
		try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
		let data = try LocalAutomationSnapshotEncoder.encode(snapshot)
		try data.write(to: snapshotURL, options: [.atomic])
	}

	public static func defaultRootURL(fileManager: FileManager = .default) -> URL {
		let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
			.first ?? fileManager.temporaryDirectory
		return appSupport.appendingPathComponent("JPtheCat", isDirectory: true)
	}
}

private func rounded2(_ value: Double) -> Double {
	(value * 100).rounded() / 100
}

private func formatPercent(_ value: Double) -> String {
	let rounded = rounded2(value)
	if rounded.rounded() == rounded {
		return "\(Int(rounded))%"
	}
	return "\(rounded)%"
}

private func formatAIU(_ value: Double) -> String {
	let rounded = (value * 100).rounded() / 100
	if rounded.rounded() == rounded { return "\(Int(rounded)) AIU" }
	return "\(rounded) AIU"
}

private func headroomReportLabel(_ headroom: LocalAutomationHeadroom) -> String {
	switch headroom.state {
	case "official":
		if let remaining = headroom.remainingPercent { return "\(formatPercent(remaining)) left (official)" }
		return "official"
	case "likely_exhausted":
		return "likely exhausted"
	default:
		return "unknown (no official limit signal)"
	}
}
