import Foundation

/// The OpenCode console is per-workspace (`https://opencode.ai/console/<wrk_…>/go`), so a usage link
/// needs the signed-in user's workspace ID. OpenCode never stores it in `auth.json`; the one durable
/// local trace is OpenCode's OWN error text in `log/opencode.log`, which embeds
/// `https://opencode.ai/workspace/<wrk_…>/{go,billing}` whenever a quota or balance is hit.
///
/// Read-only, never network, never a Keychain item. Absent → `nil` → no link (never a guessed URL).
public enum OpenCodeWorkspace {
	static let urlMarker = Data("opencode.ai/workspace/wrk_".utf8)
	static let idLength = 30  // `wrk_` + 26 Crockford base32 characters

	/// The most recently logged workspace ID under `root` (the same root `OpenCodeStorePaths` uses),
	/// cached against the log's `(size, mtime, ctime)` so repeated detail opens do not rescan 30 MB.
	public static func currentID(root: URL = OpenCodeStorePaths.defaultRoot()) -> String? {
		let log = OpenCodeStorePaths.logFile(root: root)
		guard let state = FileCursor.indexedState(fileURL: log) else { return nil }
		if let hit = cache.cached(path: log.path, state: state) { return hit }
		let id = scan(logFile: log)
		cache.store(path: log.path, state: state, id: id)
		return id
	}

	/// Uncached scan: the LAST workspace URL wins, so switching workspaces follows the newest login.
	public static func scan(logFile: URL) -> String? {
		guard let data = try? Data(contentsOf: logFile, options: .mappedIfSafe),
			let marker = data.range(of: urlMarker, options: .backwards)
		else { return nil }
		let start = marker.lowerBound + urlMarker.count - 4  // rewind onto `wrk_`
		let end = start + idLength
		guard end <= data.count, let id = String(data: data[start..<end], encoding: .utf8),
			isWellFormed(id)
		else { return nil }
		return id
	}

	static func isWellFormed(_ id: String) -> Bool {
		guard id.hasPrefix("wrk_"), id.count == idLength else { return false }
		return id.dropFirst(4).allSatisfy { $0.isASCII && ($0.isNumber || $0.isUppercase) }
	}

	private static let cache = WorkspaceIDCache()
}

private final class WorkspaceIDCache: @unchecked Sendable {
	private struct Entry {
		let size: Int
		let mtime: Double
		let ctime: Double
		let id: String?
	}
	private let lock = NSLock()
	private var path: String?
	private var entry: Entry?

	/// Double optional: `.some(nil)` is a cached "no workspace logged yet", `nil` is a cache miss.
	func cached(path: String, state: (size: Int, mtime: Double, ctime: Double)) -> String?? {
		lock.lock()
		defer { lock.unlock() }
		guard self.path == path, let entry, entry.size == state.size, entry.mtime == state.mtime,
			entry.ctime == state.ctime
		else { return nil }
		return .some(entry.id)
	}

	func store(path: String, state: (size: Int, mtime: Double, ctime: Double), id: String?) {
		lock.lock()
		defer { lock.unlock() }
		self.path = path
		entry = Entry(size: state.size, mtime: state.mtime, ctime: state.ctime, id: id)
	}
}
