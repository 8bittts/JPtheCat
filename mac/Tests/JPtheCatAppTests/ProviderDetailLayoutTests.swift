import JPtheCatCore
import XCTest
@testable import JPtheCatApp

final class ProviderDetailLayoutTests: XCTestCase {
    func testModelOrderUsesTokensAcrossPricedAndUnpricedRowsWithoutDroppingTies() {
        let rows = [
            line("z-priced", tokens: 20, cost: 100),
            line("b-free", tokens: 200, cost: nil),
            line("a-priced", tokens: 200, cost: 0.01),
            line("zero", tokens: 0, cost: 0),
            line("middle", tokens: 80, cost: 3),
        ]
        let sorted = ProviderDetailLayout.modelsByUsage(rows)
        XCTAssertEqual(sorted.map(\.model), ["a-priced", "b-free", "middle", "z-priced", "zero"])
        XCTAssertEqual(sorted.reduce(0) { $0 + $1.usage.total }, 500)
        XCTAssertNil(sorted[1].cost)
        XCTAssertEqual(sorted[3].cost, 100)
        XCTAssertEqual(ProviderDetailLayout.modelsByUsage([]).count, 0)
        XCTAssertEqual(ProviderDetailLayout.modelsByUsage([rows[0]]).map(\.model), ["z-priced"])
    }

    func testScopedWindowsSortByReportedUsageWithStableTiesAndRetainResetDates() {
        let reset = Date(timeIntervalSince1970: 2_000_000_000)
        let rows = [window("z", percent: 12, reset: reset),
                    window("b", percent: 90, reset: reset),
                    window("a", percent: 90, reset: reset)]
        let sorted = ProviderDetailLayout.windowsByUsage(rows)
        XCTAssertEqual(sorted.map(\.id), ["a", "b", "z"])
        XCTAssertEqual(sorted.map { $0.window.usedPercent }, [90, 90, 12])
        XCTAssertTrue(sorted.allSatisfy { $0.window.resetsAt == reset })
        XCTAssertTrue(ProviderDetailLayout.windowsByUsage([]).isEmpty)
    }

    private func line(_ name: String, tokens: Int, cost: Double?) -> DashboardViewModel.ModelLine {
        .init(model: name, cost: cost, usage: TokenUsage(input: tokens), eventCount: 1)
    }

    private func window(_ key: String, percent: Double, reset: Date) -> ModelScopedRateLimitWindow {
        .init(key: key, window: RateLimitWindow(usedPercent: percent, windowMinutes: 10080, resetsAt: reset))
    }
}
