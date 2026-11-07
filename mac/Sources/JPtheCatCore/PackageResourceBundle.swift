import Foundation

/// Resolves SwiftPM resource bundles from both a packaged macOS app and local SwiftPM runs/tests.
///
/// SwiftPM's generated package-resource accessor looks beside `Bundle.main.bundleURL`. In a real
/// `.app`, resources live under `Contents/Resources`, so production code must use this resolver.
public enum JPResourceBundle {
	/// Memoized target-name -> bundle. `candidates(bundleName:)` is FULLY eager — it materializes
	/// `Bundle.allBundles` × 8 ancestor directories × 3 shapes plus every `/`-containing argv entry, and
	/// standardizes every path to dedupe, all before the first `Bundle(path:)` probe. That showed up on
	/// the profiler in two places at once: on the main thread inside `SelectorRow.icon(_:)`'s SwiftUI
	/// body, and on the background refresh inside `CostCalculator`'s init. In a signed `.app` the answer
	/// can never change during a process lifetime, which is already `Bundle`'s own effective behavior.
	///
	/// Only successful lookups are cached, so a call made before resources are stageable can still
	/// retry rather than latching a permanent `nil`.
	private static let cacheLock = NSLock()
	nonisolated(unsafe) private static var resolvedBundles: [String: Bundle] = [:]
	/// Counts real candidate walks. Identity alone cannot prove the cache works — `Bundle(path:)`
	/// returns the SAME instance for a given path whether or not we memoize, so an `===` assertion
	/// passes identically with the cache removed. The walk count is the only honest signal.
	nonisolated(unsafe) private static var walkCount = 0

	/// Number of full candidate walks performed process-wide. Guard hook for
	/// `PackageResourceBundleTests.testBundleResolutionIsMemoizedPerTargetName`.
	public static var candidateWalkCount: Int {
		cacheLock.lock()
		defer { cacheLock.unlock() }
		return walkCount
	}

	public static func bundle(named targetName: String) -> Bundle? {
		cacheLock.lock()
		let hit = resolvedBundles[targetName]
		cacheLock.unlock()
		if let hit { return hit }

		cacheLock.lock()
		walkCount += 1
		cacheLock.unlock()

		let bundleName = "JPtheCat_\(targetName).bundle"
		for url in candidates(bundleName: bundleName) {
			if let bundle = Bundle(path: url.path) {
				cacheLock.lock()
				resolvedBundles[targetName] = bundle
				cacheLock.unlock()
				return bundle
			}
		}
		return nil
	}

	public static func url(
		forResource name: String,
		withExtension ext: String?,
		in targetName: String
	) -> URL? {
		bundle(named: targetName)?.url(forResource: name, withExtension: ext)
	}

	private static func candidates(bundleName: String) -> [URL] {
		var urls: [URL] = []

		if let resourceURL = Bundle.main.resourceURL {
			urls.append(resourceURL.appendingPathComponent(bundleName))
		}
		appendCandidates(near: Bundle.main.bundleURL, bundleName: bundleName, into: &urls)
		for bundle in Bundle.allBundles {
			appendCandidates(near: bundle.bundleURL, bundleName: bundleName, into: &urls)
			if let resourceURL = bundle.resourceURL {
				urls.append(resourceURL.appendingPathComponent(bundleName))
			}
		}
		for argument in CommandLine.arguments where argument.contains("/") {
			appendCandidates(near: URL(fileURLWithPath: argument), bundleName: bundleName, into: &urls)
		}

		var seen = Set<String>()
		return urls.filter { url in
			let path = url.standardizedFileURL.path
			return seen.insert(path).inserted
		}
	}

	private static func appendCandidates(near anchor: URL, bundleName: String, into urls: inout [URL]) {
		var directory = anchor.hasDirectoryPath ? anchor : anchor.deletingLastPathComponent()
		for _ in 0..<8 {
			urls.append(directory.appendingPathComponent(bundleName))
			urls.append(directory.appendingPathComponent("Resources").appendingPathComponent(bundleName))
			urls.append(directory.appendingPathComponent("Contents/Resources").appendingPathComponent(bundleName))
			let parent = directory.deletingLastPathComponent()
			if parent.path == directory.path { break }
			directory = parent
		}
	}
}
