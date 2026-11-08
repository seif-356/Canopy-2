import AppKit

struct Track: Equatable, Sendable {
    /// Bundle ID of the app that's playing (nil if unknown).
    var bundleIdentifier: String?
    var title: String
    var artist: String
    var album: String
    /// Seconds; 0 if unknown (e.g. live streams).
    var duration: Double
    var isPlaying: Bool
    /// Seconds, as of `positionDate`.
    var position: Double
    var positionDate: Date
    var playbackRate: Double = 1

    /// Playback position extrapolated to `date`, so progress moves between updates.
    func elapsed(at date: Date) -> Double {
        guard isPlaying else { return position }
        let value = position + date.timeIntervalSince(positionDate) * max(playbackRate, 0)
        return duration > 0 ? min(duration, value) : value
    }

    /// Same song (ignores position and play state).
    var identity: String {
        "\(bundleIdentifier ?? "")|\(artist)|\(album)|\(title)"
    }

    var appName: String {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return "" }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")
    }
}

enum MediaCommand: Sendable {
    case playPause
    case next
    case previous

    /// MediaRemote command ID (see mediaremote-adapter "send").
    var mediaRemoteID: Int {
        switch self {
        case .playPause: 2
        case .next: 4
        case .previous: 5
        }
    }

    /// AppleScript verb for Music and Spotify.
    var appleScriptVerb: String {
        switch self {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
    }
}

/// Media apps the AppleScript fallback can read and control.
enum MediaPlayer: String, CaseIterable, Sendable {
    case music
    case spotify

    var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var appName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Posted by the app whenever playback changes.
    var playbackNotification: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    init?(bundleIdentifier: String?) {
        guard let match = MediaPlayer.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
        self = match
    }
}

/// What a media source reports.
struct MediaUpdate {
    var track: Track?
    /// nil = unchanged / not provided by this update.
    var artworkData: Data?
    /// Spotify (AppleScript) gives a URL instead of data.
    var artworkURL: URL?
    /// A running player refused our Apple events (Automation permission denied).
    var blockedPlayer: MediaPlayer?
}

/// A way to read and control what's playing.
@MainActor
protocol MediaSource: AnyObject {
    var onUpdate: ((MediaUpdate) -> Void)? { get set }
    /// Called if the source stops working, so the service can fall back.
    var onFailure: (() -> Void)? { get set }
    /// Faster polling while the notch is open (only matters for polling sources).
    var isActive: Bool { get set }
    func start()
    func stop()
    func refresh()
    func send(_ command: MediaCommand)
    func seek(to seconds: Double)
}
