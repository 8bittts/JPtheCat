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
		// Claude emits those windows for Pro as well as Max — so a hardcoded "max" mislabelled every
		// Pro subscriber in `LocalAutomationSnapshot.plan_type` and the CLI's JSON. Never fabricate a
		// tier; the only honest local source was another app's Keychain item and reading it prompts
		// for the login password.
		return RateLimitSnapshot(
			primary: primary, secondary: secondary, planType: nil,
			capturedAt: capturedAtEpoch.map { Date(timeIntervalSince1970: $0) },
			modelWindows: modelWindows)
	}

	/// Per-model-family weekly windows (`seven_day_opus` → the "Fable" bar, `seven_day_sonnet`, …).
	///
	/// **These are captured opportunistically and are normally ABSENT.** Claude Code's own statusline
	/// schema documents only `five_hour` and `seven_day`; the model-scoped windows exist inside the
	/// binary and drive the `/usage` panel, but as of Claude Code 2.1.318 they are NOT part of the
	/// statusline payload (verified against a live capture — the object carried only `seven_day`; the
	/// Fable cap lives in Claude Code's `seven_day_overage_included` scoped window, which only `/usage`
	/// shows). So JP shows no per-model bar today, which is the honest result: an absent window
	/// means "not reported", never 0%. If Anthropic adds the field, the capture block already forwards
	/// it and this decoder lights the gauge up with a real official number — no estimate, ever.
	///
	/// Any `seven_day_*` key is accepted, not just the two known ones, so a future family needs no code
	/// change; `ModelScopedRateLimitWindow.label` humanizes an unrecognized suffix. `seven_day` itself
	/// is excluded (it is the plan-wide window, already the snapshot's `secondary`).
	static func modelScopedWindows(in root: [String: Any]) -> [ModelScopedRateLimitWindow] {
		root.keys
			.filter { $0.hasPrefix("seven_day_") }
			.sorted()
			.compactMap { key in
				RateLimitWindow(json: root[key], windowMinutes: 10080)
					.map { ModelScopedRateLimitWindow(key: key, window: $0) }
			}
	}
}
