import SwiftUI

enum JPTooltip {
	static func pinDashboard(isPinned: Bool) -> String {
		isPinned ? "Let other windows cover the dashboard" : "Keep the dashboard above every screen"
	}

	static func dashboardLayout(current: DashboardLayout) -> String {
		"\(current.title) — click for \(current.next.title.lowercased())"
	}
}

extension View {
	func jpTooltip(_ text: String) -> some View {
		help(text)
	}
}
