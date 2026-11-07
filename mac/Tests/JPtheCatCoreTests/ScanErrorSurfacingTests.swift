import XCTest

@testable import JPtheCatCore

/// Guards the money-path fix: every accumulating scan loop in Core must let a real mid-scan
/// `SQLiteError.step` PROPAGATE (so callers see nothing, or fall back to a fresh log read) rather
/// than collapsing it to loop-end like `SQLITE_DONE`, which silently truncated a partial money total
/// and presented it as authoritative. A regression back to `(try? stmt.step()) == true` — or dropping
/// `throws` from the `UsageIndex` scans — would re-open that silent-truncation hole.
///
/// The sweep is repo-wide and name-agnostic on purpose: it originally read `UsageIndex.swift` alone
/// and asserted one literal statement name, so it stayed green while `MuseSparkProvider` and
/// `OpenCodeProvider` shipped five of the forbidden loops on the same money path.
final class ScanErrorSurfacingTests: XCTestCase {
	func testNoCoreScanLoopSwallowsAStepErrorAsLoopEnd() throws {
		// Anchored on `while` so no allowlist is needed: the legitimate single-row fetches are all
		// `guard`/`if`/continuation forms (one row, nothing to truncate), never loops.
		let forbidden = [
			#"while\s*\(try\?\s*\w+\.step\(\)\)\s*==\s*true"#,
			#"while\s+let\s+\w+\s*=\s*try\?\s*\w+\.step\(\)"#,
		].map { try! NSRegularExpression(pattern: $0) }

		var offenders: [String] = []
		for (path, source) in try coreSources() {
			for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
				let text = String(line)
				let range = NSRange(text.startIndex..., in: text)
				if forbidden.contains(where: { $0.firstMatch(in: text, range: range) != nil }) {
					offenders.append("\(path):\(index + 1): \(text.trimmingCharacters(in: .whitespaces))")
				}
			}
		}
		XCTAssertEqual(
			offenders, [],
			"A scan loop swallows a mid-scan SQLite error as SQLITE_DONE — totals can silently truncate:\n"
				+ offenders.joined(separator: "\n"))
	}

	func testUsageIndexScansStayThrowing() throws {
		let source = try String(contentsOf: usageIndexURL(), encoding: .utf8)
		// The six public scan functions must be `throws` so the error can reach the caller (which then
		// returns empty / falls back), instead of being masked inside a non-throwing function.
		for signature in [
			") throws -> UsageRollup {",
			") throws -> [Double] {",
			") throws -> UsageWindowSummaries {",
			") throws -> [ModelDaySummary] {",
			") throws -> [ProviderID: HourWeekdayMatrix] {",
			") throws -> UsageMultiWindowSummaries {",
		] {
			XCTAssertTrue(source.contains(signature), "Missing throwing scan signature: \(signature)")
		}
	}

	private func coreRoot() -> URL {
		// #filePath = mac/Tests/JPtheCatCoreTests/ScanErrorSurfacingTests.swift → up 3 = mac/
		let macRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		return macRoot.appendingPathComponent("Sources/JPtheCatCore")
	}

	private func usageIndexURL() -> URL {
		coreRoot().appendingPathComponent("Persistence/UsageIndex.swift")
	}

	private func coreSources() throws -> [(path: String, source: String)] {
		let root = coreRoot()
		guard let walker = FileManager.default.enumerator(atPath: root.path) else {
			XCTFail("JPtheCatCore sources not found at \(root.path)")
			return []
		}
		var out: [(String, String)] = []
		for case let relative as String in walker where relative.hasSuffix(".swift") {
			out.append((relative, try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)))
		}
		XCTAssertGreaterThan(out.count, 20, "scan found almost no sources — the guard would pass vacuously")
		return out
	}
}
