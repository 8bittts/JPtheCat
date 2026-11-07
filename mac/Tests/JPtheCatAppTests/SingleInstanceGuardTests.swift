import XCTest

@testable import JPtheCatApp

final class SingleInstanceGuardTests: XCTestCase {
	func testCanonicalInstalledAppContinuesAndTerminatesNonCanonicalDuplicates() {
		let decision = SingleInstanceGuard.decision(
			currentPID: 10,
			currentExecutablePath: SingleInstanceGuard.canonicalExecutablePath,
			otherInstances: [
				.init(processIdentifier: 11, executablePath: "/tmp/JPtheCat.app/Contents/MacOS/JPtheCat"),
				.init(processIdentifier: 12, executablePath: SingleInstanceGuard.canonicalExecutablePath),
			])

		XCTAssertEqual(decision, .continueAndTerminateOthers([11]))
	}

	func testNonCanonicalAppTerminatesWhenCanonicalAppIsRunning() {
		let decision = SingleInstanceGuard.decision(
			currentPID: 20,
			currentExecutablePath: "/tmp/JPtheCat.app/Contents/MacOS/JPtheCat",
			otherInstances: [
				.init(processIdentifier: 21, executablePath: SingleInstanceGuard.canonicalExecutablePath)
			])

		XCTAssertEqual(decision, .terminateCurrent)
	}

	func testSecondNonCanonicalAppTerminatesInsteadOfCreatingAnotherMenuBarOwner() {
		let decision = SingleInstanceGuard.decision(
			currentPID: 30,
			currentExecutablePath: "/tmp/two/JPtheCat.app/Contents/MacOS/JPtheCat",
			otherInstances: [
				.init(processIdentifier: 31, executablePath: "/tmp/one/JPtheCat.app/Contents/MacOS/JPtheCat")
			])

		XCTAssertEqual(decision, .terminateCurrent)
	}

	/// The guard above only decides what to do once macOS has already launched a second copy —
	/// `LSMultipleInstancesProhibited` is what stops LaunchServices creating one. Parsed, not grepped:
	/// `Info.plist` holds five `<true/>` elements, so a substring check proves nothing about the value.
	func testInfoPlistProhibitsMultipleInstances() throws {
		let plistURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatAppTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.appendingPathComponent("Info.plist")
		let data = try Data(contentsOf: plistURL)
		let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

		XCTAssertEqual(
			plist?["LSMultipleInstancesProhibited"] as? Bool, true,
			"LSMultipleInstancesProhibited must be <true/> — otherwise LaunchServices happily starts a second menu-bar owner")
	}
}
