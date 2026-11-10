import Foundation

/// One place to parse a 6-digit hex string into sRGB components and to define the
/// malformed-input fallback. The SwiftUI `Color(hex:)` and AppKit `NSColor(jpHex:)`
/// wrappers in the app, plus the widget's own `Color(hex:)`, all route through this so
/// the parse rules and the fallback color can never drift between targets again.
///
/// Core stays SwiftUI/AppKit-free on purpose (it returns hex strings and now these raw
/// components); each UI target keeps only a thin initializer around this.
public enum HexColor {
	/// The visible on-theme fallback used when a hex string is malformed — ink-soft
	/// `#6C6253`, never a silent black. This is the canonical value; do not re-type the
	/// triple at a call site.
	public static let fallback: (red: Double, green: Double, blue: Double) = (
		red: 0.424, green: 0.384, blue: 0.325
	)

	/// Parse a 6-digit hex (`#` optional) into sRGB components in `0...1`, or `nil` when the
	/// string isn't exactly six hex digits.
	public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
		let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
		let scanner = Scanner(string: cleaned)
		var rgb: UInt64 = 0
		guard cleaned.count == 6, scanner.scanHexInt64(&rgb), scanner.isAtEnd else {
			return nil
		}
		return (
			red: Double((rgb >> 16) & 0xFF) / 255,
			green: Double((rgb >> 8) & 0xFF) / 255,
			blue: Double(rgb & 0xFF) / 255
		)
	}

	/// Parse a hex string, falling back to ``fallback`` when it's malformed.
	public static func componentsOrFallback(
		_ hex: String
	) -> (red: Double, green: Double, blue: Double) {
		components(hex) ?? fallback
	}

	/// Six uppercase hex digits, no `#`, for sRGB components in `0...1`. Out-of-range channels clamp,
	/// and each channel rounds to the nearest 8-bit step.
	public static func string(_ components: (Double, Double, Double)) -> String {
		func channel(_ value: Double) -> String {
			String(format: "%02X", Int((max(0, min(1, value)) * 255).rounded()))
		}
		return channel(components.0) + channel(components.1) + channel(components.2)
	}
}
