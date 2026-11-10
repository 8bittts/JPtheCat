import Foundation

/// RFC4180-safe CSV serialization of `ModelDaySummary` rows for the Advanced Analytics tray's export
/// button. Pure and testable — the App target owns the `NSSavePanel` around this, this type just
/// produces text. Columns and field values come from `AnalyticsExportTable`.
public enum AnalyticsCSVExporter {
	/// Renders `rows` as CSV text, oldest day first (callers should already pass `modelDaySummaries`'
	/// natural sort order). `\r\n` line endings per RFC4180; every field routes through `quote(_:)` so
	/// commas/quotes/newlines in a provider or model name can never corrupt column alignment.
	public static func csv(
		rows: [ModelDaySummary],
		calendar: Calendar = .current
	) -> String {
		let formatter = AnalyticsExportTable.dayFormatter(calendar: calendar)
		let table = [AnalyticsExportTable.headers]
			+ rows.map { AnalyticsExportTable.cells(for: $0, dayFormatter: formatter) }
		return table.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n")
	}

	/// A default export filename, e.g. `jpthecat-analytics-2026-07-09.csv`.
	public static func defaultFilename(now: Date = Date(), calendar: Calendar = .current) -> String {
		AnalyticsExportTable.defaultFilename(fileExtension: "csv", now: now, calendar: calendar)
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
