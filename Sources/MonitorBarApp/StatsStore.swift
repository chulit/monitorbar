import Foundation
import MonitorKit

/// Owns the collectors and a repeating timer, publishing one Snapshot
/// per tick. Collection runs on the main actor — a tick costs a few
/// milliseconds at the default 2 s cadence, the same arrangement the
/// user's other monitor uses.
@MainActor
final class StatsStore: ObservableObject {
  @Published private(set) var snapshot: Snapshot?

  private let cpuCollector = CPUCollector()
  private let memoryCollector = MemoryCollector()
  private let networkCollector = NetworkCollector()
  private let processCollector = ProcessCollector()
  private let temperatureReader = TemperatureReader()

  private var timer: Timer?
  private var currentInterval: Double = 0
  private var publicIP: String?
  private var lastPublicIPFetch = Date.distantPast

  func start() {
    guard timer == nil else { return }
    tick()
    schedule(interval: desiredInterval())
  }

  private func desiredInterval() -> Double {
    UserDefaults.standard.object(forKey: AppSettings.intervalKey) as? Double ?? 2
  }

  private func schedule(interval: Double) {
    currentInterval = interval
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        self?.tick()
        if let self, desiredInterval() != currentInterval {
          schedule(interval: desiredInterval())
        }
      }
    }
  }

  private func tick() {
    let now = Date()
    let memory = memoryCollector.collect()
    let totalMemory = memory?.totalBytes ?? ProcessInfo.processInfo.physicalMemory
    let processResult = processCollector.collect(
      now: now, totalMemoryBytes: totalMemory, limit: 2
    )
    var network = networkCollector.collect(now: now)
    refreshPublicIPIfNeeded()
    if network != nil {
      network?.publicIP = publicIP
    }
    snapshot = Snapshot(
      date: now,
      cpuTotalFraction: processResult.totalCPUFraction,
      cores: cpuCollector.collect(),
      memory: memory,
      network: network,
      temperatureCelsius: temperatureReader.readCelsius(),
      processes: processResult.processes,
      device: DeviceReader.stats()
    )
  }

  /// The one network call the app ever makes, at most once a minute,
  /// and only while the setting is on. Failure simply leaves the card
  /// showing "—".
  private func refreshPublicIPIfNeeded() {
    let enabled =
      UserDefaults.standard.object(forKey: AppSettings.publicIPKey) as? Bool ?? true
    guard enabled else {
      publicIP = nil
      return
    }
    guard now.timeIntervalSince(lastPublicIPFetch) > 60 else { return }
    lastPublicIPFetch = now
    Task {
      guard
        let url = URL(string: "https://api.ipify.org"),
        let (data, _) = try? await URLSession.shared.data(from: url),
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(
          in: .whitespacesAndNewlines
        ),
        isValidIPv4(text)
      else { return }
      publicIP = text
    }
  }

  private var now: Date { Date() }
}
