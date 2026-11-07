import XCTest

@testable import JPtheCatApp

/// Finder, Spotlight, and the widget gallery name the app from its localized `CFBundleDisplayName`, and
/// macOS applies that localization only when the base value matches the bundle's file name. With the base
/// set to "JP the Cat" and no localization, the widget gallery listed the app as "JPtheCat".
final class AppDisplayNameTests: XCTestCase {
	private let macRoot = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

	func testLocalizedNameIsJPTheCatAndTheBaseNameMatchesTheFileName() throws {
		let info = try plist(macRoot.appendingPathComponent("Info.plist"))
		XCTAssertEqual(info["CFBundleDisplayName"] as? String, "JPtheCat")
		XCTAssertEqual(info["CFBundleExecutable"] as? String, "JPtheCat")
		XCTAssertEqual(info["LSHasLocalizedDisplayName"] as? Bool, true)

		let strings = try plist(macRoot.appendingPathComponent("en.lproj/InfoPlist.strings"))
		XCTAssertEqual(strings["CFBundleDisplayName"] as? String, "JP the Cat")
		XCTAssertEqual(strings["CFBundleName"] as? String, "JP the Cat")
		XCTAssertEqual(MainMenu.appName, "JP the Cat")
	}

	func testMacOSShowsTheLocalizedNameOnlyWithTheLocalization() throws {
		XCTAssertTrue(try displayName(localized: true).hasPrefix("JP the Cat"))
		XCTAssertTrue(try displayName(localized: false).hasPrefix("JPtheCat"))
	}

	func testBothBuildScriptsBundleTheLocalization() throws {
		for script in ["scripts/build-dmg.sh", "scripts/build_and_run.sh"] {
			let source = try String(contentsOf: macRoot.appendingPathComponent(script), encoding: .utf8)
			XCTAssertTrue(source.contains("cp -R en.lproj"), "\(script) does not copy en.lproj")
		}
		let smoke = try String(contentsOf: macRoot.appendingPathComponent("scripts/smoke-test.sh"), encoding: .utf8)
		XCTAssertTrue(smoke.contains("localized app name not wired"))
	}

	/// The name macOS gives a throwaway bundle built from the real Info.plist, with or without the strings.
	///
	/// Asking for the name registers the bundle with LaunchServices. It carries a test-only bundle id and is
	/// unregistered before deletion: stray records of the shipping id break `SMAppService` login items.
	private func displayName(localized: Bool) throws -> String {
		let app = FileManager.default.temporaryDirectory
			.appendingPathComponent("jpc-name-\(UUID().uuidString)/JPtheCat.app", isDirectory: true)
		let contents = app.appendingPathComponent("Contents", isDirectory: true)
		defer {
			unregister(app)
			try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
		}
		try FileManager.default.createDirectory(
			at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
		var info = try plist(macRoot.appendingPathComponent("Info.plist"))
		info["CFBundleIdentifier"] = "com.8bittts.jpthecat.display-name-test"
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
			.write(to: contents.appendingPathComponent("Info.plist"))
		if localized {
			try FileManager.default.copyItem(
				at: macRoot.appendingPathComponent("en.lproj"),
				to: contents.appendingPathComponent("Resources/en.lproj"))
		}
		return FileManager.default.displayName(atPath: contents.deletingLastPathComponent().path)
	}

	private func unregister(_ app: URL) {
		let lsregister = Process()
		lsregister.executableURL = URL(
			fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
				+ "LaunchServices.framework/Support/lsregister")
		lsregister.arguments = ["-u", app.path]
		try? lsregister.run()
		lsregister.waitUntilExit()
	}

	private func plist(_ url: URL) throws -> [String: Any] {
		let data = try Data(contentsOf: url)
		return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
	}
}
