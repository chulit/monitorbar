import ServiceManagement
import SwiftUI

/// The only window in the app, and deliberately small: launch at
/// login, refresh cadence, what the menu bar shows, which cards are
/// visible, and the public-IP toggle. That's all the settings a
/// menu-bar monitor needs.
struct SettingsView: View {
  @EnvironmentObject private var settings: AppSettings
  @State private var launchAtLogin =
    SMAppService.mainApp.status == .enabled

  var body: some View {
    Form {
      Section("General") {
        Toggle("Launch at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { newValue in
            setLaunchAtLogin(newValue)
          }
        Picker("Refresh every", selection: $settings.refreshInterval) {
          Text("1 second").tag(1.0)
          Text("2 seconds").tag(2.0)
          Text("5 seconds").tag(5.0)
        }
      }

      Section("Menu Bar") {
        Picker("Show in menu bar", selection: $settings.menubarMetric) {
          ForEach(MenubarMetric.allCases) { metric in
            Text(metric.title).tag(metric)
          }
        }
      }

      Section("Cards") {
        ForEach(CardID.allCases) { card in
          Toggle(
            card.title,
            isOn: Binding(
              get: { settings.isVisible(card) },
              set: { settings.setVisible(card, $0) }
            )
          )
        }
      }

      Section("Network") {
        Toggle("Show public IP", isOn: $settings.showPublicIP)
        Text(
          "Fetched from api.ipify.org at most once a minute. "
            + "Turn it off and the app makes no network calls at all."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Text("MonitorBar")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Quit MonitorBar") {
            NSApplication.shared.terminate(nil)
          }
          .keyboardShortcut("q", modifiers: .command)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 360)
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      // Revert the toggle to the real state instead of pretending.
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}
