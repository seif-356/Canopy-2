import Foundation

/// UserDefaults keys shared by the settings screen (@AppStorage) and the notch controller.
enum Prefs {
    static let showOnNotchless = "showOnNotchless"
    static let showMusicActivity = "showMusicActivity"
    static let shelfPaths = "shelfPaths"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showOnNotchless: true,
            showMusicActivity: true,
        ])
    }

    static var isNotchlessEnabled: Bool {
        UserDefaults.standard.bool(forKey: showOnNotchless)
    }

    static var isMusicActivityEnabled: Bool {
        UserDefaults.standard.bool(forKey: showMusicActivity)
    }
}
