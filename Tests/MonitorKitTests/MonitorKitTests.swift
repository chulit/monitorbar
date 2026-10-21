import XCTest

@testable import MonitorKit

final class MonitorKitTests: XCTestCase {
  private let idID = Locale(identifier: "id_ID")
  private let enUS = Locale(identifier: "en_US")

  // MARK: Formatters

  func testPercentOneDecimal() {
    XCTAssertEqual(Format.percent(fraction: 0.865, locale: enUS), "86.5%")
    XCTAssertEqual(Format.percent(fraction: 0.781, locale: enUS), "78.1%")
    XCTAssertEqual(Format.percent(fraction: 0, locale: enUS), "0.0%")
  }

  func testPercentWhole() {
    XCTAssertEqual(Format.percentWhole(fraction: 0.75, locale: enUS), "75%")
  }

  func testBytesIndonesianDecimalComma() {
    // Exactly 6.44 GiB, as in the reference card.
    XCTAssertEqual(Format.bytes(6_914_897_510, locale: idID), "6,44 GB")
    XCTAssertEqual(Format.bytes(227 * 1_048_576, locale: idID), "227 MB")
    XCTAssertEqual(Format.bytes(512, locale: enUS), "512 B")
    XCTAssertEqual(Format.bytes(2_048, locale: enUS), "2 KB")
  }

  func testRateInBits() {
    // 199 kb/s ≈ 24,875 bytes/s; 1 Mb/s = 125,000 bytes/s.
    XCTAssertEqual(Format.rate(bytesPerSec: 24_875, locale: enUS), "199 kb/s")
    XCTAssertEqual(Format.rate(bytesPerSec: 125_000, locale: enUS), "1 Mb/s")
    XCTAssertEqual(Format.rate(bytesPerSec: 0, locale: enUS), "0 b/s")
  }

  func testUptime() {
    let seconds: TimeInterval = 21 * 86_400 + 10 * 3_600 + 54 * 60
    XCTAssertEqual(Format.uptime(seconds), "21d 10h 54m")
    XCTAssertEqual(Format.uptime(3_600 + 5 * 60), "1h 5m")
    XCTAssertEqual(Format.uptime(54 * 60), "54m")
    XCTAssertEqual(Format.uptime(0), "0m")
  }

  func testTemperatureFormat() {
    XCTAssertEqual(Format.temperature(celsius: 60.4), "60°C")
    XCTAssertEqual(Format.temperature(celsius: 59.6), "60°C")
  }

  func testIPv4Validation() {
    XCTAssertTrue(isValidIPv4("157.85.206.75"))
    XCTAssertTrue(isValidIPv4("192.168.1.4"))
    XCTAssertFalse(isValidIPv4("999.1.1.1"))
    XCTAssertFalse(isValidIPv4("not an ip"))
    XCTAssertFalse(isValidIPv4("1.2.3"))
  }

  // MARK: Core loads (kernel order: user, system, idle, nice)

  func testCoreLoadsSplit() {
    let previous: [[UInt64]] = [[100, 100, 100, 100]]
    let current: [[UInt64]] = [[150, 125, 175, 100]]
    let loads = coreLoads(previous: previous, current: current)
    XCTAssertEqual(loads.count, 1)
    // deltas: user 50, system 25, idle 75, nice 0 → total 150
    XCTAssertEqual(loads[0].user, 50.0 / 150.0, accuracy: 0.001)
    XCTAssertEqual(loads[0].system, 25.0 / 150.0, accuracy: 0.001)
    XCTAssertEqual(loads[0].total, 0.5, accuracy: 0.001)
  }

  func testCoreLoadsNiceCountsAsUser() {
    let previous: [[UInt64]] = [[0, 0, 0, 0]]
    let current: [[UInt64]] = [[10, 10, 60, 20]]
    let loads = coreLoads(previous: previous, current: current)
    XCTAssertEqual(loads[0].user, 0.3, accuracy: 0.001)
    XCTAssertEqual(loads[0].system, 0.1, accuracy: 0.001)
  }

  func testCoreLoadsMismatchedCounts() {
    XCTAssertTrue(coreLoads(previous: [[0, 0, 0, 0]], current: []).isEmpty)
  }

  func testCoreLoadsZeroDeltaIsIdle() {
    let same: [[UInt64]] = [[10, 10, 10, 10]]
    let loads = coreLoads(previous: same, current: same)
    XCTAssertEqual(loads[0].total, 0)
  }

  // MARK: Memory breakdown

  func testMemoryBreakdown() {
    // 8 GiB total, 16 KiB pages → 524,288 pages.
    let pageSize: UInt64 = 16_384
    let totalBytes: UInt64 = 8 * 1_073_741_824
    let result = memoryBreakdown(
      activePages: 200_000, inactivePages: 100_000,
      wiredPages: 80_000, compressedPages: 40_000,
      pageSize: pageSize, totalBytes: totalBytes
    )
    let totalPages = Double(totalBytes / pageSize)
    XCTAssertEqual(result.usedBytes, 420_000 * pageSize)
    XCTAssertEqual(
      result.usedFraction, 420_000 / totalPages, accuracy: 0.0001)
    XCTAssertEqual(result.segments.count, 4)
    XCTAssertEqual(result.segments[0].kind, .app)
    XCTAssertEqual(
      result.segments[0].fraction, 200_000 / totalPages, accuracy: 0.0001)
    let segmentSum = result.segments.reduce(0) { $0 + $1.fraction }
    XCTAssertEqual(segmentSum, result.usedFraction, accuracy: 0.0001)
  }

  func testMemoryBreakdownDegenerate() {
    let result = memoryBreakdown(
      activePages: 0, inactivePages: 0, wiredPages: 0, compressedPages: 0,
      pageSize: 0, totalBytes: 0
    )
    XCTAssertEqual(result.usedFraction, 0)
    XCTAssertTrue(result.segments.isEmpty)
  }

  // MARK: Network rates

  func testNetworkRatesSplit() {
    let rates = networkRates(
      previousIn: 1_000, previousOut: 2_000,
      currentIn: 26_000, currentOut: 12_000, elapsed: 1
    )
    XCTAssertEqual(rates?.downBytesPerSec, 25_000)
    XCTAssertEqual(rates?.upBytesPerSec, 10_000)
  }

  func testNetworkRatesCounterReset() {
    XCTAssertNil(
      networkRates(
        previousIn: 5_000, previousOut: 0,
        currentIn: 100, currentOut: 0, elapsed: 1
      )
    )
    XCTAssertNil(
      networkRates(
        previousIn: 0, previousOut: 0,
        currentIn: 100, currentOut: 0, elapsed: 0
      )
    )
  }

  // MARK: Temperature band

  func testTemperatureBands() {
    XCTAssertEqual(temperatureBand(celsius: 42), .low)
    XCTAssertEqual(temperatureBand(celsius: 60), .moderate)
    XCTAssertEqual(temperatureBand(celsius: 79.9), .moderate)
    XCTAssertEqual(temperatureBand(celsius: 85), .high)
  }

  // MARK: Process aggregation

  func testAggregateGroupsHelpersIntoApp() {
    let raw = [
      RawProcess(
        appName: "Google Chrome", appPath: "/Applications/Google Chrome.app",
        cpuPercent: 10, residentBytes: 1_000),
      RawProcess(
        appName: "Google Chrome", appPath: "/Applications/Google Chrome.app",
        cpuPercent: 12.6, residentBytes: 2_000),
      RawProcess(
        appName: "Google Drive", appPath: "/Applications/Google Drive.app",
        cpuPercent: 39.9, residentBytes: 500),
    ]
    let result = aggregateProcesses(raw, totalMemoryBytes: 10_000, limit: 2)
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result[0].appName, "Google Drive")
    XCTAssertEqual(result[1].appName, "Google Chrome")
    XCTAssertEqual(result[1].cpuPercent, 22.6, accuracy: 0.001)
    XCTAssertEqual(result[1].memoryBytes, 3_000)
    XCTAssertEqual(result[1].memoryFraction, 0.3, accuracy: 0.001)
  }

  func testAggregateLimitAndEmpty() {
    XCTAssertTrue(aggregateProcesses([], totalMemoryBytes: 0, limit: 2).isEmpty)
    let raw = (0..<5).map {
      RawProcess(appName: "App\($0)", appPath: nil, cpuPercent: Double($0), residentBytes: 0)
    }
    XCTAssertEqual(aggregateProcesses(raw, totalMemoryBytes: 0, limit: 2).count, 2)
  }

  func testAppNameFromPath() {
    let chrome = appName(
      executablePath:
        "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper",
      fallback: "Google Chrome Helper"
    )
    XCTAssertEqual(chrome.name, "Google Chrome")
    XCTAssertEqual(chrome.appPath, "/Applications/Google Chrome.app")

    let daemon = appName(executablePath: "/usr/sbin/syslogd", fallback: "syslogd")
    XCTAssertEqual(daemon.name, "syslogd")
    XCTAssertNil(daemon.appPath)
  }
}
