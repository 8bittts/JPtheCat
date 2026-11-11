import Foundation

public enum MenuBarTooltipCostBasis: Equatable, Sendable {
	case realSpend
	case notionalListPrice
	case realAndNotionalListPrice

	var tooltipDescription: String {
		switch self {
		case .realSpend:
			"real spend"
		case .notionalListPrice:
			"notional list-price estimates"
		case .realAndNotionalListPrice:
			"real spend + notional list-price estimates"
		}
	}
}

public struct MenuBarProviderLimitSummary: Equatable, Sendable {
	public let id: String
	public let name: String
	public let primaryUsedPct: Double?
	public let primaryWindowMinutes: Int?
	public let secondaryUsedPct: Double?
	public let secondaryWindowMinutes: Int?
	public let isOfficial: Bool
	public let planLabel: String?
	/// Self-relative estimate (0-100), populated ONLY for a provider with no official window signal
	/// (e.g. Copilot). Kept separate from `primary`/`secondaryUsedPct`, which stay contractually
	/// "always official". Retained for in-app activity meters; the menu-bar pill must use the actual
	/// `estimatedTokenCount` instead because a percentage-shaped activity estimate implies quota.
	public let estimatedUsedPct: Double?
	/// Actual tokens observed today for a provider with no official quota window.
	/// This is the truthful menu-bar fallback for estimate-only providers.
	public let estimatedTokenCount: Int?
	/// Other official pools on the same row. Tooltip only. They do not rotate or drive the border.
	public let additionalLines: [String]

	public init(
		id: String = "",
		name: String,
		primaryUsedPct: Double?,
		primaryWindowMinutes: Int?,
		secondaryUsedPct: Double?,
		secondaryWindowMinutes: Int?,
		isOfficial: Bool,
		planLabel: String?,
		estimatedUsedPct: Double? = nil,
		estimatedTokenCount: Int? = nil,
		additionalLines: [String] = []
	) {
		self.id = id
		self.name = name
		self.primaryUsedPct = primaryUsedPct
		self.primaryWindowMinutes = primaryWindowMinutes
		self.secondaryUsedPct = secondaryUsedPct
		self.secondaryWindowMinutes = secondaryWindowMinutes
		self.isOfficial = isOfficial
		self.planLabel = planLabel
		self.estimatedUsedPct = estimatedUsedPct
		self.estimatedTokenCount = estimatedTokenCount
		self.additionalLines = additionalLines
	}
}

/// A provider that currently has a live usage-limit window, eligible to appear in a menu-bar limit
/// format. The dashboard supplies these in its stable provider order, so the settings cycle and the
/// pill stay stable as providers come and go. Adding a provider here is all it takes to extend the
/// menu-bar picker — no new enum cases, no per-provider wiring.
public enum MenuBarDisplayWindow: String, Equatable, Sendable {
	case fiveHour
	case weekly
	case estimate
	case other

	public init(windowMinutes: Int?, isEstimate: Bool = false) {
		if isEstimate { self = .estimate }
		else if windowMinutes == 10080 { self = .weekly }
		else if windowMinutes == 300 { self = .fiveHour }
		else { self = .other }
	}

	public var titleSuffix: String {
		switch self {
		case .fiveHour: "5h"
		case .weekly: "week"
		case .estimate: ""
		case .other: ""
		}
	}
}

public struct MenuBarLimitProvider: Equatable, Sendable {
	public let id: String
	public let shortName: String
	public let windows: [MenuBarDisplayWindow]

	public init(id: String, shortName: String, windows: [MenuBarDisplayWindow] = [.fiveHour]) {
		self.id = id
		self.shortName = shortName
		self.windows = windows
	}
}

/// What the menu-bar pill shows. `.total` is the JP badge + aggregate today total; the two limit
/// kinds pin a SPECIFIC provider (dedicated per-provider entries — the pill no longer rotates). A
/// `nil` `providerID` on a limit kind means "auto: the first provider with a live limit" and is the
/// migration target for the retired rotating formats plus the safe fallback when a pinned provider
/// goes away. Identity (Equatable / persistence / cycle matching) is kind + providerID + window; the
/// `providerShortName` is a display convenience resolved from live data; `window` pins one specific
/// live window while a legacy nil-window value preserves the original 5h-first fallback.
public struct MenuBarDisplayFormat: Equatable, Sendable {
	public enum Kind: String, CaseIterable, Sendable {
		case total
		case totalAndLimit
		case limit
	}

	public let kind: Kind
	public let providerID: String?
	public let providerShortName: String?
	public let window: MenuBarDisplayWindow?

	public init(
		kind: Kind,
		providerID: String? = nil,
		providerShortName: String? = nil,
		window: MenuBarDisplayWindow? = nil
	) {
		self.kind = kind
		self.providerID = kind == .total ? nil : providerID.map(ProviderID.consolidatedRawID)
		self.providerShortName = kind == .total ? nil : providerShortName
		self.window = kind == .total || (providerID.map { ProviderID.consolidatedRawID($0) != $0 } == true && window == .estimate) ? nil : window
	}

	public static let total = MenuBarDisplayFormat(kind: .total)
	public static let defaultFormat: MenuBarDisplayFormat = .total

	// Identity is kind + providerID; the display name never participates in equality so a persisted
	// (name-less) value equals its live-named twin and redundant settings commits don't fan out.
	public static func == (lhs: MenuBarDisplayFormat, rhs: MenuBarDisplayFormat) -> Bool {
		lhs.kind == rhs.kind && lhs.providerID == rhs.providerID && lhs.window == rhs.window
	}

	/// Persistence form: "total" | "totalAndLimit" | "totalAndLimit:<id>[:<window>]" | "limit" | "limit:<id>[:<window>]".
	public var rawValue: String {
		guard kind != .total else { return "total" }
		if let providerID {
			let base = "\(kind.rawValue):\(providerID)"
			return window.map { "\(base):\($0.rawValue)" } ?? base
		}
		return kind.rawValue
	}

	public static func normalized(_ rawValue: String?) -> MenuBarDisplayFormat {
		guard let rawValue, !rawValue.isEmpty else { return defaultFormat }
		// Legacy rotating formats migrate to the auto (nil-provider) limit variants.
		switch rawValue {
		case "total": return .total
		case "totalAndPrimaryLimit", "totalAndLimit": return MenuBarDisplayFormat(kind: .totalAndLimit)
		case "primaryLimit", "limit": return MenuBarDisplayFormat(kind: .limit)
		default: break
		}
		let parts = rawValue.split(separator: ":", maxSplits: 2).map(String.init)
		guard parts.count >= 2, let kind = Kind(rawValue: parts[0]), kind != .total else {
			return defaultFormat
		}
		let window = parts.count == 3 ? MenuBarDisplayWindow(rawValue: parts[2]) : nil
		if parts.count == 3 && window == nil { return defaultFormat }
		return MenuBarDisplayFormat(kind: kind, providerID: parts[1], window: window)
	}

	/// Resolve persisted identifiers through the catalog so names survive a settings round trip.
	public var providerDisplayName: String? {
		if let providerShortName { return providerShortName }
		guard let providerID, !providerID.isEmpty else { return nil }
		if let id = ProviderID(rawValue: providerID), let descriptor = ProviderCatalog.descriptor(for: id) {
			return descriptor.shortName
		}
		return providerID.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
	}

	public var windowedProviderDisplayName: String? {
		guard let name = providerDisplayName else { return nil }
		guard let suffix = window?.titleSuffix, !suffix.isEmpty else { return name }
		return "\(name) \(suffix)"
	}

	public var settingsTitle: String {
		switch kind {
		case .total:
			return "Total"
		case .totalAndLimit:
			return windowedProviderDisplayName.map { "Total + \($0)" } ?? "Total + limit"
		case .limit:
			return windowedProviderDisplayName ?? "Limit"
		}
	}

	public var settingsSubtitle: String {
		switch kind {
		case .total:
			return "JP badge + today total"
		case .totalAndLimit:
			return window == .estimate ? "Today total + tokens" : "Today total + Limit %"
		case .limit:
			return window == .estimate ? "Today tokens" : "Limit % only"
		}
	}

	/// A limit format with no pinned provider: the pill rotates through every live-limit provider
	/// (the auto/legacy variant). `.total` is never rotating.
	public var isRotating: Bool { kind != .total && providerID == nil }

	/// The ordered cycle the settings row steps through, generated from the live limit-bearing
	/// providers: Total, then Total + <provider> <window> for each and a rotating "Total + limit", then
	/// <provider> <window> for each and a rotating "Limit". The rotating entries only appear when MORE THAN ONE
	/// live window exists (one provider with both 5h and weekly still has a meaningful rotation). Adding a
	/// provider extends the cycle automatically; with no live-limit providers only Total is offered.
	public static func selectable(providers: [MenuBarLimitProvider]) -> [MenuBarDisplayFormat] {
		var formats: [MenuBarDisplayFormat] = [.total]
		for p in providers {
			for window in p.windows {
				formats.append(MenuBarDisplayFormat(kind: .totalAndLimit, providerID: p.id, providerShortName: p.shortName, window: window))
			}
		}
		let liveWindowCount = providers.reduce(0) { $0 + $1.windows.count }
		if liveWindowCount > 1 { formats.append(MenuBarDisplayFormat(kind: .totalAndLimit)) }
		for p in providers {
			for window in p.windows {
				formats.append(MenuBarDisplayFormat(kind: .limit, providerID: p.id, providerShortName: p.shortName, window: window))
			}
		}
		if liveWindowCount > 1 { formats.append(MenuBarDisplayFormat(kind: .limit)) }
		return formats
	}

	/// Next format in the cycle for the settings row. Matches the current selection by identity so a
	/// persisted value picks up its live short name; an unknown/stale selection restarts at Total.
	public func next(providers: [MenuBarLimitProvider]) -> MenuBarDisplayFormat {
		let cycle = Self.selectable(providers: providers)
		let exactIndex = cycle.firstIndex(of: self)
		let legacyPinnedIndex = window == nil && providerID != nil
			? cycle.firstIndex { $0.kind == kind && $0.providerID == providerID }
			: nil
		guard let idx = exactIndex ?? legacyPinnedIndex else { return cycle.first ?? .total }
		return cycle[(idx + 1) % cycle.count]
	}

}

public enum MenuBarAttentionState: Equatable, Sendable {
	case normal
	case warning
	case critical
}

/// The single provider metric shown in a limit-bearing menu-bar format.
/// Official windows render percentages; estimate-only providers render actual tokens today.
public struct MenuBarProviderLimit: Equatable, Sendable {
	/// Which rate-limit window `usedPct` came from, so the pill can disambiguate a provider's 5-hour
	/// value from its weekly value ("Claude 45% (5hr)" vs "Claude 60% (W)") — the reported ambiguity
	/// when the rotation cycled both of Claude's windows with no marker for which was which. Derived
	/// from the window's minutes (300 → 5-hour, 10080 → weekly), never assumed from primary/secondary
	/// position, since a normalized weekly-only snapshot can surface in `primary`.
	public enum Window: Equatable, Sendable {
		/// The 5-hour window (300 minutes).
		case fiveHour
		/// The weekly window (10080 minutes).
		case weekly
		/// An estimate or any window that isn't the standard 5-hour/weekly pair — no suffix, since
		/// labeling it "(5hr)"/"(W)" would be dishonest.
		case other

		/// Resolves the window from its length in minutes.
		public init(minutes: Int?) {
			switch minutes {
			case 300: self = .fiveHour
			case 10080: self = .weekly
			default: self = .other
			}
		}
	}

	public let shortName: String
	public let usedPct: Double
	/// Actual observed tokens today for an estimate-only provider.
	/// When present, every visible/spoken surface renders this instead of `usedPct`.
	public let tokenCount: Int?
	/// True when `usedPct` is a self-relative estimate (no official window signal), not an official
	/// rate-limit percentage. This semantic flag is retained for callers and equality; visible
	/// menu-bar surfaces use `tokenCount` for this case instead of rendering `usedPct`.
	public let isEstimate: Bool
	/// Which limit window `usedPct` measures — drives the `(5hr)`/`(W)` pill suffix.
	public let window: Window

	public init(
		shortName: String,
		usedPct: Double,
		isEstimate: Bool = false,
		window: Window = .other,
		tokenCount: Int? = nil
	) {
		self.shortName = shortName
		self.usedPct = usedPct
		self.isEstimate = isEstimate
		self.window = window
		self.tokenCount = tokenCount
	}

	/// The suffix appended after the pill percent so a reader can tell WHICH limit window the number
	/// is: `" (5hr)"` for the 5-hour window, `" (W)"` for the weekly window, empty otherwise.
	public var windowSuffix: String {
		switch window {
		case .fiveHour: " (5hr)"
		case .weekly: " (W)"
		case .other: ""
		}
	}

	/// Spoken form of the window for VoiceOver ("in the 5-hour window"), empty for `.other`.
	public var windowSpoken: String {
		switch window {
		case .fiveHour: " in the 5-hour window"
		case .weekly: " in the weekly window"
		case .other: ""
		}
	}
}

public enum MenuBarLabelRenderer {
	/// The Settings selection shown beside the menu-bar cycle control. Pinned formats already carry
	/// their exact provider/window name. Rotating formats instead name the window CURRENTLY rendered
	/// in the pill, so Settings cannot claim a different view while the private rotation index advances.
	public static func renderedSettingsTitle(
		for displayFormat: MenuBarDisplayFormat,
		limit: MenuBarProviderLimit?
	) -> String {
		guard displayFormat.isRotating, let limit else { return displayFormat.settingsTitle }
		let suffix: String
		switch limit.window {
		case .fiveHour: suffix = " 5h"
		case .weekly: suffix = " week"
		case .other: suffix = ""
		}
		let provider = "\(limit.shortName)\(suffix)"
		return displayFormat.kind == .totalAndLimit ? "Total + \(provider)" : provider
	}

	/// The rotating format has no persisted window, so its subtitle must follow the resolved metric.
	/// Otherwise an estimate-only provider would still be described as a quota percentage.
	public static func renderedSettingsSubtitle(
		for displayFormat: MenuBarDisplayFormat,
		limit: MenuBarProviderLimit?
	) -> String {
		guard displayFormat.isRotating, limit?.tokenCount != nil else {
			return displayFormat.settingsSubtitle
		}
		return displayFormat.kind == .totalAndLimit ? "Today total + tokens" : "Today tokens"
	}

	public static func compactStatusTitle(
		aggregateToday: Double?,
		limit: MenuBarProviderLimit? = nil,
		displayFormat: MenuBarDisplayFormat = .defaultFormat,
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
		allProvidersUnavailable: Bool = false,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		if displayFormat.kind == .limit, let limit {
			return "\(limit.shortName) \(compactProviderMetric(limit))"
		}

		guard let aggregateToday else { return allProvidersUnavailable ? "—" : "…" }
		let total = compactAmount(
			aggregateToday,
			currencyCode: currencyCode,
			locale: locale,
			shortForCombined: displayFormat.kind == .totalAndLimit)
		if displayFormat.kind == .totalAndLimit, let limit {
			return "\(total) · \(limit.shortName) \(compactProviderMetric(limit))"
		}
		return total
	}

	/// The single provider limit the pill shows for `displayFormat`. A PINNED provider (`providerID`
	/// set) shows only ITS OWN limit — if it isn't live right now the pill drops to total-only rather
	/// than substituting a different provider (which would misread under a "Total + Codex" setting). The
	/// auto variant (`providerID == nil`, i.e. the migrated legacy formats) shows the first provider with
	/// a live limit. A provider's shown percent is its 5h window, falling back to its weekly window.
	public static func limit(
		for displayFormat: MenuBarDisplayFormat,
		providerLimits: [MenuBarProviderLimitSummary]
	) -> MenuBarProviderLimit? {
		guard displayFormat.kind != .total else { return nil }
		func livePct(_ s: MenuBarProviderLimitSummary) -> Double? {
			switch displayFormat.window {
			case .fiveHour: return s.primaryUsedPct
			case .weekly: return s.secondaryUsedPct
			case .estimate: return s.estimatedUsedPct
			case .other: return s.primaryUsedPct ?? s.secondaryUsedPct
			case nil: return s.primaryUsedPct ?? s.secondaryUsedPct ?? s.estimatedUsedPct
			}
		}
		let summary: MenuBarProviderLimitSummary?
		if let id = displayFormat.providerID {
			summary = providerLimits.first {
				$0.id == id && (livePct($0) != nil || ($0.estimatedTokenCount ?? 0) > 0)
			}
		} else {
			summary = providerLimits.first {
				livePct($0) != nil || ($0.estimatedTokenCount ?? 0) > 0
			}
		}
		guard let summary else { return nil }
		let pct = livePct(summary) ?? summary.estimatedUsedPct ?? 0
		let isEstimate = displayFormat.window == .estimate ||
			(summary.primaryUsedPct == nil && summary.secondaryUsedPct == nil)
		let tokenCount = isEstimate ? summary.estimatedTokenCount : nil
		if isEstimate && (tokenCount ?? 0) <= 0 { return nil }
		// The shown value is the 5h window, falling back to weekly, then the estimate — mark which
		// window it actually came from so the pill can suffix "(5hr)"/"(W)".
		let window: MenuBarProviderLimit.Window
		if displayFormat.window == .weekly {
			window = .weekly
		} else if displayFormat.window == .fiveHour {
			window = .fiveHour
		} else if summary.primaryUsedPct != nil {
			window = MenuBarProviderLimit.Window(minutes: summary.primaryWindowMinutes)
		} else if summary.secondaryUsedPct != nil {
			window = MenuBarProviderLimit.Window(minutes: summary.secondaryWindowMinutes)
		} else {
			window = .other
		}
		return MenuBarProviderLimit(
			shortName: summary.name, usedPct: pct, isEstimate: isEstimate, window: window,
			tokenCount: tokenCount)
	}

	/// The single limit the pill shows for `displayFormat` given the current rotation state. A rotating
	/// format shows ONLY a `rotatableLimits` entry (already 0%-filtered) and returns `nil` — total-only —
	/// when none qualify, so it NEVER falls back to `limit(for:)` (which is unfiltered and would re-show a
	/// "0%" provider when every live provider rounds to zero). A pinned/static format defers to
	/// `limit(for:)`, which intentionally still shows the user's explicitly-pinned provider at any percent.
	public static func pillLimit(
		for displayFormat: MenuBarDisplayFormat,
		rotatableLimits: [MenuBarProviderLimit],
		rotationIndex: Int,
		providerLimits: [MenuBarProviderLimitSummary]
	) -> MenuBarProviderLimit? {
		if displayFormat.isRotating {
			guard !rotatableLimits.isEmpty else { return nil }
			return rotatableLimits[rotationIndex % rotatableLimits.count]
		}
		return limit(for: displayFormat, providerLimits: providerLimits)
	}

	/// The entries eligible for the ROTATING limit pill. Each provider contributes ONE entry per live
	/// official window — so a provider exposing BOTH a 5-hour and a weekly window (e.g. Claude/Codex)
	/// rotates through both, each carrying its own `(5hr)`/`(W)` suffix so a reader always knows which
	/// window a number is. A provider with no official window contributes its self-relative estimate.
	/// Any window whose percentage rounds below 1% is dropped ("0%" is noise, not information), so a
	/// provider can contribute its 5-hour window while its (still-empty) weekly window stays hidden.
	public static func rotatableLimits(
		from providerLimits: [MenuBarProviderLimitSummary]
	) -> [MenuBarProviderLimit] {
		providerLimits.flatMap { summary -> [MenuBarProviderLimit] in
			func eligible(_ pct: Double?) -> Double? {
				guard let pct, Int(pct.rounded()) >= 1 else { return nil }
				return pct
			}
			var entries: [MenuBarProviderLimit] = []
			if let pct = eligible(summary.primaryUsedPct) {
				entries.append(MenuBarProviderLimit(
					shortName: summary.name, usedPct: pct,
					window: MenuBarProviderLimit.Window(minutes: summary.primaryWindowMinutes)))
			}
			if let pct = eligible(summary.secondaryUsedPct) {
				entries.append(MenuBarProviderLimit(
					shortName: summary.name, usedPct: pct,
					window: MenuBarProviderLimit.Window(minutes: summary.secondaryWindowMinutes)))
			}
			// An estimate-only provider rotates only when it has an actual token count to show.
			// The self-relative percentage remains dashboard-only and never enters the pill.
			if entries.isEmpty, let tokens = summary.estimatedTokenCount, tokens > 0 {
				entries.append(MenuBarProviderLimit(
					shortName: summary.name,
					usedPct: summary.estimatedUsedPct ?? 0,
					isEstimate: true,
					tokenCount: tokens))
			}
			return entries
		}
	}

	public static func attentionState(providerLimits: [MenuBarProviderLimitSummary]) -> MenuBarAttentionState {
		let maxUsedPct = providerLimits
			.flatMap { [$0.primaryUsedPct, $0.secondaryUsedPct] }
			.compactMap { $0 }
			.max() ?? 0
		if maxUsedPct >= 95 { return .critical }
		if maxUsedPct >= 80 { return .warning }
		return .normal
	}

	private static func compactAmount(
		_ aggregateToday: Double,
		currencyCode: String,
		locale: Locale,
		shortForCombined: Bool
	) -> String {
		guard currencyCode == MoneyFormatter.baseCurrencyCode else {
			return MoneyFormatter.currency(
				aggregateToday,
				code: currencyCode,
				decimals: shortForCombined || abs(aggregateToday) >= 1000 ? 0 : 2,
				locale: locale
			)
		}

		let sign = aggregateToday < 0 ? "-" : ""
		let value = abs(aggregateToday)
		switch value {
		case 1_000_000...:
			return "\(sign)$\(compactDecimal(value / 1_000_000))M"
		// Abbreviate only once we hit 6-figure territory ($100,000+); 4–5 figure amounts
		// (e.g. $1,234.82, $12,345.67) render in full with grouping separators.
		case 100_000...:
			return "\(sign)$\(compactDecimal(value / 1_000))K"
		case 10... where shortForCombined:
			return "\(sign)\(MoneyFormatter.currency(value, code: currencyCode, decimals: 0, locale: locale))"
		default:
			return "\(sign)\(MoneyFormatter.dollars(value, code: currencyCode, locale: locale))"
		}
	}

	public static func accessibilityValue(
		aggregateToday: Double?,
		includesNotional: Bool,
		limit: MenuBarProviderLimit?,
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
		allProvidersUnavailable: Bool = false,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		var spoken: [String] = []
		if let aggregateToday {
			let suffix = includesNotional ? ", includes notional list-price estimates" : ""
			let unit = currencyName(currencyCode, locale: locale)
			spoken.append("Today \(MoneyFormatter.amount(aggregateToday, locale: locale)) \(unit)\(suffix)")
		}
		if let limit {
			if let tokens = limit.tokenCount {
				spoken.append("\(limit.shortName) \(tokens) tokens today, quota unavailable")
			} else {
				spoken.append(String(
					format: "%@ %.0f percent used%@", limit.shortName, limit.usedPct, limit.windowSpoken))
			}
		}
		guard spoken.isEmpty else { return spoken.joined(separator: ", ") }
		// No figure to speak: distinguish "sources unavailable" (never imply a $0 day) from a first-launch load.
		return allProvidersUnavailable ? "All providers unavailable" : "Loading"
	}

	public static func tooltip(
		aggregateToday: Double?,
		windowTotal: Double?,
		windowDays: Int?,
		costBasis: MenuBarTooltipCostBasis,
		providerLimits: [MenuBarProviderLimitSummary],
		freshnessText: String?,
		currencyCode: String = MoneyFormatter.baseCurrencyCode,
		allProvidersUnavailable: Bool = false,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		var sections: [String] = []
		if let aggregateToday {
			var costLines = [
				"Today: \(MoneyFormatter.dollars(aggregateToday, code: currencyCode, locale: locale))"
			]
			if let windowTotal {
				costLines.append(
					"\(windowLabel(days: windowDays)): \(MoneyFormatter.dollars(windowTotal, code: currencyCode, locale: locale))"
				)
			}
			costLines.append("Basis: \(costBasis.tooltipDescription)")
			sections.append(costLines.joined(separator: "\n"))
		} else {
			sections.append(allProvidersUnavailable ? "No provider data available" : "Loading provider data…")
		}

		let limitLines = providerLimits.compactMap(providerLimitLine)
		if !limitLines.isEmpty {
			sections.append((["Rate limits:"] + limitLines).joined(separator: "\n"))
		}

		if let freshnessText, !freshnessText.isEmpty {
			sections.append("Freshness: \(freshnessText)")
		}

		return sections.joined(separator: "\n\n")
	}

	/// Spoken currency word ("dollars", "euros") so VoiceOver announces the right unit if a provider
	/// ever reports a non-USD native currency. Falls back to the plural display name, then the code.
	private static func currencyName(_ code: String, locale: Locale) -> String {
		if code == "USD" { return "dollars" }
		return locale.localizedString(forCurrencyCode: code) ?? code
	}

	private static func providerLimitLine(_ limit: MenuBarProviderLimitSummary) -> String? {
		var parts: [String] = []
		if let pct = limit.primaryUsedPct {
			parts.append("\(windowLabel(limit.primaryWindowMinutes, fallback: "5h")) \(roundedPercent(pct)) used")
		}
		if let pct = limit.secondaryUsedPct {
			parts.append("\(windowLabel(limit.secondaryWindowMinutes, fallback: "weekly")) \(roundedPercent(pct)) used")
		}
		if parts.isEmpty, let tokens = limit.estimatedTokenCount, tokens > 0 {
			parts.append("\(TokenFormatter.compact(tokens)) tokens today · quota unavailable")
		}
		guard !parts.isEmpty else { return nil }

		// An OpenCode gateway window is measured local cost against a published cap, NOT a
		// provider-reported percentage — so the tooltip says "measured", never "official".
		let isGateway =
			ProviderID(rawValue: limit.id).map { ProviderBasis.of($0) == .gateway } ?? false
		var meta = [isGateway ? "measured" : (limit.isOfficial ? "official" : "estimated")]
		if let plan = limit.planLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty {
			meta.append(plan)
		}
		var line = "\(limit.name): \(parts.joined(separator: " · ")) (\(meta.joined(separator: " · ")))"
		if !limit.additionalLines.isEmpty {
			line += "\n" + limit.additionalLines.joined(separator: "\n")
		}
		return line
	}

	private static func roundedPercent(_ value: Double) -> String {
		"\(Int(value.rounded()))%"
	}

	private static func compactProviderMetric(_ limit: MenuBarProviderLimit) -> String {
		if let tokens = limit.tokenCount { return TokenFormatter.compact(tokens) }
		return "\(roundedPercent(limit.usedPct))\(limit.windowSuffix)"
	}

	private static func compactDecimal(_ value: Double) -> String {
		String(format: "%.1f", value)
	}

	private static func windowLabel(_ minutes: Int?, fallback: String) -> String {
		switch minutes {
		case 300:
			"5h"
		case 10080:
			"weekly"
		case let minutes? where minutes >= 1440 && minutes % 1440 == 0:
			"\(minutes / 1440)d"
		case let minutes? where minutes >= 60 && minutes % 60 == 0:
			"\(minutes / 60)h"
		case let minutes?:
			"\(minutes)m"
		case nil:
			fallback
		}
	}

	private static func windowLabel(days: Int?) -> String {
		guard let days, days > 0 else { return "Selected window" }
		return days == 1 ? "Today" : "Last \(days) days"
	}
}
