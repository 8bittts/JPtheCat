import Foundation
import XCTest

final class AppDemoParityGuardTests: XCTestCase {
	func testAppDemoParityScriptPassesCurrentSources() throws {
		let root = repoRoot()
		let process = Process()
		process.currentDirectoryURL = root
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["scripts/verify-app-demo-parity.sh"]
		let output = Pipe()
		process.standardOutput = output
		process.standardError = output

		try process.run()
		process.waitUntilExit()

		let data = output.fileHandleForReading.readDataToEndOfFile()
		let text = String(data: data, encoding: .utf8) ?? ""
		XCTAssertEqual(process.terminationStatus, 0, text)
		XCTAssertTrue(text.contains("app-demo parity: ok"))
	}

	func testAppDemoParityScriptCoversNativeAndHomepageChromeSources() throws {
		let source = try String(
			contentsOf: repoRoot().appendingPathComponent("scripts/verify-app-demo-parity.sh"),
			encoding: .utf8)

		for path in [
			"mac/Sources/JPtheCatApp/DashboardView.swift",
			"mac/Sources/JPtheCatApp/SettingsBackView.swift",
			"mac/Sources/JPtheCatApp/WidgetGalleryOpener.swift",
			"mac/Sources/JPtheCatApp/Theme.swift",
			"web/components/site/menubar-demo.tsx",
			"web/components/site/menubar-demo-series.ts",
		] {
			XCTAssertTrue(source.contains(path), "parity script must inspect \(path)")
		}

		for invariant in [
			"chromeControlSize",
			"chromeControlGap",
			"Refresh",
			"Open JP the Cat website",
			"SITE.url",
			"settings chrome",
		] {
			XCTAssertTrue(source.contains(invariant), "parity script must pin \(invariant)")
		}
	}

	/// [CRITICAL] `scripts/verify-app-demo-parity.sh` addresses the native sources by LITERAL PATH, so
	/// splitting one of them silently drops that surface from the mac/web parity scan. Every native
	/// path the script names must still exist — a stale reference fails HERE, naming the file, instead
	/// of leaving the parity gate quietly inspecting nothing.
	func testEveryNativeSourceTheParityScriptNamesStillExists() throws {
		let root = repoRoot()
		let script = try String(
			contentsOf: root.appendingPathComponent("scripts/verify-app-demo-parity.sh"), encoding: .utf8)
		let regex = try NSRegularExpression(pattern: "mac/Sources/[A-Za-z0-9_/]+\\.swift")
		let matches = regex.matches(
			in: script, range: NSRange(script.startIndex..<script.endIndex, in: script))
		let paths = Set(matches.compactMap { Range($0.range, in: script).map { String(script[$0]) } })

		XCTAssertFalse(paths.isEmpty, "the parity script must inspect at least one native source")
		for path in paths.sorted() {
			XCTAssertTrue(
				FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
				"""
				scripts/verify-app-demo-parity.sh reads `\(path)`, which no longer exists. That surface \
				was renamed or split — point the script at its new home in the SAME change, or the \
				mac/web parity scan silently stops covering it.
				""")
		}
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
