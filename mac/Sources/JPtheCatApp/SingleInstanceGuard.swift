import AppKit
import Foundation

/// Keeps normal users on one JPtheCat process and prevents local-run/dev bundles from masquerading as
/// the installed app. Launch Services' `LSMultipleInstancesProhibited` is the first line of defense;
/// this runtime guard covers `open -n`, test bundles, and stale local-run processes with the same bundle
/// identifier.
enum SingleInstanceGuard {
	static let bundleID = "com.8bittts.jpthecat"
	static let canonicalExecutablePath = "/Applications/JPtheCat.app/Contents/MacOS/JPtheCat"

	struct RunningInstance: Equatable {
		var processIdentifier: pid_t
		var executablePath: String?
	}

	/// Returns `true` when this process should terminate because a better existing instance is already
	/// running. If this process is the canonical `/Applications` app, it is allowed to terminate
	/// duplicate non-canonical instances and continue.
	@MainActor
	static func shouldTerminateCurrentProcess() -> Bool {
		let currentPath = Bundle.main.executableURL?.path
		let currentPID = ProcessInfo.processInfo.processIdentifier
		let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
			.map { RunningInstance(processIdentifier: $0.processIdentifier, executablePath: $0.executableURL?.path) }
			.filter { $0.processIdentifier != currentPID }

		let decision = decision(
			currentPID: currentPID,
			currentExecutablePath: currentPath,
			otherInstances: others)

		switch decision {
		case .continueAndTerminateOthers(let processIDs):
			for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
			where processIDs.contains(app.processIdentifier) {
				app.terminate()
			}
			return false
		case .terminateCurrent:
			NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
				.first { $0.processIdentifier != currentPID && $0.executableURL?.path == canonicalExecutablePath }?
				.activate(options: [.activateAllWindows])
			return true
		case .continue:
			return false
		}
	}

	enum Decision: Equatable {
		case `continue`
		case continueAndTerminateOthers([pid_t])
		case terminateCurrent
	}

	static func decision(
		currentPID: pid_t,
		currentExecutablePath: String?,
		otherInstances: [RunningInstance]
	) -> Decision {
		let others = otherInstances.filter { $0.processIdentifier != currentPID }
		guard !others.isEmpty else { return .continue }

		let currentIsCanonical = currentExecutablePath == canonicalExecutablePath

		if currentIsCanonical {
			let nonCanonicalPIDs = others
				.filter { $0.executablePath != canonicalExecutablePath }
				.map(\.processIdentifier)
			return nonCanonicalPIDs.isEmpty ? .continue : .continueAndTerminateOthers(nonCanonicalPIDs)
		}

		return .terminateCurrent
	}
}
