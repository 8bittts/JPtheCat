import XCTest

/// App and widget code logs through `os.Logger` (`Log` in the app), never `NSLog` or `print`:
/// those bypass the subsystem and category a field report is filtered by. The CLI prints its
/// output on purpose and is out of scope.
final class UnifiedLoggingGuardTests: XCTestCase {
	func testAppAndWidgetSourcesNeverCallNSLogOrPrint() throws {
		let sources = repoRoot().appendingPathComponent("mac/Sources")
		var scanned = 0
		var offenders: [String] = []
		for target in ["JPtheCatApp", "JPtheCatCore", "JPtheCatWidgetExtension"] {
			let directory = sources.appendingPathComponent(target)
			let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
			for case let file as URL in files where file.pathExtension == "swift" {
				scanned += 1
				let text = try String(contentsOf: file, encoding: .utf8)
				for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
					let code = line.trimmingCharacters(in: .whitespaces)
					if code.hasPrefix("//") { continue }
					if code.contains("NSLog(") || code.hasPrefix("print(") {
						offenders.append("\(target)/\(file.lastPathComponent):\(index + 1)")
					}
				}
			}
		}
		XCTAssertGreaterThan(scanned, 100, "the scan must read the real source tree")
		XCTAssertEqual(offenders, [], "use Log.<category> from Log.swift instead")
	}

	private func repoRoot() -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
	}
}
