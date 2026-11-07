import XCTest

/// [NOTE] Both guards used to read `DashboardView.swift` by a cwd-relative literal path, which froze
/// that file. They now resolve the ticker declarations through `AppSourceScanner` wherever those live,
/// and a missing anchor throws — the `text.count` ban can no longer go vacuous by extraction.
final class HeaderTickerUnificationTests: XCTestCase {
	func testBasisBandUsesOneAnimatedTickerImplementation() throws {
		let basisChip = try AppSourceScanner.body(of: "struct BasisLabelChip: View")
		let allSources = try AppSourceScanner.joined()

		XCTAssertTrue(
			basisChip.contains("TickerTapeText(text: text"),
			"BasisLabelChip should use the single animated basis ticker implementation.")
		XCTAssertTrue(allSources.contains("SplitFlapMoney"))
		XCTAssertTrue(allSources.contains("BasisLabelChip"))
	}

	func testBasisTickerUsesSharedMotionNotLabelLength() throws {
		// Scoped to the three ticker declarations rather than a whole file: the ban is about the ticker's
		// own speed/distance math, and each anchor throws if its declaration is renamed or removed.
		let ticker = try AppSourceScanner.bodies(of: [
			"struct BasisLabelChip: View",
			"struct TickerTapeMotion: Equatable",
			"struct TickerTapeText: View",
		])

		XCTAssertTrue(ticker.contains("TickerTapeMotion"))
		XCTAssertFalse(
			ticker.contains("text.count"),
			"Ticker speed/distance must not vary by All Providers vs provider-specific label length.")
	}
}
