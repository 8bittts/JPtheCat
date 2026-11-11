import Foundation

/// Reads Claude Code's OFFICIAL rate-limit windows, which Claude only exposes through its statusline
/// feed (`rate_limits.{five_hour,seven_day}.{used_percentage, resets_at}`) and does NOT persist on
/// its own. An opt-in capture appended to the user's statusline writes that object to
/// `claude-rate-limits.json`; this store decodes it into the same `RateLimitSnapshot` Codex uses, so
/// the dashboard can show Claude's true session/weekly % (never a reconstructed estimate).
public enum ClaudeRateLimitStore {
	/// `~/Library/Application Support/JPtheCat/claude-rate-limits.json`.
	public static func defaultURL() -> URL? {
		guard
			let dir = try? FileManager.default.url(
				for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
		else { return nil }
		return dir.appendingPathComponent("JPtheCat", isDirectory: true)
			.appendingPathComponent("claude-rate-limits.json")
	}

	/// Freshness threshold for the opt-in **indicator only** — see `isActive`. It must NEVER hide a
	/// window: a still-current weekly reading stays on screen however old it is (its own `resets_at`
	/// is the only gate). v1.113 aged Codex readings out by capture age and the row collapsed to an
	/// activity sparkline, losing a valid reset countdown; v1.114 reverted that for Codex. The Claude
	/// path kept the same cutoff and re-introduced the bug for Claude's weekly window.
	public static let maxAgeSeconds: TimeInterval = 12 * 3600

	// `url` is injectable ONLY for tests (defaults to `defaultURL()`, the real production path) —
	// `load`/`isActive`/`clear` must never touch the real `~/Library/Application Support/JPtheCat/
	// claude-rate-limits.json` from a test. An earlier version of the `clear()` regression tests did
	// exactly that (no override, hardcoded `defaultURL()`), and running the full suite on a real
	// developer machine silently deleted that machine's genuine leftover capture file as a side effect
	// — caught only by noticing the file had vanished after a test run. Tests must always pass an
	// explicit temp `url:` from here on.
	public static func load(now: Date = Date(), url: URL? = nil) -> RateLimitSnapshot? {
		guard let url = url ?? defaultURL(), let data = try? Data(contentsOf: url) else { return nil }
		return decode(data, now: now)
	}

	/// True when the opt-in statusline capture is present AND fresh — i.e. Claude live limits are
	/// actually flowing. Drives the Settings status row so the user knows whether setup worked.
	///
	/// Deliberately NOT `load(...) != nil`: `load` now returns a still-current window from an old
	/// capture (correct for the gauge) which would leave this indicator "on" forever after the
	/// statusline stopped running. Freshness and "is this window still current" are separate questions.
	public static func isActive(now: Date = Date(), url: URL? = nil) -> Bool {
		guard let url = url ?? defaultURL(), let data = try? Data(contentsOf: url) else { return false }
		guard let capturedAt = capturedAtEpoch(in: data),
			now.timeIntervalSince1970 - capturedAt <= maxAgeSeconds
		else { return false }
		return decode(data, now: now) != nil
	}

	/// The capture's own unix-epoch `capturedAt`, if the payload carries one.
	static func capturedAtEpoch(in data: Data) -> Double? {
		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return nil
		}
		return (root["capturedAt"] as? NSNumber)?.doubleValue
	}

	/// Deletes the captured file, if any. Call this alongside `StatuslineCapture.uninstall()` — the
	/// capture file otherwise survives an uninstall and stays "fresh" for up to `maxAgeSeconds`, so
	/// `isActive()` kept reporting true and the Settings toggle sprang back "on" right after the user
	/// turned it off (the Claude live-limits row's `isInstalled` was `active || state == .active`, and
	/// uninstalling only ever cleared `state`, never `active`'s underlying file; that row is now one of
	/// the four `ProviderOptInDescriptor`s driving `ProviderOptInRow`, whose `isInstalled` reads the
	/// install marker ALONE). Best-effort: a missing file is not an error.
	@discardableResult
	public static func clear(url: URL? = nil) -> Bool {
		guard let url = url ?? defaultURL() else { return false }
		return (try? FileManager.default.removeItem(at: url)) != nil
	}

	/// Pure decoder (unit-testable): the captured JSON is
	/// `{capturedAt, five_hour:{used_percentage,resets_at}, seven_day:{used_percentage,resets_at}}`.
	/// `resets_at` is unix epoch seconds. Returns nil when neither window is present — or when every
	/// window has already passed its own `resets_at`. The capture's AGE never nils it.
	public static func decode(_ data: Data, now: Date = Date()) -> RateLimitSnapshot? {
		decodeRaw(data)?.current(at: now)
	}

	/// True when the fresh capture's 5-hour/weekly window has just rolled past its reset boundary — blank
	/// gauge, but a reset just happened — so the dashboard can show an "awaiting fresh data" hint rather
	/// than the gauge vanishing. Reads pre-strip so it can see the expired window `decode` drops.
	public static func awaitingResetHint(now: Date = Date(), url: URL? = nil) -> Bool {
		guard let url = url ?? defaultURL(), let data = try? Data(contentsOf: url) else { return false }
		return decodeRaw(data)?.awaitingFreshDataAfterReset(at: now) ?? false
	}

	/// `decode` without the trailing expired-window strip, so callers can still see a just-rolled-over
	/// window.
	///
	/// [DURABLE] There is deliberately NO capture-age cutoff here. A window is hidden ONLY by its own
	/// `resets_at` (via `current(at:)`), never by how long ago the statusline last ran: Claude refreshes
	/// the statusline only when it answers, so an idle night leaves a reading hours old while its 7-day
	/// boundary is still ahead. `capturedAt` is diagnostics (the frozen-high limit warning) and the
	/// `isActive` freshness indicator — never a display gate.
	static func decodeRaw(_ data: Data) -> RateLimitSnapshot? {
		guard
			let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		let capturedAtEpoch = (root["capturedAt"] as? NSNumber)?.doubleValue

		let primary = RateLimitWindow(json: root["five_hour"], windowMinutes: 300)
		let secondary = RateLimitWindow(json: root["seven_day"], windowMinutes: 10080)
		guard primary != nil || secondary != nil else { return nil }
		let modelWindows = modelScopedWindows(in: root)
		// Carry the capture time so the UI can tell a fresh reading from one frozen by a limit hit
		// (Claude only refreshes the statusline when it answers).
		// `planType` stays nil: the captured statusline JSON carries `rate_limits` but no tier, and
		// Claude emits those windows for Pro as well as Max — so a hardcoded "max" mislabeled every
		// Pro subscriber in `LocalAutomationSnapshot.plan_type` and the CLI's JSON. Never fabricate a
		// tier; the only honest local source was another app's Keychain item and reading it prompts
		// for the login password.
		return RateLimitSnapshot(
			primary: primary, secondary: secondary, planType: nil,
			capturedAt: capturedAtEpoch.map { Date(timeIntervalSince1970: $0) },
			modelWindows: modelWindows)
	}

	/// Per-model weekly windows beside the all-models `seven_day` bar.
	///
	/// Claude Code 2.1.322 sends them as `model_scoped`: an array of
	/// `{display_name, utilization, resets_at}`. `display_name` is the label Claude shows
	/// ("Fable"). `utilization` is already a 0–100 percent — the same scale as `used_percentage` —
	/// not the fractional utilization the statusline scales into `five_hour` / `seven_day`.
	/// `resets_at` is ISO-8601. An empty array means the endpoint answered and listed none. An absent
	/// key means the feed did not report one. Either is "not reported", never 0%.
	///
	/// Legacy `seven_day_*` objects (`seven_day_opus`, `seven_day_sonnet`) still decode. A legacy key
	/// whose label matches a `model_scoped` row is dropped so one model is not drawn twice. `seven_day`
	/// itself stays the plan-wide window (`secondary`), never a model row.
	static func modelScopedWindows(in root: [String: Any]) -> [ModelScopedRateLimitWindow] {
		let named = namedModelWindows(in: root)
		let namedLabels = Set(named.map { $0.label.lowercased() })
		let legacy = root.keys
			.filter { $0.hasPrefix("seven_day_") }
			.sorted()
			.compactMap { key -> ModelScopedRateLimitWindow? in
				guard let window = RateLimitWindow(json: root[key], windowMinutes: 10080) else { return nil }
				let scoped = ModelScopedRateLimitWindow(key: key, window: window)
				guard !namedLabels.contains(scoped.label.lowercased()) else { return nil }
				return scoped
			}
		return named + legacy
	}

	/// Server order. A repeated `display_name` keeps the first row.
	private static func namedModelWindows(in root: [String: Any]) -> [ModelScopedRateLimitWindow] {
		guard let rows = root["model_scoped"] as? [Any] else { return [] }
		var seen = Set<String>()
		var windows: [ModelScopedRateLimitWindow] = []
		for row in rows {
			guard let window = modelScopedWindow(from: row) else { continue }
			guard seen.insert(window.label.lowercased()).inserted else { continue }
			windows.append(window)
		}
		return windows
	}

	/// One `model_scoped` element. A missing name or a non-numeric utilization is skipped, never
	/// turned into a zero-percent bar.
	private static func modelScopedWindow(from raw: Any) -> ModelScopedRateLimitWindow? {
		guard let object = raw as? [String: Any] else { return nil }
		let rawName = (object["display_name"] as? String) ?? (object["displayName"] as? String)
		guard let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
			return nil
		}
		guard let used = JSONNumber.double(object["utilization"]) ?? JSONNumber.double(object["used_percentage"])
		else { return nil }
		let window = RateLimitWindow(
			usedPercent: min(100, max(0, used)), windowMinutes: 10080, resetsAt: resetDate(object["resets_at"]))
		return ModelScopedRateLimitWindow(key: "model_scoped:\(name)", window: window, displayName: name)
	}

	/// `model_scoped.resets_at` is ISO-8601. Legacy `seven_day_*` windows still use epoch seconds,
	/// and `RateLimitWindow.init(json:)` handles those. A missing or unreadable reset stays nil, which
	/// leaves the percentage on screen rather than inventing an expiry.
	private static func resetDate(_ raw: Any?) -> Date? {
		if let epoch = JSONNumber.double(raw) { return Date(timeIntervalSince1970: epoch) }
		guard let string = raw as? String else { return nil }
		if let date = ISOTimestamp.fractional.date(from: string) ?? ISOTimestamp.plain.date(from: string) {
			return date
		}
		let zulu = string.replacingOccurrences(of: "+00:00", with: "Z")
		guard zulu != string else { return nil }
		return ISOTimestamp.fractional.date(from: zulu) ?? ISOTimestamp.plain.date(from: zulu)
	}
}
