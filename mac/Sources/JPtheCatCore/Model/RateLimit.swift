import Foundation

/// One rolling usage window a provider reports directly (Codex `rate_limits`, and later the Claude
/// statusline feed). `usedPercent` is the OFFICIAL usage signal — no reconstruction/estimate — so it is
/// the honest primary readout for a subscription plan where dollar cost is only notional.
public struct RateLimitWindow: Sendable, Equatable {
	/// 0–100. The provider's own "how much of this window you've used" figure.
	public let usedPercent: Double
	/// Nominal window length. Codex emits 300 (5-hour) and/or 10080 (weekly); its provider
	/// normalizes those windows by duration instead of trusting the upstream slot name.
	public let windowMinutes: Int
	/// When the window rolls over. Decoded from a unix epoch-SECONDS field; nil when absent.
	public let resetsAt: Date?

	public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) {
		self.usedPercent = usedPercent
		self.windowMinutes = windowMinutes
		self.resetsAt = resetsAt
	}

	public init?(json raw: Any?, windowMinutes: Int) {
		guard let object = raw as? [String: Any],
			let used = JSONNumber.double(object["used_percentage"])
		else { return nil }
		let resets = JSONNumber.double(object["resets_at"])
		self.init(
			usedPercent: min(100, max(0, used)), windowMinutes: windowMinutes,
			resetsAt: resets.map { Date(timeIntervalSince1970: $0) })
	}

	/// Returns this window only while its reset boundary is still in the future. Once the provider says
	/// the window has rolled over, the official percentage is no longer current enough to display.
	public func current(at now: Date = Date()) -> RateLimitWindow? {
		guard let resetsAt else { return self }
		return resetsAt > now ? self : nil
	}

	/// True when this window's reset boundary is in the PAST but only recently (within `grace`). The
	/// window has genuinely rolled over — its old percentage is gone and a fresh reading hasn't arrived
	/// yet. We do NOT synthesize a new 0% (that would "invent a missing duration", forbidden by the
	/// Rate-Limit Window Freshness contract); this only marks that a reset just happened, so the UI can
	/// show a "window reset — awaiting fresh data" hint instead of the gauge silently disappearing.
	public func recentlyReset(at now: Date = Date(), grace: TimeInterval) -> Bool {
		guard let resetsAt else { return false }
		return resetsAt <= now && now.timeIntervalSince(resetsAt) <= grace
	}
}

/// A weekly window scoped to ONE model family rather than the whole plan.
/// Claude Code 2.1.322 reports these as `rate_limits.model_scoped` rows beside the all-models
/// `seven_day` window. Older captures used `seven_day_opus` and `seven_day_sonnet`.
///
/// `key` is the provider's own field name. A `model_scoped` row also carries the server
/// `display_name`. A legacy key with no name still humanizes its suffix rather than disappearing.
public struct ModelScopedRateLimitWindow: Sendable, Equatable, Identifiable {
	/// The provider's raw field name, e.g. `seven_day_opus` or `model_scoped:Fable`.
	public let key: String
	public let window: RateLimitWindow
	/// Server-supplied label from `rate_limits.model_scoped[].display_name`. Nil for a legacy
	/// `seven_day_*` key, which still maps through `labels`.
	public let displayName: String?
	public var id: String { key }

	public init(key: String, window: RateLimitWindow, displayName: String? = nil) {
		self.key = key
		self.window = window
		self.displayName = displayName
	}

	/// Display labels for the legacy `seven_day_*` keys. `seven_day_opus` kept its old spelling after
	/// Fable took that slot. Claude Code 2.1.322 names the live row itself via `display_name`, so this
	/// map is only the fallback. Anything unrecognized humanizes its own suffix — never a guessed model.
	private static let labels: [String: String] = [
		"seven_day_opus": "Fable",
		"seven_day_sonnet": "Sonnet",
		"seven_day_overage_included": "Weekly incl. credits",
	]

	/// e.g. "Fable". A server `display_name` wins; an unknown `seven_day_<x>` becomes "X".
	public var label: String {
		if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
			return displayName
		}
		if let known = Self.labels[key] { return known }
		let suffix = key.hasPrefix("seven_day_") ? String(key.dropFirst("seven_day_".count)) : key
		let words = suffix.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
		return words.isEmpty ? key : words.joined(separator: " ")
	}

	public func current(at now: Date = Date()) -> ModelScopedRateLimitWindow? {
		window.current(at: now).map {
			ModelScopedRateLimitWindow(key: key, window: $0, displayName: displayName)
		}
	}
}

/// A provider's latest rate-limit snapshot. For Codex (`plan_type == "pro"`, a subscription) this —
/// not dollars — is the truthful headline: normalized 5-hour and weekly usage windows.
public struct RateLimitSnapshot: Sendable, Equatable {
	public let primary: RateLimitWindow?
	public let secondary: RateLimitWindow?
	/// Extra per-model weekly windows, when the provider reports them (Claude's `model_scoped` rows,
	/// or a legacy `seven_day_*` key). Empty means "not reported", never "0% used". Named rows keep
	/// server order; legacy keys follow, sorted.
	public let modelWindows: [ModelScopedRateLimitWindow]
	/// e.g. "pro". Signals that dollar figures for this provider are notional list-price, not spend.
	public let planType: String?
	/// When this reading was captured, for providers whose feed only refreshes on activity. Claude's
	/// statusline only emits AFTER Claude answers, so once you're rate-limited the capture FREEZES at
	/// the last pre-limit percentage. Codex carries it too: its rollout log only records a window while
	/// a CLI turn runs against that quota pool, so usage from any other surface — and any turn billed to
	/// a different pool — leaves the last reading frozen while the real percentage moves on.
	/// It is DIAGNOSTIC here, never a display gate: an official window stays on screen until its own
	/// `resets_at` passes, because a stale percentage plus a live reset countdown tells the user more
	/// than a blank gauge does.
	public let capturedAt: Date?
	/// Last reported Codex credits, independent of the subscription windows and dollar accounting.
	public let credits: CodexCreditBalance?

	public init(
		primary: RateLimitWindow?, secondary: RateLimitWindow?, planType: String?,
		capturedAt: Date? = nil, modelWindows: [ModelScopedRateLimitWindow] = [],
		credits: CodexCreditBalance? = nil
	) {
		self.primary = primary
		self.secondary = secondary
		self.planType = planType
		self.capturedAt = capturedAt
		self.modelWindows = modelWindows
		self.credits = credits
	}

	/// Drops expired windows. Last-reported credits retain their capture timestamp, even without a
	/// current window; a credit balance does not create subscription headroom. A
	/// model-scoped window is NOT a usage signal on its own — the snapshot still needs a current
	/// plan-wide window — so an expired-but-model-scoped-only reading stays nil rather than surfacing
	/// a lone orphan bar.
	public func current(at now: Date = Date()) -> RateLimitSnapshot? {
		let primary = primary?.current(at: now)
		let secondary = secondary?.current(at: now)
		guard primary != nil || secondary != nil || credits != nil else { return nil }
		return RateLimitSnapshot(
			primary: primary, secondary: secondary, planType: planType, capturedAt: capturedAt,
			modelWindows: modelWindows.compactMap { $0.current(at: now) }, credits: credits)
	}

	/// Returns a copy stamped with the moment the provider emitted this reading.
	/// Windows and credits are carried through untouched — stamping never alters a
	/// percentage.
	public func stamped(capturedAt: Date) -> RateLimitSnapshot {
		RateLimitSnapshot(
			primary: primary, secondary: secondary, planType: planType, capturedAt: capturedAt,
			modelWindows: modelWindows, credits: credits)
	}

	/// Grace window for the "awaiting fresh data after reset" hint: long enough to cover an idle 5-hour
	/// window plus slack, short enough that a genuinely stale reading still falls back to a blank gauge.
	public static let resetHintGrace: TimeInterval = 6 * 3600

	/// True when NO window is still current but at least one recently rolled past its reset boundary —
	/// the honest "the gauge is blank because the window reset, not because there's no data" state. Drives
	/// a hint chip in place of the vanished percentage; never fabricates a replacement number.
	public func awaitingFreshDataAfterReset(
		at now: Date = Date(), grace: TimeInterval = RateLimitSnapshot.resetHintGrace
	) -> Bool {
		guard primary?.current(at: now) == nil, secondary?.current(at: now) == nil else { return false }
		return (primary?.recentlyReset(at: now, grace: grace) ?? false)
			|| (secondary?.recentlyReset(at: now, grace: grace) ?? false)
	}

	/// The 5-hour window is high AND the capture has gone quiet — the honest read of "you probably hit
	/// your limit, and the frozen percentage is understating it because Claude can't emit a fresh one
	/// while it's refusing you." Only meaningful for a capture-timestamped feed (Claude). Thresholds:
	/// a fast-moving window that hasn't refreshed in `maxFreshMinutes` while sitting ≥ `highThreshold`.
	public func likelyAtLimit(
		now: Date = Date(), highThreshold: Double = 85, maxFreshMinutes: Double = 10
	) -> Bool {
		guard let capturedAt, let primary, primary.usedPercent >= highThreshold else { return false }
		return now.timeIntervalSince(capturedAt) > maxFreshMinutes * 60
	}
}
