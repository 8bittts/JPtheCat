import Foundation

/// Shared, pure parsing helpers for provider log decoding. Every provider decodes tolerant,
/// loosely-typed JSON/JSONL (`JSONSerialization` + `[String: Any]`, never strict `Codable` — see
/// each provider's own doc comment for why), and every one of them independently needs the SAME two
/// primitives: an ISO-8601-with-or-without-fractional-seconds timestamp parse, and a tolerant
/// "whatever numeric type this happens to be, give me an Int" read. This file is the ONE place those
/// live; a new provider should reach for these rather than re-declaring its own copy — four
/// providers (Claude/Codex/Gemini/OpenCode) had done exactly that independently before this file
/// existed, byte-for-byte identical in three of the four cases.
public enum ISOTimestamp {
	/// Most provider logs carry fractional seconds (`2026-07-08T12:00:00.123Z`); this is the
	/// PRIMARY formatter — try it first.
	nonisolated(unsafe) public static let fractional: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()
	/// Fallback for the rarer plain-seconds form (`2026-07-08T12:00:00Z`).
	nonisolated(unsafe) public static let plain: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime]
		return f
	}()

	/// Parses `string` as fractional-seconds ISO-8601, falling back to plain-seconds, falling back
	/// to `fallback` (default `.distantPast`, so a malformed/missing timestamp sorts oldest rather
	/// than crashing or silently dropping the event).
	public static func parse(_ string: String?, fallback: Date = .distantPast) -> Date {
		guard let string else { return fallback }
		return fractional.date(from: string) ?? plain.date(from: string) ?? fallback
	}
}

public enum JSONNumber {
	public static func int(fromString string: String?) -> Int {
		guard let string, let value = Double(string) else { return 0 }
		return max(0, Int(value))
	}

	/// Tolerant integer read from a `JSONSerialization`-decoded value: accepts `Int`, `Double`, or
	/// numeric `NSNumber` (JSON has no distinct integer/float wire type, so a token count can arrive
	/// as any of these depending on the source); anything else (nil, a string, a bool) -> 0. Never
	/// throws — a single odd field must not drop an otherwise-valid usage event.
	public static func int(_ any: Any?) -> Int {
		switch any {
		case let value as Int: return value
		case let value as Double: return Int(value)
		case let value as NSNumber: return value.intValue
		default: return 0
		}
	}

	/// Tolerant OPTIONAL double read from a `JSONSerialization`-decoded value: accepts `Int`, `Double`,
	/// or numeric `NSNumber`; anything else (nil, a string, a bool) -> `nil`. Unlike ``int(_:)`` this
	/// returns `nil` rather than a `0` default, because callers (e.g. an official rate-limit
	/// `used_percent`) must distinguish "absent/malformed" from a real `0`.
	public static func double(_ any: Any?) -> Double? {
		switch any {
		case let value as Double: return value
		case let value as Int: return Double(value)
		case let value as NSNumber: return value.doubleValue
		default: return nil
		}
	}
}

public enum ProviderModelNormalization {
	/// Parse-time vendor-prefix strip through `ModelIdentity.withoutVendorPrefix`, so a parser and a
	/// price lookup can never disagree about where the model name starts.
	public static func strippingVendorPrefix(_ raw: String?, fallback: String) -> String {
		guard let raw, !raw.isEmpty else { return fallback }
		return ModelIdentity.withoutVendorPrefix(raw)
	}
}
