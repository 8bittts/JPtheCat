import Foundation

/// The Advanced Analytics calendar-heatmap color ramp — a SINGLE-HUE, luminance-monotonic scale.
///
/// [Load-bearing] The obvious choice (a `honey → ginger → gingerDeep` multi-stop palette ramp) COLLAPSES
/// on most shipped themes: `ginger` and `gingerDeep` are identical hex on 15 of the 24 themes, and on
/// Midnight/Ember `gingerDeep` is actually LIGHTER than `ginger`, so hot and cold cells would look
/// identical or backwards for most users. Instead every cell is the theme accent painted over the
/// theme's `track` groove at an alpha proportional to the cell's intensity — ONE hue varying only in
/// lightness/alpha, so the resolved color is monotonic in relative luminance on EVERY theme regardless
/// of that theme's accent hue. (The `track` role is always the darkest color on the dark themes and the
/// lightest on the one light theme, so the `track → accent` segment moves every channel in the same
/// direction, which is exactly what keeps the composite luminance monotonic.) This is the same
/// `track + accent-fill` idiom `SelectorRow`'s meter uses, applied per-cell.
///
/// Pure (hex in, hex out) so it lives in Core with no SwiftUI/AppKit dependency; the `HeatmapGrid` view
/// wraps the result in `Color(hex:)`. Guarded by `HeatmapRampTests`, which proves the resolved cell
/// colors are strictly luminance-monotonic across all 16 shipped themes — exactly the automated gate
/// that would have caught the collapsed-ramp defect.
public enum HeatmapRamp {
	/// Opaque composited cell color for intensity `t` (clamped to 0…1). `t == 0` returns the bare `track`
	/// groove (so an empty / no-activity day reads as "no data", never "low data"); higher `t` composites
	/// `accent` over the track at alpha `t * maxAlpha`. `maxAlpha` is the `barFillOpacity` convention
	/// (~0.55 light / ~0.9 dark). Returns a 6-digit uppercase hex WITHOUT a leading `#` (callers wrap in
	/// `Color(hex:)`, which accepts either form).
	public static func cellHex(
		t: Double,
		accentHex: String,
		trackHex: String,
		maxAlpha: Double
	) -> String {
		hexString(cellComponents(t: t, accentHex: accentHex, trackHex: trackHex, maxAlpha: maxAlpha))
	}

	/// The same composited cell color as ``cellHex(t:accentHex:trackHex:maxAlpha:)``, handed back as sRGB
	/// components in `0...1` so a UI target can build its color WITHOUT the hex round-trip.
	///
	/// [NOTE] The returned components are QUANTIZED to 8 bits per channel — exactly what
	/// `Color(hex: cellHex(...))` produces after `%02X` serialization and re-parsing — so switching a call
	/// site from the hex path to this one is pixel-identical, not merely close. `cellHex` is now a thin
	/// wrapper over this, so the two can never drift.
	///
	/// Why it exists: a 90-day Model × Day grid is 630 cells, and the hex path cost each one three
	/// `String(format: "%02X")` calls plus a third hex parse inside `Color(hex:)` — all inside a
	/// `GeometryReader`, so it repeated on every resize frame.
	public static func cellComponents(
		t: Double,
		accentHex: String,
		trackHex: String,
		maxAlpha: Double
	) -> (Double, Double, Double) {
		let clampedT = min(max(t, 0), 1)
		let alpha = clampedT * max(0, min(1, maxAlpha))
		let track = rgb(trackHex)
		let accent = rgb(accentHex)
		// A straight segment in sRGB from `track` (t=0) toward `accent`, only as far as `maxAlpha`. Because
		// every channel moves monotonically in the same direction on every theme, the composite luminance
		// is monotonic in `t` (see the type doc + `HeatmapRampTests`).
		let mixed = (
			track.0 + (accent.0 - track.0) * alpha,
			track.1 + (accent.1 - track.1) * alpha,
			track.2 + (accent.2 - track.2) * alpha)
		return (quantized(mixed.0), quantized(mixed.1), quantized(mixed.2))
	}

	// MARK: pure helpers

	/// Snap a channel to the 8-bit grid the hex form rounds to, so `hexString(cellComponents(...))` is
	/// byte-for-byte the old `cellHex` output and a component-built color matches the hex-built one.
	private static func quantized(_ x: Double) -> Double {
		(max(0, min(1, x)) * 255).rounded() / 255
	}

	private static func rgb(_ hex: String) -> (Double, Double, Double) {
		let components = HexColor.componentsOrFallback(hex)
		return (components.red, components.green, components.blue)
	}

	private static func hexString(_ c: (Double, Double, Double)) -> String {
		func h(_ x: Double) -> String { String(format: "%02X", Int((max(0, min(1, x)) * 255).rounded())) }
		return h(c.0) + h(c.1) + h(c.2)
	}
}
