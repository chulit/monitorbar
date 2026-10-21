import AppKit
import MonitorKit
import SwiftUI

/// Colours sampled from the reference layout: near-black cards, grey
/// titles, and one blue / purple / teal accent family.
enum Theme {
  static let popoverBackground = Color(white: 0.07)
  static let cardBackground = Color(white: 0.115)
  static let title = Color(white: 0.62)
  static let secondary = Color(white: 0.55)
  static let blue = Color(red: 0.30, green: 0.65, blue: 1.00)
  static let purple = Color(red: 0.43, green: 0.38, blue: 1.00)
  static let teal = Color(red: 0.38, green: 0.79, blue: 0.70)
  static let track = Color(red: 0.16, green: 0.16, blue: 0.23)
  static let pill = Color.white.opacity(0.08)
}

struct CardHeader: View {
  let card: CardID

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: card.icon)
        .font(.system(size: 16, weight: .medium))
      Text(card.title)
        .font(.system(size: 15, weight: .semibold))
    }
    .foregroundStyle(Theme.title)
    .accessibilityAddTraits(.isHeader)
  }
}

struct CardShell<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Theme.cardBackground)
    )
  }
}

struct Pill: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .bold))
      Text(text)
        .font(.system(size: 14, weight: .bold).monospacedDigit())
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.pill))
  }
}

// MARK: - Memory

struct MemoryCard: View {
  let memory: MemoryStats?

  var body: some View {
    CardShell {
      CardHeader(card: .memory)
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text(memory.map { Format.percent(fraction: $0.usedFraction) } ?? "—")
            .font(.system(size: 34, weight: .bold).monospacedDigit())
          if let memory {
            Text(
              "\(Format.bytes(memory.usedBytes)) / \(Format.bytes(memory.totalBytes))"
            )
            .font(.system(size: 15, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.secondary)
          }
          Spacer(minLength: 6)
          HStack(spacing: 8) {
            if let disk = memory?.diskUsedFraction {
              Pill(
                icon: "arrow.down.to.line",
                text: Format.percentWhole(fraction: disk)
              )
              .accessibilityLabel("Disk \(Format.percentWhole(fraction: disk)) used")
            }
            if let swap = memory?.swapUsedBytes {
              Pill(icon: "arrow.left.arrow.right", text: Format.bytes(swap))
                .accessibilityLabel("Swap \(Format.bytes(swap))")
            }
          }
        }
        Spacer()
        DonutView(segments: memory?.segments ?? [])
          .frame(width: 104, height: 104)
      }
    }
  }
}

struct DonutView: View {
  let segments: [MemorySegment]

  private func color(_ kind: MemorySegmentKind) -> Color {
    switch kind {
    case .app: return Theme.teal
    case .wired: return Theme.blue
    case .compressed: return Theme.purple
    case .cached: return Theme.track
    }
  }

  /// Draw order matches the reference ring: compressed, wired, app,
  /// cached, starting at the top and going clockwise.
  private var ordered: [MemorySegment] {
    let order: [MemorySegmentKind] = [.compressed, .wired, .app, .cached]
    return order.compactMap { kind in segments.first { $0.kind == kind } }
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(Theme.track, lineWidth: 17)
      ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
        Circle()
          .trim(from: slice.start, to: slice.end)
          .stroke(
            color(slice.kind),
            style: StrokeStyle(lineWidth: 17, lineCap: .butt)
          )
          .rotationEffect(.degrees(-90))
      }
    }
    .accessibilityLabel("Memory breakdown")
  }

  private var slices: [(kind: MemorySegmentKind, start: Double, end: Double)] {
    var result: [(MemorySegmentKind, Double, Double)] = []
    var cursor = 0.0
    for segment in ordered where segment.fraction > 0.003 {
      let start = cursor
      cursor += segment.fraction
      result.append((segment.kind, start + 0.004, min(cursor - 0.004, 1)))
    }
    return result
  }
}

// MARK: - Processor Load

struct CPUCard: View {
  let totalFraction: Double?
  let cores: [CoreLoad]

  var body: some View {
    CardShell {
      CardHeader(card: .cpu)
      Text(totalFraction.map { Format.percent(fraction: $0) } ?? "—")
        .font(.system(size: 34, weight: .bold).monospacedDigit())
      Spacer(minLength: 4)
      CoreGridView(cores: cores)
        .frame(height: 72)
    }
  }
}

struct CoreGridView: View {
  let cores: [CoreLoad]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(displayCores.enumerated()), id: \.offset) { _, core in
        GeometryReader { geometry in
          let height = geometry.size.height
          VStack(spacing: 2) {
            Spacer(minLength: 0)
            Rectangle()
              .fill(Theme.blue)
              .frame(height: max(core.system * height - 1, 0))
            Rectangle()
              .fill(Theme.purple)
              .frame(height: max(core.user * height - 1, 0))
          }
        }
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      }
    }
    .accessibilityLabel("Per-core processor load")
  }

  /// Before the first delta lands, draw empty columns so the card
  /// already has its final shape.
  private var displayCores: [CoreLoad] {
    if !cores.isEmpty { return cores }
    return Array(
      repeating: CoreLoad(user: 0, system: 0),
      count: max(ProcessInfo.processInfo.processorCount, 1)
    )
  }
}

// MARK: - Network

struct NetworkCard: View {
  let network: NetworkStats?

  var body: some View {
    CardShell {
      CardHeader(card: .network)
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Connection")
            .foregroundStyle(Theme.secondary)
            .font(.system(size: 14))
          Text(network?.connectionLabel ?? "—")
            .font(.system(size: 15, weight: .semibold))
        }
        Spacer()
        VStack(alignment: .leading, spacing: 6) {
          rateRow(symbol: "arrowtriangle.down.fill", value: network?.downBytesPerSec)
          rateRow(symbol: "arrowtriangle.up.fill", value: network?.upBytesPerSec)
        }
      }
      Spacer(minLength: 4)
      VStack(alignment: .leading, spacing: 7) {
        ipRow(icon: "globe", value: network?.publicIP)
        ipRow(icon: "network", value: network?.localIP)
      }
      .font(.system(size: 14).monospacedDigit())
      .foregroundStyle(Theme.secondary)
    }
  }

  private func rateRow(symbol: String, value: Double?) -> some View {
    HStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 10))
        .foregroundStyle(Theme.blue)
      Text(value.map { Format.rate(bytesPerSec: $0) } ?? "—")
        .font(.system(size: 17, weight: .bold).monospacedDigit())
    }
  }

  private func ipRow(icon: String, value: String?) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 13))
      Text(value ?? "—")
    }
  }
}

// MARK: - Temperature

struct TemperatureCard: View {
  let celsius: Double?

  var body: some View {
    CardShell {
      CardHeader(card: .temperature)
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 10) {
          Text(celsius.map { Format.temperature(celsius: $0) } ?? "—")
            .font(.system(size: 34, weight: .bold).monospacedDigit())
          if let celsius {
            Pill(
              icon: "chart.bar.fill",
              text: temperatureBand(celsius: celsius).rawValue
            )
          }
          Spacer(minLength: 0)
        }
        Spacer()
        ThermometerView(celsius: celsius)
          .padding(.trailing, 10)
      }
    }
  }
}

struct ThermometerView: View {
  let celsius: Double?

  private var fillFraction: Double {
    guard let celsius else { return 0 }
    return min(max(celsius / 110, 0), 1)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      VStack(spacing: 0) {
        ZStack(alignment: .bottom) {
          Capsule().fill(Theme.track).frame(width: 17, height: 92)
          Capsule()
            .fill(
              LinearGradient(
                colors: [Theme.purple, Theme.blue],
                startPoint: .bottom, endPoint: .top
              )
            )
            .frame(width: 17, height: max(92 * fillFraction, 17))
        }
        Circle()
          .fill(Theme.purple)
          .frame(width: 32, height: 32)
          .offset(y: -8)
      }
      VStack(alignment: .leading, spacing: 9) {
        tick(width: 13)
        tick(width: 13)
        Rectangle()
          .fill(Theme.blue)
          .frame(width: 19, height: 2.5)
      }
      .padding(.bottom, 58)
    }
    .accessibilityLabel(
      celsius.map { "Processor \($0)" } ?? "Processor temperature unavailable"
    )
  }

  private func tick(width: CGFloat) -> some View {
    Rectangle()
      .fill(Color(white: 0.35))
      .frame(width: width, height: 2.5)
  }
}

// MARK: - Processes

struct ProcessesCard: View {
  let processes: [ProcessStat]

  var body: some View {
    CardShell {
      CardHeader(card: .processes)
      if processes.isEmpty {
        Text("—")
          .foregroundStyle(Theme.secondary)
          .font(.system(size: 14))
          .padding(.top, 6)
      }
      VStack(alignment: .leading, spacing: 14) {
        ForEach(processes) { process in
          HStack(alignment: .top, spacing: 10) {
            ProcessIconView(appPath: process.appPath)
              .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
              Text(process.appName)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
              HStack(spacing: 10) {
                Text(Format.percent(value: process.cpuPercent))
                Text(Format.percent(fraction: process.memoryFraction))
                  .foregroundStyle(Theme.secondary)
                Text(Format.bytes(process.memoryBytes))
              }
              .font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            "\(process.appName), CPU \(Format.percent(value: process.cpuPercent)), "
              + "memory \(Format.bytes(process.memoryBytes))"
          )
        }
      }
      .padding(.top, 2)
    }
  }
}

struct ProcessIconView: View {
  let appPath: String?

  var body: some View {
    if let appPath {
      Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
        .resizable()
        .aspectRatio(contentMode: .fit)
    } else {
      RoundedRectangle(cornerRadius: 7)
        .fill(Color.white.opacity(0.10))
        .overlay(
          Image(systemName: "terminal")
            .font(.system(size: 14))
            .foregroundStyle(.white)
        )
    }
  }
}

// MARK: - Device

struct DeviceCard: View {
  let device: DeviceStats?

  var body: some View {
    CardShell {
      CardHeader(card: .device)
      Text(device?.osVersion ?? "—")
        .font(.system(size: 30, weight: .bold).monospacedDigit())
      Spacer(minLength: 6)
      VStack(alignment: .leading, spacing: 3) {
        Text("Up time")
          .foregroundStyle(Theme.secondary)
          .font(.system(size: 14))
        Text(device.map { Format.uptime($0.uptime) } ?? "—")
          .font(.system(size: 16, weight: .bold).monospacedDigit())
      }
    }
  }
}
