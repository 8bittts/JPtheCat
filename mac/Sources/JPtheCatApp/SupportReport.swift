import Foundation
import JPtheCatCore

struct SupportReportInput {
	var appVersion: String
	var buildNumber: String
	var installedAppVersion: String?
	var runningExecutablePath: String?
	var widgetAccess: WidgetAccessState?
	var macOSVersion: String
	var providerRows: [DashboardViewModel.ProviderRow]
	var selectedDays: Int
}

enum SupportReport {
	static func make(_ input: SupportReportInput, generatedAt: Date = Date()) -> String {
		var lines: [String] = [
			"JP the Cat support report",
			"Generated: \(LocalAutomationSnapshotEncoder.string(from: generatedAt))",
			"App: \(input.appVersion) (\(input.buildNumber))",
			"Installed app: \(input.installedAppVersion ?? "unknown")",
			"Running executable: \(executableLabel(input.runningExecutablePath))",
			"macOS: \(input.macOSVersion)",
			"Widget access: \(input.widgetAccess?.rawValue ?? "unknown")",
			"Window: \(input.selectedDays)d",
		]

		lines.append("")
		lines.append("Providers:")
		if input.providerRows.isEmpty {
			lines.append("- none")
		} else {
			for row in input.providerRows {
				lines.append("- Provider: \(row.name) (\(row.id))")
				lines.append("  Availability: \(availabilityLabel(row.availability))")
				lines.append("  Today: \(MoneyFormatter.dollars(row.today ?? 0, code: row.currencyCode))")
				lines.append("  \(input.selectedDays)d: \(MoneyFormatter.dollars(row.week, code: row.currencyCode))")
				lines.append("  Events: today \(row.todayEvents), window \(row.weekEvents)")
				if row.notional {
					lines.append("  Cost basis: notional list-price")
				}
				if let usedPct = row.usedPct {
					lines.append("  5h used: \(percent(usedPct))")
				}
				if let weeklyUsedPct = row.weeklyUsedPct {
					lines.append("  weekly used: \(percent(weeklyUsedPct))")
				}
				if !row.unpricedModels.isEmpty {
					lines.append("  Unpriced models: \(row.unpricedModels.sorted().joined(separator: ", "))")
				}
			}
		}

		lines.append("")
		lines.append("Privacy: No request text, code, conversation logs, token payloads, secrets, or raw file paths are included.")
		return lines.joined(separator: "\n")
	}

	static func executableLabel(_ path: String?) -> String {
		guard let path, !path.isEmpty else { return "unknown" }
		if path == SingleInstanceGuard.canonicalExecutablePath { return path }
		if path.contains("/JPtheCat.app/Contents/MacOS/JPtheCat") {
			return "non-canonical JPtheCat.app/Contents/MacOS/JPtheCat"
		}
		return "non-canonical executable"
	}

	private static func availabilityLabel(_ availability: DashboardProviderAvailability) -> String {
		switch availability {
		case .available:
			"available"
		case .stale:
			"stale"
		case .unavailable:
			"unavailable"
		case .disabled:
			"disabled"
		}
	}

	private static func percent(_ value: Double) -> String {
		let rounded = (value * 100).rounded() / 100
		if rounded.rounded() == rounded {
			return "\(Int(rounded))%"
		}
		return "\(rounded)%"
	}
}
