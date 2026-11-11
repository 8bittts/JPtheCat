import Foundation
import XCTest

/// Per-model weekly windows (Claude Code's `model_scoped` rows, such as the server label "Fable",
/// and a legacy `seven_day_sonnet`) are deliberately scoped to PROVIDER DETAIL only.
///
/// The menu bar, the widget, and the 80%/95% attention border all stay on the PLAN-WIDE window a user
/// actually budgets by. A per-model bar is a narrower cap that is routinely at 100% while the plan is
/// nowhere near its limit (exactly the state in the screenshot that prompted this feature: all-models
/// 87%, Fable 100%), so promoting it into the pill would read as "you are out of Claude" and would
/// trip the attention border every week. This is an explicit exclusion, not an oversight — per the
/// widget-audit requirement, the answer is recorded here rather than left implicit.
final class ModelScopedWindowScopeTests: XCTestCase {
	/// The menu-bar and widget payloads must carry no per-model window field at all — the strongest
	/// form of the exclusion, since a field that does not exist cannot leak into the pill or a face.
	func testMenuBarAndWidgetPayloadsCarryNoPerModelWindow() throws {
		let carriers = [
			"MenuBarLabelRenderer.swift", "StatusBarController.swift", "WidgetSnapshot.swift",
			"DashboardWidgetPublisher.swift", "WidgetComponents.swift",
		]
		let sources = try swiftSources()
		var checked = 0
		for (path, source) in sources {
			guard carriers.contains((path as NSString).lastPathComponent) else { continue }
			checked += 1
			XCTAssertFalse(
				source.contains("modelWindows"),
				"\(path) reads modelWindows: per-model caps belong in provider detail, not the pill/widget")
			XCTAssertFalse(source.contains("seven_day_"), "\(path) hardcodes a per-model rate-limit key")
		}
		XCTAssertEqual(
			checked, carriers.count,
			"a menu-bar/widget carrier was renamed — the guard would otherwise pass vacuously")
	}

	/// Provider detail is the ONE surface allowed to render them, so the exclusion above is meaningful
	/// rather than "nothing renders it anywhere".
	func testProviderDetailIsTheOneSurfaceThatRendersThem() throws {
		let renderers = try swiftSources()
			.filter { $0.source.contains("row.modelWindows") }
			.map { ($0.path as NSString).lastPathComponent }
			.sorted()
		XCTAssertEqual(renderers, ["ProviderDetailView.swift"])
	}

	private func swiftSources() throws -> [(path: String, source: String)] {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatAppTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.appendingPathComponent("Sources")
		guard let walker = FileManager.default.enumerator(atPath: root.path) else {
			XCTFail("Sources/ not found at \(root.path)")
			return []
		}
		var out: [(String, String)] = []
		for case let relative as String in walker where relative.hasSuffix(".swift") {
			let url = root.appendingPathComponent(relative)
			out.append((relative, try String(contentsOf: url, encoding: .utf8)))
		}
		XCTAssertGreaterThan(out.count, 20, "scan found almost no sources — the guard would pass vacuously")
		return out
	}
}
