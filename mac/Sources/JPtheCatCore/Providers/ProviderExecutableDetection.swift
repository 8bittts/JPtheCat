import Foundation

/// Shared GUI-safe executable detection for opt-in local providers.
///
/// A LaunchServices-launched app does not inherit the user's interactive shell PATH, so callers pass
/// the executable names they own while this helper supplies the established fixed install locations.
/// A surviving dotfolder is never evidence that a CLI is still installed.
public enum ProviderExecutableDetection {
	public static func defaultSearchDirectories(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> [URL] {
		var directories = [
			URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
			URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
			home.appendingPathComponent(".npm-global/bin", isDirectory: true),
			home.appendingPathComponent(".local/bin", isDirectory: true),
		]
		if let path = ProcessInfo.processInfo.environment["PATH"] {
			directories += path.split(separator: ":").map {
				URL(fileURLWithPath: String($0), isDirectory: true)
			}
		}
		return directories
	}

	public static func containsExecutable(
		named names: [String],
		searchDirectories: [URL] = defaultSearchDirectories()
	) -> Bool {
		searchDirectories.contains { directory in
			names.contains {
				FileManager.default.isExecutableFile(
					atPath: directory.appendingPathComponent($0, isDirectory: false).path)
			}
		}
	}
}
