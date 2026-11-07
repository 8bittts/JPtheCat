import JPtheCatCore
import XCTest

@testable import JPtheCatWidgetExtension

/// "Preview data" must mark sample figures only. The widget gallery shows the stored snapshot when one
/// exists, and it once labeled those real numbers "Preview data".
final class WidgetEntryPreviewLabelTests: XCTestCase {
	func testStoredFiguresAreNeverLabeledPreviewData() {
		let configuration = JPtheCatWidgetConfigurationIntent()
		let real = JPtheCatWidgetTimelineProvider.entry(for: configuration, stored: WidgetPreviewData.snapshot)
		XCTAssertFalse(real.isPreview)

		let sample = JPtheCatWidgetTimelineProvider.entry(for: configuration, stored: nil)
		XCTAssertTrue(sample.isPreview)
		XCTAssertEqual(sample.snapshot.totalToday, WidgetPreviewData.snapshot.totalToday)
	}
}
