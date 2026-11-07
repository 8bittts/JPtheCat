struct DashboardRefreshGate {
	struct Token: Equatable, Sendable {
		let generation: Int
		let days: Int
	}

	private var generation = 0

	mutating func invalidate() {
		generation += 1
	}

	func token(days: Int) -> Token {
		Token(generation: generation, days: days)
	}

	func shouldApply(_ token: Token, currentDays: Int) -> Bool {
		token.generation == generation && token.days == currentDays
	}
}

struct DashboardRefreshQueue {
	enum Next: Equatable {
		case none
		case windowOnly
		case reindex
	}

	private var needsWindowOnly = false
	private var needsReindex = false

	mutating func request(reindex: Bool) {
		if reindex {
			needsReindex = true
		} else {
			needsWindowOnly = true
		}
	}

	mutating func popNext() -> Next {
		if needsWindowOnly {
			needsWindowOnly = false
			return .windowOnly
		}
		if needsReindex {
			needsReindex = false
			// A reindex recomputes everything a window-only pass would, so it consumes any window-only
			// request queued alongside it instead of leaving one to fire redundantly right after.
			needsWindowOnly = false
			return .reindex
		}
		return .none
	}
}
