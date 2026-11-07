import Darwin
import JPtheCatCore
import XCTest

@testable import JPtheCatApp

final class WidgetExtensionRetirerTests: XCTestCase {
	/// The live process listing must find the test process itself by its executable name, with the path
	/// it was launched from, so an empty result can never pass as "nothing stale".
	func testProcessListingFindsTheCurrentProcess() throws {
		var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
		XCTAssertGreaterThan(proc_pidpath(getpid(), &buffer, UInt32(buffer.count)), 0)
		let ownPath = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
		let ownName = (ownPath as NSString).lastPathComponent

		let found = WidgetExtensionRetirer.runningProcesses(named: ownName)
		XCTAssertTrue(found.contains { $0.pid == getpid() && $0.executablePath == ownPath }, "\(found)")
		XCTAssertTrue(WidgetExtensionRetirer.runningProcesses(named: "no-such-executable-\(UUID())").isEmpty)
	}

	/// Replays a Sparkle install against a real running process: move its bundle into the staging folder,
	/// install a new copy at the old path, delete the moved copy. `proc_pidpath` then either names the
	/// installed path, where a file exists (measured on a real update), or fails, so only the mapped-region
	/// path shows the process is stale.
	func testProcessMovedAwayBySparkleIsReportedAtItsStagingPathAndRetired() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-retirer-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let installedApp = root.appendingPathComponent("Applications/JPtheCat.app", isDirectory: true)
		let macOS = installedApp.appendingPathComponent(
			"Contents/PlugIns/JPtheCatWidgetExtension.appex/Contents/MacOS", isDirectory: true)
		try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
		let executable = macOS.appendingPathComponent(WidgetExtensionRetirer.executableName)
		try compileSleeper(to: executable)

		let child = Process()
		child.executableURL = executable
		try child.run()
		defer { if child.isRunning { child.terminate() } }
		Thread.sleep(forTimeInterval: 0.3)

		let staging = root.appendingPathComponent(
			"Caches/com.8bittts.jpthecat/org.sparkle-project.Sparkle/Installation/abc", isDirectory: true)
		try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
		let moved = staging.appendingPathComponent("JPtheCat.app", isDirectory: true)
		try FileManager.default.moveItem(at: installedApp, to: moved)
		try FileManager.default.copyItem(at: moved, to: installedApp)
		try FileManager.default.removeItem(at: moved)

		let listed = try XCTUnwrap(
			WidgetExtensionRetirer.runningProcesses(named: WidgetExtensionRetirer.executableName)
				.first { $0.pid == child.processIdentifier })
		XCTAssertTrue(
			listed.executablePath.contains("/org.sparkle-project.Sparkle/Installation/abc/"),
			"reported \(listed.executablePath)")
		XCTAssertEqual(
			StaleWidgetExtension.stale(
				[listed], executableName: WidgetExtensionRetirer.executableName,
				fileExists: { FileManager.default.fileExists(atPath: $0) }),
			[child.processIdentifier])
	}

	/// A tiny native stand-in for the extension. A copied system binary cannot stand in: macOS kills a
	/// platform binary run from another path.
	private func compileSleeper(to executable: URL) throws {
		let source = executable.deletingLastPathComponent().appendingPathComponent("sleeper.c")
		try "#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n"
			.write(to: source, atomically: true, encoding: .utf8)
		let cc = Process()
		cc.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
		cc.arguments = ["-o", executable.path, source.path]
		try cc.run()
		cc.waitUntilExit()
		XCTAssertEqual(cc.terminationStatus, 0, "cc failed to build the stand-in")
		try FileManager.default.removeItem(at: source)
	}

	/// Every launch retires a stale extension, because a Sparkle update always ends in a relaunch.
	func testLaunchRetiresStaleWidgetExtensions() throws {
		let source = try String(
			contentsOf: URL(fileURLWithPath: #filePath)
				.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
				.appendingPathComponent("Sources/JPtheCatApp/AppDelegate.swift"),
			encoding: .utf8)
		let launch = try XCTUnwrap(source.range(of: "func applicationDidFinishLaunching"))
		let reopen = try XCTUnwrap(source.range(of: "func applicationShouldHandleReopen"))
		XCTAssertTrue(source[launch.upperBound..<reopen.lowerBound].contains("WidgetExtensionRetirer.retireStaleProcesses()"))
		XCTAssertEqual(WidgetExtensionRetirer.executableName, "JPtheCatWidgetExtension")
	}
}
