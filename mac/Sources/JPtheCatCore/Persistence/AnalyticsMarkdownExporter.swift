import Foundation

/// GitHub-flavored Markdown table serialization of `ModelDaySummary` rows for the Advanced Analytics
/// export. Pure and testable — the App target owns the `NSSavePanel`;
/// this type just produces text. Same columns/field values as `AnalyticsCSVExporter`, formatted as a
/// pasteable table (numeric columns right-aligned; `cost_usd` at the CSV's `%.4f` precision).
public enum AnalyticsMarkdownExporter {
	// Left-align text columns, right-align the numeric ones (index ≥ 3), matching the header order.
	private static let alignments = [":--", ":--", ":--", "--:", "--:", "--:", "--:", "--:", "--:", "--:"]

	/// Renders `rows` as one Markdown table, oldest day first (callers already pass `modelDaySummaries`'
	/// natural order). Cell values route through `escape(_:)` so a `|` or newline in a provider/model
	/// name can never break the table. Returns just the header + separator when `rows` is empty.
	public static func markdown(
		rows: [ModelDaySummary],
		calendar: Calendar = .current
	) -> String {
		let formatter = AnalyticsExportTable.dayFormatter(calendar: calendar)
		let body = rows.map { AnalyticsExportTable.cells(for: $0, dayFormatter: formatter).map(escape) }
		return ([AnalyticsExportTable.headers, alignments] + body)
			.map { "| \($0.joined(separator: " | ")) |" }
			.joined(separator: "\n")
	}

	/// A default export filename, e.g. `jpthecat-analytics-2026-07-09.md`.
	public static func defaultFilename(now: Date = Date(), calendar: Calendar = .current) -> String {
		AnalyticsExportTable.defaultFilename(fileExtension: "md", now: now, calendar: calendar)
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
