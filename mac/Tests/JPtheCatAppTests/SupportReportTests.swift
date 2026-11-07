import JPtheCatCore
import XCTest

@testable import JPtheCatApp

final class SupportReportTests: XCTestCase {
	func testReportIncludesUsefulSupportStateWithoutSecrets() {
		let report = SupportReport.make(
			SupportReportInput(
				appVersion: "1.002",
				buildNumber: "135",
				installedAppVersion: "1.002 (135)",
				runningExecutablePath: "/Applications/JPtheCat.app/Contents/MacOS/JPtheCat",
				widgetAccess: .premium,
				macOSVersion: "Version 15.5",
				providerRows: [
					providerRow(
						id: "claude",
						name: "Claude Code",
						today: 1.25,
						window: 8.5,
						usedPct: nil,
						weeklyUsedPct: nil),
					providerRow(
						id: "codex",
						name: "Codex",
						today: 2.5,
						window: 12.75,
						usedPct: 83,
						weeklyUsedPct: 41,
						notional: true),
				],
				selectedDays: 14),
			generatedAt: Date(timeIntervalSince1970: 1_783_425_600))

		XCTAssertTrue(report.contains("JP the Cat support report"))
		XCTAssertTrue(report.contains("App: 1.002 (135)"))
		XCTAssertTrue(report.contains("Installed app: 1.002 (135)"))
		XCTAssertTrue(report.contains("Running executable: /Applications/JPtheCat.app/Contents/MacOS/JPtheCat"))
		XCTAssertTrue(report.contains("Widget access: premium"))
		XCTAssertTrue(report.contains("macOS: Version 15.5"))
		XCTAssertTrue(report.contains("Provider: Codex (codex)"))
		XCTAssertTrue(report.contains("5h used: 83%"))
		XCTAssertTrue(report.contains("weekly used: 41%"))
		// JP is free: the report carries no license, device, or price lines.
		XCTAssertFalse(report.localizedCaseInsensitiveContains("license"))
		XCTAssertFalse(report.contains("Device hash"))
		XCTAssertFalse(report.contains("Price"))
		XCTAssertFalse(report.localizedCaseInsensitiveContains("prompt"))
		XCTAssertFalse(report.localizedCaseInsensitiveContains("transcript"))
		XCTAssertFalse(report.localizedCaseInsensitiveContains("/Users/"))
		XCTAssertFalse(report.localizedCaseInsensitiveContains("input_tokens"))
	}

	func testReportSanitizesNonCanonicalExecutablePaths() {
		XCTAssertEqual(
			SupportReport.executableLabel(
				"/Users/example/Documents/JPtheCat/workstreams/demo/mac/build/local-run/JPtheCat.app/Contents/MacOS/JPtheCat"),
			"non-canonical JPtheCat.app/Contents/MacOS/JPtheCat")
		XCTAssertEqual(
			SupportReport.executableLabel("/Users/example/tmp/JPtheCat"),
			"non-canonical executable")
	}

	private func providerRow(
		id: String,
		name: String,
		today: Double,
		window: Double,
		usedPct: Double?,
		weeklyUsedPct: Double?,
		notional: Bool = false
	) -> DashboardViewModel.ProviderRow {
		DashboardViewModel.ProviderRow(
			id: id,
			name: name,
			tintHex: "#000000",
			availability: .available,
			currencyCode: MoneyFormatter.baseCurrencyCode,
			today: today,
			week: window,
			todayUsage: TokenUsage(input: 1, output: 1),
			weekUsage: TokenUsage(input: 2, output: 2),
			todayEvents: 3,
			weekEvents: 9,
			series: [today, window],
			notional: notional,
			usedPct: usedPct,
			weeklyUsedPct: weeklyUsedPct,
			usageOfficial: usedPct != nil || weeklyUsedPct != nil,
			planLabel: "Pro",
			unpricedModels: [],
			byModel7d: [],
			cacheSavings7d: nil,
			resetsAt5h: nil,
			resetsAtWeekly: nil,
			windowMinutes5h: 300,
			windowMinutesWeekly: 10_080)
	}
}
