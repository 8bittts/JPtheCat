import Foundation

/// The column contract the Advanced Analytics exporters share: one header list, one day format, one
/// text rendering of a row, and one filename stem. CSV, Markdown, and JSON each add only their own
/// quoting, so the three formats cannot describe different rows.
enum AnalyticsExportTable {
	static let headers = [
		"date", "provider", "model", "events", "input_tokens", "output_tokens", "cache_5m_tokens",
		"cache_1h_tokens", "cache_read_tokens", "cost_usd",
	]

	/// `yyyy-MM-dd` in the caller's calendar and timezone, so a row's day matches the dashboard's.
	static func dayFormatter(calendar: Calendar) -> DateFormatter {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}

	/// One row as unquoted text cells, in `headers` order; `cost_usd` carries four decimals.
	static func cells(for row: ModelDaySummary, dayFormatter: DateFormatter) -> [String] {
		[
			dayFormatter.string(from: row.day),
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
	}

	/// A default export filename, e.g. `jpthecat-analytics-2026-07-09.csv`.
	static func defaultFilename(fileExtension: String, now: Date, calendar: Calendar) -> String {
		"jpthecat-analytics-\(dayFormatter(calendar: calendar).string(from: now)).\(fileExtension)"
	}
}
