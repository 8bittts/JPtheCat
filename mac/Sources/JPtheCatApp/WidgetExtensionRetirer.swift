import Darwin
import Foundation
import JPtheCatCore
import WidgetKit

/// Retires widget extension processes left running from a replaced app build (see `StaleWidgetExtension`),
/// then asks WidgetKit to rebuild timelines, which relaunches the installed extension on demand.
///
/// Runs at every launch, and a Sparkle update always ends in a relaunch, so the first launch of a new
/// version clears the previous version's extension. Sending SIGTERM is safe: `chronod` restarts a widget
/// extension whenever a widget needs a timeline.
enum WidgetExtensionRetirer {
	static let executableName = "JPtheCatWidgetExtension"

	static func retireStaleProcesses() {
		let stale = StaleWidgetExtension.stale(
			runningProcesses(named: executableName),
			executableName: executableName,
			fileExists: { FileManager.default.fileExists(atPath: $0) })
		guard !stale.isEmpty else { return }
		for pid in stale { kill(pid, SIGTERM) }
		WidgetCenter.shared.reloadAllTimelines()
	}

	/// This user's processes whose executable file is named `name`, with the file each is running.
	static func runningProcesses(named name: String) -> [StaleWidgetExtension.Process] {
		let capacity = proc_listpids(UInt32(PROC_UID_ONLY), UInt32(getuid()), nil, 0)
		guard capacity > 0 else { return [] }
		var pids = [Int32](repeating: 0, count: Int(capacity) / MemoryLayout<Int32>.size + 64)
		let bytes = pids.withUnsafeMutableBytes { buffer in
			proc_listpids(UInt32(PROC_UID_ONLY), UInt32(getuid()), buffer.baseAddress, Int32(buffer.count))
		}
		guard bytes > 0 else { return [] }
		// Match on the process name: `proc_pidpath` fails outright once the running file is deleted.
		var processName = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
		// PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN) is a C macro Swift does not import.
		var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
		return pids.prefix(Int(bytes) / MemoryLayout<Int32>.size).compactMap { pid in
			guard pid > 0, proc_name(pid, &processName, UInt32(processName.count)) > 0,
				processName.withUnsafeBufferPointer({ String(cString: $0.baseAddress!) }) == name
			else { return nil }
			if let mapped = mappedExecutablePath(pid: pid, named: name) {
				return StaleWidgetExtension.Process(pid: pid, executablePath: mapped)
			}
			guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
			let launchPath = path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
			return StaleWidgetExtension.Process(pid: pid, executablePath: launchPath)
		}
	}

	/// Where the file a process runs lives now, read from its mapped executable region.
	///
	/// `proc_pidpath` keeps reporting the launch path. A Sparkle update moves the running bundle into
	/// its staging folder, installs the new build at the old path, and deletes the moved copy, so the
	/// old extension still reports `/Applications/...`, where the new binary exists. Measured on the
	/// 1.130 to 1.131 update: `proc_pidpath` gave the installed path while the mapped region was the
	/// deleted staging copy.
	static func mappedExecutablePath(pid: Int32, named name: String) -> String? {
		var region = proc_regionwithpathinfo()
		let size = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
		var address: UInt64 = 0
		// The executable's `__TEXT` is among the first regions; the bound only stops a runaway walk.
		for _ in 0..<4096 {
			guard proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &region, size) == size else { return nil }
			let path = withUnsafeBytes(of: region.prp_vip.vip_path) {
				String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
			}
			if (path as NSString).lastPathComponent == name { return path }
			address = region.prp_prinfo.pri_address + region.prp_prinfo.pri_size
		}
		return nil
	}
}
