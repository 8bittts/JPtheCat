import SwiftUI
import JPtheCatCore

extension View {
    /// Apply before the background and inset border so neither changes the label height.
    func labelBadgeLayout() -> some View {
        self.lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, LabelBadgeMetrics.horizontalInset)
            .frame(height: LabelBadgeMetrics.height)
    }
}
