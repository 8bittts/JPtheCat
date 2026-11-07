import CoreServices
import Foundation

/// Thin FSEvents wrapper: fires `onChange` (coalesced within `latency` seconds) whenever anything
/// under the watched directory trees changes. FSEvents watches subtrees recursively, so pointing it
/// at a provider's log root catches every nested `*.jsonl` write. `RefreshCoordinator` uses it to
/// refresh the instant a provider writes usage, instead of waiting for the next timer tick.
///
/// The FSEvents callback is delivered on the main dispatch queue; `onChange` hops to the caller's
/// actor. Read-only — it observes the provider log dirs and never writes to them.
final class FileSystemWatcher {
  private var stream: FSEventStreamRef?
  private let onChange: @Sendable () -> Void

  /// Returns `nil` if none of the paths exist yet or the stream can't be created — the caller then
  /// degrades to timer-only refresh (a provider whose dir appears later is picked up on the next
  /// coordinator start).
  init?(paths: [URL], latency: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void) {
    let existing = paths.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !existing.isEmpty else { return nil }
    self.onChange = onChange

    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil, release: nil, copyDescription: nil)
    let flags = UInt32(
      kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents
        | kFSEventStreamCreateFlagIgnoreSelf)
    guard
      let stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        { _, info, _, _, _, _ in
          guard let info else { return }
          Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        },
        &context,
        existing.map(\.path) as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latency,
        flags)
    else { return nil }

    self.stream = stream
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      return nil
    }
  }

  func stop() {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
  }

  deinit { stop() }
}
