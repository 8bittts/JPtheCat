import Foundation

/// GitHub-flavored Markdown table serialization of `ModelDaySummary` rows for the Advanced Analytics
/// export. Pure and testable — the App target owns the `NSSavePanel`;
/// this type just produces text. Same columns/field values as `AnalyticsCSVExporter`, formatted as a
/// pasteable table (numeric columns right-aligned; `cost_usd` at the CSV's `%.4f` precision).
public enum AnalyticsMarkdownExporter {
	private static let headers = [
		"date", "provider", "model", "events", "input_tokens", "output_tokens", "cache_5m_tokens",
		"cache_1h_tokens", "cache_read_tokens", "cost_usd",
	]
	// Left-align text columns, right-align the numeric ones (index ≥ 3), matching the header order.
	private static let alignments = [":--", ":--", ":--", "--:", "--:", "--:", "--:", "--:", "--:", "--:"]

	/// Renders `rows` as one Markdown table, oldest day first (callers already pass `modelDaySummaries`'
	/// natural order). Cell values route through `escape(_:)` so a `|` or newline in a provider/model
	/// name can never break the table. Returns just the header + separator when `rows` is empty.
	public static func markdown(
		rows: [ModelDaySummary],
		calendar: Calendar = .current
	) -> String {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyy-MM-dd"

		var lines = [
			"| \(headers.joined(separator: " | ")) |",
			"| \(alignments.joined(separator: " | ")) |",
		]
		for row in rows {
			let cells: [String] = [
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
			lines.append("| \(cells.map(escape).joined(separator: " | ")) |")
		}
		return lines.joined(separator: "\n")
	}

	/// A default export filename, e.g. `jpthecat-analytics-2026-07-09.md`.
	public static func defaultFilename(now: Date = Date(), calendar: Calendar = .current) -> String {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyy-MM-dd"
		return "jpthecat-analytics-\(formatter.string(from: now)).md"
	}

	/// Escapes a table cell: `|` would start a new column and a newline would break the row, so both are
	/// neutralized (`\|` renders as a literal pipe; a hard line break becomes a space).
	private static func escape(_ field: String) -> String {
		field
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "|", with: "\\|")
			.replacingOccurrences(of: "\r\n", with: " ")
			.replacingOccurrences(of: "\n", with: " ")
			.replacingOccurrences(of: "\r", with: " ")
	}
}
