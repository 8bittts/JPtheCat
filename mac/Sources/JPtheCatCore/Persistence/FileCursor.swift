import Foundation

/// The last-ingested state of one data file: its size/mtime (for change detection) and the byte
/// `offset` up to which complete lines were consumed (always a line boundary; a trailing partial
/// line stays unconsumed until it completes).
public struct FileState: Sendable, Equatable {
	public let size: Int
	public let mtime: Double
	public let offset: Int
	public let fingerprint: String
	/// The inode's `ctime` at the time this cursor was last verified — see `FileCursor.changeTime(fileURL:)`.
	/// `0` means "not yet recorded" (a cursor persisted before this field existed), which must NOT be
	/// treated as a real match against a live ctime of `0` (astronomically unlikely but defensively
	/// excluded) — always fall through to a real fingerprint read in that case.
	public let ctime: Double
	/// Which provider owns this cursor. `""` means "not yet recorded" (a cursor persisted before this
	/// column existed); `UsageIndexer.refresh` backfills it on the next pass so the durable-retention
	/// sweep can scope stale-file detection to ONE provider's cursors — see `UsageIndex.cursorPaths`.
	public let provider: String
	/// Revision of the provider parser that produced this cursor. A mismatch forces one full, scoped
	/// reread so parser fixes repair already-indexed rows even when source bytes are unchanged.
	public let parserRevision: Int
	/// Opaque provider-owned state at `offset`. Stateful append parsers use it to resume without
	/// rereading the file prefix. An empty value forces their safe full-read fallback.
	public let parserState: String
	public init(
		size: Int, mtime: Double, offset: Int, fingerprint: String = "", ctime: Double = 0,
		provider: String = "", parserRevision: Int = 1, parserState: String = ""
	) {
		self.size = size
		self.mtime = mtime
		self.offset = offset
		self.fingerprint = fingerprint
		self.ctime = ctime
		self.provider = provider
		self.parserRevision = parserRevision
		self.parserState = parserState
	}
}

/// How a file must be (re)read this refresh.
public enum FileChange: Sendable, Equatable {
	case unchanged  // identical size+mtime -> skip entirely (this is the full-corpus-walk killer)
	case appended(from: Int)  // grew; tail from this offset (append-only providers only)
	case reset  // new / truncated / rotated / in-place rewrite -> read the whole file
}

public enum FileCursor {
	/// Decide how to re-read a file from its current `(size, mtime)` and last ingested `FileState`.
	/// `canTailAppend` is false for providers that cannot resume safely from a mid-file offset.
	public static func classify(
		size: Int, mtime: Double, fingerprint: String = "", stored: FileState?, canTailAppend: Bool
	) -> FileChange {
		guard let stored else { return .reset }  // never seen -> full read
		if size < stored.size { return .reset }  // truncated / rotated -> full read
		if size == stored.size {
			// Same length: unchanged only if the clock and sampled content both agree.
			let sameFingerprint =
				fingerprint.isEmpty || stored.fingerprint.isEmpty || fingerprint == stored.fingerprint
			return mtime == stored.mtime && sameFingerprint ? .unchanged : .reset
		}
		// Grew. Tail only if the provider's parse is line-independent; otherwise re-read whole.
		return canTailAppend ? .appended(from: stored.offset) : .reset
	}

	public static func fingerprint(fileURL: URL, size: Int) -> String {
		guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
		defer { try? handle.close() }

		let sampleSize = min(4096, max(0, size))
		var hash: UInt64 = 14_695_981_039_346_656_037
		func mix(_ data: Data) {
			for byte in data {
				hash ^= UInt64(byte)
				hash &*= 1_099_511_628_211
			}
		}
		if sampleSize > 0, let head = try? handle.read(upToCount: sampleSize) {
			mix(head)
		}
		if size > sampleSize {
			do {
				try handle.seek(toOffset: UInt64(max(0, size - sampleSize)))
				if let tail = try handle.read(upToCount: sampleSize) { mix(tail) }
			} catch {
				return ""
			}
		}
		return "\(size):\(String(hash, radix: 16))"
	}

	/// The inode's change time (`st_ctime`) — bumped by the kernel on ANY metadata-or-content change and,
	/// unlike `mtime`, NOT settable by a plain userspace call (`utimes`/`setattrlist`/`FileManager
	/// .setAttributes(.modificationDate:)` all bump ctime even while explicitly overriding mtime). This
	/// makes (size, mtime, ctime) — unlike (size, mtime) alone — a safe, cheap `stat()`-only signal that a
	/// file genuinely hasn't been touched since it was last read: a tool that deliberately preserves mtime
	/// across a real rewrite (`rsync --times`, `cp -p`, `touch -r`) still bumps ctime, so this correctly
	/// falls through to a real read for exactly the case `UsageIndexTests
	/// .testSameSizeSameMtimeRewriteIsDetected` guards. Returns `nil` if the file can't be stat'd.
	public static func changeTime(fileURL: URL) -> Double? {
		var info = stat()
		guard stat(fileURL.path, &info) == 0 else { return nil }
		return ctimeSeconds(info)
	}

	/// Every field `UsageIndexer`'s skip decision needs, from ONE `stat(2)`.
	///
	/// [Why] ONE `stat(2)` instead of `FileManager.attributesOfItem` (which bridges an 18-entry
	/// `NSDictionary`) plus a separate ctime stat.
	///
	/// It changes HOW the same three numbers are obtained, never WHICH numbers the skip decision
	/// compares: the `(size, mtime, ctime)` triple, the `stored.ctime > 0` requirement, the
	/// `parserRevision` check and the fingerprint fallback are all untouched.
	///
	/// Note this moves size/mtime from `lstat` semantics (what `attributesOfItem` uses) to `stat`,
	/// which FOLLOWS symlinks — making the triple coherent, since ctime was already read via `stat`.
	public static func state(fileURL: URL) -> (size: Int, mtime: Double, ctime: Double)? {
		var info = stat()
		guard stat(fileURL.path, &info) == 0 else { return nil }
		return (Int(info.st_size), mtimeSeconds(info), ctimeSeconds(info))
	}

	/// SQLite commits can change only the WAL while the database inode stays unchanged.
	/// Combine both files for the index cursor, without opening or modifying the source database.
	public static func indexedState(fileURL: URL) -> (size: Int, mtime: Double, ctime: Double)? {
		guard let base = state(fileURL: fileURL) else { return nil }
		guard fileURL.pathExtension == "db",
			let wal = state(fileURL: URL(fileURLWithPath: fileURL.path + "-wal"))
		else { return base }
		return (base.size + wal.size, max(base.mtime, wal.mtime), max(base.ctime, wal.ctime))
	}

	public static func indexedFingerprint(fileURL: URL) -> String {
		guard let base = state(fileURL: fileURL) else { return "" }
		let baseFingerprint = fingerprint(fileURL: fileURL, size: base.size)
		let walURL = URL(fileURLWithPath: fileURL.path + "-wal")
		guard fileURL.pathExtension == "db", let wal = state(fileURL: walURL) else {
			return baseFingerprint
		}
		return baseFingerprint + ":wal:" + fingerprint(fileURL: walURL, size: wal.size)
	}

	/// [CRITICAL — bit-exactness, not approximation] Must reproduce
	/// `FileManager.attributesOfItem[.modificationDate].timeIntervalSince1970` EXACTLY, because every
	/// already-persisted `cursors.mtime` was written from that value and `classify` compares it with
	/// `==`. The obvious `Double(tv_sec) + Double(tv_nsec)/1e9` does NOT: Foundation builds a
	/// `CFAbsoluteTime` against the 2001 reference epoch, and the different rounding order diverges by
	/// 1 ULP, silently invalidating a large fraction of stored cursors and forcing a full-corpus
	/// re-fingerprint. Guarded by `FileCursorStatParityTests`, including a negative control
	/// that pins the naive form as divergent so nobody "simplifies" this back.
	private static func mtimeSeconds(_ info: stat) -> Double {
		Date(
			timeIntervalSinceReferenceDate: Double(info.st_mtimespec.tv_sec)
				- Date.timeIntervalBetween1970AndReferenceDate
				+ Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
		).timeIntervalSince1970
	}

	/// ctime deliberately keeps the NAIVE derivation. Unlike mtime it is only ever compared against
	/// itself — every persisted `cursors.ctime` was written by `changeTime` in exactly this form — so
	/// switching it to the reference-epoch form would change ~25% of live values and make a quarter of
	/// all cursors miss the cheap skip once, on the very upgrade whose point is to make that skip
	/// cheaper. It is money-safe either way (ctime is not an input to `classify`), just needless.
	private static func ctimeSeconds(_ info: stat) -> Double {
		Double(info.st_ctimespec.tv_sec) + Double(info.st_ctimespec.tv_nsec) / 1_000_000_000
	}
}
