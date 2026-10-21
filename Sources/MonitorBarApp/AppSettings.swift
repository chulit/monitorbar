import Foundation

/// The six cards, in popover order. The raw value doubles as the
/// UserDefaults key fragment and the Settings toggle identity.
enum CardID: String, CaseIterable, Identifiable {
  case memory
  case cpu
  case network
  case temperature
  case processes
  case device

  var id: String { rawValue }

  var title: String {
    switch self {
    case .memory: return "Memory"
    case .cpu: return "Processor Load"
    case .network: return "Network Activity"
    case .temperature: return "Processor Temperature"
    case .processes: return "Processes"
    case .device: return "Device"
    }
  }

  var icon: String {
    switch self {
    case .memory: return "memorychip"
    case .cpu: return "cpu"
    case .network: return "globe"
    case .temperature: return "thermometer.medium"
    case .processes: return "terminal"
    case .device: return "laptopcomputer"
    }
  }
}

enum MenubarMetric: String, CaseIterable, Identifiable {
  case cpuMemory
  case cpu
  case memory
  case network
  case temperature
  case iconOnly

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cpuMemory: return "CPU + Memory"
    case .cpu: return "CPU"
    case .memory: return "Memory"
    case .network: return "Network"
    case .temperature: return "Temperature"
    case .iconOnly: return "Icon only"
    }
  }
}

/// UserDefaults-backed settings — the app's only configuration surface.
/// Keys are shared with StatsStore, which reads them directly each tick
/// so changes apply without a restart.
final class AppSettings: ObservableObject {
  static let intervalKey = "refreshInterval"
  static let publicIPKey = "showPublicIP"

  @Published var refreshInterval: Double {
    didSet { UserDefaults.standard.set(refreshInterval, forKey: Self.intervalKey) }
  }
  @Published var menubarMetric: MenubarMetric {
    didSet { UserDefaults.standard.set(menubarMetric.rawValue, forKey: "menubarMetric") }
  }
  @Published var showPublicIP: Bool {
    didSet { UserDefaults.standard.set(showPublicIP, forKey: Self.publicIPKey) }
  }
  @Published var hiddenCards: Set<String> {
    didSet {
      UserDefaults.standard.set(Array(hiddenCards), forKey: "hiddenCards")
    }
  }

  init() {
    let defaults = UserDefaults.standard
    refreshInterval = defaults.object(forKey: Self.intervalKey) as? Double ?? 2
    menubarMetric =
      MenubarMetric(rawValue: defaults.string(forKey: "menubarMetric") ?? "") ?? .cpuMemory
    showPublicIP = defaults.object(forKey: Self.publicIPKey) as? Bool ?? true
    hiddenCards = Set(defaults.stringArray(forKey: "hiddenCards") ?? [])
  }

  func isVisible(_ card: CardID) -> Bool {
    !hiddenCards.contains(card.rawValue)
  }

  func setVisible(_ card: CardID, _ visible: Bool) {
    if visible {
      hiddenCards.remove(card.rawValue)
    } else {
      hiddenCards.insert(card.rawValue)
    }
  }
}
