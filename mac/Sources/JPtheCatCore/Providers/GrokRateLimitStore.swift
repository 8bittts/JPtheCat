import Foundation

/// Reads Grok Build's OFFICIAL SuperGrok / weekly credit usage, which Grok only fetches live
/// (`billing: fetched credits config` → `creditUsagePercent`) and does not expose as a stable local
/// product file. An opt-in capture (`GrokRateLimitCapture`) writes that reading to
/// `grok-rate-limits.json`; this store decodes it into the same `RateLimitSnapshot` Claude/Codex use
/// so the dashboard can show the real weekly % (never a reconstructed token estimate).
public enum GrokRateLimitStore {
	/// `~/Library/Application Support/JPtheCat/grok-rate-limits.json`.
	public static func defaultURL() -> URL? {
		guard
			let dir = try? FileManager.default.url(
				for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
		else { return nil }
		return dir.appendingPathComponent("JPtheCat", isDirectory: true)
			.appendingPathComponent("grok-rate-limits.json")
	}

	/// A capture older than this is treated as stale and ignored — better no gauge than a day-old %.
	public static let maxAgeSeconds: TimeInterval = 12 * 3600

	// `url` is injectable ONLY for tests — never touch the real Application Support path from XCTest.
	public static func load(now: Date = Date(), url: URL? = nil) -> RateLimitSnapshot? {
		guard let url = url ?? defaultURL(), let data = try? Data(contentsOf: url) else { return nil }
		return decode(data, now: now)
	}

	/// True when the opt-in capture has produced a fresh reading.
	public static func isActive(now: Date = Date(), url: URL? = nil) -> Bool {
		load(now: now, url: url) != nil
	}

	/// Deletes the captured file, if any. Call alongside `GrokRateLimitCapture.uninstall()` so a
	/// leftover reading cannot keep the Settings toggle or dashboard gauge alive after opt-out.
	@discardableResult
	public static func clear(url: URL? = nil) -> Bool {
		guard let url = url ?? defaultURL() else { return false }
		return (try? FileManager.default.removeItem(at: url)) != nil
	}

	/// Pure decoder (unit-testable). Expected JSON shape written by the capture:
	/// ```
	/// { "capturedAt": <epoch>,
	///   "weekly": { "used_percentage": 23.0, "resets_at": <epoch> },
	///   "plan_type": "X Premium+" }
	/// ```
	/// Returns nil when stale or when no weekly window is present.
	public static func decode(_ data: Data, now: Date = Date()) -> RateLimitSnapshot? {
		decodeRaw(data, now: now)?.current(at: now)
	}

	/// True when the fresh capture's window has just rolled past its reset boundary (blank gauge, but a
	/// reset just happened) — drives the "awaiting fresh data" hint. Reads pre-strip so it can see the
	/// expired window `decode` drops.
	public static func awaitingResetHint(now: Date = Date(), url: URL? = nil) -> Bool {
		guard let url = url ?? defaultURL(), let data = try? Data(contentsOf: url) else { return false }
		return decodeRaw(data, now: now)?.awaitingFreshDataAfterReset(at: now) ?? false
	}

	/// `decode` without the trailing expired-window strip, so callers can still see a just-rolled-over
	/// window. Still honors the stale-capture and no-window early-nil guards.
	static func decodeRaw(_ data: Data, now: Date = Date()) -> RateLimitSnapshot? {
		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		let capturedAtEpoch = (root["capturedAt"] as? NSNumber)?.doubleValue
		if let capturedAtEpoch, now.timeIntervalSince1970 - capturedAtEpoch > maxAgeSeconds {
			return nil
		}

		// SuperGrok weekly is the only official window today. Map it to the secondary (weekly) slot
		// so Claude/Codex consumers that already prefer 5h-primary + weekly-secondary stay consistent;
		// when primary is absent, the dashboard meter falls back to `weeklyUsedPct`.
		let weekly = RateLimitWindow(json: root["weekly"], windowMinutes: 10_080)
		guard weekly != nil else { return nil }

		let plan =
			(root["plan_type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
			?? "SuperGrok"

		return RateLimitSnapshot(
			primary: nil,
			secondary: weekly,
			planType: plan,
			capturedAt: capturedAtEpoch.map { Date(timeIntervalSince1970: $0) }
		)
	}

}
