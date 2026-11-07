import AppKit
import SwiftUI
import XCTest
import JPtheCatCore
@testable import JPtheCatApp

final class LabelBadgeLayoutTests: XCTestCase {
    private let words = ["Low", "Medium", "High", "real", "notional", "local", "official", "measured", "est.", "stale", "unavailable", "disabled", "FIRST RUN"]

    @MainActor func testLabelHeightDoesNotDependOnTextFontBorderOrWidthProposal() {
        let fonts = [JPAppFont.micro, JPAppFont.microMedium, JPAppFont.chip]
        for word in words {
            for font in fonts {
                for border in [CGFloat(0), 0.7, 1] {
                    let label = Text(word).font(font).labelBadgeLayout()
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black, lineWidth: border))
                    let host = NSHostingView(rootView: label)
                    XCTAssertEqual(host.fittingSize.height, LabelBadgeMetrics.height, accuracy: 0.01, word)
                    XCTAssertGreaterThan(host.fittingSize.width, LabelBadgeMetrics.horizontalInset * 2)
                    let narrow = NSHostingView(rootView: label.frame(width: 20))
                    XCTAssertEqual(narrow.fittingSize.height, LabelBadgeMetrics.height, accuracy: 0.01, word)
                }
            }
        }
    }
}
