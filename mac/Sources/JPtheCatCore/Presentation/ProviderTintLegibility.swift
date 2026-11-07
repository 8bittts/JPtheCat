import Foundation

/// WCAG legibility lift for per-provider brand tints, shared by the app dashboard (`JPAppColor
/// .providerTint`) and the widget extension so both answer "is this tint readable on the active card?"
/// with identical math.
///
/// Brand tints are chosen for the light card and can disappear on a dark card (Codex charcoal
/// `#2F2F33` reads ~1.1:1 on the midnight card). This returns the SAME tint when it already clears the
/// WCAG graphical-object floor (so terracotta / ginger pass through UNCHANGED on both themes) and
/// otherwise lifts it toward the theme ink until it reads. Codex is a curated special case: even lifted
/// to the floor it stays a neutral gray that blends into the gray meter track, so on a dark card it
/// gets a bright neutral that reads on both the card and the track.
///
/// Pure (hex in, hex out) so it lives in Core with no SwiftUI/AppKit dependency; call sites wrap the
/// result in their own `Color(hex:)`. The icon CHIP must keep the RAW brand tint (a white glyph sits on
/// it); only data-viz (dot, meter fill, sparkline) goes through this lift.
public enum ProviderTintLegibility {
	/// Codex brand charcoal — the one shipped tint dark enough to need a curated dark-mode neutral.
	public static let codexTintHex = "#2F2F33"
	/// The curated bright neutral Codex resolves to on a dark card (reads on card AND meter track).
	private static let codexDarkLift = "A6A6A8"

	/// A brand tint hex made legible on `backgroundHex`. Returns a 6-digit uppercase hex WITHOUT a
	/// leading `#` (callers wrap in `Color(hex:)`, which accepts either form).
	/// - Parameters:
	///   - tintHex: the brand tint (with or without `#`).
	///   - backgroundHex: the card/background the tint is drawn on.
	///   - inkHex: the theme ink the tint is lifted toward when it is too low-contrast.
	///   - isDark: whether the active theme is dark (drives the Codex special case).
	///   - minContrast: WCAG floor; default 2.9 sits just under brand ginger (2.97:1) so the shipped
	///     brand tints pass through unchanged while genuinely-too-dark tints get lifted.
	public static func legibleHex(
		tintHex: String,
		backgroundHex: String,
		inkHex: String,
		isDark: Bool,
		minContrast: Double = 2.9
	) -> String {
		if isDark, tintHex.caseInsensitiveCompare(codexTintHex) == .orderedSame { return codexDarkLift }
		let bg = rgb(backgroundHex)
		let brand = rgb(tintHex)
		if contrast(brand, bg) >= minContrast { return normalized(tintHex) }
		let ink = rgb(inkHex)  // light on a dark theme, dark on a light theme
		var mixT = 0.15
		while mixT < 1 {
			let lifted = mix(brand, ink, mixT)
			if contrast(lifted, bg) >= minContrast { return hexString(lifted) }
			mixT += 0.1
		}
		return normalized(inkHex)
	}

	// MARK: WCAG helpers (pure)

	private static func normalized(_ hex: String) -> String {
		(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).uppercased()
	}
	private static func rgb(_ hex: String) -> (Double, Double, Double) {
		let components = HexColor.componentsOrFallback(hex)
		return (components.red, components.green, components.blue)
	}
	private static func hexString(_ c: (Double, Double, Double)) -> String {
		func h(_ x: Double) -> String { String(format: "%02X", Int((max(0, min(1, x)) * 255).rounded())) }
		return h(c.0) + h(c.1) + h(c.2)
	}
	private static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double)
		-> (Double, Double, Double)
	{ (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
	private static func luminance(_ c: (Double, Double, Double)) -> Double {
		func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
		return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
	}
	private static func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
		let la = luminance(a), lb = luminance(b)
		return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
	}
}
