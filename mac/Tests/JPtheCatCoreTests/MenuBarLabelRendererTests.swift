import XCTest

@testable import JPtheCatCore

final class MenuBarLabelRendererTests: XCTestCase {
	func testPersistedFormatsRestoreEveryCatalogDisplayName() {
		for provider in ProviderCatalog.all where ProviderID.consolidatedRawID(provider.id.rawValue) == provider.id.rawValue {
			let raw = "totalAndLimit:\(provider.id.rawValue):estimate"
			let format = MenuBarDisplayFormat.normalized(raw)
			XCTAssertEqual(format.rawValue, raw)
			XCTAssertEqual(format.providerDisplayName, provider.shortName)
		}
		XCTAssertEqual(MenuBarDisplayFormat.normalized("totalAndLimit:big_pickle:estimate").settingsTitle, "Total + Big Pickle")
		XCTAssertEqual(MenuBarDisplayFormat.normalized("totalAndLimit:opencodego:estimate").rawValue, "totalAndLimit:opencode")
	}

	private let enUS = Locale(identifier: "en_US")

	func testCompactStatusTitleShowsFullFiguresBelowSixDigits() {
		XCTAssertEqual(
			MenuBarLabelRenderer.compactStatusTitle(aggregateToday: 1234.56, locale: enUS),
			"$1,234.56"
		)
		XCTAssertEqual(
			MenuBarLabelRenderer.compactStatusTitle(aggregateToday: 12345.67, locale: enUS),
			"$12,345.67"
		)
	}

	func testCompactStatusTitleAbbreviatesOnlyAtSixFigures() {
		let title = MenuBarLabelRenderer.compactStatusTitle(
			aggregateToday: 111123.23,
			locale: enUS
		)

		XCTAssertEqual(title, "$111.1K")
	}

	func testCompactStatusTitleCanShowCostAndPrimaryLimitWithoutExpandingUnboundedText() {
		let title = MenuBarLabelRenderer.compactStatusTitle(
			aggregateToday: 1234.56,
			limit: MenuBarProviderLimit(shortName: "Codex", usedPct: 82),
			displayFormat: MenuBarDisplayFormat(kind: .totalAndLimit),
			locale: enUS
		)

		// Grouping separator must match the plain Total format ($1,235), not drop to $1235.
		XCTAssertEqual(title, "$1,235 · Codex 82%")
		XCTAssertLessThanOrEqual(title.count, 19)
	}

	func testCompactStatusTitleCanShowPrimaryLimitOnly() {
		let title = MenuBarLabelRenderer.compactStatusTitle(
			aggregateToday: 1234.56,
			limit: MenuBarProviderLimit(shortName: "Codex", usedPct: 82),
			displayFormat: MenuBarDisplayFormat(kind: .limit),
			locale: enUS
		)

		XCTAssertEqual(title, "Codex 82%")
	}

	func testCompactStatusTitleRotatingLimitUsesProviderShortName() {
		XCTAssertEqual(
			MenuBarLabelRenderer.compactStatusTitle(
				aggregateToday: 12.34,
				limit: MenuBarProviderLimit(shortName: "Claude", usedPct: 45),
				displayFormat: MenuBarDisplayFormat(kind: .limit),
				locale: enUS
			),
			"Claude 45%"
		)
	}

	func testCompactStatusTitleFallsBackWhenLimitFormatHasNoLimit() {
		XCTAssertEqual(
			MenuBarLabelRenderer.compactStatusTitle(
				aggregateToday: 12.34,
				limit: nil,
				displayFormat: MenuBarDisplayFormat(kind: .limit),
				locale: enUS
			),
			"$12.34"
		)
	}

	func testAttentionStateOnlyChangesForUsageLimitThresholds() {
		XCTAssertEqual(MenuBarLabelRenderer.attentionState(providerLimits: []), .normal)
		XCTAssertEqual(
			MenuBarLabelRenderer.attentionState(providerLimits: [
				MenuBarProviderLimitSummary(
					name: "Codex",
					primaryUsedPct: 79.9,
					primaryWindowMinutes: 300,
					secondaryUsedPct: nil,
					secondaryWindowMinutes: nil,
					isOfficial: true,
					planLabel: nil)
			]),
			.normal
		)
		XCTAssertEqual(
			MenuBarLabelRenderer.attentionState(providerLimits: [
				MenuBarProviderLimitSummary(
					name: "Codex",
					primaryUsedPct: 80,
					primaryWindowMinutes: 300,
					secondaryUsedPct: nil,
					secondaryWindowMinutes: nil,
					isOfficial: true,
					planLabel: nil)
			]),
			.warning
		)
		XCTAssertEqual(
			MenuBarLabelRenderer.attentionState(providerLimits: [
				MenuBarProviderLimitSummary(
					name: "Codex",
					primaryUsedPct: nil,
					primaryWindowMinutes: nil,
					secondaryUsedPct: 95,
					secondaryWindowMinutes: 10080,
					isOfficial: true,
					planLabel: nil)
			]),
			.critical
		)
	}

	func testCompactStatusTitleKeepsLoadingAndUnavailableDistinct() {
		XCTAssertEqual(MenuBarLabelRenderer.compactStatusTitle(aggregateToday: nil), "…")
		XCTAssertEqual(
			MenuBarLabelRenderer.compactStatusTitle(
				aggregateToday: nil,
				allProvidersUnavailable: true
			),
			"—"
		)
	}

	func testAccessibilityValueLabelsAggregateWhenItIncludesNotionalCost() {
		let value = MenuBarLabelRenderer.accessibilityValue(
			aggregateToday: 12.34,
			includesNotional: true,
			limit: MenuBarProviderLimit(shortName: "Codex", usedPct: 39),
			locale: enUS
		)

		XCTAssertEqual(
			value,
			"Today 12.34 dollars, includes notional list-price estimates, Codex 39 percent used"
		)
	}

	func testAccessibilityValueGroupsThousandsWithComma() {
		let value = MenuBarLabelRenderer.accessibilityValue(
			aggregateToday: 1123.37,
			includesNotional: false,
			limit: nil,
			locale: enUS
		)

		XCTAssertEqual(value, "Today 1,123.37 dollars")
	}

	func testTooltipUsesReadableSectionsForBasisLimitsAndFreshness() {
		let tooltip = MenuBarLabelRenderer.tooltip(
			aggregateToday: 1217.10,
			windowTotal: 4321.05,
			windowDays: 14,
			costBasis: .realAndNotionalListPrice,
			providerLimits: [
				MenuBarProviderLimitSummary(
					name: "Codex",
					primaryUsedPct: 5,
					primaryWindowMinutes: 300,
					secondaryUsedPct: 87,
					secondaryWindowMinutes: 10080,
					isOfficial: true,
					planLabel: "pro")
			],
			freshnessText: "Updated just now",
			locale: enUS
		)

		XCTAssertEqual(
			tooltip,
			"""
			Today: $1,217.10
			Last 14 days: $4,321.05
			Basis: real spend + notional list-price estimates

			Rate limits:
			Codex: 5h 5% used · weekly 87% used (official · pro)

			Freshness: Updated just now
			"""
		)
	}

	// MARK: - Per-provider display format (dedicated entries + rotating entry)

	private let claude = MenuBarLimitProvider(
		id: "claude", shortName: "Claude", windows: [.fiveHour, .weekly])
	private let codex = MenuBarLimitProvider(
		id: "codex", shortName: "Codex", windows: [.fiveHour, .weekly])

	func testSelectableBuildsDedicatedPerProviderEntriesPlusRotating() {
		let cycle = MenuBarDisplayFormat.selectable(providers: [claude, codex])
		// Per-provider entries, plus a rotating "Total + limit" and "Limit" (no pinned provider) that
		// appear only when >1 provider has a live limit.
		XCTAssertEqual(
			cycle.map(\.rawValue),
			["total", "totalAndLimit:claude:fiveHour", "totalAndLimit:claude:weekly",
			 "totalAndLimit:codex:fiveHour", "totalAndLimit:codex:weekly", "totalAndLimit",
			 "limit:claude:fiveHour", "limit:claude:weekly", "limit:codex:fiveHour",
			 "limit:codex:weekly", "limit"])
		// Adding a provider extends the cycle with no new enum cases.
		XCTAssertEqual(MenuBarDisplayFormat.selectable(providers: []).map(\.rawValue), ["total"])
	}

	func testSelectableIncludesRotatingEntryForASingleProviderWithTwoWindows() {
		XCTAssertEqual(
			MenuBarDisplayFormat.selectable(providers: [codex]).map(\.rawValue),
			["total", "totalAndLimit:codex:fiveHour", "totalAndLimit:codex:weekly",
			 "totalAndLimit", "limit:codex:fiveHour", "limit:codex:weekly", "limit"])
	}

	func testSelectableOmitsRotatingEntryForOneProviderWithOneWindow() {
		let grok = MenuBarLimitProvider(id: "grok", shortName: "Grok", windows: [.weekly])
		XCTAssertEqual(
			MenuBarDisplayFormat.selectable(providers: [grok]).map(\.rawValue),
			["total", "totalAndLimit:grok:weekly", "limit:grok:weekly"])
	}

	func testRotatingFormatsAreFlaggedIsRotating() {
		XCTAssertTrue(MenuBarDisplayFormat(kind: .limit).isRotating)
		XCTAssertTrue(MenuBarDisplayFormat(kind: .totalAndLimit).isRotating)
		XCTAssertFalse(MenuBarDisplayFormat(kind: .limit, providerID: "codex").isRotating)
		XCTAssertFalse(MenuBarDisplayFormat.total.isRotating)
	}

	func testNextCyclesThroughEveryProviderAndRotatingThenWrapsToTotal() {
		let providers = [claude, codex]
		var format = MenuBarDisplayFormat.total
		var seen: [String] = []
		for _ in 0..<12 {
			format = format.next(providers: providers)
			seen.append(format.rawValue)
		}
		XCTAssertEqual(
			seen,
			["totalAndLimit:claude:fiveHour", "totalAndLimit:claude:weekly",
			 "totalAndLimit:codex:fiveHour", "totalAndLimit:codex:weekly", "totalAndLimit",
			 "limit:claude:fiveHour", "limit:claude:weekly", "limit:codex:fiveHour",
			 "limit:codex:weekly", "limit", "total", "totalAndLimit:claude:fiveHour"])
	}

	func testNextFromStaleProviderSelectionRestartsAtTotal() {
		// A pinned provider that is no longer live isn't in the cycle → advance restarts at the front.
		let stale = MenuBarDisplayFormat(kind: .limit, providerID: "gemini")
		XCTAssertEqual(stale.next(providers: [claude, codex]), .total)
	}

	func testNextFromLegacyWindowlessProviderContinuesIntoWeeklyView() {
		let legacy = MenuBarDisplayFormat(kind: .totalAndLimit, providerID: "claude")
		XCTAssertEqual(
			legacy.next(providers: [claude, codex]).rawValue,
			"totalAndLimit:claude:weekly")
	}

	func testLegacyRotatingRawValuesMigrateToAutoLimitVariants() {
		XCTAssertEqual(MenuBarDisplayFormat.normalized("totalAndPrimaryLimit"),
			MenuBarDisplayFormat(kind: .totalAndLimit))
		XCTAssertEqual(MenuBarDisplayFormat.normalized("primaryLimit"),
			MenuBarDisplayFormat(kind: .limit))
		// Auto variants carry no provider id, so they format the "provider limit" fallback copy.
		XCTAssertEqual(MenuBarDisplayFormat.normalized("primaryLimit").settingsTitle, "Limit")
	}

	func testRawValueRoundTripsProviderPinnedFormats() {
		let pinned = MenuBarDisplayFormat(kind: .totalAndLimit, providerID: "codex", providerShortName: "Codex")
		XCTAssertEqual(pinned.rawValue, "totalAndLimit:codex")
		XCTAssertEqual(MenuBarDisplayFormat.normalized(pinned.rawValue), pinned)
		let weekly = MenuBarDisplayFormat(
			kind: .totalAndLimit, providerID: "claude", providerShortName: "Claude", window: .weekly)
		XCTAssertEqual(weekly.rawValue, "totalAndLimit:claude:weekly")
		XCTAssertEqual(MenuBarDisplayFormat.normalized(weekly.rawValue), weekly)
		XCTAssertEqual(MenuBarDisplayFormat.normalized("nonsense"), .total)
	}

	func testProviderPinnedFormatsCarryFriendlyDisplayCopy() {
		let pinned = MenuBarDisplayFormat(kind: .limit, providerID: "codex", providerShortName: "Codex")
		XCTAssertEqual(pinned.settingsTitle, "Codex")
		XCTAssertEqual(pinned.settingsSubtitle, "Limit % only")
		let total = MenuBarDisplayFormat(kind: .totalAndLimit, providerID: "claude", providerShortName: "Claude")
		XCTAssertEqual(total.settingsTitle, "Total + Claude")
		XCTAssertEqual(total.settingsSubtitle, "Today total + Limit %")
		let weekly = MenuBarDisplayFormat(
			kind: .limit, providerID: "claude", providerShortName: "Claude", window: .weekly)
		XCTAssertEqual(weekly.settingsTitle, "Claude week")
		XCTAssertEqual(weekly.settingsSubtitle, "Limit % only")
		// A persisted (name-less) value still displays a capitalized id.
		XCTAssertEqual(MenuBarDisplayFormat.normalized("limit:codex").settingsTitle, "Codex")
	}

	func testRenderedSettingsTitleTracksCurrentRotatingWindow() {
		let rotatingTotal = MenuBarDisplayFormat(kind: .totalAndLimit)
		XCTAssertEqual(
			MenuBarLabelRenderer.renderedSettingsTitle(
				for: rotatingTotal,
				limit: MenuBarProviderLimit(shortName: "Claude", usedPct: 72, window: .weekly)),
			"Total + Claude week")
		XCTAssertEqual(
			MenuBarLabelRenderer.renderedSettingsTitle(
				for: MenuBarDisplayFormat(kind: .limit),
				limit: MenuBarProviderLimit(shortName: "Codex", usedPct: 12, window: .fiveHour)),
			"Codex 5h")
		XCTAssertEqual(
			MenuBarLabelRenderer.renderedSettingsTitle(for: rotatingTotal, limit: nil),
			"Total + limit")
	}

	func testRenderedSettingsSubtitleNamesTokensForRotatingEstimate() {
		let estimate = MenuBarProviderLimit(
			shortName: "Cursor", usedPct: 100, isEstimate: true, tokenCount: 17_200)
		XCTAssertEqual(
			MenuBarLabelRenderer.renderedSettingsSubtitle(
				for: MenuBarDisplayFormat(kind: .totalAndLimit), limit: estimate),
			"Today total + tokens")
		XCTAssertEqual(
			MenuBarLabelRenderer.renderedSettingsSubtitle(
				for: MenuBarDisplayFormat(kind: .limit), limit: estimate),
			"Today tokens")
	}

	private func summary(_ id: String, _ name: String, primary: Double?, weekly: Double? = nil)
		-> MenuBarProviderLimitSummary {
		MenuBarProviderLimitSummary(
			id: id, name: name, primaryUsedPct: primary, primaryWindowMinutes: 300,
			secondaryUsedPct: weekly, secondaryWindowMinutes: 10080, isOfficial: true, planLabel: nil)
	}

	func testLimitIsNilForTotalFormat() {
		XCTAssertNil(MenuBarLabelRenderer.limit(
			for: .total, providerLimits: [summary("codex", "Codex", primary: 6)]))
	}

	func testPinnedFormatShowsOnlyItsOwnProvider() {
		let limits = [summary("claude", "Claude", primary: 7), summary("codex", "Codex", primary: 6)]
		let codex = MenuBarLabelRenderer.limit(
			for: MenuBarDisplayFormat(kind: .totalAndLimit, providerID: "codex"), providerLimits: limits)
		XCTAssertEqual(codex, MenuBarProviderLimit(shortName: "Codex", usedPct: 6, window: .fiveHour))
	}

	func testPinnedProviderWithNoLiveLimitDropsToTotalOnlyRatherThanSubstituting() {
		// Codex pinned but only Claude is live → return nil (pill shows total), never Claude's number.
		let limits = [summary("claude", "Claude", primary: 7), summary("codex", "Codex", primary: nil)]
		XCTAssertNil(MenuBarLabelRenderer.limit(
			for: MenuBarDisplayFormat(kind: .totalAndLimit, providerID: "codex"), providerLimits: limits))
	}

	func testAutoVariantUsesFirstLiveProvider() {
		let limits = [summary("claude", "Claude", primary: nil), summary("codex", "Codex", primary: 6)]
		let auto = MenuBarLabelRenderer.limit(for: MenuBarDisplayFormat(kind: .limit), providerLimits: limits)
		XCTAssertEqual(auto, MenuBarProviderLimit(shortName: "Codex", usedPct: 6, window: .fiveHour))
	}

	func testLimitFallsBackToWeeklyWhenNoPrimaryWindow() {
		let auto = MenuBarLabelRenderer.limit(
			for: MenuBarDisplayFormat(kind: .limit, providerID: "codex"),
			providerLimits: [summary("codex", "Codex", primary: nil, weekly: 43)])
		XCTAssertEqual(auto, MenuBarProviderLimit(shortName: "Codex", usedPct: 43, window: .weekly))
	}

	func testPinnedWeeklyViewSelectsWeeklyEvenWhenFiveHourIsAlsoLive() {
		let weekly = MenuBarLabelRenderer.limit(
			for: MenuBarDisplayFormat(kind: .limit, providerID: "claude", window: .weekly),
			providerLimits: [summary("claude", "Claude", primary: 45, weekly: 87)])
		XCTAssertEqual(weekly, MenuBarProviderLimit(shortName: "Claude", usedPct: 87, window: .weekly))
	}

	func testIdentityIgnoresDisplayNameSoPersistedEqualsLive() {
		let live = MenuBarDisplayFormat(kind: .limit, providerID: "codex", providerShortName: "Codex")
		let persisted = MenuBarDisplayFormat(kind: .limit, providerID: "codex")
		XCTAssertEqual(live, persisted)
	}

	// MARK: - Estimate-only providers (e.g. Copilot, no official window signal)

	private func estimateSummary(
		_ id: String, _ name: String, estimated: Double, tokens: Int? = nil
	)
		-> MenuBarProviderLimitSummary {
		MenuBarProviderLimitSummary(
			id: id, name: name, primaryUsedPct: nil, primaryWindowMinutes: nil,
			secondaryUsedPct: nil, secondaryWindowMinutes: nil, isOfficial: false, planLabel: nil,
			estimatedUsedPct: estimated, estimatedTokenCount: tokens)
	}

	func testAutoVariantShowsActualTokensForAnEstimateOnlyProvider() {
		let limits = [estimateSummary("copilot", "Copilot", estimated: 42, tokens: 42_000)]
		let auto = MenuBarLabelRenderer.limit(for: MenuBarDisplayFormat(kind: .limit), providerLimits: limits)
		XCTAssertEqual(
			auto,
			MenuBarProviderLimit(
				shortName: "Copilot", usedPct: 42, isEstimate: true, tokenCount: 42_000))
	}

	func testAutoVariantUsesFirstLiveProviderInDashboardOrderEvenWhenItsAnEstimate() {
		// Auto rotation follows dashboard order, not official-before-estimate — an estimate-only
		// provider earlier in the row order is picked, still correctly flagged `isEstimate`.
		let limits = [
			summary("codex", "Codex", primary: 6),
			estimateSummary("copilot", "Copilot", estimated: 90),
		]
		let auto = MenuBarLabelRenderer.limit(for: MenuBarDisplayFormat(kind: .limit), providerLimits: limits)
		XCTAssertEqual(auto, MenuBarProviderLimit(shortName: "Codex", usedPct: 6, window: .fiveHour))
	}

	func testCompactStatusTitleShowsTokensInsteadOfEstimatePercentage() {
		let title = MenuBarLabelRenderer.compactStatusTitle(
			aggregateToday: 12.34,
			limit: MenuBarProviderLimit(
				shortName: "Copilot", usedPct: 42, isEstimate: true, tokenCount: 53_600),
			displayFormat: MenuBarDisplayFormat(kind: .limit),
			locale: enUS)
		XCTAssertEqual(title, "Copilot 53.6K")

		let totalAndLimit = MenuBarLabelRenderer.compactStatusTitle(
			aggregateToday: 12.34,
			limit: MenuBarProviderLimit(
				shortName: "Copilot", usedPct: 42, isEstimate: true, tokenCount: 53_600),
			displayFormat: MenuBarDisplayFormat(kind: .totalAndLimit),
			locale: enUS)
		XCTAssertEqual(totalAndLimit, "$12 · Copilot 53.6K")
	}

	func testAccessibilityValueNamesTokensAndUnavailableQuota() {
		let value = MenuBarLabelRenderer.accessibilityValue(
			aggregateToday: nil,
			includesNotional: false,
			limit: MenuBarProviderLimit(
				shortName: "Copilot", usedPct: 42, isEstimate: true, tokenCount: 53_600),
			locale: enUS)
		XCTAssertEqual(value, "Copilot 53600 tokens today, quota unavailable")
	}

	func testAttentionStateIgnoresEstimateOnlyProvidersEvenWhenHigh() {
		// An estimate must never drive the amber/red attention border — only an official % may.
		XCTAssertEqual(
			MenuBarLabelRenderer.attentionState(providerLimits: [
				estimateSummary("copilot", "Copilot", estimated: 99)
			]),
			.normal
		)
	}

	func testTooltipNamesEstimateOnlyTokensAndUnavailableQuota() {
		let tooltip = MenuBarLabelRenderer.tooltip(
			aggregateToday: 12.34,
			windowTotal: nil,
			windowDays: 14,
			costBasis: .notionalListPrice,
			providerLimits: [estimateSummary("copilot", "Copilot", estimated: 42, tokens: 42_000)],
			freshnessText: nil,
			locale: enUS
		)
		XCTAssertTrue(tooltip.contains("Copilot: 42.0K tokens today · quota unavailable (estimated)"))
	}

	// MARK: - Rotating pill eligibility (skip empty estimates and official values that round to 0%)

	func testRotatableLimitsSkipsProvidersThatRoundToZeroPercent() {
		let limits = [
			summary("codex", "Codex", primary: 6),
			estimateSummary("muse", "Muse Spark", estimated: 0), // "0%" is noise
			summary("grok", "Grok", primary: 0.4), // rounds to 0% → dropped
			estimateSummary("copilot", "Copilot", estimated: 42, tokens: 42_000),
		]
		let rotatable = MenuBarLabelRenderer.rotatableLimits(from: limits)
		XCTAssertEqual(
			rotatable,
			[
				MenuBarProviderLimit(shortName: "Codex", usedPct: 6, window: .fiveHour),
				MenuBarProviderLimit(
					shortName: "Copilot", usedPct: 42, isEstimate: true, tokenCount: 42_000),
			])
	}

	func testRotatableLimitsKeepsAProviderThatRoundsUpToOnePercent() {
		// 0.6 rounds to 1% — a real, if small, number, so it stays in the rotation.
		let rotatable = MenuBarLabelRenderer.rotatableLimits(
			from: [summary("codex", "Codex", primary: 0.6)])
		XCTAssertEqual(rotatable, [MenuBarProviderLimit(shortName: "Codex", usedPct: 0.6, window: .fiveHour)])
	}

	func testRotatableLimitsEmitsBothWindowsForAProviderExposingFiveHourAndWeekly() {
		// A provider with BOTH a live 5-hour and weekly window rotates through TWO labeled entries so a
		// reader can always tell which window a number is — the reported ambiguity.
		let rotatable = MenuBarLabelRenderer.rotatableLimits(
			from: [summary("claude", "Claude", primary: 45, weekly: 60)])
		XCTAssertEqual(
			rotatable,
			[
				MenuBarProviderLimit(shortName: "Claude", usedPct: 45, window: .fiveHour),
				MenuBarProviderLimit(shortName: "Claude", usedPct: 60, window: .weekly),
			])
	}

	func testRotatableLimitsDropsAZeroWindowButKeepsTheOtherLabeled() {
		// A live 5-hour window with a still-empty weekly window contributes only the 5-hour entry.
		let rotatable = MenuBarLabelRenderer.rotatableLimits(
			from: [summary("claude", "Claude", primary: 45, weekly: 0)])
		XCTAssertEqual(
			rotatable, [MenuBarProviderLimit(shortName: "Claude", usedPct: 45, window: .fiveHour)])
	}

	func testCompactStatusTitleSuffixesTheWindowSoFiveHourAndWeeklyAreDistinct() {
		XCTAssertEqual(
			MenuBarLabelRenderer.compactStatusTitle(
				aggregateToday: 12.34,
				limit: MenuBarProviderLimit(shortName: "Claude", usedPct: 45, window: .fiveHour),
				displayFormat: MenuBarDisplayFormat(kind: .limit),
				locale: enUS),
			"Claude 45% (5hr)")
		XCTAssertEqual(
			MenuBarLabelRenderer.compactStatusTitle(
				aggregateToday: 12.34,
				limit: MenuBarProviderLimit(shortName: "Claude", usedPct: 60, window: .weekly),
				displayFormat: MenuBarDisplayFormat(kind: .totalAndLimit),
				locale: enUS),
			"$12 · Claude 60% (W)")
	}

	func testAccessibilityValueSpeaksWhichWindowTheLimitMeasures() {
		let value = MenuBarLabelRenderer.accessibilityValue(
			aggregateToday: nil,
			includesNotional: false,
			limit: MenuBarProviderLimit(shortName: "Claude", usedPct: 45, window: .fiveHour),
			locale: enUS)
		XCTAssertEqual(value, "Claude 45 percent used in the 5-hour window")
	}

	func testPillLimitShowsTotalOnlyWhenEveryRotatingProviderRoundsToZero() {
		// An estimate-only provider with no tokens has no honest menu-bar value.
		// The pill must fall to total-only — never back to its internal self-relative percentage.
		let providerLimits = [estimateSummary("muse", "Muse Spark", estimated: 0)]
		let rotatable = MenuBarLabelRenderer.rotatableLimits(from: providerLimits)
		XCTAssertTrue(rotatable.isEmpty)
		XCTAssertNil(MenuBarLabelRenderer.pillLimit(
			for: MenuBarDisplayFormat(kind: .limit), rotatableLimits: rotatable,
			rotationIndex: 0, providerLimits: providerLimits))
		XCTAssertNil(MenuBarLabelRenderer.pillLimit(
			for: MenuBarDisplayFormat(kind: .totalAndLimit), rotatableLimits: rotatable,
			rotationIndex: 0, providerLimits: providerLimits))
	}

	func testPillLimitStillShowsAPinnedProviderAtZeroPercent() {
		// A pinned (non-rotating) provider is an explicit user choice — it shows at any percent.
		let providerLimits = [summary("codex", "Codex", primary: 0)]
		let pinned = MenuBarLabelRenderer.pillLimit(
			for: MenuBarDisplayFormat(kind: .totalAndLimit, providerID: "codex"),
			rotatableLimits: [], rotationIndex: 0, providerLimits: providerLimits)
		XCTAssertEqual(pinned, MenuBarProviderLimit(shortName: "Codex", usedPct: 0, window: .fiveHour))
	}

	func testPillLimitRotatesThroughTheFilteredEntries() {
		let providerLimits = [summary("codex", "Codex", primary: 6), summary("grok", "Grok", primary: 20)]
		let rotatable = MenuBarLabelRenderer.rotatableLimits(from: providerLimits)
		XCTAssertEqual(
			MenuBarLabelRenderer.pillLimit(
				for: MenuBarDisplayFormat(kind: .limit), rotatableLimits: rotatable,
				rotationIndex: 1, providerLimits: providerLimits),
			MenuBarProviderLimit(shortName: "Grok", usedPct: 20, window: .fiveHour))
	}
}
