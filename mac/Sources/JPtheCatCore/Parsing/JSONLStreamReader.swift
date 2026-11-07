import Foundation

/// Streams a (possibly multi-GB) JSONL file line-by-line in fixed chunks, never loading the
/// whole file into memory via `String(contentsOf:)` or `readToEnd()` — a single Claude session
/// log on this machine already measures 81,910,350 bytes (~78MB) and the corpus is GBs.
///
/// [CRITICAL] Every chunk loop here MUST stay wrapped in `autoreleasepool`. `FileHandle`'s
/// `read(upToCount:)` hands back an autoreleased bridged `Data`, so without a per-chunk pool
/// every chunk survives until the CALLER's pool drains: reading the 82MB log above peaked
/// +78MB of pure autorelease residue on top of a logical buffer that never exceeded 1.27MB.
/// A pool in the calling provider cannot fix it — the accumulation happens WITHIN one file.
public struct JSONLStreamReader: Sendable {
	public let chunkSize: Int
	private let scanObserver: (@Sendable (Int) -> Void)?

	public init(chunkSize: Int = 64 * 1024) {
		self.chunkSize = chunkSize
		self.scanObserver = nil
	}

	init(chunkSize: Int, scanObserver: @escaping @Sendable (Int) -> Void) {
		self.chunkSize = chunkSize
		self.scanObserver = scanObserver
	}

	public static func firstMatchingTail<Result>(
		fileURL: URL, maxBytes: UInt64 = 1_048_576, parse: (Data) -> Result?
	) -> Result? {
		matchingTail(fileURL: fileURL, maxBytes: maxBytes, limit: 1, parse: parse).first
	}

	/// Returns up to `limit` matching records from newest to oldest within the bounded tail.
	/// Callers that need to classify a newest record against its immediate predecessor can do so
	/// without loading or scanning a multi-GB JSONL file.
	public static func matchingTail<Result>(
		fileURL: URL, maxBytes: UInt64 = 1_048_576, limit: Int, parse: (Data) -> Result?
	) -> [Result] {
		guard limit > 0 else { return [] }
		guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
		defer { try? handle.close() }
		do {
			let size = try handle.seekToEnd()
			let start = size > maxBytes ? size - maxBytes : 0
			try handle.seek(toOffset: start)
			guard var data = try handle.readToEnd(), !data.isEmpty else { return [] }
			let newline = UInt8(ascii: "\n")
			if start > 0 {
				guard let firstNewline = data.firstIndex(of: newline) else { return [] }
				data.removeSubrange(data.startIndex...firstNewline)
			}
			var results: [Result] = []
			var lineEnd = data.endIndex
			while lineEnd > data.startIndex {
				if data[data.index(before: lineEnd)] == newline {
					lineEnd = data.index(before: lineEnd)
					continue
				}
				let separator = data[..<lineEnd].lastIndex(of: newline)
				let lineStart = separator.map { data.index(after: $0) } ?? data.startIndex
				if lineStart < lineEnd, let result = parse(data.subdata(in: lineStart..<lineEnd)) {
					results.append(result)
					if results.count == limit { break }
				}
				guard let separator else { break }
				lineEnd = separator
			}
			return results
		} catch {
			return []
		}
	}

	/// Calls `onLine` with the raw bytes of each newline-terminated line.
	public func read(fileURL: URL, onLine: (Data) -> Void) {
		guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
		defer { try? handle.close() }
		var buffer = Data()
		var scannedPrefix = 0
		var done = false
		while !done {
			// The pool is load-bearing, not hygiene — see the type comment. `break` cannot cross
			// the closure boundary, so EOF and a mid-read IO error both set `done` and `return`.
			autoreleasepool {
				// Throwing read (not readData) so a mid-read IO error skips the file instead of
				// raising an uncatchable ObjC exception.
				let chunk: Data
				do { chunk = try handle.read(upToCount: chunkSize) ?? Data() } catch {
					done = true
					return
				}
				if chunk.isEmpty {
					done = true
					return
				}
				buffer.append(chunk)
				_ = Self.drainCompleteLines(
					from: &buffer, scannedPrefix: &scannedPrefix,
					scanObserver: scanObserver, onLine: onLine)
			}
		}
		if !buffer.isEmpty { onLine(buffer) }
	}

	/// Reads from byte `offset` to EOF, calling `onLine` for each COMPLETE (newline-terminated) line,
	/// and returns the offset just past the last complete line. A trailing partial line (a file being
	/// actively appended to) is left unconsumed so it is re-read whole once its newline arrives.
	/// Real Claude/Codex JSONL files end in `\n`, so a completed file's every line is consumed and
	/// the returned offset equals its size.
	///
	/// [CRITICAL] This is the path EVERY never-before-seen file takes (`FileCursor.classify` returns
	/// `.reset`, which `UsageIndexer` maps to `from: 0`), so it must stay chunked — a `readToEnd()`
	/// here allocates the whole remainder contiguously and cost +78MB on the 82MB log.
	@discardableResult
	public func read(fileURL: URL, from offset: Int, onLine: (Data) -> Void) -> Int {
		guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return offset }
		defer { try? handle.close() }
		do { try handle.seek(toOffset: UInt64(max(0, offset))) } catch { return offset }

		var consumed = offset
		var buffer = Data()
		var scannedPrefix = 0
		var done = false
		var readFailed = false
		while !done {
			autoreleasepool {
				let chunk: Data
				do { chunk = try handle.read(upToCount: chunkSize) ?? Data() } catch {
					readFailed = true
					done = true
					return
				}
				if chunk.isEmpty {
					done = true
					return
				}
				buffer.append(chunk)
				consumed += Self.drainCompleteLines(
					from: &buffer, scannedPrefix: &scannedPrefix,
					scanObserver: scanObserver, onLine: onLine)
			}
		}
		// A mid-read IO error is not EOF, so what is left in the buffer is not a trailing partial
		// line: return the cursor just past the last COMPLETE line actually emitted.
		guard !readFailed, !buffer.isEmpty else { return consumed }
		if (try? JSONSerialization.jsonObject(with: buffer)) != nil {
			onLine(buffer)
			consumed += buffer.count
		}
		return consumed
	}

	/// Emits every complete (newline-terminated) non-empty line at the head of `buffer`, removes them,
	/// and returns the byte count consumed (newlines included). Compaction happens ONCE per call
	/// rather than per line so a chunk of short lines costs one memmove, not one per line.
	private static func drainCompleteLines(
		from buffer: inout Data, scannedPrefix: inout Int,
		scanObserver: (@Sendable (Int) -> Void)?, onLine: (Data) -> Void
	) -> Int {
		let newline = UInt8(ascii: "\n")
		var lineStart = buffer.startIndex
		var searchStart = buffer.index(
			buffer.startIndex, offsetBy: min(scannedPrefix, buffer.count))
		while searchStart < buffer.endIndex,
			let idx = buffer[searchStart...].firstIndex(of: newline)
		{
			scanObserver?(buffer.distance(from: searchStart, to: idx) + 1)
			if idx > lineStart { onLine(buffer.subdata(in: lineStart..<idx)) }
			lineStart = buffer.index(after: idx)
			searchStart = lineStart
		}
		if searchStart < buffer.endIndex {
			scanObserver?(buffer.distance(from: searchStart, to: buffer.endIndex))
		}
		// Every retained byte was searched and contained no newline. Resume at the old end after the
		// next append instead of rescanning the entire partial record. A real Grok record on this
		// machine reached 14.5 MB, which made the former per-chunk restart consume one core for minutes.
		scannedPrefix = buffer.distance(from: lineStart, to: buffer.endIndex)
		guard lineStart > buffer.startIndex else { return 0 }
		let consumed = buffer.distance(from: buffer.startIndex, to: lineStart)
		buffer.removeSubrange(buffer.startIndex..<lineStart)
		return consumed
	}
}
