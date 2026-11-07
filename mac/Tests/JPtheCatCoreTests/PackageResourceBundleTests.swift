import XCTest

@testable import JPtheCatCore

final class PackageResourceBundleTests: XCTestCase {
	func testFindsCoreResourcesFromSwiftPMTestExecutable() {
		let url = JPResourceBundle.url(
			forResource: "pricing-default",
			withExtension: "json",
			in: "JPtheCatCore")

		XCTAssertNotNil(url)
	}

	/// [Regression guard — uncached bundle walk on a SwiftUI body and every CostCalculator init]
	/// `candidates(bundleName:)` is fully eager: it materializes `Bundle.allBundles` x 8 ancestor
	/// directories x 3 shapes plus every `/`-containing argv entry, then standardizes each path to
	/// dedupe — all before the first `Bundle(path:)` probe. It showed up on the profiler twice at once,
	/// on the main thread inside `SelectorRow.icon(_:)` and on the background refresh inside
	/// `CostCalculator`'s init. In a packaged `.app` the answer cannot change during a process lifetime.
	/// NOTE: an `===` identity assertion would be VACUOUS here — `Bundle(path:)` returns the same
	/// instance for a given path whether or not we memoize, so such a test passes with the cache
	/// deleted. The walk COUNT is the only assertion that actually fails when the cache is removed.
	func testBundleResolutionIsMemoizedPerTargetName() {
		_ = JPResourceBundle.bundle(named: "JPtheCatCore")  // ensure resolved before counting
		let before = JPResourceBundle.candidateWalkCount

		for _ in 0..<5 { XCTAssertNotNil(JPResourceBundle.bundle(named: "JPtheCatCore")) }

		XCTAssertEqual(
			JPResourceBundle.candidateWalkCount, before,
			"a resolved bundle must never re-run the eager candidate walk")
	}

	/// A failed lookup must NOT be cached: a call made before resources are stageable has to be able to
	/// retry rather than latching a permanent `nil` for the process lifetime. The walk count proves the
	/// retry is real rather than a cached `nil` being returned.
	func testUnresolvableTargetIsNotCachedAsAPermanentFailure() {
		XCTAssertNil(JPResourceBundle.bundle(named: "NoSuchTarget"))
		let afterFirstMiss = JPResourceBundle.candidateWalkCount
		XCTAssertNil(JPResourceBundle.bundle(named: "NoSuchTarget"))
		XCTAssertEqual(
			JPResourceBundle.candidateWalkCount, afterFirstMiss + 1,
			"a miss must re-walk on the next call, never latch a permanent nil")
		// Still resolves a real target afterwards — a negative result never poisons the cache.
		XCTAssertNotNil(JPResourceBundle.bundle(named: "JPtheCatCore"))
	}
}
