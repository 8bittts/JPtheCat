import XCTest
@testable import JPtheCatCore

final class ProviderTintLegibilityTests: XCTestCase {
	// Widget/app card background stops the lift is measured against.
	private let lightCard = "FFFDF7"
	private let darkCard = "221E1B"
	private let lightInk = "221D15"
	private let darkInk = "F2F1EC"

	private func lift(_ hex: String, dark: Bool) -> String {
		ProviderTintLegibility.legibleHex(
			tintHex: hex,
			backgroundHex: dark ? darkCard : lightCard,
			inkHex: dark ? darkInk : lightInk,
			isDark: dark)
	}

	// Codex charcoal is invisible on the dark card (~1.1:1); the curated bright neutral is the whole
	// point of the shared lift — this is the regression the widget was missing entirely.
	func testCodexLiftsToBrightNeutralOnDark() {
		XCTAssertEqual(lift(ProviderTintLegibility.codexTintHex, dark: true), "A6A6A8")
	}

	// On the light card Codex charcoal already reads (dark on cream), so it passes through unchanged.
	func testCodexPassesThroughOnLight() {
		XCTAssertEqual(lift(ProviderTintLegibility.codexTintHex, dark: false), "2F2F33")
	}

	// Brand terracotta clears the floor on BOTH cards, so it must never be altered.
	func testClaudeBrandPassesThroughOnBothThemes() {
		XCTAssertEqual(lift("#D6783F", dark: false), "D6783F")
		XCTAssertEqual(lift("#D6783F", dark: true), "D6783F")
	}

	// Brand ginger sits at 2.97:1 — just above the 2.9 floor — so it also passes unchanged.
	func testGingerBrandPassesThrough() {
		XCTAssertEqual(lift("#DF7A2E", dark: false), "DF7A2E")
		XCTAssertEqual(lift("#DF7A2E", dark: true), "DF7A2E")
	}

	// Output is normalized to uppercase, no `#`, regardless of input form.
	func testResultIsNormalizedHex() {
		XCTAssertEqual(lift("#d6783f", dark: false), "D6783F")
		XCTAssertEqual(lift("d6783f", dark: false), "D6783F")
	}

	// A genuinely-too-dark NON-Codex tint on the dark card must be lifted until it clears the WCAG
	// graphical-object floor — assert the invariant (contrast >= floor), not a hand-computed hex.
	func testTooDarkTintIsLiftedAboveFloorOnDark() {
		let input = "#243024"  // a dark green that vanishes on the charcoal card
		let out = lift(input, dark: true)
		XCTAssertNotEqual(out, "243024", "expected a genuinely-too-dark tint to be lifted")
		XCTAssertGreaterThanOrEqual(
			Self.contrast(out, darkCard), 2.9,
			"lifted tint must clear the WCAG graphical-object floor on the dark card")
	}

	// A tint that already clears the floor is returned verbatim (no needless lift). gingerDeep
	// (#A84D14) reads ~5.2:1 on the cream card, well above the 2.9 floor.
	func testTintAboveFloorIsUnchanged() {
		XCTAssertGreaterThanOrEqual(Self.contrast("A84D14", lightCard), 2.9)
		XCTAssertEqual(lift("#A84D14", dark: false), "A84D14")
	}

	// MARK: local WCAG contrast (mirror of the private Core math, for invariant assertions)
	private static func contrast(_ a: String, _ b: String) -> Double {
		func rgb(_ hex: String) -> (Double, Double, Double) {
			let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
			var v: UInt64 = 0
			_ = Scanner(string: s).scanHexInt64(&v)
			return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
		}
		func lum(_ c: (Double, Double, Double)) -> Double {
			func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
			return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
		}
		let la = lum(rgb(a)), lb = lum(rgb(b))
		return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
	}
}
