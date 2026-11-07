import Foundation

/// RFC4180-safe CSV serialization of `ModelDaySummary` rows for the Advanced Analytics tray's export
/// button (gated on `LicenseFeature.export`). Pure and testable — the App target owns the
/// `NSSavePanel` around this, this type just produces text.
public enum AnalyticsCSVExporter {
	private static let header = [
		"date", "provider", "model", "events", "input_tokens", "output_tokens", "cache_5m_tokens",
		"cache_1h_tokens", "cache_read_tokens", "cost_usd",
	]

	/// Renders `rows` as CSV text, oldest day first (callers should already pass `modelDaySummaries`'
	/// natural sort order). `\r\n` line endings per RFC4180; every field routes through `quote(_:)` so
	/// commas/quotes/newlines in a provider or model name can never corrupt column alignment.
	public static func csv(
		rows: [ModelDaySummary],
		calendar: Calendar = .current
	) -> String {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyy-MM-dd"

		var lines: [String] = [header.map(quote).joined(separator: ",")]
		for row in rows {
			let fields: [String] = [
				formatter.string(from: row.day),
				row.provider.rawValue,
				row.model,
				String(row.eventCount),
				String(row.inputTokens),
				String(row.outputTokens),
				String(row.cache5mTokens),
				String(row.cache1hTokens),
				String(row.cacheReadTokens),
				String(format: "%.4f", row.cost),
			]
			lines.append(fields.map(quote).joined(separator: ","))
		}
		return lines.joined(separator: "\r\n")
	}

	/// A default export filename, e.g. `jpthecat-analytics-2026-07-09.csv`.
	public static func defaultFilename(now: Date = Date(), calendar: Calendar = .current) -> String {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyy-MM-dd"
		return "jpthecat-analytics-\(formatter.string(from: now)).csv"
	}

	/// RFC4180 quoting: a field is wrapped in double quotes (with internal quotes doubled) only when it
	/// contains a comma, double quote, or newline — everything else is emitted bare.
	private static func quote(_ field: String) -> String {
		guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
		else { return field }
		let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
		return "\"\(escaped)\""
	}
}
