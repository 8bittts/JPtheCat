import Foundation

/// Per-request usage for completed Grok turns.
///
/// Grok Build writes billed usage once per `turn_completed`, summed over every model request in the
/// turn, while xAI's 200K premium applies to each request. `CostCalculator` decides the tier from one
/// event's context, so a turn made of many sub-200K requests billed every token at 2x. Measured on one
/// Mac: pricing 861 retained requests one at a time gave $200.43, against $232.72 with each turn tiered.
///
/// `~/.grok/logs/unified.jsonl` keeps each request (`shell.turn.inference_done`) for recent sessions only.
/// When a single-model turn's latest requests sum EXACTLY to its totals, the turn is recorded as one
/// event per request and priced exactly. Otherwise the turn stays one event: an upper bound whenever its
/// summed context crosses the premium boundary.
enum GrokRequestRounds {
	private final class Cache: @unchecked Sendable {
		private struct Key: Equatable {
			let path: String
			let size: Int
			let mtime: Double
			let ctime: Double
		}
		private let lock = NSLock()
		private var key: Key?
		private var value: [String: [GrokInferenceRound]] = [:]

		func rounds(logURL: URL) -> [String: [GrokInferenceRound]] {
			guard let state = FileCursor.state(fileURL: logURL) else { return [:] }
			let current = Key(path: logURL.path, size: state.size, mtime: state.mtime, ctime: state.ctime)
			lock.lock()
			if key == current {
				defer { lock.unlock() }
				return value
			}
			lock.unlock()
			let loaded = Dictionary(grouping: GrokProvider.loadInferenceRounds(logURL: logURL), by: \.sid)
				.mapValues { $0.sorted { $0.timestamp < $1.timestamp } }
			lock.lock()
			key = current
			value = loaded
			lock.unlock()
			return loaded
		}
	}

	private static let cache = Cache()

	/// Each session's requests, oldest first, cached against the log's size, mtime, and ctime so a full
	/// reindex of every session reads the log once.
	static func bySession(logURL: URL) -> [String: [GrokInferenceRound]] {
		cache.rounds(logURL: logURL)
	}

	/// The requests that make up one turn, oldest first, or nil when no run of the session's latest
	/// requests before `completedAt` reconciles exactly with the turn's usage.
	static func rounds(
		forTurn usage: TokenUsage, completedAt: Date, in sessionRounds: [GrokInferenceRound]
	) -> [GrokInferenceRound]? {
		// Grok stamps turns with whole seconds, so a request can carry a slightly later timestamp.
		let candidates = sessionRounds.filter { $0.timestamp <= completedAt.addingTimeInterval(2) }
		var sum = TokenUsage()
		for (offset, round) in candidates.enumerated().reversed() {
			sum += round.usage
			if sum == usage { return Array(candidates[offset...]) }
			if sum.input > usage.input || sum.output > usage.output || sum.cacheRead > usage.cacheRead {
				return nil
			}
		}
		return nil
	}
}
