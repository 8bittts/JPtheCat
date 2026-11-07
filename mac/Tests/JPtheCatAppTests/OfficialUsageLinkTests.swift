import XCTest

@testable import JPtheCatApp

final class OfficialUsageLinkTests: XCTestCase {
	func testVerifiedProviderUsageDestinations() {
		let expected = [
			"claude": "https://claude.ai/settings/usage",
			"codex": "https://chatgpt.com/settings/usage?tab=overview",
			"grok_bot": "https://grok.com/dashboard",
			"muse_spark": "https://dev.meta.ai/usage/",
			"copilot": "https://github.com/settings/copilot/features",
			"cursor": "https://cursor.com/dashboard/spending",
		]

		for (provider, url) in expected {
			let sentence = OfficialUsageLink.sentence(for: provider)
			XCTAssertEqual(sentence?.links.map(\.url.absoluteString), [url])
			XCTAssertEqual(sentence?.links.count, 1)
		}
	}

	func testGrokSentenceLinksCursorAndGrok() {
		let sentence = OfficialUsageLink.sentence(for: "grok")
		XCTAssertEqual(sentence?.plainText, "View official Cursor or Grok plan usage.")
		XCTAssertEqual(sentence?.links.map(\.text), ["Cursor", "Grok"])
		XCTAssertEqual(sentence?.links.map(\.url.absoluteString), [
			"https://cursor.com/dashboard/spending",
			"https://grok.com/?_s=usage",
		])
	}

	func testProviderWithoutAccountUsagePageHasNoLink() {
		XCTAssertNil(OfficialUsageLink.sentence(for: "unknown"))
	}

	/// OpenCode's console is per-workspace: both gateway names are links built from the locally
	/// detected ID, and the sentence is absent — never a guessed URL — when no workspace has been logged.
	func testOpenCodeGatewayLinksCarryTheDetectedWorkspace() {
		let wrk = "wrk_01M1PV99CD5YN9VQK5QRN21P9V"
		let sentence = OfficialUsageLink.sentence(for: "opencode", openCodeWorkspaceID: wrk)
		XCTAssertEqual(sentence?.plainText, "View official Zen or Go usage.")
		XCTAssertEqual(sentence?.links.map(\.text), ["Zen", "Go"])
		XCTAssertEqual(sentence?.links.map(\.url.absoluteString), [
			"https://opencode.ai/console/\(wrk)/billing",
			"https://opencode.ai/console/\(wrk)/go",
		])
		XCTAssertEqual(
			OfficialUsageLink.sentence(for: "opencodego", openCodeWorkspaceID: wrk)?.links.map(\.url.absoluteString),
			sentence?.links.map(\.url.absoluteString))
		XCTAssertNil(OfficialUsageLink.sentence(for: "opencode"))
		XCTAssertNil(OfficialUsageLink.sentence(for: "opencodego", openCodeWorkspaceID: nil))
	}
}
