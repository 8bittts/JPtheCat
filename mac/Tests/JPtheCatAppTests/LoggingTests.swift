import XCTest

@testable import JPtheCatApp

final class LoggingTests: XCTestCase {
	func testLogCategoriesStayOnCanonicalSubsystem() {
		XCTAssertEqual(Log.subsystem, "com.8bittts.jpthecat")
		XCTAssertEqual(Log.Category.updater.rawValue, "updater")
		XCTAssertEqual(Log.Category.usage.rawValue, "usage")
		XCTAssertEqual(Log.Category.api.rawValue, "api")
		let canonicalLoggers = [Log.updater, Log.usage, Log.api]
		XCTAssertEqual(canonicalLoggers.count, 3)
	}

}
