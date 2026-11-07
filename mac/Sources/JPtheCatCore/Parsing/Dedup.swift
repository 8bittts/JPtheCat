import Foundation

/// Identifies one underlying request. A resumed session re-logs the same request across files, and
/// a streamed response logs many partial copies — all share this key.
public struct DedupKey: Hashable, Sendable {
	public let messageId: String
	public let requestId: String
	public init(messageId: String, requestId: String) {
		self.messageId = messageId
		self.requestId = requestId
	}
}

/// De-duplicates assistant events GLOBALLY across all files, keeping the copy with the LARGEST
/// `output` (the final streaming snapshot). Keeping the FIRST copy is ccusage #888's undercount.
/// Stateful so incremental tails dedup against already-ingested history.
public struct Deduplicator {
	public private(set) var best: [DedupKey: UsageEvent] = [:]

	public init() {}

	public mutating func add(_ event: UsageEvent) {
		let key = DedupKey(messageId: event.messageId, requestId: event.requestId)
		if let existing = best[key] {
			// keep-max-output; on an output tie, prefer the larger total so the result is
			// deterministic regardless of file / enumeration order.
			if existing.usage.output > event.usage.output { return }
			if existing.usage.output == event.usage.output,
				existing.usage.total >= event.usage.total
			{ return }
		}
		best[key] = event
	}

	public var events: [UsageEvent] { Array(best.values) }

	public static func dedupe<S: Sequence>(_ events: S) -> [UsageEvent]
	where S.Element == UsageEvent {
		var d = Deduplicator()
		for e in events { d.add(e) }
		return d.events
	}
}
