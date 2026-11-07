import JPtheCatCore
import XCTest

@testable import JPtheCatApp

/// Guards for the ONE provider opt-in row (`ProviderOptInRow` + the four `ProviderOptInDescriptor`s on
/// `SettingsBackView`) that replaced four hand-copied ~95-line rows.
///
/// [Regression guard — copy-paste drift, already shipped] `CursorHookRow.toggled(to:)` was
/// `requested ? confirmInstall() : confirmUninstall()` with NO `.installable` check, so an
/// `.unavailable` Cursor jumped straight to the install alert instead of the open-docs fallback its
/// three siblings had. `testEveryProviderOptInRowFallsBackToSetupDocsWhenUnavailable` pins that all
/// four now share one decision, and the source guards below pin that they still share one row.
@MainActor
final class ProviderOptInRowTests: XCTestCase {

	// MARK: - The shared toggle decision (the drift that shipped)

	/// The fallback all four rows must have: when there is no install path, offer the setup docs —
	/// never the install alert, which would otherwise try to configure a tool that is not there.
	func testEveryProviderOptInRowFallsBackToSetupDocsWhenUnavailable() {
		XCTAssertEqual(
			ProviderOptInIntent.resolve(requested: true, isOn: false, state: .unavailable),
			.openSetupDocs,
			"an unavailable provider must route to setup docs, never NSAlert + install()")
	}

	func testOnlyAnInstallableProviderReachesTheInstallAlert() {
		XCTAssertEqual(
			ProviderOptInIntent.resolve(requested: true, isOn: false, state: .installable),
			.confirmInstall)
		for state in [ProviderOptInState.unavailable, .active] {
			XCTAssertNotEqual(
				ProviderOptInIntent.resolve(requested: true, isOn: false, state: state),
				.confirmInstall,
				"only `.installable` may reach the install alert (state: \(state))")
		}
	}

	/// Turning a row OFF always confirms first — an uninstall is a real filesystem revert, never silent.
	func testTurningARowOffAlwaysConfirmsFirst() {
		for state in [ProviderOptInState.active, .installable, .unavailable] {
			XCTAssertEqual(
				ProviderOptInIntent.resolve(requested: false, isOn: true, state: state),
				.confirmUninstall)
		}
	}

	/// SwiftUI re-sends the current value on rebuild; a redundant flip must not re-open an alert.
	func testARedundantFlipIsIgnored() {
		XCTAssertEqual(
			ProviderOptInIntent.resolve(requested: true, isOn: true, state: .active), .ignore)
		XCTAssertEqual(
			ProviderOptInIntent.resolve(requested: false, isOn: false, state: .installable), .ignore)
	}

	// MARK: - Descriptors

	/// Only Claude and Grok write a capture file that can outlive its install marker, so only they may
	/// clear one. Copilot and Cursor must carry NO `reconcileStaleCapture` — flattening that branch
	/// into all four rows is exactly the kind of copy-paste that produced the Cursor drift.
	func testOnlyClaudeAndGrokReconcileAStaleCaptureFile() {
		XCTAssertNotNil(SettingsBackView.claudeLiveLimits.reconcileStaleCapture)
		XCTAssertNotNil(SettingsBackView.grokLiveLimits.reconcileStaleCapture)
		XCTAssertNil(SettingsBackView.copilotLiveData.reconcileStaleCapture)
		XCTAssertNil(SettingsBackView.cursorLiveData.reconcileStaleCapture)
	}

	/// Every descriptor still renders three distinct titles and three distinct subtitles, and the
	/// `.unavailable` title never reads as the "Enable …" call to action (a provider that cannot be
	/// configured must not look like it can be).
	func testEveryDescriptorRendersThreeDistinctStates() {
		let descriptors: [(String, ProviderOptInDescriptor)] = [
			("claude", SettingsBackView.claudeLiveLimits),
			("grok", SettingsBackView.grokLiveLimits),
			("copilot", SettingsBackView.copilotLiveData),
			("cursor", SettingsBackView.cursorLiveData),
		]
		for (name, descriptor) in descriptors {
			let titles = [
				descriptor.title(.active, true),
				descriptor.title(.installable, false),
				descriptor.title(.unavailable, false),
			]
			let subtitles = [
				descriptor.subtitle(.active, true),
				descriptor.subtitle(.installable, false),
				descriptor.subtitle(.unavailable, false),
			]
			XCTAssertEqual(Set(titles).count, 3, "\(name) must title all three states distinctly")
			XCTAssertEqual(Set(subtitles).count, 3, "\(name) must subtitle all three states distinctly")
			XCTAssertTrue(descriptor.title(.installable, false).hasPrefix("Enable "), name)
			XCTAssertFalse(
				descriptor.title(.unavailable, false).hasPrefix("Enable "),
				"\(name) must not offer to enable a provider it cannot configure")
			XCTAssertFalse(descriptor.installAlert.message.isEmpty, name)
			XCTAssertFalse(descriptor.uninstallAlert.message.isEmpty, name)
			XCTAssertEqual(descriptor.installAlert.confirmButton, "Enable", name)
			XCTAssertEqual(descriptor.uninstallAlert.confirmButton, "Turn off", name)
		}
	}

	/// The exact strings `web/tests/site-copy.test.ts` mirrors on the homepage demo toggles. The refactor
	/// had to be byte-identical in rendered output — this is the mac side of that parity pin.
	func testLiveLimitCopyStaysByteIdenticalToTheWebMirror() {
		XCTAssertEqual(
			SettingsBackView.claudeLiveLimits.title(.active, true), "Claude live limits · on")
		XCTAssertEqual(
			SettingsBackView.claudeLiveLimits.title(.installable, false), "Enable Claude live limits")
		XCTAssertEqual(SettingsBackView.grokLiveLimits.title(.active, true), "Grok live limits · on")
		XCTAssertEqual(
			SettingsBackView.grokLiveLimits.title(.installable, false), "Enable Grok live limits")
		XCTAssertEqual(
			SettingsBackView.copilotLiveData.title(.active, true), "Copilot CLI live data · on")
		XCTAssertEqual(
			SettingsBackView.cursorLiveData.title(.active, true), "Cursor CLI live data · on")
	}

	/// A fresh capture file must refine DISPLAY only, never the switch — the "toggle doesn't stick"
	/// regression was `active || state == .active`. Claude/Grok read differently at `.active` depending
	/// on freshness; the switch itself is `state == .active` inside `ProviderOptInRow`.
	func testCaptureFreshnessRefinesDisplayOnly() {
		XCTAssertNotEqual(
			SettingsBackView.claudeLiveLimits.title(.active, true),
			SettingsBackView.claudeLiveLimits.title(.active, false))
		XCTAssertNotEqual(
			SettingsBackView.grokLiveLimits.title(.active, true),
			SettingsBackView.grokLiveLimits.title(.active, false))
		// Copilot and Cursor have no capture-freshness signal at all, so it must change nothing.
		XCTAssertEqual(
			SettingsBackView.copilotLiveData.title(.active, true),
			SettingsBackView.copilotLiveData.title(.active, false))
		XCTAssertEqual(
			SettingsBackView.cursorLiveData.title(.active, true),
			SettingsBackView.cursorLiveData.title(.active, false))
	}

	// MARK: - Hidden until detected

	/// [HARD REQUIREMENT] A UI offering to enable/connect/configure a provider must stay hidden until
	/// the tool is detected locally. On a CLEAN fixture — an empty search path and an empty home —
	/// every detector reads false and every state resolves `.unavailable`, so the row is gated out of
	/// `LiveDataWindowContent` and, even if it were rendered, could only route to docs.
	func testProviderRowsStayHiddenOnACleanFixture() throws {
		let clean = FileManager.default.temporaryDirectory
			.appendingPathComponent("jp-clean-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: clean, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: clean) }

		XCTAssertFalse(CopilotOtelSetup.isCopilotCLIDetected(searchDirectories: [clean]))
		XCTAssertFalse(CursorHookSetup.isCursorCLIDetected(searchDirectories: [clean]))
		XCTAssertFalse(GrokProvider.isGrokBuildDetected(home: clean))

		// An undetected tool resolves `.unavailable`, never `.installable` — nothing to offer.
		XCTAssertEqual(CursorHookSetup.state(cursorHome: clean, appSupport: clean, detected: false), .unavailable)
		XCTAssertEqual(GrokRateLimitCapture.state(grokHome: clean, detected: false), .unavailable)

		// …and an `.unavailable` row can never reach install(), for any of the four providers.
		XCTAssertEqual(
			ProviderOptInIntent.resolve(requested: true, isOn: false, state: .unavailable),
			.openSetupDocs)
	}

	/// The row's own half of the self-hiding contract: it re-probes on `.onAppear`, so an install or
	/// uninstall performed outside the app is reflected the next time the window opens.
	func testProviderOptInRowReprobesOnAppear() throws {
		let row = try AppSourceScanner.body(of: "struct ProviderOptInRow")
		XCTAssertTrue(row.contains(".onAppear(perform: refresh)"))
		XCTAssertTrue(row.contains("state = descriptor.probeState()"))
		// ONE ground-truth signal: the install marker. Never OR'd with capture freshness.
		XCTAssertTrue(row.contains("private var isInstalled: Bool { state == .active }"))
		XCTAssertFalse(row.contains("captureIsFresh || state == .active"))
		// Any row that changes what a provider reports forces an immediate reindex, not the next poll.
		XCTAssertTrue(row.contains("model.refresh(reindex: true)"))
	}

	/// The Live Data window's half: each provider-configuring row stays behind its detection gate, and
	/// the gates are re-evaluated on appear. Ordering is only meaningful inside one declaration, so this
	/// slices `LiveDataWindowContent` itself.
	func testLiveDataWindowGatesEveryProviderRowOnLocalDetection() throws {
		let content = try AppSourceScanner.body(of: "struct LiveDataWindowContent")

		for gate in ["if grokBuildDetected {", "if museSparkDetected {", "if copilotCLIDetected {", "if cursorCLIDetected {", "if cursorSignInSourceDetected || grokBotDetected {", "if grokBuildDetected || grokBotDetected || cursorSignInSourceDetected || cursorCLIDetected {"] {
			XCTAssertTrue(content.contains(gate), "missing detection gate: \(gate)")
		}
		for probe in [
			"copilotCLIDetected = CopilotOtelSetup.isCopilotCLIDetected()",
			"cursorCLIDetected = CursorHookSetup.isCursorCLIDetected()",
			"cursorSignInSourceDetected = CursorAuthToken.isSourcePresent()",
			"grokBuildDetected = GrokProvider.isGrokBuildDetected()",
			"grokBotDetected = GrokBotProvider.isGrokBotDetected()",
		] {
			XCTAssertTrue(content.contains(probe), "detection must be re-probed on appear: \(probe)")
		}

		// Each gated provider's row must sit AFTER its gate opens.
		for (gate, descriptor) in [
			("if grokBuildDetected {", "SettingsBackView.grokLiveLimits"),
			("if copilotCLIDetected {", "SettingsBackView.copilotLiveData"),
			("if cursorCLIDetected {", "SettingsBackView.cursorLiveData"),
			("if cursorSignInSourceDetected || grokBotDetected {", "SettingsBackView.grokPlanUsage"),
		] {
			let gateIndex = try XCTUnwrap(content.range(of: gate)?.lowerBound)
			let rowIndex = try XCTUnwrap(content.range(of: descriptor)?.lowerBound)
			XCTAssertLessThan(gateIndex, rowIndex, "\(descriptor) escaped its detection gate")
		}

		// Exactly five opt-in rows, all rendered by the one shared view.
		XCTAssertEqual(try AppSourceScanner.occurrences(of: "ProviderOptInRow(model: model"), 5)
	}
}
