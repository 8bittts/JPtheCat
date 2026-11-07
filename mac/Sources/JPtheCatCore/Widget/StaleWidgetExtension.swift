import Foundation

/// A WidgetKit extension process that outlived the app update that replaced its binary.
///
/// Sparkle installs an update by moving the running app into
/// `~/Library/Caches/<bundle id>/org.sparkle-project.Sparkle/Installation/`, putting the new build at the
/// old path, and deleting the moved copy. A widget extension process that `chronod` started earlier keeps
/// running the moved file and renders every placed widget with the older release's code until logout.
/// Measured on one Mac: one such process ran for four days, across the 1.129 and 1.130 updates, and on the
/// 1.130 to 1.131 update the old process outlived the new app's launch.
///
/// A process is stale only when its executable name is ours AND the file it runs is in a Sparkle staging
/// folder or no longer exists. `executablePath` must be where that file is now (its mapped region), not the
/// launch path, which still names the new install. The current install and live development builds are
/// never selected.
public enum StaleWidgetExtension {
	public struct Process: Equatable, Sendable {
		public let pid: Int32
		public let executablePath: String

		public init(pid: Int32, executablePath: String) {
			self.pid = pid
			self.executablePath = executablePath
		}
	}

	/// Path component Sparkle uses for its staged update copies.
	static let sparkleStagingMarker = "/org.sparkle-project.Sparkle/Installation/"

	/// The processes to retire, in input order.
	public static func stale(
		_ processes: [Process], executableName: String, fileExists: (String) -> Bool
	) -> [Int32] {
		processes.compactMap { process in
			guard (process.executablePath as NSString).lastPathComponent == executableName else { return nil }
			let staged = process.executablePath.contains(sparkleStagingMarker)
			return staged || !fileExists(process.executablePath) ? process.pid : nil
		}
	}
}
