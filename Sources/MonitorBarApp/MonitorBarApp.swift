import MonitorKit
import SwiftUI

/// Menu-bar-only: no WindowGroup, no Dock icon (LSUIElement is set in
/// the packaging Info.plist). The popover below is the entire UI; the
/// Settings scene is the only window the app can ever show.
@main
struct MonitorBarApp: App {
  @StateObject private var store = StatsStore()
  @StateObject private var settings = AppSettings()

  var body: some Scene {
    MenuBarExtra {
      PopoverView()
        .environmentObject(store)
        .environmentObject(settings)
    } label: {
      MenuBarLabel()
        .environmentObject(store)
        .environmentObject(settings)
        .onAppear { store.start() }
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environmentObject(settings)
    }
  }
}

/// What sits in the menu bar itself: a gauge icon plus the metric the
/// user picked in Settings.
struct MenuBarLabel: View {
  @EnvironmentObject private var store: StatsStore
  @EnvironmentObject private var settings: AppSettings

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "gauge.with.dots.needle.33percent")
      if let text = labelText {
        Text(text)
          .font(.system(size: 12, weight: .medium).monospacedDigit())
      }
    }
    .accessibilityLabel("MonitorBar")
  }

  private var labelText: String? {
    guard let snapshot = store.snapshot else { return nil }
    switch settings.menubarMetric {
    case .iconOnly:
      return nil
    case .cpu:
      return snapshot.cpuTotalFraction.map { Format.percent(fraction: $0) } ?? "—"
    case .memory:
      return snapshot.memory.map { Format.percent(fraction: $0.usedFraction) } ?? "—"
    case .cpuMemory:
      let cpu = snapshot.cpuTotalFraction.map { Format.percent(fraction: $0) } ?? "—"
      let memory = snapshot.memory.map { Format.percent(fraction: $0.usedFraction) } ?? "—"
      return "\(cpu) · \(memory)"
    case .network:
      guard let network = snapshot.network else { return "—" }
      let total = network.downBytesPerSec + network.upBytesPerSec
      return Format.rate(bytesPerSec: total)
    case .temperature:
      return snapshot.temperatureCelsius.map { Format.temperature(celsius: $0) } ?? "—"
    }
  }
}
