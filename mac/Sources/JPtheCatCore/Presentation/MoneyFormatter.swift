import Foundation

/// One place that turns a dollar amount into a display string. Every user-facing figure routes
/// through here — see the money rule in `mac/AGENTS.md`.
///
/// Currency reality: every figure the app shows is **USD**. Claude cost is derived from a USD-per-token
/// pricing table (`PricingTable`) and Codex's notional figure is USD list price; the provider JSONL we
/// read carries no native-currency field, and we have no FX rates offline, so we never invent a
/// conversion. What we *do* respect is presentation: `NumberFormatter`'s `.currency` style localizes
/// grouping/decimal separators and symbol placement to the user's locale (a German user sees
/// `1.123,37 $` for the same USD amount), and the `code` parameter is threaded end-to-end so that if a
/// provider ever reports usage already denominated in a native currency we format it correctly
/// (`¥1,123` for JPY's zero-decimal rule, etc.) rather than forcing `$`.
public enum MoneyFormatter {
	/// The currency all current provider figures are denominated in. Single source of truth so a future
	/// provider that reports a native currency only has to pass a different `code`.
	public static let baseCurrencyCode = "USD"

	/// [Perf] `NumberFormatter` construction is expensive (each allocation drags in ICU state); reused
	/// instances measured ~58x faster, and the widget calls this ~14x per Large-face render.
	///
	/// [CRITICAL] The old per-call construction was justified by THREAD SAFETY, which a lock solves and
	/// re-allocation does not. `NumberFormatter` is not safe for CONCURRENT use, so the cached instances
	/// are only ever touched — construction AND `string(from:)` — while holding `lock`. Never hand a
	/// cached formatter out past the lock. The cache is bounded by construction: the key space is
	/// (style x currency code x fraction digits x locale), all of which come from a fixed set.
	///
	/// The key carries the whole `Locale`, not `locale.identifier`: a system with customized number or
	/// currency separators makes `.autoupdatingCurrent` format DIFFERENTLY from a plain
	/// `Locale(identifier:)` that shares its identifier, and an identifier-only key would hand the wrong
	/// formatter to one of them.
	private struct FormatterKey: Hashable {
		let style: Style
		let code: String
		let decimals: Int?
		let locale: Locale

		enum Style: Hashable {
			case currency
			case decimal
		}
	}

	private static let lock = NSLock()
	private nonisolated(unsafe) static var cache: [FormatterKey: NumberFormatter] = [:]

	/// Builds (or reuses) the formatter for `key` and formats `value` with it, all under `lock`.
	private static func format(_ value: Double, key: FormatterKey) -> String? {
		lock.lock()
		defer { lock.unlock() }
		let formatter: NumberFormatter
		if let cached = cache[key] {
			formatter = cached
		} else {
			formatter = makeFormatter(key)
			cache[key] = formatter
		}
		return formatter.string(from: NSNumber(value: value))
	}

	/// Byte-identical configuration to the previous per-call builders — `MoneyFormatter`'s output is
	/// test-pinned and every money figure in the app routes through it, so this must never drift.
	private static func makeFormatter(_ key: FormatterKey) -> NumberFormatter {
		let f = NumberFormatter()
		f.locale = key.locale
		switch key.style {
		case .currency:
			f.numberStyle = .currency
			f.currencyCode = key.code
			if let decimals = key.decimals {
				f.minimumFractionDigits = decimals
				f.maximumFractionDigits = decimals
			}
		case .decimal:
			f.numberStyle = .decimal
			f.usesGroupingSeparator = true
			if let decimals = key.decimals {
				f.minimumFractionDigits = decimals
				f.maximumFractionDigits = decimals
			}
		}
		return f
	}

	/// Localized currency string, e.g. `$1,123.37` (en_US / USD) or `1.123,37 $` (de_DE / USD).
	/// `decimals == nil` uses the currency's own rule (2 for USD, 0 for JPY); pass a value to override
	/// (e.g. 3 for cost-per-turn, 0 for a rounded run-rate).
	public static func currency(
		_ value: Double,
		code: String = baseCurrencyCode,
		decimals: Int? = nil,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		format(
			value,
			key: FormatterKey(style: .currency, code: code, decimals: decimals, locale: locale))
			?? String(format: "%.\(decimals ?? 2)f", value)
	}

	/// Convenience for the common USD case. Keeps `decimals` non-optional (default 2) so existing call
	/// sites read naturally; routes through `currency` for the localization + grouping.
	public static func dollars(
		_ value: Double,
		decimals: Int = 2,
		code: String = baseCurrencyCode,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		currency(value, code: code, decimals: decimals, locale: locale)
	}

	/// Grouped magnitude with no currency symbol, e.g. `1,123.37`. Used where the caller supplies its
	/// own wording (the spoken VoiceOver value, which appends the currency name).
	public static func amount(
		_ value: Double,
		decimals: Int = 2,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		format(
			value,
			key: FormatterKey(style: .decimal, code: baseCurrencyCode, decimals: decimals, locale: locale))
			?? String(format: "%.\(decimals)f", value)
	}

	/// Compact currency for tight single-line layouts (a legend row, a chip) — `$10.1K` above $1,000,
	/// `$1.2M` above $1,000,000, otherwise the normal `dollars(_:)` two-decimal form. Uppercase `K`/`M`
	/// to match `TokenFormatter.compact(_:)`'s token magnitudes, since both can appear side by side in the
	/// same row (e.g. the composition legend mixing a priced provider's dollars with Copilot's tokens).
	public static func compactDollars(
		_ value: Double,
		code: String = baseCurrencyCode,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		let magnitude = abs(value)
		let symbol = code == baseCurrencyCode ? "$" : "\(code) "
		if magnitude >= 1_000_000 { return "\(symbol)\(String(format: "%.1fM", value / 1_000_000))" }
		if magnitude >= 1_000 { return "\(symbol)\(String(format: "%.1fK", value / 1_000))" }
		return dollars(value, code: code, locale: locale)
	}
}
