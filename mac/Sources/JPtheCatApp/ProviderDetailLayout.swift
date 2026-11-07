import JPtheCatCore
import SwiftUI

/// Layout-only ordering keeps usage totals, quotas, and model identity unchanged.
enum ProviderDetailLayout {
    static func modelsByUsage(_ models: [DashboardViewModel.ModelLine]) -> [DashboardViewModel.ModelLine] {
        models.sorted {
            if $0.usage.total != $1.usage.total { return $0.usage.total > $1.usage.total }
            return $0.model < $1.model
        }
    }

    static func windowsByUsage(_ windows: [ModelScopedRateLimitWindow]) -> [ModelScopedRateLimitWindow] {
        windows.sorted {
            if $0.window.usedPercent != $1.window.usedPercent {
                return $0.window.usedPercent > $1.window.usedPercent
            }
            return $0.id < $1.id
        }
    }
}

/// Each child is one complete cell, so labels, meters, and resets never split across columns.
/// `columnCount` is the most a call site wants; the one-column layout caps every grid at one.
struct DashboardDetailGrid<Content: View>: View {
    var columnCount = 2
    @ViewBuilder var content: () -> Content
    @Environment(\.dashboardLayout) private var layout

    var body: some View {
        LazyVGrid(columns: Array(
            repeating: GridItem(.flexible(), spacing: DashboardSurfaceMetrics.selectorColumnGap, alignment: .topLeading),
            count: layout.columns(upTo: columnCount)
        ), alignment: .leading, spacing: 11) {
            content()
        }
    }
}
