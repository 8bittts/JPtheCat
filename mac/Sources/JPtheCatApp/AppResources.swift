import AppKit
import Foundation
import JPtheCatCore

enum AppResources {
	static var bundle: Bundle? { JPResourceBundle.bundle(named: "JPtheCatApp") }

	static func url(forResource name: String, withExtension ext: String?) -> URL? {
		JPResourceBundle.url(forResource: name, withExtension: ext, in: "JPtheCatApp")
	}

	static func image(forResource name: String) -> NSImage? {
		bundle?.image(forResource: name)
	}

	/// Memoized provider-mark loader. `NSImage(contentsOf:)` performs NO caching, so every call re-read
	/// and re-decoded a `provider-*.svg` off disk. Both call sites sit directly in a SwiftUI `body`
	/// (`SelectorRow.icon(_:)`, `AnalyticsProviderMark.icon(_:)`), which re-runs on every hover in/out
	/// and on every refresh, so the decode ran continuously during normal use.
	///
	/// This is the second half of the fix `JPResourceBundle` started: that type memoized the BUNDLE
	/// lookup after `SelectorRow.icon(_:)` showed up on the profiler, but left the image decode uncached.
	///
	/// Bounded by construction — the key space is the provider marks plus the JP mark. Only successful
	/// lookups are cached, matching `JPResourceBundle.bundle(named:)`, so a call made before resources
	/// are stageable retries instead of latching a permanent `nil`.
	private static let iconCacheLock = NSLock()
	nonisolated(unsafe) private static var cachedIcons: [String: NSImage] = [:]
	/// Counts real disk loads. Identity alone cannot prove the cache works, so the guard test asserts
	/// on this instead — the same reasoning as `JPResourceBundle.candidateWalkCount`.
	nonisolated(unsafe) private static var iconLoadCount = 0

	/// Number of on-disk icon decodes performed process-wide. Guard hook for `AppResourcesIconCacheTests`.
	static var iconDiskLoadCount: Int {
		iconCacheLock.lock()
		defer { iconCacheLock.unlock() }
		return iconLoadCount
	}

	/// Provider marks are white SVG glyphs (`provider-*.svg`); NSImage renders SVG with correct
	/// transparency on macOS 14. Falls back to a bundled raster (e.g. the JP mark PNG).
	static func icon(named name: String) -> NSImage? {
		iconCacheLock.lock()
		let hit = cachedIcons[name]
		iconCacheLock.unlock()
		if let hit { return hit }

		iconCacheLock.lock()
		iconLoadCount += 1
		iconCacheLock.unlock()

		let loaded: NSImage?
		if let url = url(forResource: name, withExtension: "svg"), let img = NSImage(contentsOf: url) {
			loaded = img
		} else {
			loaded = image(forResource: name)
		}

		if let loaded {
			iconCacheLock.lock()
			cachedIcons[name] = loaded
			iconCacheLock.unlock()
		}
		return loaded
	}
}
