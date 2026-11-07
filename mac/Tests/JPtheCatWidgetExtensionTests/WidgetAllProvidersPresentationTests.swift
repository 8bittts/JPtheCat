import JPtheCatCore
import XCTest

@testable import JPtheCatWidgetExtension

/// Regression guard for Widget All-Providers Coverage: presentation must never silently drop a
/// contributing provider via `prefix(N)` / hard maxRows as the ladder grows past 2 (Medium) or 3
/// (stale Large a11y). Density may change; the display set must stay complete.
final class WidgetAllProvidersPresentationTests: XCTestCase {
	func testPreviewTotalsAndTimeframesMatchVisibleDollarRows() {
		let snapshot = WidgetPreviewData.snapshot
		let dollarRows = snapshot.providers.filter { $0.metric == .dollars }
		XCTAssertEqual(snapshot.totalToday, dollarRows.reduce(0) { $0 + $1.today }, accuracy: 1e-9)
		for days in [7, 14, 30, 90] {
			let selected = snapshot.selectingWindow(days: days)
			XCTAssertEqual(selected.totalWindow, selected.providers.filter { $0.metric == .dollars }.reduce(0) { $0 + $1.window }, accuracy: 1e-9)
		}
		XCTAssertEqual(Set(snapshot.providers.map(\.id)), Set(JPWidgetProviderChoice.allCases.compactMap(\.providerID)))
	}

	func testOpenCodeProvidersHaveSelectablePreviewsAndBundledMarks() throws {
		for choice in [JPWidgetProviderChoice.nemotron, .mimo, .bigPickle, .deepseek] {
			let id = try XCTUnwrap(choice.providerID)
			let focused = WidgetPreviewData.snapshot.focused(providerID: id)
			XCTAssertEqual(focused.providers.map(\.id), [id])
			XCTAssertNotNil(WidgetAssets.svg(named: "provider-" + id))
		}
	}

	/// OpenCode Zen / Go are `ProviderBasis.gateway` ROLLUPS: their usage is already displayed under
	/// the model-brand rows (Muse Spark/Nemotron/MiMo/Big Pickle/DeepSeek). A widget that also showed
	/// the gateway slice would double-DISPLAY the same dollars, so they are deliberately EXCLUDED from
	/// the widget picker. This assertion pins that decision so a future `ProviderCatalog.live`-driven
	/// picker cannot silently add them.
	func testOpenCodeGatewaysAreDeliberatelyExcludedFromTheWidgetPicker() {
		let rawValues = Set(JPWidgetProviderChoice.allCases.map(\.rawValue))
		XCTAssertFalse(rawValues.contains("opencode"))
		XCTAssertFalse(rawValues.contains("opencodego"))
		XCTAssertNil(JPWidgetProviderChoice(rawValue: "opencode"))
		XCTAssertNil(JPWidgetProviderChoice(rawValue: "opencodego"))
	}

	func testProvidersToDisplayNeverTruncates() {
		for count in 0...10 {
			let providers = (0..<count).map { Self.stubProvider(id: "p\($0)", name: "Provider \($0)") }
			let displayed = WidgetAllProvidersPresentation.providersToDisplay(providers)
			XCTAssertEqual(
				displayed.map(\.id), providers.map(\.id),
				"Display set must equal the full provider list at count \(count)")
		}
	}

	func testPreviewSnapshotIncludesEveryCurrentWidgetVisibleProvider() {
		// Fixture is the gallery / render-harness All-providers set — if a provider is in the
		// snapshot it must also be in the display set (no silent drop of Grok/Copilot).
		let providers = WidgetPreviewData.snapshot.providers
		XCTAssertGreaterThanOrEqual(
			providers.count, 4,
			"Preview fixture must carry the current four widget-visible providers")
		let ids = Set(providers.map(\.id))
		XCTAssertTrue(ids.isSuperset(of: ["claude", "codex", "grok", "copilot"]))
		XCTAssertEqual(
			WidgetAllProvidersPresentation.providersToDisplay(providers).map(\.id),
			providers.map(\.id))
	}

	func testMediumUsesFullRowsForTwoProvidersAndGridBeyond() {
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .medium, providerCount: 0),
			.fullRows)
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .medium, providerCount: 1),
			.fullRows)
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .medium, providerCount: 2),
			.fullRows)
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .medium, providerCount: 3),
			.twoColumnGrid)
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .medium, providerCount: 4),
			.twoColumnGrid)
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .medium, providerCount: 6),
			.twoColumnGrid)
	}

	func testLargeUsesFullRowsThroughFourThenCompactWithoutDropping() {
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .large, providerCount: 3),
			.fullRows)
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .large, providerCount: 4),
			.fullRows)
		XCTAssertEqual(
			WidgetAllProvidersPresentation.layout(family: .large, providerCount: 5),
			.compactRows)
		// Compact densifies only — display set still complete.
		let five = (0..<5).map { Self.stubProvider(id: "p\($0)", name: "P\($0)") }
		XCTAssertEqual(
			WidgetAllProvidersPresentation.providersToDisplay(five).count, 5)
	}

	func testTenProvidersUseTheExistingGridOnBothFaces() {
		for family in [WidgetAllProvidersPresentation.Family.medium, .large] {
			XCTAssertEqual(WidgetAllProvidersPresentation.layout(family: family, providerCount: 10), .twoColumnGrid)
		}
	}

	func testShortNamesForDenseGrid() {
		XCTAssertEqual(
			WidgetAllProvidersPresentation.shortName(
				for: Self.stubProvider(id: "claude", name: "Claude Code")),
			"Claude")
		XCTAssertEqual(
			WidgetAllProvidersPresentation.shortName(
				for: Self.stubProvider(id: "codex", name: "Codex")),
			"Codex")
		XCTAssertEqual(
			WidgetAllProvidersPresentation.shortName(
				for: Self.stubProvider(id: "grok", name: "Grok")),
			"Grok")
		XCTAssertEqual(
			WidgetAllProvidersPresentation.shortName(
				for: Self.stubProvider(id: "copilot", name: "GitHub Copilot")),
			"Copilot")
		XCTAssertEqual(
			WidgetAllProvidersPresentation.shortName(
				for: Self.stubProvider(id: "future", name: "Future Agent CLI")),
			"Future")
		// Catalog short names win over the first-token fallback: "Muse Spark" is not "Muse".
		XCTAssertEqual(
			WidgetAllProvidersPresentation.shortName(
				for: Self.stubProvider(id: "muse_spark", name: "Muse Spark")),
			"Muse Spark")
		XCTAssertEqual(
			WidgetAllProvidersPresentation.shortName(
				for: Self.stubProvider(id: "big_pickle", name: "Big Pickle")),
			"Big Pickle")
	}

	func testSourceHasNoSilentMaxRowsPrefixOnAllProvidersFace() throws {
		// Packaging-style guard: the face files must not reintroduce a hard maxRows/prefix truncation.
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Sources/JPtheCatWidgetExtension")
		let faces = try String(
			contentsOf: root.appendingPathComponent("JPtheCatWidget.swift"), encoding: .utf8)
		let components = try String(
			contentsOf: root.appendingPathComponent("WidgetComponents.swift"), encoding: .utf8)
		XCTAssertFalse(
			faces.contains("maxRows"),
			"JPtheCatWidget.swift must not hard-cap provider rows with maxRows")
		XCTAssertFalse(
			faces.contains("providers.prefix"),
			"JPtheCatWidget.swift must not silently prefix the provider list")
		XCTAssertFalse(
			components.contains("providers.prefix"),
			"ProviderGaugeList must not silently prefix the provider list")
		XCTAssertFalse(
			components.contains("maxRows"),
			"ProviderGaugeList must not take a maxRows cap")
		XCTAssertTrue(
			faces.contains("WidgetAllProvidersPresentation.providersToDisplay"),
			"VoiceOver path must route through the no-truncate presentation helper")
		XCTAssertTrue(
			components.contains("WidgetAllProvidersPresentation.providersToDisplay"),
			"Visual list must route through the no-truncate presentation helper")
	}

	private static func stubProvider(id: String, name: String) -> WidgetProviderSnapshot {
		WidgetProviderSnapshot(
			id: id,
			name: name,
			tintHex: "#D6783F",
			today: 1,
			window: 2,
			basis: .realSpend,
			usedPercent: nil,
			weeklyUsedPercent: nil,
			usageOfficial: false,
			series: [1, 2])
	}
}
