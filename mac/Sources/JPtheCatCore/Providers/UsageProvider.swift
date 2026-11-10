import Foundation

/// A pluggable source of usage events. The checklist for adding one is
/// `_docs/11-adding-a-provider.md`.
public protocol UsageProvider: Sendable {
	var id: ProviderID { get }

	/// Directories the app's FSEvents watcher observes for instant refresh.
	func watchPaths() -> [URL]

	/// True if this tool has any local data on this machine.
	func isAvailable() -> Bool

	/// All de-duplicated usage events currently on disk.
	func loadEvents() -> [UsageEvent]

	/// The provider's latest current official rate-limit snapshot (subscription usage), if it exposes
	/// one. Expired windows must already be filtered out. This is the honest headline for subscription
	/// plans where dollar cost is only notional.
	/// Default: none — Codex reads rollout JSONL; Claude reads the opt-in statusline capture.
	func latestRateLimits() -> RateLimitSnapshot?

	/// True when the provider HAS a recent official window that just rolled past its reset boundary with
	/// no fresher reading yet — so `latestRateLimits()` is (correctly) blank not because there's no data,
	/// but because the window reset. Lets the dashboard show a "window reset — awaiting fresh data" hint
	/// instead of the gauge silently vanishing (the "bars reset randomly" report). Never fabricates a
	/// percentage. Default: false.
	func latestRateLimitAwaitingReset(now: Date) -> Bool
}

extension UsageProvider {
	public func latestRateLimits() -> RateLimitSnapshot? { nil }
	public func latestRateLimitAwaitingReset(now: Date) -> Bool { false }
}
