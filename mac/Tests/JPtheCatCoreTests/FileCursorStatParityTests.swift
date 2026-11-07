import Foundation
import XCTest

@testable import JPtheCatCore

/// [CRITICAL correctness guard] `UsageIndexer` reads `(size, mtime, ctime)` from ONE `stat(2)` via
/// `FileCursor.state(fileURL:)` instead of `FileManager.attributesOfItem`. Every already-persisted
/// `cursors.mtime` was written from `attributesOfItem[.modificationDate].timeIntervalSince1970`, and
/// `FileCursor.classify` compares it with `==` — so the replacement must be BIT-EXACT, not merely
/// close. A single ULP of drift invalidates cursors en masse and forces a full-corpus re-fingerprint.
///
/// Measured on the real 10,351-file local corpus: the naive `Double(tv_sec) + Double(tv_nsec)/1e9`
/// form mismatches Foundation on 2,569 files (24.82%); the shipped reference-epoch form on 0.
final class FileCursorStatParityTests: XCTestCase {
  private func makeFile(_ dir: URL, _ name: String, bytes: Int) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try Data(repeating: 0x41, count: bytes).write(to: url)
    return url
  }

  private func setNanosecondMtime(_ url: URL, seconds: Int, nanoseconds: Int) throws {
    var times = [timespec(tv_sec: seconds, tv_nsec: nanoseconds), timespec(tv_sec: seconds, tv_nsec: nanoseconds)]
    let result = url.path.withCString { utimensat(AT_FDCWD, $0, &times, 0) }
    try XCTSkipIf(result != 0, "utimensat unavailable in this environment")
  }

  /// Sweeps fractional-second values, which is exactly where the two derivations diverge.
  func testStatMtimeIsBitIdenticalToFileManagerAcrossANanosecondSweep() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("jpc-statparity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Deterministic spread over the fractional range plus the exact-second boundaries.
    let nanos = [0, 1, 999, 1_000, 500_000_000, 123_456_789, 999_999_999, 987_654_321, 1_000_00]
    let secondsBase = 1_783_000_000

    var compared = 0
    for (i, ns) in nanos.enumerated() {
      for secOffset in [0, 1, 61, 3607] {
        let url = try makeFile(dir, "f-\(i)-\(secOffset).bin", bytes: 16 + i)
        try setNanosecondMtime(url, seconds: secondsBase + secOffset, nanoseconds: ns)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let foundation = try XCTUnwrap((attrs[.modificationDate] as? Date)?.timeIntervalSince1970)
        let foundationSize = try XCTUnwrap((attrs[.size] as? NSNumber)?.intValue)
        let live = try XCTUnwrap(FileCursor.state(fileURL: url))

        XCTAssertEqual(
          live.mtime.bitPattern, foundation.bitPattern,
          """
          BIT-EXACT parity is required: cursors.mtime was persisted from Foundation and compared \
          with ==. ns=\(ns) secOffset=\(secOffset) stat=\(live.mtime) foundation=\(foundation)
          """)
        XCTAssertEqual(live.size, foundationSize)
        compared += 1
      }
    }
    XCTAssertGreaterThan(compared, 30, "the sweep must actually run")
  }

  /// NEGATIVE CONTROL. Pins the naive derivation as genuinely divergent, so nobody "simplifies"
  /// `FileCursor.state`'s mtime back to `Double(tv_sec) + Double(tv_nsec)/1e9` and finds the parity
  /// test still green. If this ever stops failing, the parity test above has stopped proving anything.
  func testTheNaiveDerivationGenuinelyDivergesSoTheParityGuardIsNotVacuous() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("jpc-statnaive-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    var divergences = 0
    var checked = 0
    for (i, ns) in [1, 999, 123_456_789, 999_999_999, 987_654_321, 333_333_333].enumerated() {
      let url = try makeFile(dir, "n-\(i).bin", bytes: 8)
      try setNanosecondMtime(url, seconds: 1_783_000_000 + i, nanoseconds: ns)

      var info = stat()
      guard stat(url.path, &info) == 0 else { continue }
      let naive =
        Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
      let foundation = try XCTUnwrap(
        (try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
          .timeIntervalSince1970)
      checked += 1
      if naive.bitPattern != foundation.bitPattern { divergences += 1 }
    }
    XCTAssertGreaterThan(checked, 0)
    XCTAssertGreaterThan(
      divergences, 0,
      """
      The naive derivation must still diverge from Foundation somewhere in this sweep. If it no \
      longer does, `testStatMtimeIsBitIdenticalToFileManagerAcrossANanosecondSweep` has become \
      vacuous and can no longer catch a regression to the naive form.
      """)
  }

  /// ctime deliberately keeps the naive form — every persisted `cursors.ctime` was written that way
  /// by `changeTime`, and it is only ever compared against itself. Switching it would make ~25% of
  /// cursors miss the cheap skip once, for no benefit.
  func testChangeTimeAndStateAgreeOnCtimeSoPersistedCursorsKeepMatching() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("jpc-statctime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let url = try makeFile(dir, "c.bin", bytes: 32)
    let legacy = try XCTUnwrap(FileCursor.changeTime(fileURL: url))
    let live = try XCTUnwrap(FileCursor.state(fileURL: url))
    XCTAssertEqual(
      live.ctime.bitPattern, legacy.bitPattern,
      "state() must reproduce changeTime() exactly, or every persisted cursor.ctime stops matching")
  }
}
