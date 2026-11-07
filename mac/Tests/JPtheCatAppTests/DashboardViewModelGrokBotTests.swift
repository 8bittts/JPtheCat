import AppKit
import SwiftUI
import XCTest
@testable import JPtheCatApp
@testable import JPtheCatCore

final class DashboardViewModelGrokBotTests: XCTestCase {
	private func plan(secondary: Bool = false, weekly: Bool = true) -> CursorPlanUsage {
		let reset = Date().addingTimeInterval(86_400)
		var meters: [CursorPlanMeter] = weekly ? [CursorPlanMeter(key: CursorPlanMeter.grokBotKey,
			label: "Weekly included usage", usedPercent: 30.46, resetsAt: reset)] : []
		if secondary || !weekly {
			meters += [CursorPlanMeter(key: "cursor_models", label: "Cursor Models", usedPercent: 64, resetsAt: reset),
				CursorPlanMeter(key: "other_models", label: "Other Models", usedPercent: 18, resetsAt: reset)]
		}
		return CursorPlanUsage(planName: "Team", isTeam: true, meters: meters, fetchedAt: Date(),
			reportedPlanLabel: "Grok Bot Plan")
	}

	private func build(_ plan: CursorPlanUsage?, local: Bool = false, enabled: Bool = true, model: String = "composer-2.5-fast") throws -> DashboardViewModel.RefreshBuild {
		let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let file = root.appendingPathComponent("cursor.jsonl")
		if local {
			try JSONSerialization.data(withJSONObject: ["captured_at": Date().timeIntervalSince1970,
				"generation_id": "cursor-fixture", "conversation_id": "fixture",
				"model": model, "input_tokens": 10000, "output_tokens": 2000]).write(to: file)
		}
		return DashboardViewModel.buildRefreshResult(reindex: false, days: 14,
			calculator: CostCalculator(), claude: ClaudeProvider(root: root.appendingPathComponent("claude")),
			codex: CodexProvider(root: root.appendingPathComponent("codex")), grok: GrokProvider(root: root.appendingPathComponent("grok"),
				rateLimitStoreURL: root.appendingPathComponent("grok-rate-limits.json")),
			copilot: CopilotProvider(root: root.appendingPathComponent("copilot")), cursor: CursorProvider(root: file),
			museSpark: MuseSparkProvider(root: root.appendingPathComponent("opencode")), index: nil,
			claudeEnabled: false, codexEnabled: false, grokEnabled: enabled, copilotEnabled: false,
			cursorEnabled: local, cursorPlan: plan, grokPlanEnabled: true, museSparkEnabled: false, enabledBrands: [],
			openCodeZenEnabled: false, openCodeGoEnabled: false, previousRows: [], hadPreviousRefresh: false)
	}

	func testPlanOnlyHasOneProviderAndNoThirdPrimaryGauge() throws {
		let result = try build(plan())
		let row = try XCTUnwrap(result.rows.first)
		XCTAssertEqual(result.rows.map(\.id), ["grok"])
		XCTAssertTrue(row.heroShowsOfficialPlanUsage())
		XCTAssertEqual(row.heroPrimaryTextOverride(), "30%")
		XCTAssertEqual(row.selectorTrailingAmount(), "30%")
		XCTAssertEqual(row.selectorOfficialPlanBadge(), "official")
		XCTAssertEqual(row.heroChartQuotaFraction()!, 0.3046, accuracy: 0.00001)
		XCTAssertEqual(row.detailPlanMeters().count, 0)
		XCTAssertFalse(row.detailShowsPrimaryWindow)
		XCTAssertFalse(row.detailShowsWeeklyWindow)
		XCTAssertEqual(result.aggregateWeek, 0)
	}

	func testSecondaryPoolsRemainButWeeklyNeverRepeatsInDetail() throws {
		let row = try XCTUnwrap(build(plan(secondary: true)).rows.first)
		XCTAssertEqual(row.detailPlanMeters().map(\.key), ["cursor_models", "other_models"])
		XCTAssertFalse(row.detailShowsWeeklyWindow)
		let mixed = try XCTUnwrap(build(plan(secondary: true), local: true).rows.first)
		XCTAssertFalse(mixed.heroShowsOfficialPlanUsage())
		XCTAssertTrue(mixed.detailShowsWeeklyWindow)
		XCTAssertEqual(mixed.detailPlanMeters().map(\.key), ["cursor_models", "other_models"])
		XCTAssertGreaterThan(mixed.week, 0)
		XCTAssertTrue(mixed.isAggregable)
		XCTAssertEqual(mixed.weekEvents, 1)
		XCTAssertEqual(mixed.detailWindowLabel(10080, fallback: "7-day"), "Weekly included usage")
		XCTAssertFalse(mixed.detailWindowLabel(10080, fallback: "7-day").contains("Team seat"))
	}

	func testMonthlyOnlyPlanIsNeverLabelledWeeklyOrFiveHour() throws {
		let row = try XCTUnwrap(build(plan(weekly: false)).rows.first)
		XCTAssertTrue(row.heroShowsOfficialPlanUsage())
		XCTAssertEqual(row.heroPrimaryTextOverride(), "64%")
		XCTAssertEqual(row.primaryPlanWindowLabel, "Billing-cycle window")
		XCTAssertNil(row.weeklyUsedPct)
		XCTAssertNil(row.usedPct)
		XCTAssertEqual(row.detailPlanMeters().map(\.key), ["other_models"])
	}

	func testMissingOrExpiredPlanNeverBecomesADeadZeroDollarChart() throws {
		let row = try XCTUnwrap(build(nil).rows.first)
		XCTAssertTrue(row.heroShowsOfficialPlanUsage())
		XCTAssertEqual(row.heroPrimaryTextOverride(), "—")
		XCTAssertTrue(row.detailPlanMeters().isEmpty)
		XCTAssertEqual(row.primaryPlanWindowLabel, "Awaiting official plan usage")
	}

	@MainActor func testMonthlyWidgetAndMarkdownAreOfficialPercentNotDollars() throws {
		let result = try build(plan(weekly: false))
		let state = DashboardState(rows: result.rows, aggregateSeries: [], aggregateToday: 0,
			aggregateWeek: 0, selectedId: "cursor", selectedDays: 14)
		let widget = DashboardWidgetPublisher.makeSnapshot(from: state, index: nil, access: .premium)
		XCTAssertEqual(widget.providers.first?.today, 64)
		XCTAssertEqual(widget.providers.first?.metric, .percent)
		XCTAssertEqual(widget.providers.first?.usageOfficial, true)
		XCTAssertNil(widget.providers.first?.weeklyUsedPercent)
		let focused = widget.focused(providerID: "cursor")
		XCTAssertFalse(focused.disclosesNotionalBasis)
		XCTAssertEqual(focused.primaryValueCaption, "included usage")
		XCTAssertEqual(focused.heroAccessibilitySummary(amount: "64%"), "Grok, official plan usage, 64% used")
		let report = DashboardWidgetPublisher.makeAutomationSnapshot(from: state).markdownReport()
		XCTAssertTrue(report.contains("official plan usage 64%"))
		XCTAssertFalse(report.contains("$64.00"))
	}

	func testUnknownCursorModelShowsTokensAndNoFabricatedDollars() throws {
		let row = try XCTUnwrap(build(nil, local: true, model: "unknown-cursor-model").rows.first)
		XCTAssertEqual(row.id, "grok")
		XCTAssertTrue(row.isFullyUnpriced)
		XCTAssertTrue(row.usesTokenDisplay)
		XCTAssertEqual(row.weekUsage.total, 12000)
		XCTAssertEqual(row.tokenSeries.reduce(0,+), 12000)
	}

	func testUnifiedSwitchDisablesEverySource() throws {
		XCTAssertTrue(try build(plan(), local: true, enabled: false).rows.isEmpty)
	}

	@MainActor func testWidgetAndAutomationUsePercentageUnitsWithoutSummingThem() throws {
		let result = try build(plan())
		let state = DashboardState(rows: result.rows, aggregateSeries: [], aggregateToday: 0,
			aggregateWeek: 0, selectedId: "grok_bot", selectedDays: 14)
		let widget = DashboardWidgetPublisher.makeSnapshot(from: state, index: nil, access: .premium)
		XCTAssertEqual(widget.providers.first?.metric, .percent)
		XCTAssertEqual(widget.focused(providerID: "cursor").metric, .percent)
		XCTAssertEqual(widget.totalToday, 0)
		let automation = DashboardWidgetPublisher.makeAutomationSnapshot(from: state)
		XCTAssertEqual(automation.providers.first?.valueMetric, .percent)
		XCTAssertEqual(automation.totalToday, 0)
	}

	@MainActor func testLegacySelectionsAndUnifiedPreferenceMigrateWithoutDroppingConfiguration() throws {
		let row = try XCTUnwrap(build(plan()).rows.first)
		for id in ["cursor", "grok_bot", "grok-bot"] {
			XCTAssertEqual(DashboardViewModel.selectableProviderID(id, rows: [row]), "grok")
			XCTAssertEqual(MenuBarDisplayFormat.normalized("limit:" + id).providerID, "grok")
		}
		let suite = "GrokFixture-" + UUID().uuidString
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set(false, forKey: SettingsStore.Key.providerGrokEnabled)
		defaults.set(true, forKey: SettingsStore.Key.providerGrokBotEnabled)
		XCTAssertTrue(SettingsStore.unifiedGrokEnabled(defaults))
		defaults.set(false, forKey: SettingsStore.Key.providerGrokBotEnabled)
		XCTAssertTrue(SettingsStore.unifiedGrokEnabled(defaults, legacySourceEnabled: true),
			"Cursor's pre-existing opt-in had no master provider toggle and must not be hidden by the Grok Build setting")
		defaults.set(false, forKey: SettingsStore.Key.providerUnifiedGrokEnabled)
		XCTAssertFalse(SettingsStore.unifiedGrokEnabled(defaults, legacySourceEnabled: true))
	}

	@MainActor func testLegacyDisabledBuildAndEnabledBotKeepUnifiedGrokVisible() throws {
		let suite = "GrokMigration-" + UUID().uuidString
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set(false, forKey: SettingsStore.Key.providerGrokEnabled)
		defaults.set(true, forKey: SettingsStore.Key.providerGrokBotEnabled)
		let settings = SettingsStore(defaults: defaults)
		XCTAssertTrue(settings.grokProviderEnabled)
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: root) }
		try GrokBotPlanUsageStore.enable(appSupport: root)
		let weekly = try XCTUnwrap(plan().primaryMeter)
		try GrokBotPlanUsageStore.save(GrokBotPlanUsage(planName: "Team", planLabel: "Team seat",
			isTeam: true, weekly: weekly, fetchedAt: Date()), appSupport: root)
		XCTAssertTrue(GrokPlanUsageStore.isEnabled(appSupport: root))
		let result = try build(GrokPlanUsageStore.load(appSupport: root), enabled: settings.grokProviderEnabled)
		XCTAssertEqual(result.rows.map(\.id), ["grok"])
		XCTAssertEqual(result.rows.first?.heroPrimaryTextOverride(), "30%")
		settings.grokProviderEnabled = false
		XCTAssertFalse(SettingsStore(defaults: defaults).grokProviderEnabled,
			"An explicit unified opt-out must remain authoritative on the next launch")
	}

	func testAuthoritativeEmptyUnifiedCacheNeverReloadsLegacyBotInDashboard() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: root) }
		try GrokBotPlanUsageStore.enable(appSupport: root)
		try GrokBotPlanUsageStore.save(GrokBotPlanUsage(planName: "Team", planLabel: "Team seat",
			isTeam: true, weekly: plan().primaryMeter, fetchedAt: Date()), appSupport: root)
		try GrokPlanUsageStore.save(CursorPlanUsage(planName: nil, isTeam: false, meters: [], fetchedAt: Date()), appSupport: root)
		let row = try XCTUnwrap(build(GrokPlanUsageStore.load(appSupport: root)).rows.first)
		XCTAssertNil(row.weeklyUsedPct)
		XCTAssertEqual(row.heroPrimaryTextOverride(), "—")
	}

	func testOneLocalSourceFailureKeepsTheCompleteUnifiedReadingStale() throws {
		let previous = try XCTUnwrap(build(plan(), local: true).rows.first)
		let partial = try XCTUnwrap(build(plan()).rows.first)
		let result = DashboardViewModel.reconcileProviderAvailability(rows: [partial],
			previousRows: [previous], hadPreviousRefresh: true, unavailableProviderIDs: [],
			failedProviderIDs: ["grok"], days: 14)
		let row = try XCTUnwrap(result.rows.first)
		XCTAssertEqual(row.availability, .stale)
		XCTAssertEqual(row.weekEvents, previous.weekEvents)
		XCTAssertEqual(row.week, previous.week)
		XCTAssertTrue(row.contributesToAggregate)
	}

	@MainActor func testRenderUnifiedDashboardPlanOnlyAndCombined() throws {
		try XCTSkipUnless(ProcessInfo.processInfo.environment["JP_RENDER"] != nil, "Set JP_RENDER=1")
		let old = JPTheme.current
		defer { JPTheme.current = old }
		JPTheme.current = .sunlit
		for (name, local) in [("plan-only", false), ("combined", true)] {
			let result = try build(plan(secondary: local), local: local)
			let state = DashboardState(rows: result.rows, aggregateSeries: result.aggregateSeries,
				aggregateToday: result.aggregateToday, aggregateWeek: result.aggregateWeek,
				refreshStatus: .idle(lastRefresh: Date()), selectedId: "grok", selectedDays: 14)
			let model = DashboardViewModel(index: nil, initialState: state)
			let view = DashboardView(fixtureModel: model).environment(\.dashboardLayout, .twoColumns)
				.environment(\.jpMotionPaused, true)
			let renderer = ImageRenderer(content: view)
			renderer.scale = 2
			let image = try XCTUnwrap(renderer.nsImage)
			XCTAssertGreaterThan(image.size.width, 0)
			// ImageRenderer validates the SwiftUI tree; AppKit caches the same offscreen host
			// so the NSViewRepresentable timeframe picker is rendered rather than a yellow
			// unsupported-view placeholder. No window is shown and no real app is launched.
			let host = NSHostingController(rootView: view)
			host.view.frame = NSRect(origin: .zero, size: image.size)
			let window = NSWindow(contentRect: host.view.frame, styleMask: .borderless, backing: .buffered, defer: false)
			window.contentViewController = host
			host.view.layoutSubtreeIfNeeded()
			// Let native view appearance and the 0.5s quota-width animation settle offscreen.
			RunLoop.current.run(until: Date().addingTimeInterval(0.65))
			host.view.layoutSubtreeIfNeeded()
			let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
			host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
			let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
			let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
				.deletingLastPathComponent().deletingLastPathComponent()
				.appendingPathComponent(".build/grok-consolidated-" + name + ".png")
			try png.write(to: url)
			window.contentViewController = nil
			print("GROK RENDER \(url.path) \(image.size)")
		}
	}
}
