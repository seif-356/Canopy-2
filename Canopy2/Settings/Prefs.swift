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
    static let lockScreenPosition = "lockScreenPosition" // LockScreenPosition raw value

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
            lockScreenPosition: LockScreenPosition.center.rawValue,
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

/// Where the lock-screen player goes. "Under the clock" shows big artwork with the
/// controls below it, sized to stay between the clock and the user picture.
/// The corners show just the controls.
enum LockScreenPosition: String, CaseIterable, Identifiable {
    case center
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center: "Under the clock (artwork + controls)"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    /// Window frame for a card of `size` on `screen` (screen coordinates).
    func frame(for size: CGSize, on screen: NSRect) -> NSRect {
        let margin: CGFloat = 48
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .center:
            x = screen.midX - size.width / 2
            y = screen.midY - size.height / 2
        case .topLeft:
            x = screen.minX + margin
            y = screen.maxY - size.height - margin * 1.5
        case .topRight:
            x = screen.maxX - size.width - margin
            y = screen.maxY - size.height - margin * 1.5
        case .bottomLeft:
            x = screen.minX + margin
            y = screen.minY + margin
        case .bottomRight:
            x = screen.maxX - size.width - margin
            y = screen.minY + margin
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
