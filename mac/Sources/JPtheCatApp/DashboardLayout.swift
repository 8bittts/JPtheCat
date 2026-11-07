import SwiftUI

/// The dashboard card's column layout, cycled from the top chrome and persisted by `SettingsStore`.
/// One column is the compact 384pt card; two columns place providers, gauges, models, and Settings
/// side by side at 768pt. Both keep intrinsic height and no internal scrolling. Layout never changes
/// accounting, row order, or which information is shown.
enum DashboardLayout: String, CaseIterable, Sendable {
	case oneColumn
	case twoColumns

	static let defaultLayout: DashboardLayout = .twoColumns

	/// 384pt fits the split-flap hero and a week total up to $99,999.99 without wrapping.
	/// 768pt gives each provider column the same row budget as the compact card.
	var width: CGFloat {
		switch self {
		case .oneColumn: 384
		case .twoColumns: 768
		}
	}

	var columnCount: Int {
		switch self {
		case .oneColumn: 1
		case .twoColumns: 2
		}
	}

	/// A grid asks for up to `requested` columns; the layout never grants more than it has.
	func columns(upTo requested: Int) -> Int {
		min(max(1, requested), columnCount)
	}

	var next: DashboardLayout {
		switch self {
		case .oneColumn: .twoColumns
		case .twoColumns: .oneColumn
		}
	}

	var title: String {
		switch self {
		case .oneColumn: "One column"
		case .twoColumns: "Two columns"
		}
	}

	/// The chrome button draws the CURRENT layout, like a collapsed Finder view switcher.
	var systemImage: String {
		switch self {
		case .oneColumn: "rectangle.split.1x2"
		case .twoColumns: "rectangle.split.2x1"
		}
	}

	/// An absent or unknown stored value falls back to the default, never to a crash or a blank card.
	static func normalized(_ raw: String?) -> DashboardLayout {
		raw.flatMap(DashboardLayout.init(rawValue:)) ?? defaultLayout
	}
}

/// `DashboardView` injects the persisted layout once; every face and detail reads it from here.
/// Surfaces hosted outside the dashboard (tests, previews) get the default layout.
private struct DashboardLayoutKey: EnvironmentKey {
	static let defaultValue = DashboardLayout.defaultLayout
}

extension EnvironmentValues {
	var dashboardLayout: DashboardLayout {
		get { self[DashboardLayoutKey.self] }
		set { self[DashboardLayoutKey.self] = newValue }
	}
}
