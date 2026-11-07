import Foundation

/// Pure, testable timing model for the split-flap hero ticker (`SplitFlapMoney`).
///
/// Given the old and new character arrays for a value change, it computes which indices actually
/// change and the exact schedule of flap events (flip-down → glyph swap → release). The view derives
/// its animation from this value instead of open-coding hand-timed `DispatchQueue.asyncAfter` closures
/// with magic delays and no finish-state coverage — so a unit test can assert the terminal state
/// (`displayed(at: finishAt) == new`, `flipping(at: finishAt)` empty) and the per-index schedule.
///
/// The view keeps its shipped `asyncAfter` + implicit-`withAnimation` visuals verbatim (identical flap
/// look); only the *timing/finish-state* now flows from this tested type.
struct SplitFlapTransition {
	struct Step: Equatable {
		/// Character index (into the equal-length old/new arrays) that flips.
		let index: Int
		/// When this tile enters `flipping` (rotates down).
		let flipAt: TimeInterval
		/// When this tile's glyph swaps to the new character.
		let swapAt: TimeInterval
		/// When this tile leaves `flipping` (rotates back up).
		let releaseAt: TimeInterval
	}

	let old: [Character]
	let new: [Character]
	let steps: [Step]
	/// When the whole run is guaranteed settled (all glyphs swapped, nothing flipping) — the view snaps
	/// `displayed = new` / `flipping = []` here as a belt-and-braces terminal reset.
	let finishAt: TimeInterval

	/// Returns `nil` when there is nothing to animate — unequal lengths, an empty from-state, or no
	/// changed indices — signalling the caller to snap straight to `new` with no flap.
	init?(
		old: [Character],
		new: [Character],
		stepDelay: TimeInterval = 0.075,
		swapDelay: TimeInterval = 0.12,
		releaseDelay: TimeInterval = 0.24,
		finishPad: TimeInterval = 0.08
	) {
		guard old.count == new.count, !old.isEmpty else { return nil }
		let changed = new.indices.filter { old[$0] != new[$0] }
		guard !changed.isEmpty else { return nil }

		self.old = old
		self.new = new
		self.steps = changed.enumerated().map { step, index in
			let base = Double(step) * stepDelay
			return Step(index: index, flipAt: base, swapAt: base + swapDelay, releaseAt: base + releaseDelay)
		}
		self.finishAt = Double(changed.count - 1) * stepDelay + releaseDelay + finishPad
	}

	/// Indices that change, in flip order.
	var changedIndices: [Int] { steps.map(\.index) }

	/// The characters shown at elapsed time `t`: each changed index swaps to its new glyph at `swapAt`.
	func displayed(at t: TimeInterval) -> [Character] {
		var chars = old
		for step in steps where t >= step.swapAt {
			chars[step.index] = new[step.index]
		}
		return chars
	}

	/// The set of indices mid-flip at elapsed time `t` (inside `[flipAt, releaseAt)`).
	func flipping(at t: TimeInterval) -> Set<Int> {
		Set(steps.filter { t >= $0.flipAt && t < $0.releaseAt }.map(\.index))
	}
}
