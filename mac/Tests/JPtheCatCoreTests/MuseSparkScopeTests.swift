import Foundation
import XCTest

@testable import JPtheCatCore

final class MuseSparkScopeTests: XCTestCase {
	private func stageAuth(metaKey: String?) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-muse-scope-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		var meta: [String: Any] = ["type": "api"]
		if let metaKey { meta["key"] = metaKey }
		let payload: [String: Any] = ["meta": meta]
		let data = try JSONSerialization.data(withJSONObject: payload)
		try data.write(to: root.appendingPathComponent("auth.json"))
		return root
	}

	func testHasMetaAPIKeyConfiguredTrueWhenKeyPresent() throws {
		let root = try stageAuth(metaKey: "sk-test")
		XCTAssertTrue(MuseSparkScope.hasMetaAPIKeyConfigured(opencodeRoot: root))
	}

	func testHasMetaAPIKeyConfiguredFalseWhenAuthMissing() {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("jpc-muse-scope-missing-\(UUID().uuidString)", isDirectory: true)
		XCTAssertFalse(MuseSparkScope.hasMetaAPIKeyConfigured(opencodeRoot: root))
	}

	func testDetailNoteElevatesWhenKeyPresentAndSparseLocalUsage() throws {
		let root = try stageAuth(metaKey: "sk-test")
		let note = MuseSparkScope.detailNote(weekEvents: 1, opencodeRoot: root)
		XCTAssertTrue(note.contains("only 1 turn"))
		XCTAssertTrue(note.contains(MuseSparkScope.baseNote))
	}

	func testDetailNoteUsesBaseWhenUsageIsHealthy() throws {
		let root = try stageAuth(metaKey: "sk-test")
		let note = MuseSparkScope.detailNote(weekEvents: 12, opencodeRoot: root)
		XCTAssertEqual(note, MuseSparkScope.baseNote)
	}

	func testDetailNoteUsesBaseWithoutMetaKey() throws {
		let root = try stageAuth(metaKey: nil)
		let note = MuseSparkScope.detailNote(weekEvents: 1, opencodeRoot: root)
		XCTAssertEqual(note, MuseSparkScope.baseNote)
	}
}