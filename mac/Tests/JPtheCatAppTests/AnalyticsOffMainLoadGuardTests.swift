import XCTest

@testable import JPtheCatApp

/// [Regression guard — Advanced Analytics stalled the main thread on open]
///
/// `AdvancedAnalyticsTrayView` is a `View`, and in Swift 6 that conformance infers `@MainActor` onto the
/// WHOLE type — static members included. An unstructured `Task { }` INHERITS the enclosing actor, so the
/// tray's `reload()`/`export()` ran two unbounded `UsageIndex` SQL scans (under `withConnectionLock`) plus
/// a full `CopilotProvider().loadEvents()` synchronously on the main thread, while the file's own guard
/// comment claimed the load was detached. It also made `loadTask?.cancel()` and
/// `.onDisappear { loadTask?.cancel() }` dead code: with no suspension point before the scan finished,
/// nothing could ever observe the cancellation.
///
/// This is a SOURCE scan because the isolation bug is invisible at runtime from a test — the work still
/// produces the right rows, just on the wrong thread. `Task.detached` + `nonisolated static` are the two
/// halves of the fix, and both are cheap to delete by accident.
final class AnalyticsOffMainLoadGuardTests: XCTestCase {

	private func trayViewSource() throws -> String {
		let url = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // JPtheCatAppTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // mac
			.appendingPathComponent("Sources/JPtheCatApp/AdvancedAnalyticsWindow.swift")
		return try String(contentsOf: url, encoding: .utf8)
	}

	/// Every unstructured task in the analytics window must be `Task.detached`; a bare `Task {` would run
	/// on the main actor again.
	func testTrayNeverSpawnsAnActorInheritingTask() throws {
		let source = try trayViewSource()
		for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
			let code = line.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0]
			XCTAssertFalse(
				code.contains("Task {") || code.contains("Task{"),
				"AdvancedAnalyticsWindow.swift:\(offset + 1) spawns a bare `Task {` — it inherits the "
					+ "View's inferred @MainActor and runs the UsageIndex scans on the main thread. "
					+ "Use `Task.detached(priority: .utility)`.")
		}
		XCTAssertTrue(
			source.contains("Task.detached(priority: .utility)"),
			"the analytics load/export must run off-main via `Task.detached`")
	}

	/// The scan bodies themselves must stay off the main actor, or `Task.detached` would just hop back.
	func testLoadHelpersStayNonisolated() throws {
		let source = try trayViewSource()
		for helper in ["loadData", "loadRows"] {
			XCTAssertTrue(
				source.contains("nonisolated static func \(helper)("),
				"`\(helper)` must be declared `nonisolated static` — a View's inferred @MainActor "
					+ "otherwise pulls the UsageIndex scan back onto the main thread")
		}
	}

	/// The cancellation path is only real while the detached body checks it before publishing.
	func testDetachedLoadStillHonorsCancellation() throws {
		let source = try trayViewSource()
		XCTAssertTrue(source.contains("guard !Task.isCancelled else { return }"))
		XCTAssertTrue(source.contains(".onDisappear { loadTask?.cancel() }"))
	}
}
