import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

/// SURFACE 2 of 3 in the compact-token three-way agreement (`TokenFormatterTests` in Core pins the
/// ladder and the menu-bar tooltip; `WidgetTokenFormatParityTests` pins the widget faces).
///
/// [CRITICAL] The dashboard used to own a top-level `formatTokenCount(_:)` that was a byte-identical
/// copy of `MenuBarLabelRenderer.compactTokenCount`, while the widget's third copy rounded to a whole
/// `K` — 97,600 tokens read `97.6K` here and `98K tok` on the Medium widget. All three now route
/// through Core's `TokenFormatter`; the source guard below is what keeps a fourth copy from appearing.
final class TokenFormatterParityTests: XCTestCase {
	private let cal = Calendar.current

	private func copilotRow(day: Date, tokens: Int) -> ModelDaySummary {
		ModelDaySummary(
			provider: .copilot, model: "copilot-m", day: day, eventCount: 1,
			inputTokens: tokens, outputTokens: 0, cache5mTokens: 0, cache1hTokens: 0,
			cacheReadTokens: 0, cost: 0)
	}

	/// The app's token-display surface (a fully-unpriced provider's figure) must be the SAME string the
	/// menu bar and the widget render for the same count — modulo the widget's `" tok"` unit suffix.
	func testAppTokenFiguresMatchTheSharedLadder() {
		let now = Date()
		let today = cal.startOfDay(for: now)
		for tokens in [0, 999, 1_500, 53_600, 97_600, 1_234_567] {
			let readout = AnalyticsReadout(
				rows: [copilotRow(day: today, tokens: tokens)],
				scopedProviders: [.copilot], days: 7, measure: .tokens,
				focusedProvider: .copilot, now: now)
			XCTAssertEqual(
				readout.providerFigure(.copilot), TokenFormatter.compact(tokens),
				"app provider figure drifted from TokenFormatter at \(tokens)")
			XCTAssertEqual(
				readout.heroPrimaryValue, TokenFormatter.compact(tokens),
				"app hero figure drifted from TokenFormatter at \(tokens)")
		}
	}

	/// The exact regression: the dashboard's rung is one decimal place, and the widget was fixed to
	/// match THIS side (not the other way round).
	func testThousandsRungIsPinnedToTheDashboardForm() {
		let now = Date()
		let readout = AnalyticsReadout(
			rows: [copilotRow(day: cal.startOfDay(for: now), tokens: 97_600)],
			scopedProviders: [.copilot], days: 7, measure: .tokens, focusedProvider: .copilot, now: now)
		XCTAssertEqual(readout.providerFigure(.copilot), "97.6K")
	}

	/// [CRITICAL] No app source may re-implement the ladder. Scans EVERY `Sources/JPtheCatApp/**/*.swift`
	/// (never a hardcoded file list), so moving a surface between files cannot make this pass vacuously.
	func testNoAppSourceReimplementsTheCompactTokenLadder() throws {
		let sources = try AppSourceScanner.files()
		for source in sources {
			for rung in ["%.1fK", "%.0fK", "%.1fM", "%.0fM"] {
				XCTAssertFalse(
					source.text.contains(rung),
					"""
					\(source.name) formats a compact magnitude with `\(rung)` — the K/M ladder lives in \
					Core's `TokenFormatter` (tokens) and `MoneyFormatter.compactDollars` (dollars). \
					A local copy is exactly how the dashboard and the widget drifted to 97.6K vs 98K.
					""")
			}
		}
	}

	/// The basis policy the app used to encode twice now resolves from Core, so the selector badge and
	/// the Advanced Analytics sidebar read from one table.
	func testDashboardBadgeVocabularyComesFromCore() {
		XCTAssertEqual(ProviderBasis.of(rawID: "claude").badge, "real")
		XCTAssertEqual(ProviderBasis.of(rawID: "codex").badge, "notional")
		XCTAssertEqual(ProviderBasis.of(rawID: "muse_spark").badge, "notional")
		XCTAssertEqual(ProviderBasis.of(rawID: "copilot").badge, "estimate")
		XCTAssertEqual(ProviderBasis.of(rawID: "cursor").badge, "notional")
		XCTAssertEqual(ProviderBasis.of(rawID: "opencode").badge, "gateway")
		XCTAssertEqual(ProviderBasis.of(rawID: "opencodego").badge, "gateway")
	}

	/// [CRITICAL] `DashboardView.selectorBadge(for:)`'s `.available` arm must stay a LITERAL ternary —
	/// `scripts/verify-app-demo-parity.sh` pins that exact line as the mac/web badge-parity anchor, so
	/// it cannot be rewritten as `ProviderBasis.of(rawID:).badge` without updating the script in the
	/// same change. This guard is what stops the surviving literals from drifting away from Core's
	/// vocabulary. The dashboard intentionally presents non-aggregable `.estimate` rows as `local`
	/// because that word describes the visible data source without implying an official quota estimate.
	func testSelectorBadgeWordsMatchProviderBasis() throws {
		let body = try AppSourceScanner.body(
			of: "private func selectorBadge(for row: DashboardViewModel.ProviderRow) -> String?")
		let vocabulary = Set(ProviderBasis.allCases.map(\.badge))
		XCTAssertEqual(vocabulary, ["real", "notional", "estimate", "gateway", "official"])
		// Non-aggregable bases (`estimate`, `gateway`, `official`) are presented as `local` / plan badge
		// by the selector, so they never appear as a basis word in the `.available` switch arm.
		for word in vocabulary.subtracting(["estimate", "gateway", "official"]) {
			XCTAssertTrue(
				body.contains("\"\(word)\"") || body.contains(".\(word).badge"),
				"""
				selectorBadge(for:) no longer emits the `\(word)` basis word. The dashboard selector and \
				the Advanced Analytics sidebar share ONE vocabulary (`ProviderBasis.badge`) — a row whose \
				basis has no pill is readable only by the ABSENCE of one.
				""")
		}
		XCTAssertTrue(body.contains("return \"local\""))
		// The availability words are a separate axis and must not be confused with a basis.
		for word in ["stale", "unavailable", "disabled"] {
			XCTAssertTrue(body.contains("\"\(word)\""), "selectorBadge lost the `\(word)` availability word")
			XCTAssertFalse(vocabulary.contains(word), "`\(word)` must never become a basis word")
		}
	}
}
