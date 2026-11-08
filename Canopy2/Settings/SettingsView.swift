import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var notifications: NotificationMirror

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MediaSettings(nowPlaying: nowPlaying)
                .tabItem { Label("Media", systemImage: "music.note") }
            NotificationSettings(notifications: notifications)
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            HUDSettings()
                .tabItem { Label("Volume & Brightness", systemImage: "speaker.wave.2") }
            WidgetSettings()
                .tabItem { Label("Widget", systemImage: "rectangle.on.rectangle") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 470)
        .onAppear { NSApp.activate() }
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.showOnNotchless) private var showOnNotchless = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show a notch on displays without one", isOn: $showOnNotchless)
            } footer: {
                Text("Hover over the notch to open it. Drag files onto it to put them on the shelf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

private struct MediaSettings: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @AppStorage(Prefs.mediaSource) private var mediaSource = MediaSourcePreference.automatic.rawValue
    @AppStorage(Prefs.showMusicActivity) private var showMusicActivity = true
    @AppStorage(Prefs.trackBanner) private var trackBanner = true
    @AppStorage(Prefs.lyricsEnabled) private var lyricsEnabled = true
    @AppStorage(Prefs.closedLyrics) private var closedLyrics = false

    var body: some View {
        Form {
            Section {
                Picker("Show media from", selection: $mediaSource) {
                    ForEach(MediaSourcePreference.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                LabeledContent("In use", value: nowPlaying.sourceDescription)
            } footer: {
                Text("\"All apps\" covers browsers, Podcasts, VLC and anything else that shows up in Control Center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show artwork and bars beside the camera while playing", isOn: $showMusicActivity)
                Toggle("Show a banner when the song changes", isOn: $trackBanner)
            }
            Section {
                Toggle("Synced lyrics", isOn: $lyricsEnabled)
                Toggle("Show the current line under the closed notch", isOn: $closedLyrics)
                    .disabled(!lyricsEnabled || !showMusicActivity)
            } footer: {
                Text("Lyrics come from LRCLIB (lrclib.net), a free, open lyrics database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotificationSettings: View {
    @ObservedObject var notifications: NotificationMirror
    @AppStorage(Prefs.notificationMirroring) private var mirroring = false

    var body: some View {
        Form {
            Section {
                Toggle("Show other apps' notifications in the notch", isOn: $mirroring)
                LabeledContent("Status", value: statusText)
                if notifications.status == .needsFullDiskAccess {
                    Button("Open Full Disk Access Settings") { SystemSettings.open(.fullDiskAccess) }
                }
            } footer: {
                Text("""
                    macOS has no public way to read other apps' notifications, so Canopy 2 reads the \
                    Notification Center database. That needs Full Disk Access: add Canopy2 in \
                    System Settings › Privacy & Security › Full Disk Access. Canopy 2 only reads new \
                    notifications and never sends them anywhere. To avoid seeing each one twice, set \
                    those apps' alert style to None in System Settings › Notifications.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch notifications.status {
        case .off: "Off"
        case .running: "Working"
        case .needsFullDiskAccess: "Needs Full Disk Access"
        case .unavailable(let reason): reason
        }
    }
}

private struct HUDSettings: View {
    @AppStorage(Prefs.volumeHUD) private var volumeHUD = true
    @AppStorage(Prefs.replaceSystemHUD) private var replaceSystemHUD = false
    @State private var isTrusted = MediaKeyTap.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Show volume changes in the notch", isOn: $volumeHUD)
            }
            Section {
                Toggle("Replace the macOS volume and brightness pop-ups", isOn: $replaceSystemHUD)
                LabeledContent("Accessibility", value: isTrusted ? "Allowed" : "Not allowed")
                if !isTrusted {
                    Button("Allow in Accessibility Settings…") {
                        MediaKeyTap.requestTrust()
                        SystemSettings.open(.accessibility)
                    }
                }
            } footer: {
                Text("""
                    To hide Apple's pop-up, Canopy 2 handles the volume, mute and brightness keys \
                    itself, which needs Accessibility permission. Each new build of the app has to be \
                    allowed again (remove the old Canopy2 entry first).
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            isTrusted = MediaKeyTap.isTrusted
        }
    }
}

private struct WidgetSettings: View {
    @AppStorage(Prefs.widgetEnabled) private var widgetEnabled = false
    @AppStorage(Prefs.widgetPreset) private var widgetPreset = WidgetPreset.lockScreen.rawValue
    @AppStorage(Prefs.lockScreenWidget) private var lockScreenWidget = false

    var body: some View {
        Form {
            Section {
                Toggle("Show the widget on the desktop", isOn: $widgetEnabled)
                Picker("Layout", selection: $widgetPreset) {
                    ForEach(WidgetPreset.allCases) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                .disabled(!widgetEnabled)
            } footer: {
                Text("Drag the bar at the top of the widget to move it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show Now Playing on the lock screen (experimental)", isOn: $lockScreenWidget)
            } footer: {
                Text("""
                    Uses private macOS APIs that Apple can change in any update. If your Mac \
                    misbehaves at the lock screen, turn this off.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/seif-356/Canopy-2")!)
            }
            Section("Credits") {
                Text("System-wide media uses mediaremote-adapter by Jonas van den Berg (BSD 3-Clause License).")
                Text("Lyrics from LRCLIB (lrclib.net).")
            }
            .font(.callout)
        }
        .formStyle(.grouped)
    }
}
