import Darwin
import Foundation

/// Per-core CPU ticks via `host_processor_info` — the same API Stats and
/// Activity Monitor style tools use for per-core history. The aggregate
/// CPU percentage shown big on the card does NOT come from here: Mach
/// tick counters can freeze under tickless idle on Apple Silicon, so the
/// total is summed from per-process rusage deltas (see ProcessCollector),
/// an approach already proven on the user's Mac.
public final class CPUCollector {
  private var previousTicks: [[UInt64]]?

  public init() {}

  /// Empty on the first read: a load needs two snapshots.
  public func collect() -> [CoreLoad] {
    guard let ticks = Self.readTicks() else { return [] }
    defer { previousTicks = ticks }
    guard let previousTicks else { return [] }
    return coreLoads(previous: previousTicks, current: ticks)
  }

  /// Tick order per core is the kernel's: [user, system, idle, nice].
  private static func readTicks() -> [[UInt64]]? {
    var numCPUs: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var numCpuInfo: mach_msg_type_number_t = 0
    let result = host_processor_info(
      mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo
    )
    guard result == KERN_SUCCESS, let cpuInfo else { return nil }
    defer {
      let byteSize = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
      vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), byteSize)
    }
    let statesPerCore = Int(CPU_STATE_MAX)
    return (0..<Int(numCPUs)).map { core in
      let base = core * statesPerCore
      return (0..<statesPerCore).map { state in
        UInt64(UInt32(bitPattern: cpuInfo[base + state]))
      }
    }
  }
}

/// Memory (host_statistics64), swap (vm.swapusage) and boot-volume use.
public struct MemoryCollector {
  public init() {}

  public func collect() -> MemoryStats? {
    var vmStats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    )
    let host = mach_host_self()
    defer { mach_port_deallocate(mach_task_self_, host) }
    let result = withUnsafeMutablePointer(to: &vmStats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(host, HOST_VM_INFO64, $0, &count)
      }
    }
    var pageSize: vm_size_t = 0
    host_page_size(host, &pageSize)
    guard result == KERN_SUCCESS, pageSize > 0 else { return nil }
    let totalBytes = ProcessInfo.processInfo.physicalMemory
    let breakdown = memoryBreakdown(
      activePages: UInt64(vmStats.active_count),
      inactivePages: UInt64(vmStats.inactive_count),
      wiredPages: UInt64(vmStats.wire_count),
      compressedPages: UInt64(vmStats.compressor_page_count),
      pageSize: UInt64(pageSize),
      totalBytes: totalBytes
    )
    return MemoryStats(
      usedFraction: breakdown.usedFraction,
      usedBytes: breakdown.usedBytes,
      totalBytes: totalBytes,
      segments: breakdown.segments,
      swapUsedBytes: Self.swapUsedBytes(),
      diskUsedFraction: Self.diskUsedFraction()
    )
  }

  private static func swapUsedBytes() -> UInt64? {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
      return nil
    }
    return usage.xsu_used
  }

  private static func diskUsedFraction() -> Double? {
    guard
      let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
      let total = attributes[.systemSize] as? NSNumber,
      let free = attributes[.systemFreeSize] as? NSNumber,
      total.doubleValue > 0
    else { return nil }
    return min(max(1 - free.doubleValue / total.doubleValue, 0), 1)
  }
}

/// Throughput on the primary physical interface (en0 first), split into
/// download and upload, plus that interface's IPv4 address.
public final class NetworkCollector {
  private var previous: (name: String, inBytes: UInt64, outBytes: UInt64, at: Date)?

  public init() {}

  public func collect(now: Date) -> NetworkStats? {
    guard let primary = Self.primaryInterface() else { return nil }
    defer { previous = (primary.name, primary.inBytes, primary.outBytes, now) }
    let label = primary.name == "en0" ? "Wi-Fi" : "Ethernet"
    guard let previous, previous.name == primary.name else {
      // First read (or the interface changed): no honest rate yet.
      return NetworkStats(
        downBytesPerSec: 0, upBytesPerSec: 0,
        connectionLabel: label, localIP: primary.ipv4
      )
    }
    let rates = networkRates(
      previousIn: previous.inBytes, previousOut: previous.outBytes,
      currentIn: primary.inBytes, currentOut: primary.outBytes,
      elapsed: now.timeIntervalSince(previous.at)
    )
    return NetworkStats(
      downBytesPerSec: rates?.downBytesPerSec ?? 0,
      upBytesPerSec: rates?.upBytesPerSec ?? 0,
      connectionLabel: label, localIP: primary.ipv4
    )
  }

  private struct Interface {
    let name: String
    let ipv4: String?
    let inBytes: UInt64
    let outBytes: UInt64
  }

  private static func primaryInterface() -> Interface? {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return nil }
    defer { freeifaddrs(first) }
    var ipv4ByName: [String: String] = [:]
    var countersByName: [String: (UInt64, UInt64)] = [:]
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let current = cursor {
      let interface = current.pointee
      cursor = interface.ifa_next
      guard let namePointer = interface.ifa_name else { continue }
      let name = String(cString: namePointer)
      guard name.hasPrefix("en"), let address = interface.ifa_addr else { continue }
      switch Int32(address.pointee.sa_family) {
      case AF_INET:
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(
          address, socklen_t(address.pointee.sa_len),
          &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST
        ) == 0 {
          ipv4ByName[name] = String(cString: hostBuffer)
        }
      case AF_LINK:
        if let data = interface.ifa_data {
          let stats = data.assumingMemoryBound(to: if_data.self).pointee
          countersByName[name] = (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
        }
      default:
        break
      }
    }
    for name in countersByName.keys.sorted() {
      guard let counters = countersByName[name] else { continue }
      return Interface(
        name: name, ipv4: ipv4ByName[name],
        inBytes: counters.0, outBytes: counters.1
      )
    }
    return nil
  }
}

/// Per-process CPU from rusage deltas (nanoseconds) and resident memory
/// from task info, aggregated to app level. Also yields the system-wide
/// CPU total as the sum of all process deltas over elapsed capacity —
/// the figure the Processor Load card shows big.
public final class ProcessCollector {
  private var previousUsage: [Int32: UInt64] = [:]
  private var previousAt: Date?

  public init() {}

  public func collect(
    now: Date, totalMemoryBytes: UInt64, limit: Int
  ) -> (processes: [ProcessStat], totalCPUFraction: Double?) {
    let current = Self.enumerate()
    defer {
      previousUsage = current.usage
      previousAt = now
    }
    guard let previousAt, now > previousAt else { return ([], nil) }
    let elapsed = now.timeIntervalSince(previousAt)
    let processors = max(ProcessInfo.processInfo.processorCount, 1)
    var raw: [RawProcess] = []
    var busyNanos: UInt64 = 0
    for reading in current.readings {
      guard let before = previousUsage[reading.pid] else { continue }
      let delta = reading.totalNanos &- before
      busyNanos &+= delta
      let cpuPercent = Double(delta) / (elapsed * 1_000_000_000) * 100
      let app = appName(executablePath: reading.path, fallback: reading.name)
      raw.append(
        RawProcess(
          appName: app.name, appPath: app.appPath,
          cpuPercent: cpuPercent, residentBytes: reading.residentBytes
        )
      )
    }
    let capacity = elapsed * 1_000_000_000 * Double(processors)
    let totalFraction = capacity > 0
      ? min(max(Double(busyNanos) / capacity, 0), 1) : nil
    return (
      aggregateProcesses(raw, totalMemoryBytes: totalMemoryBytes, limit: limit),
      totalFraction
    )
  }

  private struct Reading {
    let pid: Int32
    let name: String
    let path: String
    let totalNanos: UInt64
    let residentBytes: UInt64
  }

  private static func enumerate() -> (usage: [Int32: UInt64], readings: [Reading]) {
    var usage: [Int32: UInt64] = [:]
    var readings: [Reading] = []
    for pid in allPIDs() {
      var usageInfo = rusage_info_v2()
      let rusageRead: Int32 = withUnsafeMutablePointer(to: &usageInfo) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
          proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
        }
      }
      guard rusageRead == 0 else { continue }
      let totalNanos = usageInfo.ri_user_time &+ usageInfo.ri_system_time
      usage[pid] = totalNanos

      var taskInfo = proc_taskinfo()
      let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
      let resident: UInt64 =
        proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize
        ? taskInfo.pti_resident_size : 0

      var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
      let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
      let path = pathLength > 0 ? String(cString: pathBuffer) : ""

      var bsdInfo = proc_bsdinfo()
      let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
      var name = "pid \(pid)"
      if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
        name = withUnsafePointer(to: bsdInfo.pbi_comm) {
          $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
        }
      }
      readings.append(
        Reading(pid: pid, name: name, path: path, totalNanos: totalNanos, residentBytes: resident)
      )
    }
    return (usage, readings)
  }

  private static func allPIDs() -> [pid_t] {
    var capacity = 4096
    for _ in 0..<3 {
      var buffer = [pid_t](repeating: 0, count: capacity)
      let bytes = buffer.withUnsafeMutableBufferPointer {
        proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.stride))
      }
      guard bytes > 0 else { return [] }
      let count = Int(bytes) / MemoryLayout<pid_t>.stride
      if count < capacity {
        return Array(buffer.prefix(count)).filter { $0 > 0 }
      }
      capacity = count + 256
    }
    return []
  }
}

/// macOS version and boot uptime for the Device card.
public enum DeviceReader {
  public static func stats() -> DeviceStats {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return DeviceStats(
      osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      uptime: ProcessInfo.processInfo.systemUptime
    )
  }
}
