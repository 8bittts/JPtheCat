import XCTest

@testable import JPtheCatCore

final class WidgetSnapshotTests: XCTestCase {
	/// Token rows say what the dashboard says: OpenCode Zen and Go are gateways, not estimates.
	func testTokenRowsCarryTheDashboardBasisWord() {
		func row(_ id: String) -> WidgetProviderSnapshot {
			WidgetProviderSnapshot(
				id: id, name: id, tintHex: "#000000", today: 1, window: 1, metric: .tokens,
				basis: .notionalListPrice, usedPercent: nil, weeklyUsedPercent: nil, usageOfficial: false,
				series: [])
		}
		XCTAssertEqual(row("opencode").tokenBasisLabel, "gateway")
		XCTAssertEqual(row("opencodego").tokenBasisLabel, "gateway")
		XCTAssertEqual(row("cursor").tokenBasisLabel, "estimate")
		XCTAssertEqual(row("copilot").tokenBasisLabel, "estimate")
	}

	func testSnapshotStoreRoundTripsPremiumWidgetData() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let snapshot = WidgetSnapshot.fixture(access: .premium)
		let store = WidgetSnapshotStore(rootURL: root)

		try store.write(snapshot)
		let decoded = try store.read()

		XCTAssertEqual(decoded.access, .premium)
		XCTAssertEqual(decoded.title, "All providers")
		XCTAssertEqual(decoded.totalToday, 1235.08, accuracy: 0.001)
		XCTAssertEqual(decoded.currencyCode, "USD")
		XCTAssertEqual(decoded.basis, .realAndNotionalListPrice)
		XCTAssertEqual(decoded.providers.map(\.id), ["claude", "codex"])
		XCTAssertEqual(decoded.series, [120, 90, 160, 130])
	}

	func testSnapshotCanFocusAConfiguredProviderWithoutChangingAccess() {
		let snapshot = WidgetSnapshot.fixture(access: .trialActive)

		let focused = snapshot.focused(providerID: "codex")

		XCTAssertEqual(focused.access, .trialActive)
		XCTAssertEqual(focused.title, "Codex")
		XCTAssertEqual(focused.totalToday, 225.19, accuracy: 0.001)
		XCTAssertEqual(focused.totalWindow, 4439.43, accuracy: 0.001)
		XCTAssertEqual(focused.series, [60, 40, 75, 50])
		XCTAssertEqual(focused.basis, .notionalListPrice)
		XCTAssertEqual(focused.providers.map(\.id), ["codex"])
		XCTAssertEqual(focused.windowDays, 14)
	}

	func testLegacyPaidEraAccessValuesStillDecode() throws {
		// JP is free and always writes `.premium`, but widgets placed by older builds may hold a
		// snapshot that says `trialActive` or `locked`; it must still decode instead of blanking.
		for raw in ["premium", "trialActive", "locked"] {
			let data = Data("\"\(raw)\"".utf8)
			XCTAssertEqual(try JSONDecoder().decode(WidgetAccessState.self, from: data).rawValue, raw)
		}
	}

	// Rule (b): the notional basis must be disclosed whenever the total blends in Codex list-price. The
	// mixed real+notional aggregate (the default when Codex is present) and a wholly-notional total both
	// disclose; only pure real spend may stay silent. Guards against the earlier inverted logic that hid
	// "incl notional" exactly when Codex was included.
	func testDisclosesNotionalBasisForEveryCodexInclusiveBasis() {
		func snapshot(_ basis: WidgetCostBasis) -> WidgetSnapshot {
			var base = WidgetSnapshot.fixture(access: .premium)
			base = WidgetSnapshot(
				generatedAt: base.generatedAt, access: base.access, title: base.title,
				totalToday: base.totalToday, totalWindow: base.totalWindow, currencyCode: base.currencyCode,
				windowDays: base.windowDays, basis: basis, series: base.series, providers: base.providers,
				staleAfter: base.staleAfter, errorMessage: base.errorMessage)
			return base
		}

		XCTAssertTrue(snapshot(.realAndNotionalListPrice).disclosesNotionalBasis)
		XCTAssertTrue(snapshot(.notionalListPrice).disclosesNotionalBasis)
		XCTAssertFalse(snapshot(.realSpend).disclosesNotionalBasis)
		XCTAssertEqual(WidgetCostBasis.realAndNotionalListPrice.shortLabel, "incl notional")
	}

	// The availability/error disclosure the widget both SHOWS (footer/caption) and SPEAKS (VoiceOver
	// summary): a hard errorMessage wins over the softer availabilityNotice, and it is nil only when both
	// are absent. Guards the VoiceOver summary against announcing a bare "$0.00" with no disclosure when
	// every source is unavailable.
	func testDisclosureNoticePrefersErrorThenAvailabilityNotice() {
		func snapshot(error: String?, notice: String?) -> WidgetSnapshot {
			let base = WidgetSnapshot.fixture(access: .premium)
			return WidgetSnapshot(
				generatedAt: base.generatedAt, access: base.access, title: base.title,
				totalToday: 0, totalWindow: base.totalWindow, currencyCode: base.currencyCode,
				windowDays: base.windowDays, basis: base.basis, series: base.series, providers: base.providers,
				staleAfter: base.staleAfter, errorMessage: error, availabilityNotice: notice)
		}
		XCTAssertEqual(
			snapshot(error: "Refresh failed", notice: "Codex excluded").disclosureNotice, "Refresh failed")
		XCTAssertEqual(
			snapshot(error: nil, notice: "All sources unavailable — open JP the Cat.").disclosureNotice,
			"All sources unavailable — open JP the Cat.")
		XCTAssertNil(snapshot(error: nil, notice: nil).disclosureNotice)
	}

	func testIsStaleTracksTheStaleAfterHorizon() {
		let snapshot = WidgetSnapshot.fixture(access: .premium)  // staleAfter = 1_780_003_600
		XCTAssertFalse(snapshot.isStale(now: Date(timeIntervalSince1970: 1_780_003_599)))
		XCTAssertTrue(snapshot.isStale(now: Date(timeIntervalSince1970: 1_780_003_601)))
	}

	func testReadRejectsSnapshotFromAnUnsupportedSchemaVersion() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let store = WidgetSnapshotStore(rootURL: root)
		try store.write(WidgetSnapshot.fixture(access: .premium))

		// Rewrite the on-disk schemaVersion to a future value the current build must not trust.
		let data = try Data(contentsOf: store.snapshotURL)
		var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		json["schemaVersion"] = WidgetSnapshot.schemaVersion + 1
		try JSONSerialization.data(withJSONObject: json).write(to: store.snapshotURL)

		XCTAssertThrowsError(try store.read()) { error in
			XCTAssertEqual(
				error as? WidgetSnapshotStoreError,
				.unsupportedSchemaVersion(found: WidgetSnapshot.schemaVersion + 1, expected: WidgetSnapshot.schemaVersion))
		}
		// readIfAvailable swallows it so the widget falls back to the placeholder instead of mis-rendering.
		XCTAssertNil(store.readIfAvailable())
	}

	func testHasSameContentIgnoresOnlyTheMovingTimestamps() {
		let a = WidgetSnapshot.fixture(access: .premium)
		let later = WidgetSnapshot(
			generatedAt: a.generatedAt.addingTimeInterval(600), access: a.access, title: a.title,
			totalToday: a.totalToday, totalWindow: a.totalWindow, currencyCode: a.currencyCode,
			windowDays: a.windowDays, basis: a.basis, series: a.series, providers: a.providers,
			staleAfter: a.staleAfter.addingTimeInterval(600), errorMessage: a.errorMessage, windows: a.windows)
		XCTAssertTrue(a.hasSameContent(as: later), "only generatedAt/staleAfter changed — no reload needed")

		let changed = WidgetSnapshot(
			generatedAt: a.generatedAt, access: a.access, title: a.title,
			totalToday: a.totalToday + 1, totalWindow: a.totalWindow, currencyCode: a.currencyCode,
			windowDays: a.windowDays, basis: a.basis, series: a.series, providers: a.providers,
			staleAfter: a.staleAfter, errorMessage: a.errorMessage, windows: a.windows)
		XCTAssertFalse(a.hasSameContent(as: changed))
	}

	// A windows-only diff must NOT be treated as same-content — otherwise the publisher's dedupe would
	// silently skip a write/WidgetCenter reload when only the non-selected timeframes' data changed.
	func testHasSameContentDetectsAWindowsOnlyDifference() {
		let a = WidgetSnapshot.fixture(access: .premium)
		let differentWindowsOnly = WidgetSnapshot(
			generatedAt: a.generatedAt, access: a.access, title: a.title,
			totalToday: a.totalToday, totalWindow: a.totalWindow, currencyCode: a.currencyCode,
			windowDays: a.windowDays, basis: a.basis, series: a.series, providers: a.providers,
			staleAfter: a.staleAfter, errorMessage: a.errorMessage, windows: [:])
		XCTAssertFalse(a.hasSameContent(as: differentWindowsOnly))
	}

	// Republish-suppression compares money at CENT granularity everywhere — top-level AND the nested
	// per-provider / per-window figures — so the grouped scan's ~1e-9 GROUP-BY-order FP tail can't force a
	// wasted App-Group write + WidgetCenter reload. A real ≥1¢ change must still be detected.
	func testHasSameContentIgnoresSubCentDriftInNestedFigures() {
		let a = WidgetSnapshot.fixture(access: .premium)
		let p0 = a.providers[0]
		let driftedProvider = WidgetProviderSnapshot(
			id: p0.id, name: p0.name, tintHex: p0.tintHex, today: p0.today + 1e-9, window: p0.window + 1e-9,
			currencyCode: p0.currencyCode, metric: p0.metric, basis: p0.basis, usedPercent: p0.usedPercent,
			weeklyUsedPercent: p0.weeklyUsedPercent, usageOfficial: p0.usageOfficial,
			series: p0.series.map { $0 + 1e-9 })
		let (wDays, w0) = a.windows.first!
		let driftedWindow = WidgetWindowSnapshot(
			days: w0.days, totalWindow: w0.totalWindow + 1e-9, series: w0.series.map { $0 + 1e-9 },
			providerWindows: w0.providerWindows.mapValues {
				WidgetProviderWindow(window: $0.window + 1e-9, series: $0.series.map { $0 + 1e-9 })
			})
		let drifted = WidgetSnapshot(
			generatedAt: a.generatedAt, access: a.access, title: a.title,
			totalToday: a.totalToday + 1e-9, totalWindow: a.totalWindow + 1e-9, currencyCode: a.currencyCode,
			windowDays: a.windowDays, basis: a.basis, series: a.series.map { $0 + 1e-9 },
			providers: [driftedProvider] + a.providers.dropFirst(),
			staleAfter: a.staleAfter, errorMessage: a.errorMessage,
			windows: a.windows.merging([wDays: driftedWindow]) { _, new in new })
		XCTAssertTrue(a.hasSameContent(as: drifted), "sub-cent FP drift anywhere must not force a republish")

		// A real one-cent change in a NESTED provider value must still be detected.
		let realProvider = WidgetProviderSnapshot(
			id: p0.id, name: p0.name, tintHex: p0.tintHex, today: p0.today + 0.01, window: p0.window,
			currencyCode: p0.currencyCode, metric: p0.metric, basis: p0.basis, usedPercent: p0.usedPercent,
			weeklyUsedPercent: p0.weeklyUsedPercent, usageOfficial: p0.usageOfficial, series: p0.series)
		let realChange = WidgetSnapshot(
			generatedAt: a.generatedAt, access: a.access, title: a.title,
			totalToday: a.totalToday, totalWindow: a.totalWindow, currencyCode: a.currencyCode,
			windowDays: a.windowDays, basis: a.basis, series: a.series,
			providers: [realProvider] + a.providers.dropFirst(),
			staleAfter: a.staleAfter, errorMessage: a.errorMessage, windows: a.windows)
		XCTAssertFalse(a.hasSameContent(as: realChange), "a nested ≥1¢ change must trigger a republish")
	}

	// selectingWindow(days:) is the widget's per-instance timeframe pick. Every requested day-count must
	// swap the singular totals/series AND every provider's window/series while preserving every other
	// provider field untouched (today, rate-limit %, tint, basis, currency) — the exact ~10-arg
	// copy-construct where a dropped field would silently regress a currently-working feature.
	func testSnapshotCanSelectADifferentWindow() {
		let snapshot = WidgetSnapshot.fixture(access: .premium)

		for days in [7, 14, 30, 90] {
			let selected = snapshot.selectingWindow(days: days)
			let expected = try! XCTUnwrap(snapshot.windows[days])

			XCTAssertEqual(selected.windowDays, days)
			XCTAssertEqual(selected.totalWindow, expected.totalWindow, accuracy: 0.001)
			XCTAssertEqual(selected.series, expected.series)

			for provider in selected.providers {
				let providerWindow = try! XCTUnwrap(expected.providerWindows[provider.id])
				XCTAssertEqual(provider.window, providerWindow.window, accuracy: 0.001)
				XCTAssertEqual(provider.series, providerWindow.series)
			}

			// Fields that are NOT window-dependent must be preserved unchanged from the original.
			XCTAssertEqual(selected.providers.map(\.today), snapshot.providers.map(\.today))
			XCTAssertEqual(selected.providers.map(\.usedPercent), snapshot.providers.map(\.usedPercent))
			XCTAssertEqual(selected.providers.map(\.weeklyUsedPercent), snapshot.providers.map(\.weeklyUsedPercent))
			XCTAssertEqual(selected.providers.map(\.usageOfficial), snapshot.providers.map(\.usageOfficial))
			XCTAssertEqual(selected.providers.map(\.tintHex), snapshot.providers.map(\.tintHex))
			XCTAssertEqual(selected.providers.map(\.basis), snapshot.providers.map(\.basis))
			XCTAssertEqual(selected.providers.map(\.currencyCode), snapshot.providers.map(\.currencyCode))
			XCTAssertEqual(selected.totalToday, snapshot.totalToday, accuracy: 0.001)
		}
	}

	// A day-count the snapshot doesn't carry must no-op rather than crash or silently produce garbage.
	func testSelectingAnUnavailableWindowIsANoOp() {
		let snapshot = WidgetSnapshot.fixture(access: .premium)
		let selected = snapshot.selectingWindow(days: 365)
		XCTAssertEqual(selected, snapshot)
	}

	// The TimelineProvider's exact call order: select the window BEFORE narrowing to one provider, so
	// `focused` picks up the already-window-selected provider figures rather than the default window.
	func testSelectingWindowThenFocusingComposesCorrectly() {
		let snapshot = WidgetSnapshot.fixture(access: .premium)
		let expected = try! XCTUnwrap(snapshot.windows[90]?.providerWindows["codex"])

		let composed = snapshot.selectingWindow(days: 90).focused(providerID: "codex")

		XCTAssertEqual(composed.windowDays, 90)
		XCTAssertEqual(composed.totalWindow, expected.window, accuracy: 0.001)
		XCTAssertEqual(composed.series, expected.series)
		XCTAssertEqual(composed.providers.map(\.id), ["codex"])
		XCTAssertEqual(composed.metric, composed.providers.first?.metric)
	}
}

private extension WidgetSnapshot {
	static func fixture(access: WidgetAccessState) -> WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
			access: access,
			title: "All providers",
			totalToday: 1235.08,
			totalWindow: 12409.47,
			currencyCode: "USD",
			windowDays: 14,
			basis: .realAndNotionalListPrice,
			series: [120, 90, 160, 130],
			providers: [
				WidgetProviderSnapshot(
					id: "claude",
					name: "Claude Code",
					tintHex: "#D6783F",
					today: 1009.89,
					window: 7970.04,
					currencyCode: "USD",
					basis: .realSpend,
					usedPercent: nil,
					weeklyUsedPercent: nil,
					usageOfficial: true,
					series: [60, 50, 85, 80]),
				WidgetProviderSnapshot(
					id: "codex",
					name: "Codex",
					tintHex: "#2F2F33",
					today: 225.19,
					window: 4439.43,
					currencyCode: "USD",
					basis: .notionalListPrice,
					usedPercent: 83,
					weeklyUsedPercent: 62,
					usageOfficial: true,
					series: [60, 40, 75, 50]),
			],
			staleAfter: Date(timeIntervalSince1970: 1_780_003_600),
			errorMessage: nil,
			windows: [
				7: WidgetWindowSnapshot(
					days: 7, totalWindow: 6000.00, series: [90, 130],
					providerWindows: [
						"claude": WidgetProviderWindow(window: 3800.00, series: [50, 85]),
						"codex": WidgetProviderWindow(window: 2200.00, series: [40, 45]),
					]),
				14: WidgetWindowSnapshot(
					days: 14, totalWindow: 12409.47, series: [120, 90, 160, 130],
					providerWindows: [
						"claude": WidgetProviderWindow(window: 7970.04, series: [60, 50, 85, 80]),
						"codex": WidgetProviderWindow(window: 4439.43, series: [60, 40, 75, 50]),
					]),
				30: WidgetWindowSnapshot(
					days: 30, totalWindow: 25000.00, series: [120, 90, 160, 130, 200],
					providerWindows: [
						"claude": WidgetProviderWindow(window: 16000.00, series: [60, 50, 85, 80, 120]),
						"codex": WidgetProviderWindow(window: 9000.00, series: [60, 40, 75, 50, 80]),
					]),
				90: WidgetWindowSnapshot(
					days: 90, totalWindow: 70000.00, series: [120, 90, 160, 130, 200, 300],
					providerWindows: [
						"claude": WidgetProviderWindow(window: 45000.00, series: [60, 50, 85, 80, 120, 180]),
						"codex": WidgetProviderWindow(window: 25000.00, series: [60, 40, 75, 50, 80, 120]),
					]),
			])
	}
}
