import Darwin
import Foundation
import OSLog

enum PerformanceBudget {
  static let coldStartToFirstNumberMilliseconds: Double = 400
  static let incrementalReloadMilliseconds: Double = 50
  static let idleResidentMemoryMegabytes: Double = 50
  /// "Idle CPU ~0%" is measured as a trend; one percent is the alerting threshold for noisy samples.
  static let idleCPUPercent: Double = 1
}

struct PerformanceResourceSnapshot: Equatable {
  let uptimeSeconds: TimeInterval
  let residentMemoryBytes: UInt64
  let totalCPUTimeSeconds: TimeInterval

  var residentMemoryMegabytes: Double {
    Double(residentMemoryBytes) / 1_048_576
  }

  func cpuPercent(since previous: PerformanceResourceSnapshot) -> Double? {
    let wall = uptimeSeconds - previous.uptimeSeconds
    let cpu = totalCPUTimeSeconds - previous.totalCPUTimeSeconds
    guard wall > 0, cpu >= 0 else { return nil }
    return (cpu / wall) * 100
  }

  static func current() -> PerformanceResourceSnapshot? {
    var task = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
    let result = withUnsafeMutablePointer(to: &task) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }

    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    let user = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
    let system = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
    return PerformanceResourceSnapshot(
      uptimeSeconds: ProcessInfo.processInfo.systemUptime,
      residentMemoryBytes: UInt64(task.resident_size),
      totalCPUTimeSeconds: user + system)
  }
}

@MainActor
final class PerformanceInstrumentation {
  static let shared = PerformanceInstrumentation()

  private let logger = Logger(subsystem: "com.8bittts.jpthecat", category: "performance")
  private let clock = ContinuousClock()
  private let processStart: ContinuousClock.Instant
  private var firstNumberLogged = false
  private var refreshStart: ContinuousClock.Instant?
  private var refreshWasReindexing = false
  private var idleBaseline: PerformanceResourceSnapshot?
  private var idleSampleScheduled = false

  private init() {
    processStart = clock.now
    idleBaseline = PerformanceResourceSnapshot.current()
  }

  func markAppDidFinishLaunching() {
    scheduleIdleResourceSample(reason: "launch")
  }

  func markRefreshStarted(reindex: Bool) {
    refreshStart = clock.now
    refreshWasReindexing = reindex
  }

  func markRefreshFinished(hasDisplayableNumber: Bool) {
    if let refreshStart {
      let elapsed = milliseconds(from: refreshStart, to: clock.now)
      let budget = refreshWasReindexing
        ? PerformanceBudget.coldStartToFirstNumberMilliseconds
        : PerformanceBudget.incrementalReloadMilliseconds
      logger.info(
        "refresh_finished reindex=\(self.refreshWasReindexing, privacy: .public) elapsed_ms=\(elapsed, format: .fixed(precision: 1), privacy: .public) budget_ms=\(budget, format: .fixed(precision: 0), privacy: .public)"
      )
    }
    refreshStart = nil
    if hasDisplayableNumber { markFirstNumberAvailable() }
  }

  func markFirstNumberAvailable() {
    guard !firstNumberLogged else { return }
    firstNumberLogged = true
    let elapsed = milliseconds(from: processStart, to: clock.now)
    logger.info(
      "cold_start_first_number_ms=\(elapsed, format: .fixed(precision: 1), privacy: .public) budget_ms=\(PerformanceBudget.coldStartToFirstNumberMilliseconds, format: .fixed(precision: 0), privacy: .public)"
    )
    scheduleIdleResourceSample(reason: "first-number")
  }

  private func scheduleIdleResourceSample(reason: String) {
    guard !idleSampleScheduled else { return }
    idleSampleScheduled = true
    let baseline = idleBaseline ?? PerformanceResourceSnapshot.current()
    idleBaseline = baseline
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard let self else { return }
      self.idleSampleScheduled = false
      self.logIdleResources(since: baseline, reason: reason)
    }
  }

  private func logIdleResources(since baseline: PerformanceResourceSnapshot?, reason: String) {
    guard let current = PerformanceResourceSnapshot.current() else { return }
    let cpu = baseline.flatMap { current.cpuPercent(since: $0) }
    let cpuText = cpu.map { String(format: "%.2f", $0) } ?? "n/a"
    logger.info(
      "idle_resources reason=\(reason, privacy: .public) rss_mb=\(current.residentMemoryMegabytes, format: .fixed(precision: 1), privacy: .public) rss_budget_mb=\(PerformanceBudget.idleResidentMemoryMegabytes, format: .fixed(precision: 0), privacy: .public) cpu_percent=\(cpuText, privacy: .public) cpu_budget_percent=\(PerformanceBudget.idleCPUPercent, format: .fixed(precision: 0), privacy: .public)"
    )
    idleBaseline = current
  }

  private func milliseconds(
    from start: ContinuousClock.Instant,
    to end: ContinuousClock.Instant
  ) -> Double {
    Double(start.duration(to: end).components.attoseconds) / 1_000_000_000_000_000
      + Double(start.duration(to: end).components.seconds) * 1000
  }
}
