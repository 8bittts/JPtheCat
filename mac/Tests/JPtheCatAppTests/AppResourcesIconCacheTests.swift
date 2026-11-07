import AppKit
import XCTest

@testable import JPtheCatApp

/// [Regression guard — uncached provider-mark decode on every SwiftUI body pass]
/// `NSImage(contentsOf:)` performs NO caching, so `SelectorRow.icon(_:)` used to re-read AND re-decode
/// a `provider-*.svg` off disk on every call. It is called from inside a SwiftUI `body` that re-runs on
/// every hover in/out and on every refresh, so that decode ran continuously during normal use.
///
/// [CRITICAL] Every assertion here is on `AppResources.iconDiskLoadCount`, never on `NSImage` identity.
/// An `===` assertion is VACUOUS for the same reason it was in `PackageResourceBundleTests`: it cannot
/// distinguish a working cache from a removed one, so it passes either way. The disk-load COUNT is the
/// only signal that actually fails when the memoization is deleted.
///
/// Every count assertion below is also ORDER-INDEPENDENT: the hit-path test warms its own key first,
/// and the delegation/miss tests use a deliberately absent mark, which is never cached and is therefore
/// cold on every call no matter what else ran first in this process.
final class AppResourcesIconCacheTests: XCTestCase {
	/// A real bundled provider mark. Resolving it also proves the app resource bundle is reachable from
	/// the SwiftPM test executable, so a `nil` here is a staging failure, not a cache failure.
	private let markName = "provider-claude"
	/// Deliberately absent. Misses are never cached, so this is cold on EVERY call.
	private let missingMarkName = "provider-no-such-mark"

	func testRepeatedIconLoadsNeverTouchDiskAgain() throws {
		XCTAssertNotNil(
			AppResources.icon(named: markName),
			"the JPtheCatApp resource bundle must resolve from the test executable")
		let before = AppResources.iconDiskLoadCount

		for _ in 0..<5 { XCTAssertNotNil(AppResources.icon(named: markName)) }

		XCTAssertEqual(
			AppResources.iconDiskLoadCount, before,
			"""
			A cached provider mark must never be re-read or re-decoded off disk. This runs from a SwiftUI \
			body on every hover and every refresh — never reintroduce a bare NSImage(contentsOf:).
			""")
	}

	/// Proves the counter tracks REAL work, so "no extra loads" above cannot be satisfied by a loader
	/// that stopped loading (or by a counter that stopped counting).
	func testEveryUncachedLookupCostsExactlyOneDiskLoad() {
		let before = AppResources.iconDiskLoadCount
		XCTAssertNil(AppResources.icon(named: missingMarkName))
		XCTAssertEqual(AppResources.iconDiskLoadCount, before + 1)
	}

	/// A failed lookup must NOT be cached: a call made before resources are stageable has to retry
	/// rather than latching a permanent `nil` for the process lifetime. The load count proves the retry
	/// is real rather than a cached `nil` being handed back.
	func testUnresolvableIconIsNotCachedAsAPermanentFailure() {
		XCTAssertNil(AppResources.icon(named: missingMarkName))
		let afterFirstMiss = AppResources.iconDiskLoadCount
		XCTAssertNil(AppResources.icon(named: missingMarkName))
		XCTAssertEqual(
			AppResources.iconDiskLoadCount, afterFirstMiss + 1,
			"a miss must retry on the next call, never latch a permanent nil")
	}

	/// The dashboard's selector rows must go THROUGH the memoized loader rather than decoding the file
	/// themselves. A `SelectorRow.icon` that called `NSImage(contentsOf:)` directly would return the
	/// same answers as the wrapper does while leaving this counter untouched — which is exactly the
	/// regression this file exists to catch.
	@MainActor
	func testSelectorRowIconRoutesThroughTheMemoizedLoader() {
		let before = AppResources.iconDiskLoadCount
		XCTAssertNil(SelectorRow.icon(missingMarkName))
		XCTAssertEqual(
			AppResources.iconDiskLoadCount, before + 1,
			"SelectorRow.icon must delegate to AppResources.icon(named:), not load the file itself")

		XCTAssertNotNil(AppResources.icon(named: markName))  // warm the shared cache
		let warmed = AppResources.iconDiskLoadCount
		for _ in 0..<3 { XCTAssertNotNil(SelectorRow.icon(markName)) }
		XCTAssertEqual(
			AppResources.iconDiskLoadCount, warmed,
			"selector-row icon lookups must be served from the shared memo, not re-decoded")
	}
}
