import XCTest

@testable import JPtheCatApp

/// The split-flap hero ticker used to open-code its animation as N×4 hand-timed
/// `DispatchQueue.asyncAfter` closures with magic delays and NO finish-state coverage. The timing +
/// terminal state now flow from the pure `SplitFlapTransition`; these pin the schedule and, crucially,
/// that the run always settles on the target with nothing left flipping.
final class SplitFlapTransitionTests: XCTestCase {
	private func chars(_ s: String) -> [Character] { Array(s) }

	func testFinishStateShowsTargetWithNothingFlipping() throws {
		let transition = try XCTUnwrap(
			SplitFlapTransition(old: chars("$1.20"), new: chars("$9.87"))
		)
		// At (and past) finishAt the displayed value equals the target and no tile is mid-flip.
		XCTAssertEqual(String(transition.displayed(at: transition.finishAt)), "$9.87")
		XCTAssertTrue(transition.flipping(at: transition.finishAt).isEmpty)
		XCTAssertEqual(String(transition.displayed(at: transition.finishAt + 5)), "$9.87")
		XCTAssertTrue(transition.flipping(at: transition.finishAt + 5).isEmpty)
	}

	func testOnlyChangedIndicesAnimate() throws {
		// "$1.20" -> "$9.87": indices 1 (1->9), 3 (2->8), 4 (0->7) change; "$" and "." hold.
		let transition = try XCTUnwrap(
			SplitFlapTransition(old: chars("$1.20"), new: chars("$9.87"))
		)
		XCTAssertEqual(transition.changedIndices, [1, 3, 4])
	}

	func testScheduleIsMonotonicAndOrdered() throws {
		let transition = try XCTUnwrap(
			SplitFlapTransition(old: chars("00"), new: chars("99"))
		)
		// Each tile flips before it swaps before it releases; later steps start no earlier.
		for step in transition.steps {
			XCTAssertLessThan(step.flipAt, step.swapAt)
			XCTAssertLessThan(step.swapAt, step.releaseAt)
			XCTAssertLessThanOrEqual(step.releaseAt, transition.finishAt)
		}
		XCTAssertEqual(transition.steps.map(\.flipAt).sorted(), transition.steps.map(\.flipAt))
	}

	func testMidFlightSwapHappensExactlyAtSwapTime() throws {
		let transition = try XCTUnwrap(
			SplitFlapTransition(old: chars("0"), new: chars("5"))
		)
		let step = try XCTUnwrap(transition.steps.first)
		// Just before its swap the old glyph shows and the tile is flipping; at swap the new glyph shows.
		XCTAssertEqual(String(transition.displayed(at: step.swapAt - 0.001)), "0")
		XCTAssertTrue(transition.flipping(at: step.flipAt).contains(0))
		XCTAssertEqual(String(transition.displayed(at: step.swapAt)), "5")
	}

	func testUnanimatableTransitionsReturnNil() {
		// Different lengths -> snap (no flap): the caller sets displayed = new directly.
		XCTAssertNil(SplitFlapTransition(old: chars("$1.20"), new: chars("$10.20")))
		// Empty from-state -> snap (first appearance).
		XCTAssertNil(SplitFlapTransition(old: chars(""), new: chars("$1.20")))
		// No changed characters -> nothing to animate.
		XCTAssertNil(SplitFlapTransition(old: chars("$1.20"), new: chars("$1.20")))
	}
}
