import XCTest

@testable import JPtheCatApp
import JPtheCatCore

/// Guards the Advanced Analytics heatmap ramp: for a rising sequence of intensities the resolved cell
/// colors' relative luminance MUST be strictly ordered (monotonic in one direction) on every one of the
/// 16 shipped themes. This is exactly the automated gate that catches a collapsed / inverted ramp — the
/// `honey → ginger → gingerDeep` palette ramp that motivated `HeatmapRamp` collapsed on 11 themes and
/// inverted on Midnight/Ember. Mirrors the structure of `ThemeTests.testEveryThemeMeetsContrastFloors()`.
final class HeatmapRampTests: XCTestCase {

	private let intensities: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

	func testRampIsLuminanceMonotonicAcrossEveryTheme() {
		for theme in JPTheme.all {
			// Same inputs the `HeatmapGrid` view feeds the ramp: the theme accent (aggregate ginger) over
			// the theme track groove, at the `barFillOpacity` convention (~0.55 light / ~0.9 dark).
			let maxAlpha = theme.isDark ? 0.9 : 0.55
			assertMonotonic(theme: theme, accentHex: theme.ginger, accentName: "aggregate ginger", maxAlpha: maxAlpha)

			// And an empty cell (t == 0) must be exactly the bare track groove, so "no data" never reads
			// as "low data".
			XCTAssertEqual(
				HeatmapRamp.cellHex(t: 0, accentHex: theme.ginger, trackHex: theme.track, maxAlpha: maxAlpha),
				theme.track.uppercased(),
				"\(theme.name): an empty heatmap cell must be the bare track color")
		}
	}

	/// Focus mode reheats the heatmap ramp `accent` from the aggregate ginger to the FOCUSED provider's
	/// LEGIBLE tint (`ProviderTintLegibility.legibleHex(...)`, the same value `JPAppColor.providerTint`
	/// renders). The ramp's monotonicity guarantee is per-accent, so it must be re-proven for each
	/// provider tint on EVERY theme — otherwise a focus-mode ramp could read hot-for-cold on some theme.
	func testRampIsLuminanceMonotonicForEveryProviderTintAccent() {
		let providerTints: [(name: String, hex: String)] = [
			("Claude", JPAppColor.claudeTintHex),
			("Codex", JPAppColor.codexTintHex),
			("Copilot", JPAppColor.copilotTintHex),
		]
		for theme in JPTheme.all {
			let maxAlpha = theme.isDark ? 0.9 : 0.55
			for tint in providerTints {
				let accent = ProviderTintLegibility.legibleHex(
					tintHex: tint.hex, backgroundHex: theme.card, inkHex: theme.ink, isDark: theme.isDark)
				assertMonotonic(
					theme: theme, accentHex: accent, accentName: "\(tint.name) tint", maxAlpha: maxAlpha)
			}
		}
	}

	/// The heatmap cells now build their `Color` from `cellComponents` instead of parsing `cellHex` back —
	/// a pure perf change that is only safe while the two paths resolve to the SAME 8-bit color. This pins
	/// that: `cellComponents` must be exactly what `cellHex` serializes, on every theme, accent and `t`
	/// (including the out-of-range clamps), so a future edit to one path cannot silently re-tint the grid.
	func testCellComponentsAreTheExactColorCellHexSerializes() {
		for theme in JPTheme.all {
			let maxAlpha = theme.isDark ? 0.9 : 0.55
			for t in [-0.5, 0.0, 0.18, 0.25, 0.5, 0.75, 1.0, 1.5] {
				let components = HeatmapRamp.cellComponents(
					t: t, accentHex: theme.ginger, trackHex: theme.track, maxAlpha: maxAlpha)
				let hex = HeatmapRamp.cellHex(
					t: t, accentHex: theme.ginger, trackHex: theme.track, maxAlpha: maxAlpha)
				let parsed = rgb(hex)
				XCTAssertEqual(components.0, parsed.0, accuracy: 1e-12, "\(theme.name) t=\(t) red")
				XCTAssertEqual(components.1, parsed.1, accuracy: 1e-12, "\(theme.name) t=\(t) green")
				XCTAssertEqual(components.2, parsed.2, accuracy: 1e-12, "\(theme.name) t=\(t) blue")
			}
		}
	}

	/// Asserts the resolved cell luminances are strictly monotonic (one direction) for a rising `t`
	/// (increasing on dark themes where track < accent, decreasing on the one light theme where the
	/// cream track is lighter than the accent).
	private func assertMonotonic(theme: JPTheme, accentHex: String, accentName: String, maxAlpha: Double) {
		let luminances = intensities.map { t -> Double in
			relativeLuminance(
				HeatmapRamp.cellHex(t: t, accentHex: accentHex, trackHex: theme.track, maxAlpha: maxAlpha))
		}
		let increasing = zip(luminances, luminances.dropFirst()).allSatisfy { $0 < $1 }
		let decreasing = zip(luminances, luminances.dropFirst()).allSatisfy { $0 > $1 }
		XCTAssertTrue(
			increasing || decreasing,
			"\(theme.name) · \(accentName): heatmap ramp is not strictly luminance-monotonic — "
				+ "\(luminances.map { String(format: "%.4f", $0) }.joined(separator: " → "))")
	}

	// MARK: WCAG 2.1 relative-luminance helpers (same math as `ThemeTests`)

	private func relativeLuminance(_ hex: String) -> Double {
		let c = rgb(hex)
		func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
		return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
	}

	private func rgb(_ hex: String) -> (Double, Double, Double) {
		let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
		var value: UInt64 = 0
		Scanner(string: cleaned).scanHexInt64(&value)
		return (
			Double((value >> 16) & 0xFF) / 255,
			Double((value >> 8) & 0xFF) / 255,
			Double(value & 0xFF) / 255)
	}
}
