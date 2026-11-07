import Foundation

/// Shared "resets in …" phrasing for provider windows (dashboard hero, provider detail).
public enum ProviderRelativeReset {
	/// `"2d 16h"`, `"4h 30m"`, `"12m"`; nil when the reset is absent or already elapsed.
	public static func compact(until date: Date?, now: Date = Date()) -> String? {
		guard let date, date.timeIntervalSince(now) > 0 else { return nil }
		let mins = Int(date.timeIntervalSince(now) / 60)
		if mins < 60 { return "\(max(1, mins))m" }
		let hours = mins / 60, remMins = mins % 60
		if hours < 24 { return remMins > 0 ? "\(hours)h \(remMins)m" : "\(hours)h" }
		let days = hours / 24, remHours = hours % 24
		return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
	}

	public static func resetsInPhrase(until date: Date?, now: Date = Date()) -> String? {
		compact(until: date, now: now).map { "resets in \($0)" }
	}
}
