import Foundation

/// One place that turns a raw token count into a compact display string — `53.6K`, `1.2M`, or the
/// bare number below 1,000. Used wherever a fully-unpriced provider (`ProviderRow.isFullyUnpriced`,
/// Copilot/Cursor) shows tokens in place of a dead `$0.00`, and by the menu-bar tooltip and the
/// widget faces for the same figures.
///
/// [CRITICAL] This exists because the ladder shipped THREE times — the dashboard's
/// `formatTokenCount`, `MenuBarLabelRenderer.compactTokenCount`, and the widget's `compactTokens` —
/// and the widget's copy used `%.0fK`, so 97,600 Copilot tokens read `97.6K` on the dashboard and in
/// the menu-bar pill but `98K tok` on the Medium widget grid cell. Mac surfaces are kept 1:1, so
/// every surface now routes through here; never re-implement the ladder locally.
/// Guards: `TokenFormatterTests` (Core), `TokenFormatterParityTests` (app), `WidgetTokenFormatParityTests`.
///
/// `suffix` is appended verbatim (the widget appends `" tok"` because its cells carry no other unit
/// context); it never changes the magnitude ladder itself.
/// Uppercase `K`/`M` matches `MoneyFormatter.compactDollars`, since a token figure and a dollar
/// figure can sit side by side in the same row.
public enum TokenFormatter {
	/// Compact form of an exact token count.
	public static func compact(_ value: Int, suffix: String = "") -> String {
		let magnitude = abs(value)
		if magnitude >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) + suffix }
		if magnitude >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) + suffix }
		return "\(value)" + suffix
	}

	/// Compact form for callers whose token total already arrived as a `Double` (the widget snapshot
	/// stores every metric as one `Double` series regardless of unit). Byte-identical to the `Int`
	/// overload for whole values; below 1,000 the value rounds to a whole token, and the rounding
	/// happens ONLY in that branch so a large magnitude can never trap converting to `Int`.
	public static func compact(_ value: Double, suffix: String = "") -> String {
		let magnitude = abs(value)
		if magnitude >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) + suffix }
		if magnitude >= 1_000 { return String(format: "%.1fK", value / 1_000) + suffix }
		return "\(Int(value.rounded()))" + suffix
	}
}
