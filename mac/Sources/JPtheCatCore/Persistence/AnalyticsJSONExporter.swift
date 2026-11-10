import Foundation

/// JSON serialization of `ModelDaySummary` rows for the Advanced Analytics export. Pure and
/// testable — the App target owns the `NSSavePanel`; this type just produces text. Mirrors `AnalyticsCSVExporter`'s columns/field names exactly (so a spreadsheet, a
/// `jq` pipeline, and the CSV all describe the same rows), emitting a pretty-printed array of objects.
public enum AnalyticsJSONExporter {
	private struct Row: Encodable {
		let date: String
		let provider: String
		let model: String
		let events: Int
		let input_tokens: Int
		let output_tokens: Int
		let cache_5m_tokens: Int
		let cache_1h_tokens: Int
		let cache_read_tokens: Int
		let cost_usd: Double
	}

	/// Renders `rows` as a pretty-printed JSON array, oldest day first (callers already pass
	/// `modelDaySummaries`' natural order). Keys are sorted for deterministic, diff-friendly output;
	/// `cost_usd` is a real JSON number rounded to 4 decimals to match the CSV's `%.4f` precision.
	public static func json(
		rows: [ModelDaySummary],
		calendar: Calendar = .current
	) -> String {
		let formatter = AnalyticsExportTable.dayFormatter(calendar: calendar)
		let dtos = rows.map { row in
			Row(
				date: formatter.string(from: row.day),
				provider: row.provider.rawValue,
				model: row.model,
				events: row.eventCount,
				input_tokens: row.inputTokens,
				output_tokens: row.outputTokens,
				cache_5m_tokens: row.cache5mTokens,
				cache_1h_tokens: row.cache1hTokens,
				cache_read_tokens: row.cacheReadTokens,
				cost_usd: (row.cost * 10000).rounded() / 10000)
		}

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		guard let data = try? encoder.encode(dtos), let text = String(data: data, encoding: .utf8) else {
			return "[]"
		}
		return text
	}

	/// A default export filename, e.g. `jpthecat-analytics-2026-07-09.json`.
	public static func defaultFilename(now: Date = Date(), calendar: Calendar = .current) -> String {
		AnalyticsExportTable.defaultFilename(fileExtension: "json", now: now, calendar: calendar)
	}
}
