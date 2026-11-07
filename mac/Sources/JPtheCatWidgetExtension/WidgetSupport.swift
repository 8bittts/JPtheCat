import AppIntents
import AppKit
import JPtheCatCore
import SwiftUI
import WidgetKit

// MARK: - Resource + palette helpers

/// Loads the widget extension's bundled assets (loose PNG + SVG marks) the SAME way the app does — via
/// NSImage, NOT SwiftUI's `Image(name:bundle:)`, which does not resolve loose (non-asset-catalog)
/// resources on macOS (that was the blank-mark bug). Resolves the widget's resource bundle by name so
/// it never touches SwiftPM's `Bundle.module`, which can trap in a packaged `.app`.
enum WidgetAssets {
  private static var bundle: Bundle? {
    JPResourceBundle.bundle(named: "JPtheCatWidgetExtension")
  }
	static func image(named name: String) -> NSImage? { bundle?.image(forResource: name) }
	static func svg(named name: String) -> NSImage? {
    guard
      let url = JPResourceBundle.url(
        forResource: name, withExtension: "svg",
        in: "JPtheCatWidgetExtension")
		else { return nil }
		return NSImage(contentsOf: url)
	}
}

/// Theme-matched color roles for the widget, resolved per `ColorScheme` (the widget follows the system
/// appearance). Values mirror the app's Sunlit / Midnight `JPTheme` ink/track roles so the widget and
/// the dashboard read as one product; the data-viz tint lift is the SAME Core math the app uses
/// (`ProviderTintLegibility`), keyed to the widget card's dominant background stop.
enum WidgetPalette {
	// Background stops the tint lift is measured against (dominant mid stop of JPWidgetBackground).
	private static func cardHex(_ s: ColorScheme) -> String { s == .dark ? "221E1B" : "FFFDF7" }
	private static func inkHex(_ s: ColorScheme) -> String { s == .dark ? "F2F1EC" : "221D15" }

	static func card(_ s: ColorScheme) -> Color { Color(hex: cardHex(s)) }
	static func ink(_ s: ColorScheme) -> Color { Color(hex: inkHex(s)) } // primary text / money
  static func inkSoft(_ s: ColorScheme) -> Color {
    Color(hex: s == .dark ? "B8B6AE" : "6C6253")
  }  // captions
  static func track(_ s: ColorScheme) -> Color {
    Color(hex: s == .dark ? "4E4A40" : "ECDCBD")
  }  // meter groove
	static func gingerDeep(_ s: ColorScheme) -> Color {
    Color(hex: s == .dark ? "FBA85F" : "A84D14")
  }
	static func sageDeep(_ s: ColorScheme) -> Color {
		Color(hex: s == .dark ? "9FD4A8" : "2F6B3A")
	}
	static func sageWash(_ s: ColorScheme) -> Color {
		Color(hex: s == .dark ? "9FD4A8" : "2F6B3A").opacity(0.22)
	}
	static func honeyWash(_ s: ColorScheme) -> Color {
		Color(hex: s == .dark ? "EBB454" : "EDB454").opacity(0.25)
	}
	static func markRim(_ s: ColorScheme) -> Color {
		s == .dark ? Color.white.opacity(0.48) : Color(hex: "221D15").opacity(0.12)
	}

	/// The widget card background gradient — warm cream (light) / warm charcoal (dark). The dominant
	/// mid/first stop reuses `cardHex` so the card color and the `viz(...)` WCAG legibility reference
	/// (which measures against `cardHex`) can never silently drift apart from two hand-kept copies.
	static func background(_ s: ColorScheme) -> LinearGradient {
    let stops =
      s == .dark
			? ["2B2622", cardHex(s), "191512"]  // cardHex(.dark) is the dominant mid stop
			: [cardHex(s), "FAF6EC", "F4ECDA"]  // cardHex(.light) is the top stop
		return LinearGradient(
      colors: stops.map { Color(hex: $0) }, startPoint: .topLeading,
      endPoint: .bottomTrailing)
	}

	/// JP's mascot-art gold — used ONLY for the fallback mark badge when the bundled mark can't load.
	/// Bright gold is mascot art, never a data/UI surface role.
	static let mascotBadge = Color(hex: "FDCD2D")

	/// A brand tint made legible on the widget card for data-viz (dot fallback, meter fill, sparkline).
	/// The icon CHIP keeps the raw brand tint — only these lifted values go on the card/track.
	static func viz(_ hex: String, _ s: ColorScheme) -> Color {
    Color(
      hex: ProviderTintLegibility.legibleHex(
        tintHex: hex, backgroundHex: cardHex(s), inkHex: inkHex(s),
        isDark: s == .dark))
	}
}

enum WidgetPreviewData {
	private static let providers: [WidgetProviderSnapshot] = [
			WidgetProviderSnapshot(
				id: "claude",
				name: "Claude Code",
				tintHex: "#D6783F",
				today: 1009.89,
				window: 7970.04,
				basis: .realSpend,
				usedPercent: 60,
				weeklyUsedPercent: 42,
				usageOfficial: true,
				series: [300, 260, 360, 290, 330, 300, 420, 470]),
			WidgetProviderSnapshot(
				id: "codex",
				name: "Codex",
				tintHex: "#2F2F33",
				today: 225.19,
				window: 4439.43,
				basis: .notionalListPrice,
				usedPercent: 83,
				weeklyUsedPercent: 62,
				usageOfficial: true,
				series: [120, 100, 170, 100, 125, 140, 190, 265]),
      WidgetProviderSnapshot(
        id: "grok", name: "Grok", tintHex: "#111111", today: 42.18,
        window: 318.42,
        basis: .notionalListPrice, usedPercent: nil, weeklyUsedPercent: 23,
        usageOfficial: true, series: [22, 31, 28, 44, 39, 51, 48, 55]),
      WidgetProviderSnapshot(
        id: "muse_spark", name: "Muse Spark", tintHex: "#0866FF", today: 12.40,
        window: 96.80,
        basis: .notionalListPrice, usedPercent: nil, weeklyUsedPercent: nil,
        usageOfficial: false, series: [8, 10, 11, 12, 14, 15, 13, 12]),
      WidgetProviderSnapshot(
        id: "nemotron", name: "Nemotron", tintHex: "#76b900", today: 640_000, window: 4_300_000, metric: .tokens,
        basis: .notionalListPrice, usedPercent: nil, weeklyUsedPercent: nil,
        usageOfficial: false, series: [120, 140, 130, 150, 145, 160, 155, 170]),
      WidgetProviderSnapshot(
        id: "mimo", name: "MiMo", tintHex: "#e74856", today: 0.42, window: 2.60,
        basis: .notionalListPrice, usedPercent: nil, weeklyUsedPercent: nil,
        usageOfficial: false, series: [80, 95, 110, 105, 120, 115, 130, 125]),
      WidgetProviderSnapshot(
        id: "big_pickle", name: "Big Pickle", tintHex: "#0d9488", today: 0, window: 0,
        basis: .notionalListPrice, usedPercent: nil, weeklyUsedPercent: nil,
        usageOfficial: false, series: [40, 55, 50, 60, 58, 62, 57, 65]),
      WidgetProviderSnapshot(
        id: "deepseek", name: "DeepSeek", tintHex: "#1a56db", today: 0.38, window: 0.90,
        basis: .notionalListPrice, usedPercent: nil, weeklyUsedPercent: nil,
        usageOfficial: false, series: [70, 85, 90, 88, 95, 92, 98, 100]),
      WidgetProviderSnapshot(
        id: "copilot", name: "GitHub Copilot", tintHex: "#6E40C9",
        today: 184_200,
        window: 1_482_000, metric: .tokens, basis: .realSpend,
        usedPercent: nil,
        weeklyUsedPercent: nil, usageOfficial: false,
        series: [
          112_000, 98_000, 145_000, 176_000, 151_000, 190_000,
          184_200,
        ]),

	]

	private static var dollarProviders: [WidgetProviderSnapshot] {
		providers.filter { $0.metric == .dollars }
	}

	static let snapshot: WidgetSnapshot = {
		let now = Date()
		let totalWindow = dollarProviders.reduce(0) { $0 + $1.window }
		let series = [420.0, 360, 530, 390, 455, 440, 610, 735]
		let windows = Dictionary(uniqueKeysWithValues: [7, 14, 30, 90].map { days in
			let scale = Double(days) / 14
			let values = Dictionary(uniqueKeysWithValues: providers.map { provider in
				(provider.id, WidgetProviderWindow(window: provider.window * scale,
					series: provider.series.map { $0 * scale }))
			})
			return (days, WidgetWindowSnapshot(days: days, totalWindow: totalWindow * scale,
				series: series.map { $0 * scale }, providerWindows: values))
		})
		return WidgetSnapshot(generatedAt: now, access: .premium, title: "All providers",
			totalToday: dollarProviders.reduce(0) { $0 + $1.today }, totalWindow: totalWindow,
			currencyCode: "USD", windowDays: 14, basis: .realAndNotionalListPrice,
			series: series, providers: providers, staleAfter: now.addingTimeInterval(30 * 60),
			errorMessage: nil, windows: windows)
	}()
}

enum WidgetValueFormatter {
  static func string(_ value: Double, metric: WidgetValueMetric, code: String) -> String {
    switch metric {
    case .percent:
      "\(Int(value.rounded()))%"
    case .dollars:
      MoneyFormatter.dollars(value, code: code)
    case .tokens:
      // [CRITICAL] Route tokens through Core's `TokenFormatter` only — never re-implement the compact
      // ladder locally. Pinned: `WidgetTokenFormatParityTests` (a local copy read `98K` where the rest
      // of the app reads `97.6K`).
      TokenFormatter.compact(value, suffix: " tok")
    }
  }
}

// MARK: - All-providers presentation policy

/// Pure layout policy for the All-providers face.
///
/// **Contract:** every contributing provider in the snapshot is always represented on Medium and Large.
/// Density adapts (full row → compact row → 2-column grid) so locked exact sizes still fit.
/// There is intentionally NO `maxRows` / silent `prefix` — that was the Copilot/Grok truncation bug.
enum WidgetAllProvidersPresentation {
	enum Family: Equatable, Sendable {
		case medium
		case large
	}

	enum Layout: Equatable, Sendable {
		/// Full-width gauge rows (name + optional limit bar + amount).
		case fullRows
		/// Full-width rows without limit bars, slightly tighter type/spacing.
		case compactRows
		/// Two-column mark + short-name + amount cells (Medium when 3+ providers).
		case twoColumnGrid
	}

	/// Medium fits two full gauge rows under the hero at 364×170; more providers switch to a 2-column
	/// grid so Grok/Copilot (and future rows) never disappear. Large keeps full rows through four
	/// providers (current ladder ceiling + Copilot), then densifies without dropping anyone.
	static func layout(family: Family, providerCount: Int) -> Layout {
		let count = max(0, providerCount)
		switch family {
		case .medium:
			return count <= 2 ? .fullRows : .twoColumnGrid
		case .large:
			if count <= 4 { return .fullRows }
			return count > 6 ? .twoColumnGrid : .compactRows
		}
	}

	/// Display set for Medium/Large All-providers. Always the full list — never truncated.
	static func providersToDisplay(
		_ providers: [WidgetProviderSnapshot]
	) -> [WidgetProviderSnapshot] {
		providers
	}

	/// Short label for dense grid cells ("Claude Code" → "Claude"); full names stay on full rows.
	/// Resolved through `ProviderCatalog` (by id, then by full name) so the widget can never disagree
	/// with the menu bar's compact label — it once clipped "Muse Spark" to "Muse".
	static func shortName(for provider: WidgetProviderSnapshot) -> String {
		if let id = ProviderID(rawValue: provider.id),
			let descriptor = ProviderCatalog.descriptor(for: id)
		{
			return descriptor.shortName
		}
		// Not in the catalog: first whitespace-separated token, else the name itself.
		if let first = provider.name.split(separator: " ").first { return String(first) }
		return provider.name
	}
}

extension WidgetSnapshot {
	var tintHex: String {
		providers.first?.tintHex ?? "#DF7A2E"
	}
}

extension Color {
	// Parsing + the malformed-input fallback live in Core's `HexColor`, shared with the app's
	// `Color(hex:)`/`NSColor(jpHex:)` so the fallback color can't drift between targets again.
	init(hex: String) {
		let c = HexColor.componentsOrFallback(hex)
		self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
	}
}
