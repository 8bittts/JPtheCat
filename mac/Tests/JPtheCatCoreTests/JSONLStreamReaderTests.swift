import Darwin
import Foundation
import XCTest

@testable import JPtheCatCore

final class JSONLStreamReaderTests: XCTestCase {
	func testMatchingTailStopsAfterRequestedMatchesWithoutSplittingTheWholeTail() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("rollout-test.jsonl")
		let oldLines = (0..<1_000).map { #"{"match":false,"old":\#($0)}"# }
		let contents = (oldLines + [
			#"{"match":true,"value":1}"#,
			#"{"match":false,"recent":true}"#,
			#"{"match":true,"value":2}"#,
		]).joined(separator: "\n") + "\n"
		try Data(contents.utf8).write(to: file)

		var parsedLines = 0
		let values: [Int] = JSONLStreamReader.matchingTail(fileURL: file, limit: 2) { data in
			parsedLines += 1
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			return object?["match"] as? Bool == true ? object?["value"] as? Int : nil
		}

		XCTAssertEqual(values, [2, 1])
		XCTAssertEqual(parsedLines, 3)
	}

	// MARK: - Offset-read parity with the pre-chunking implementation

	/// The chunked `read(fileURL:from:)` replaced a `readToEnd()` implementation whose returned
	/// offset `UsageIndexer` PERSISTS as a cursor, so both the emitted lines and the returned
	/// offset must stay byte-for-byte identical. `referenceReadFromOffset` below is that original
	/// algorithm, kept here purely as the oracle.
	func testOffsetReadMatchesThePreChunkingImplementation() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let cases: [(name: String, body: String)] = [
			("newline-terminated", #"{"a":1}"# + "\n" + #"{"a":2}"# + "\n"),
			("trailing-partial-valid-json", #"{"a":1}"# + "\n" + #"{"a":2}"#),
			("trailing-partial-invalid-json", #"{"a":1}"# + "\n" + #"{"a":2"#),
			("empty", ""),
			("blank-lines-between-records", #"{"a":1}"# + "\n\n\n" + #"{"a":2}"# + "\n"),
			("only-newlines", "\n\n\n"),
			("no-trailing-newline-single-line", #"{"a":1}"#),
			("trailing-partial-bare-json-scalar", #"{"a":1}"# + "\n" + "123"),
			(
				"long-lines-spanning-chunks",
				(0..<40).map { #"{"index":\#($0),"pad":"\#(String(repeating: "x", count: 500))"}"# }
					.joined(separator: "\n") + "\n"
			),
		]

		for (name, body) in cases {
			let file = directory.appendingPathComponent("\(name).jsonl")
			try Data(body.utf8).write(to: file)
			let size = body.utf8.count

			// Small chunk sizes force lines, newlines and the trailing partial to straddle chunks.
			for chunkSize in [1, 2, 7, 64, 4096] {
				for offset in [0, 1, size, size + 5] where offset >= 0 {
					var expectedLines: [Data] = []
					let expectedOffset = referenceReadFromOffset(fileURL: file, offset: offset) {
						expectedLines.append($0)
					}
					var actualLines: [Data] = []
					let actualOffset = JSONLStreamReader(chunkSize: chunkSize)
						.read(fileURL: file, from: offset) { actualLines.append($0) }

					let label = "\(name) chunk=\(chunkSize) offset=\(offset)"
					XCTAssertEqual(actualLines, expectedLines, "lines differ for \(label)")
					XCTAssertEqual(actualOffset, expectedOffset, "offset differs for \(label)")
				}
			}
		}
	}

	func testOffsetReadOnAFullyConsumedFileReturnsItsSize() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("complete.jsonl")
		let body = (0..<50).map { #"{"i":\#($0)}"# }.joined(separator: "\n") + "\n"
		try Data(body.utf8).write(to: file)

		var lines = 0
		let consumed = JSONLStreamReader(chunkSize: 13).read(fileURL: file, from: 0) { _ in lines += 1 }
		XCTAssertEqual(lines, 50)
		XCTAssertEqual(consumed, body.utf8.count)
	}

	func testOffsetReadLeavesAnUnparsableTrailingPartialUnconsumedSoItIsReReadWhole() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("growing.jsonl")
		let complete = #"{"a":1}"# + "\n"
		let partial = #"{"a":2"#
		try Data((complete + partial).utf8).write(to: file)

		var firstPass: [String] = []
		let cursor = JSONLStreamReader(chunkSize: 3).read(fileURL: file, from: 0) {
			firstPass.append(String(decoding: $0, as: UTF8.self))
		}
		XCTAssertEqual(firstPass, [#"{"a":1}"#])
		XCTAssertEqual(cursor, complete.utf8.count)

		// Once the newline arrives the previously-partial line is delivered whole, exactly once.
		try Data((complete + partial + "}\n").utf8).write(to: file)
		var secondPass: [String] = []
		let finalCursor = JSONLStreamReader(chunkSize: 3).read(fileURL: file, from: cursor) {
			secondPass.append(String(decoding: $0, as: UTF8.self))
		}
		XCTAssertEqual(secondPass, [#"{"a":2}"#])
		XCTAssertEqual(finalCursor, (complete + partial + "}\n").utf8.count)
	}

	func testWholeFileReadEmitsEveryNonEmptyLineIncludingATrailingPartial() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("whole.jsonl")
		try Data((#"{"a":1}"# + "\n\n" + #"{"a":2}"# + "\n" + "tail").utf8).write(to: file)

		for chunkSize in [1, 5, 64, 4096] {
			var lines: [String] = []
			JSONLStreamReader(chunkSize: chunkSize).read(fileURL: file) {
				lines.append(String(decoding: $0, as: UTF8.self))
			}
			XCTAssertEqual(lines, [#"{"a":1}"#, #"{"a":2}"#, "tail"], "chunk=\(chunkSize)")
		}
	}

	func testLongRecordIsScannedOnceInsteadOfOncePerChunk() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("huge-line.jsonl")
		let body = #"{"pad":"\#(String(repeating: "x", count: 2 * 1_024 * 1_024))"}"# + "\n"
		try Data(body.utf8).write(to: file)

		let scannedBytes = ScannedByteCounter()
		let reader = JSONLStreamReader(chunkSize: 1_024) { scannedBytes.add($0) }
		var lines = 0
		reader.read(fileURL: file) { _ in lines += 1 }

		XCTAssertEqual(lines, 1)
		XCTAssertEqual(scannedBytes.value, body.utf8.count)
	}

	// MARK: - Memory regression

	/// [CRITICAL] Both entry points must stay O(chunkSize), not O(file). `FileHandle.read(upToCount:)`
	/// returns an autoreleased bridged `Data`, so dropping the per-chunk `autoreleasepool` (or going
	/// back to `readToEnd()`) makes resident bytes track FILE size — measured at +78MB on a real 82MB
	/// Claude session log. The fixture is deliberately far larger than the allowance so an O(file)
	/// regression cannot squeak under it.
	func testReadingAMultiMegabyteFileStaysWithinASmallMultipleOfChunkSize() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("large.jsonl")

		let record = #"{"pad":"\#(String(repeating: "x", count: 900))"}"#
		var body = Data()
		body.reserveCapacity(12 * 1_024 * 1_024)
		while body.count < 12 * 1_024 * 1_024 {
			body.append(Data((record + "\n").utf8))
		}
		try body.write(to: file)
		let fileSize = body.count
		body = Data()

		let reader = JSONLStreamReader()
		// 3MB: comfortably above the ~64KB chunk plus test-harness noise, far below the 12MB file.
		let allowance = 3 * 1_024 * 1_024

		var wholeFileLines = 0
		let wholeFilePeak = peakHeapGrowth { sample in
			reader.read(fileURL: file) { _ in
				wholeFileLines += 1
				if wholeFileLines % 256 == 0 { sample() }
			}
		}
		XCTAssertGreaterThan(wholeFileLines, 0)
		XCTAssertLessThan(
			wholeFilePeak, allowance,
			"read(fileURL:onLine:) grew the heap by \(wholeFilePeak) bytes on a \(fileSize)-byte file"
		)

		var offsetLines = 0
		let offsetPeak = peakHeapGrowth { sample in
			let consumed = reader.read(fileURL: file, from: 0) { _ in
				offsetLines += 1
				if offsetLines % 256 == 0 { sample() }
			}
			XCTAssertEqual(consumed, fileSize)
		}
		XCTAssertEqual(offsetLines, wholeFileLines)
		XCTAssertLessThan(
			offsetPeak, allowance,
			"read(fileURL:from:) grew the heap by \(offsetPeak) bytes on a \(fileSize)-byte file"
		)
	}

	// MARK: - Helpers

	private func makeTemporaryDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	/// Runs `work`, which calls the supplied `sample` closure periodically, and returns the largest
	/// observed growth in live heap bytes over the baseline taken just before `work` started.
	private func peakHeapGrowth(_ work: (_ sample: () -> Void) -> Void) -> Int {
		func liveHeapBytes() -> Int {
			var stats = malloc_statistics_t()
			malloc_zone_statistics(nil, &stats)
			return Int(stats.size_in_use)
		}
		return autoreleasepool {
			let baseline = liveHeapBytes()
			var peak = 0
			work { peak = max(peak, liveHeapBytes() - baseline) }
			return max(peak, liveHeapBytes() - baseline)
		}
	}

	/// The verbatim pre-chunking implementation of `read(fileURL:from:)`, used only as a test oracle.
	private func referenceReadFromOffset(
		fileURL: URL, offset: Int, onLine: (Data) -> Void
	) -> Int {
		guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return offset }
		defer { try? handle.close() }
		do { try handle.seek(toOffset: UInt64(max(0, offset))) } catch { return offset }
		let data = (try? handle.readToEnd()) ?? Data()
		if data.isEmpty { return offset }

		var consumed = offset
		var start = data.startIndex
		let newline = UInt8(ascii: "\n")
		while let idx = data[start...].firstIndex(of: newline) {
			let line = data.subdata(in: start..<idx)
			if !line.isEmpty { onLine(line) }
			consumed += data.distance(from: start, to: idx) + 1
			start = data.index(after: idx)
		}
		if start < data.endIndex {
			let line = data.subdata(in: start..<data.endIndex)
			if (try? JSONSerialization.jsonObject(with: line)) != nil {
				onLine(line)
				consumed += data.distance(from: start, to: data.endIndex)
			}
		}
		return consumed
	}
}

private final class ScannedByteCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var storedValue = 0

	var value: Int {
		lock.lock()
		defer { lock.unlock() }
		return storedValue
	}

	func add(_ count: Int) {
		lock.lock()
		storedValue += count
		lock.unlock()
	}
}
