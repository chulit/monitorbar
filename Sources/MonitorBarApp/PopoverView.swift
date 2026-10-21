import MonitorKit
import SwiftUI

/// The whole app: a 2-column grid of cards matching the reference
/// layout, plus a slim footer with Settings and Quit. Nothing else.
struct PopoverView: View {
  @EnvironmentObject private var store: StatsStore
  @EnvironmentObject private var settings: AppSettings

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  var body: some View {
    VStack(spacing: 12) {
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(CardID.allCases) { card in
          if settings.isVisible(card) {
            cardView(card)
          }
        }
      }
      footer
    }
    .padding(14)
    .frame(width: 700)
    .background(Theme.popoverBackground)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private func cardView(_ card: CardID) -> some View {
    let snapshot = store.snapshot
    switch card {
    case .memory:
      MemoryCard(memory: snapshot?.memory)
    case .cpu:
      CPUCard(totalFraction: snapshot?.cpuTotalFraction, cores: snapshot?.cores ?? [])
    case .network:
      NetworkCard(network: snapshot?.network)
    case .temperature:
      TemperatureCard(celsius: snapshot?.temperatureCelsius)
    case .processes:
      ProcessesCard(processes: snapshot?.processes ?? [])
    case .device:
      DeviceCard(device: snapshot?.device)
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      Text("MonitorBar \(Self.appVersion)")
        .font(.caption)
        .foregroundStyle(Theme.secondary)
      Spacer()
      SettingsLink {
        Label("Settings", systemImage: "gearshape")
          .font(.system(size: 13, weight: .medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white.opacity(0.85))
      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Label("Quit", systemImage: "power")
          .font(.system(size: 13, weight: .medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white.opacity(0.85))
      .keyboardShortcut("q", modifiers: .command)
    }
    .padding(.horizontal, 4)
  }

  private static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "1.0.0"
  }
}
