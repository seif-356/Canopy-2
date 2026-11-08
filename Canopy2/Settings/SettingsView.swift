import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.showOnNotchless) private var showOnNotchless = true
    @AppStorage(Prefs.showMusicActivity) private var showMusicActivity = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Show a notch on displays without one", isOn: $showOnNotchless)
                Toggle("Show the playing song while the notch is closed", isOn: $showMusicActivity)
            } footer: {
                Text("Hover over the notch to open it. Drag files onto it to put them on the shelf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Accessory apps don't come to the front on their own.
            NSApp.activate()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
