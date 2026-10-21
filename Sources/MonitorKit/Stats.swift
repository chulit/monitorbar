import Foundation

/// One core's load split the way the reference card draws it: the purple
/// block at the bottom is user time, the blue block above it is system
/// time, and whatever is left of the column stays dark (idle).
public struct CoreLoad: Equatable, Sendable {
  public let user: Double
  public let system: Double
  public var total: Double { min(user + system, 1) }

  public init(user: Double, system: Double) {
    self.user = min(max(user, 0), 1)
    self.system = min(max(system, 0), 1)
  }
}

/// Per-core loads from two `host_processor_info` snapshots. Each core is
/// kernel-ordered tick counts `[user, system, idle, nice]`; nice counts
/// as user time. A counter that went backwards (reset) contributes its
/// raw value.
public func coreLoads(previous: [[UInt64]], current: [[UInt64]]) -> [CoreLoad] {
  guard previous.count == current.count else { return [] }
  return zip(previous, current).map { prev, curr in
    func delta(_ i: Int) -> Double {
      guard prev.indices.contains(i), curr.indices.contains(i) else { return 0 }
      return curr[i] >= prev[i] ? Double(curr[i] - prev[i]) : Double(curr[i])
    }
    let user = delta(0) + delta(3)
    let system = delta(1)
    let idle = delta(2)
    let total = user + system + idle
    guard total > 0 else { return CoreLoad(user: 0, system: 0) }
    return CoreLoad(user: user / total, system: system / total)
  }
}

public enum MemorySegmentKind: String, Equatable, Sendable, CaseIterable {
  case app
  case wired
  case compressed
  case cached
}

public struct MemorySegment: Equatable, Sendable {
  public let kind: MemorySegmentKind
  /// Fraction of total physical memory, 0...1.
  public let fraction: Double

  public init(kind: MemorySegmentKind, fraction: Double) {
    self.kind = kind
    self.fraction = min(max(fraction, 0), 1)
  }
}

public struct MemoryStats: Equatable, Sendable {
  public let usedFraction: Double
  public let usedBytes: UInt64
  public let totalBytes: UInt64
  public let segments: [MemorySegment]
  public let swapUsedBytes: UInt64?
  /// Fraction of the boot volume in use, 0...1. Shown as the download
  /// badge on the memory card in the reference layout.
  public let diskUsedFraction: Double?

  public init(
    usedFraction: Double, usedBytes: UInt64, totalBytes: UInt64,
    segments: [MemorySegment], swapUsedBytes: UInt64?, diskUsedFraction: Double?
  ) {
    self.usedFraction = min(max(usedFraction, 0), 1)
    self.usedBytes = usedBytes
    self.totalBytes = totalBytes
    self.segments = segments
    self.swapUsedBytes = swapUsedBytes
    self.diskUsedFraction = diskUsedFraction
  }
}

/// Shapes raw `vm_statistics64` page counts into the donut breakdown.
/// "Used" follows the convention the user's other monitor uses:
/// active + inactive + wired + compressed pages.
public func memoryBreakdown(
  activePages: UInt64, inactivePages: UInt64, wiredPages: UInt64,
  compressedPages: UInt64, pageSize: UInt64, totalBytes: UInt64
) -> (usedFraction: Double, usedBytes: UInt64, segments: [MemorySegment]) {
  guard pageSize > 0, totalBytes > 0 else { return (0, 0, []) }
  let totalPages = Double(totalBytes / pageSize)
  guard totalPages > 0 else { return (0, 0, []) }
  func fraction(_ pages: UInt64) -> Double { Double(pages) / totalPages }
  let usedPages = activePages + inactivePages + wiredPages + compressedPages
  let segments = [
    MemorySegment(kind: .app, fraction: fraction(activePages)),
    MemorySegment(kind: .wired, fraction: fraction(wiredPages)),
    MemorySegment(kind: .compressed, fraction: fraction(compressedPages)),
    MemorySegment(kind: .cached, fraction: fraction(inactivePages)),
  ]
  return (
    usedFraction: min(Double(usedPages) / totalPages, 1),
    usedBytes: usedPages * pageSize,
    segments: segments
  )
}

/// Split network rates from two byte-counter reads. A counter that went
/// backwards means the interface reset: report nil rather than a spike.
public func networkRates(
  previousIn: UInt64, previousOut: UInt64,
  currentIn: UInt64, currentOut: UInt64,
  elapsed: TimeInterval
) -> (downBytesPerSec: Double, upBytesPerSec: Double)? {
  guard elapsed > 0, currentIn >= previousIn, currentOut >= previousOut else {
    return nil
  }
  return (
    downBytesPerSec: Double(currentIn - previousIn) / elapsed,
    upBytesPerSec: Double(currentOut - previousOut) / elapsed
  )
}

public struct NetworkStats: Equatable, Sendable {
  public let downBytesPerSec: Double
  public let upBytesPerSec: Double
  /// "Wi-Fi" or "Ethernet" for the primary interface.
  public let connectionLabel: String
  public let localIP: String?
  /// Filled in by the app layer (an HTTPS lookup), not the collector.
  public var publicIP: String?

  public init(
    downBytesPerSec: Double, upBytesPerSec: Double,
    connectionLabel: String, localIP: String?, publicIP: String? = nil
  ) {
    self.downBytesPerSec = downBytesPerSec
    self.upBytesPerSec = upBytesPerSec
    self.connectionLabel = connectionLabel
    self.localIP = localIP
    self.publicIP = publicIP
  }
}

public enum TemperatureBand: String, Equatable, Sendable {
  case low = "Low"
  case moderate = "Moderate"
  case high = "High"
}

/// 60°C reads "Moderate" in the reference layout; the bands are set so
/// normal Apple Silicon load sits in the middle band.
public func temperatureBand(celsius: Double) -> TemperatureBand {
  if celsius < 50 { return .low }
  if celsius < 80 { return .moderate }
  return .high
}

/// A raw per-process reading before app-level aggregation.
public struct RawProcess: Equatable, Sendable {
  public let appName: String
  public let appPath: String?
  public let cpuPercent: Double
  public let residentBytes: UInt64

  public init(appName: String, appPath: String?, cpuPercent: Double, residentBytes: UInt64) {
    self.appName = appName
    self.appPath = appPath
    self.cpuPercent = cpuPercent
    self.residentBytes = residentBytes
  }
}

public struct ProcessStat: Equatable, Sendable, Identifiable {
  public var id: String { appPath ?? appName }
  public let appName: String
  public let appPath: String?
  /// Activity Monitor style: 100% is one full core.
  public let cpuPercent: Double
  public let memoryBytes: UInt64
  public let memoryFraction: Double

  public init(
    appName: String, appPath: String?, cpuPercent: Double,
    memoryBytes: UInt64, memoryFraction: Double
  ) {
    self.appName = appName
    self.appPath = appPath
    self.cpuPercent = cpuPercent
    self.memoryBytes = memoryBytes
    self.memoryFraction = min(max(memoryFraction, 0), 1)
  }
}

/// Groups helper processes into their owning app ("Google Chrome Helper
/// (Renderer)" counts towards Google Chrome because its executable lives
/// inside Google Chrome.app), sums CPU and memory, sorts by CPU.
public func aggregateProcesses(
  _ raw: [RawProcess], totalMemoryBytes: UInt64, limit: Int
) -> [ProcessStat] {
  var grouped: [String: (name: String, path: String?, cpu: Double, bytes: UInt64)] = [:]
  for process in raw {
    let key = process.appPath ?? process.appName
    var entry = grouped[key] ?? (process.appName, process.appPath, 0, 0)
    entry.cpu += process.cpuPercent
    entry.bytes += process.residentBytes
    grouped[key] = entry
  }
  return grouped.values
    .map { entry in
      ProcessStat(
        appName: entry.name,
        appPath: entry.path,
        cpuPercent: entry.cpu,
        memoryBytes: entry.bytes,
        memoryFraction: totalMemoryBytes > 0
          ? Double(entry.bytes) / Double(totalMemoryBytes) : 0
      )
    }
    .sorted { $0.cpuPercent > $1.cpuPercent }
    .prefix(max(limit, 0))
    .map { $0 }
}

/// The app a process belongs to, from its executable path:
/// "/Applications/Google Chrome.app/Contents/…/Helper" → "Google Chrome".
/// Processes outside any .app bundle keep their own name.
public func appName(executablePath: String, fallback: String) -> (name: String, appPath: String?) {
  guard let range = executablePath.range(of: ".app/") else {
    return (fallback, nil)
  }
  let bundlePath = String(executablePath[..<range.upperBound].dropLast(1))
  let name = (bundlePath as NSString).lastPathComponent
    .replacingOccurrences(of: ".app", with: "")
  return (name.isEmpty ? fallback : name, bundlePath)
}

public struct DeviceStats: Equatable, Sendable {
  /// "27.0.1" — no "macOS" prefix, like the reference card.
  public let osVersion: String
  public let uptime: TimeInterval

  public init(osVersion: String, uptime: TimeInterval) {
    self.osVersion = osVersion
    self.uptime = uptime
  }
}

public struct Snapshot: Sendable {
  public let date: Date
  public let cpuTotalFraction: Double?
  public let cores: [CoreLoad]
  public let memory: MemoryStats?
  public let network: NetworkStats?
  public let temperatureCelsius: Double?
  public let processes: [ProcessStat]
  public let device: DeviceStats

  public init(
    date: Date, cpuTotalFraction: Double?, cores: [CoreLoad],
    memory: MemoryStats?, network: NetworkStats?,
    temperatureCelsius: Double?, processes: [ProcessStat], device: DeviceStats
  ) {
    self.date = date
    self.cpuTotalFraction = cpuTotalFraction
    self.cores = cores
    self.memory = memory
    self.network = network
    self.temperatureCelsius = temperatureCelsius
    self.processes = processes
    self.device = device
  }
}
