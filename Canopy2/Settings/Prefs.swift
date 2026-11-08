import Foundation

/// UserDefaults keys shared by the settings screen (@AppStorage) and the controllers.
enum Prefs {
    // General
    static let showOnNotchless = "showOnNotchless"

    // Media
    static let mediaSource = "mediaSource"            // MediaSourcePreference raw value
    static let showMusicActivity = "showMusicActivity"
    static let trackBanner = "trackBanner"
    static let lyricsEnabled = "lyricsEnabled"
    static let closedLyrics = "closedLyrics"

    // Notifications
    static let notificationMirroring = "notificationMirroring"

    // HUD
    static let volumeHUD = "volumeHUD"
    static let replaceSystemHUD = "replaceSystemHUD"

    // Widget
    static let widgetEnabled = "widgetEnabled"
    static let widgetPreset = "widgetPreset"          // WidgetPreset raw value
    static let lockScreenWidget = "lockScreenWidget"

    // Shelf
    static let shelfPaths = "shelfPaths"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showOnNotchless: true,
            mediaSource: MediaSourcePreference.automatic.rawValue,
            showMusicActivity: true,
            trackBanner: true,
            lyricsEnabled: true,
            closedLyrics: false,
            notificationMirroring: false,
            volumeHUD: true,
            replaceSystemHUD: false,
            widgetEnabled: false,
            widgetPreset: WidgetPreset.lockScreen.rawValue,
            lockScreenWidget: false,
        ])
    }

    static func bool(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func string(_ key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    static var isNotchlessEnabled: Bool { bool(showOnNotchless) }
    static var isMusicActivityEnabled: Bool { bool(showMusicActivity) }

    /// Snapshot of every setting, so observers can tell which ones changed.
    static func snapshot() -> [String: String] {
        let keys = [
            showOnNotchless, mediaSource, showMusicActivity, trackBanner, lyricsEnabled, closedLyrics,
            notificationMirroring, volumeHUD, replaceSystemHUD, widgetEnabled, widgetPreset, lockScreenWidget,
        ]
        var result: [String: String] = [:]
        for key in keys {
            result[key] = UserDefaults.standard.object(forKey: key).map { "\($0)" } ?? ""
        }
        return result
    }
}

enum MediaSourcePreference: String, CaseIterable, Identifiable {
    /// Every app (browsers, Podcasts, VLC…) through MediaRemote, falling back to AppleScript.
    case automatic
    /// Only Music and Spotify, through AppleScript.
    case appleScript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "All apps (recommended)"
        case .appleScript: "Music and Spotify only"
        }
    }
}

enum WidgetPreset: String, CaseIterable, Identifiable {
    case lockScreen
    case nowPlaying
    case lyrics
    case clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockScreen: "Clock + Now Playing"
        case .nowPlaying: "Now Playing"
        case .lyrics: "Lyrics"
        case .clock: "Minimal Clock"
        }
    }
}
