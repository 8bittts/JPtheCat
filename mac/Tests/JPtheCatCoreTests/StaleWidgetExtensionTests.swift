import XCTest

@testable import JPtheCatCore

/// Measured on one Mac: after two Sparkle updates, WidgetKit still ran the widget extension from the
/// deleted staging copy of an older release, so placed widgets showed old code until logout.
final class StaleWidgetExtensionTests: XCTestCase {
	private let extensionName = "JPtheCatWidgetExtension"
	private let installed =
		"/Applications/JPtheCat.app/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/MacOS/JPtheCatWidgetExtension"
	private let staged =
		"/Users/u/Library/Caches/com.8bittts.jpthecat/org.sparkle-project.Sparkle/Installation/6Y9C6mLD5/kgBFJSBdz/JPtheCat.app/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/MacOS/JPtheCatWidgetExtension"
	private let devBuild =
		"/Users/u/Documents/JPtheCat/workstreams/x/mac/build/local-run/JPtheCat.app/Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/MacOS/JPtheCatWidgetExtension"

	func testRetiresSparkleStagingCopiesAndDeletedBinariesOnly() {
		let existing: Set<String> = [installed, devBuild]
		let processes = [
			StaleWidgetExtension.Process(pid: 10, executablePath: installed),
			StaleWidgetExtension.Process(pid: 11, executablePath: staged),
			StaleWidgetExtension.Process(pid: 12, executablePath: devBuild),
			StaleWidgetExtension.Process(pid: 13, executablePath: "/private/var/old/JPtheCatWidgetExtension"),
			StaleWidgetExtension.Process(pid: 14, executablePath: "/Applications/Other.app/Contents/MacOS/Other"),
		]
		XCTAssertEqual(
			StaleWidgetExtension.stale(processes, executableName: extensionName, fileExists: existing.contains),
			[11, 13])
	}

	/// A staged copy is stale even while Sparkle has not yet deleted its directory.
	func testStagingCopyIsStaleEvenWhileItStillExists() {
		let processes = [StaleWidgetExtension.Process(pid: 20, executablePath: staged)]
		XCTAssertEqual(StaleWidgetExtension.stale(processes, executableName: extensionName, fileExists: { _ in true }), [20])
	}

	func testCurrentInstallIsNeverRetired() {
		let processes = [StaleWidgetExtension.Process(pid: 30, executablePath: installed)]
		XCTAssertTrue(StaleWidgetExtension.stale(processes, executableName: extensionName, fileExists: { _ in true }).isEmpty)
	}
}
