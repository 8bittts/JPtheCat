import XCTest

/// [NOTE] The `DashboardView.swift` reads below used a literal path, which froze that file. They now
/// resolve through `AppSourceScanner` — the dashboard face's own type surface for routing contracts,
/// whole-app scans for copy — so a moved surface fails loudly instead of emptying the guard.
final class OnboardingViewContractTests: XCTestCase {
	func testFirstRunOnboardingHasPersistentCompletionFlag() throws {
		let source = try AppSourceScanner.source(named: "SettingsStore.swift")

		XCTAssertTrue(source.contains(#"static let onboardingCompleted = "JPtheCat.onboarding.completed""#))
		XCTAssertTrue(source.contains("defaultOnboardingCompleted = false"))
		XCTAssertTrue(source.contains("@Published var onboardingCompleted: Bool"))
		XCTAssertTrue(source.contains("nonisolated static func onboardingCompleted"))
	}

	func testDashboardRoutesInitialFaceThroughOnboarding() throws {
		let source = try AppSourceScanner.typeSurface("DashboardView")

		XCTAssertTrue(source.contains("@State private var showingOnboarding = !SettingsStore.onboardingCompleted()"))
		XCTAssertTrue(source.contains("OnboardingView("))
		XCTAssertTrue(source.contains("completeOnboarding()"))
		XCTAssertTrue(source.contains("SettingsStore.shared.onboardingCompleted = true"))
		XCTAssertTrue(
			source.contains(
				#""\(showingOnboarding)-\(showingSettings)-\(layout.rawValue)-\(model.state.surfaceSizingSignature)""#))
	}

	func testDashboardHasNoPaywallFace() throws {
		let source = try AppSourceScanner.typeSurface("DashboardView")

		// JP is free: there is no locked upsell face and no license gate on the dashboard.
		XCTAssertFalse(source.contains("isDashboardLocked"))
		XCTAssertFalse(source.contains("lockedFace"))
		XCTAssertFalse(source.contains("LicenseManager"))
	}

	func testOnboardingViewIsLocalFirstAndCanOpenSettings() throws {
		let source = try AppSourceScanner.source(named: "OnboardingView.swift")

		XCTAssertTrue(source.contains("struct OnboardingView: View"))
		XCTAssertTrue(source.contains("let onContinue: () -> Void"))
		XCTAssertTrue(source.contains("let onOpenSettings: () -> Void"))
		XCTAssertTrue(source.contains(#""jp-first-run-peek""#))
		XCTAssertTrue(source.contains(#"Text("Start tracking")"#))
		XCTAssertTrue(source.contains(#"Text("Open Settings")"#))
		XCTAssertFalse(source.localizedCaseInsensitiveContains("license"))
		XCTAssertFalse(source.localizedCaseInsensitiveContains("trial"))
		XCTAssertTrue(source.contains("Prompts, code, and transcripts stay on this Mac."))
	}
}
