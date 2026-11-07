import XCTest

@testable import JPtheCatApp
@testable import JPtheCatCore

final class AppResourcesTests: XCTestCase {
	func testOpenCodeProviderMarksResolveThroughTheSharedLoader() {
		// Every provider that can render a dashboard selector row needs its white glyph bundled,
		// including the OpenCode GATEWAYS — their marks were missing entirely when Zen/Go were
		// promoted and the rows rendered as bare tint chips.
		for id in [
			"nemotron", "mimo", "big_pickle", "deepseek", "opencode", "opencodego",
		] {
			XCTAssertNotNil(AppResources.icon(named: "provider-" + id), id)
		}
	}

	func testEveryLiveProviderMarkResolvesThroughProviderIDRawValue() {
		for descriptor in ProviderCatalog.all where descriptor.support == .live {
			let resource = "provider-\(descriptor.id.rawValue)"
			XCTAssertNotNil(
				AppResources.icon(named: resource),
				"missing bundled mark for live provider \(descriptor.id.rawValue) (expected \(resource).svg)")
		}
	}

	func testGrokBotMarkAndTintDifferFromGrok() throws {
		let grokURL = try XCTUnwrap(AppResources.url(forResource: "provider-grok", withExtension: "svg"))
		let botURL = try XCTUnwrap(AppResources.url(forResource: "provider-grok_bot", withExtension: "svg"))
		let grokData = try Data(contentsOf: grokURL)
		let botData = try Data(contentsOf: botURL)
		XCTAssertNotEqual(grokData, botData)
		XCTAssertNotEqual(JPAppColor.grokTintHex, JPAppColor.grokBotTintHex)
	}

	func testFindsAppImagesAndSoundsFromSwiftPMTestExecutable() {
		XCTAssertNotNil(AppResources.image(forResource: "jp-menubar"))
		XCTAssertNotNil(AppResources.image(forResource: "jp-first-run-peek"))
		XCTAssertNotNil(AppResources.url(forResource: "jp-meow", withExtension: "m4a"))
		// The celebration confetti "pop" (app-only, like the meow — not a mirrored UI cue).
		XCTAssertNotNil(AppResources.url(forResource: "confetti-pop", withExtension: "m4a"))
		XCTAssertNotNil(AppResources.url(forResource: "provider-codex", withExtension: "svg"))
		XCTAssertNotNil(AppResources.url(forResource: "provider-grok", withExtension: "svg"))
		XCTAssertNotNil(AppResources.url(forResource: "provider-grok_bot", withExtension: "svg"))
		XCTAssertNotNil(AppResources.url(forResource: "provider-muse_spark", withExtension: "svg"))
	}

	func testBundlesEveryInteractiveSoundCue() {
		// Each UI cue must be packaged so the toggle/click sounds resolve at runtime (mirrored in
		// web/public as ui-*.m4a for the homepage demo).
		for cue in InteractiveSounds.Cue.allCases {
			XCTAssertNotNil(
				InteractiveSounds.url(for: cue),
				"Missing packaged sound for \(cue.rawValue).m4a")
		}
	}
}
