import AppIntents
import AppKit
import JPtheCatCore
import SwiftUI
import WidgetKit

enum JPWidgetProviderChoice: String, AppEnum {
	case all
	case claude
	case codex
	case grok
	case museSpark
	case nemotron
	case mimo
	case bigPickle
	case deepseek
	case copilot
	case cursor
	case grokBot = "grok_bot"

	static var allCases: [JPWidgetProviderChoice] { [.all, .claude, .codex, .grok, .museSpark, .nemotron, .mimo, .bigPickle, .deepseek, .copilot] }

	static var typeDisplayRepresentation: TypeDisplayRepresentation {
		"View"
	}

	static var caseDisplayRepresentations: [JPWidgetProviderChoice: DisplayRepresentation] {
		[
			.all: "All providers",
			.claude: "Claude Code",
			.codex: "Codex",
			.grok: "Grok",
			.museSpark: "Muse Spark",
			.nemotron: "Nemotron",
			.mimo: "MiMo",
			.bigPickle: "Big Pickle",
			.deepseek: "DeepSeek",
			.copilot: "GitHub Copilot",
			.cursor: "Grok (legacy Cursor)",
			.grokBot: "Grok (legacy Grok Bot)",
		]
	}

	var providerID: String? {
		switch self {
		case .all: return nil
		case .claude: return "claude"
		case .codex: return "codex"
		case .grok: return "grok"
		case .museSpark: return "muse_spark"
		case .nemotron: return "nemotron"
		case .mimo: return "mimo"
		case .bigPickle: return "big_pickle"
		case .deepseek: return "deepseek"
		case .copilot: return "copilot"
		case .cursor, .grokBot: return "grok"
		}
	}
}

/// Per-widget-instance timeframe choice, mirroring the app dashboard's own `TimeframePicker`
/// (7/14/30/90 days, default 14) so a widget can independently show a different window than
/// whatever the in-app dashboard currently has selected.
enum JPWidgetTimeframeChoice: String, AppEnum {
	case sevenDays
	case fourteenDays
	case thirtyDays
	case ninetyDays

	static var typeDisplayRepresentation: TypeDisplayRepresentation {
		"Timeframe"
	}

	static var caseDisplayRepresentations: [JPWidgetTimeframeChoice: DisplayRepresentation] {
		[
			.sevenDays: "7 days",
			.fourteenDays: "14 days",
			.thirtyDays: "30 days",
			.ninetyDays: "90 days",
		]
	}

	var days: Int {
		switch self {
		case .sevenDays: return 7
		case .fourteenDays: return 14
		case .thirtyDays: return 30
		case .ninetyDays: return 90
		}
	}
}

struct JPtheCatWidgetConfigurationIntent: WidgetConfigurationIntent {
	static var title: LocalizedStringResource { "JP the Cat" }
	// periphery:ignore - AppIntent metadata the system reads; nothing in the package calls it.
	static var description: IntentDescription {
		"Choose the provider view for the JP the Cat widget."
	}

	@Parameter(title: "View", default: .all)
	var provider: JPWidgetProviderChoice

	@Parameter(title: "Show limits", default: true)
	var showLimits: Bool

	@Parameter(title: "Timeframe", default: .fourteenDays)
	var timeframe: JPWidgetTimeframeChoice
}

struct JPtheCatWidgetEntry: TimelineEntry {
	let date: Date
	let configuration: JPtheCatWidgetConfigurationIntent
	let snapshot: WidgetSnapshot
	let isPreview: Bool
}

struct JPtheCatWidgetTimelineProvider: AppIntentTimelineProvider {
	func placeholder(in context: Context) -> JPtheCatWidgetEntry {
		// The gallery/loading state must look like a real widget, not an empty $0 card with no rows, so
		// the placeholder uses the representative sample snapshot (marked isPreview) instead of `.zero`.
		JPtheCatWidgetEntry(
			date: Date(),
			configuration: JPtheCatWidgetConfigurationIntent(),
			snapshot: WidgetPreviewData.snapshot,
			isPreview: true)
	}

	func snapshot(
		for configuration: JPtheCatWidgetConfigurationIntent,
		in context: Context
	) async -> JPtheCatWidgetEntry {
		entry(for: configuration)
	}

	func timeline(
		for configuration: JPtheCatWidgetConfigurationIntent,
		in context: Context
	) async -> Timeline<JPtheCatWidgetEntry> {
		let entry = entry(for: configuration)
		return Timeline(
			entries: [entry],
			policy: .after(entry.date.addingTimeInterval(30 * 60)))
	}

	private func entry(for configuration: JPtheCatWidgetConfigurationIntent) -> JPtheCatWidgetEntry {
		Self.entry(for: configuration, stored: WidgetSnapshotStore().readIfAvailable())
	}

	/// `isPreview` means the figures are sample data, so it follows `stored`, not `context.isPreview`.
	/// The gallery shows the stored snapshot when one exists, and flagging it by context labeled the
	/// user's real numbers "Preview data".
	static func entry(
		for configuration: JPtheCatWidgetConfigurationIntent, stored: WidgetSnapshot?
	) -> JPtheCatWidgetEntry {
		let base = stored ?? WidgetPreviewData.snapshot
		// Window-select BEFORE provider-focus so `focused` narrows from the already-correct window's
		// per-provider figures rather than whichever window happened to be the snapshot's default.
		let windowed = base.selectingWindow(days: configuration.timeframe.days)
		let focused = windowed.focused(providerID: configuration.provider.providerID)
		return JPtheCatWidgetEntry(
			date: Date(),
			configuration: configuration,
			snapshot: focused,
			isPreview: stored == nil)
	}
}
