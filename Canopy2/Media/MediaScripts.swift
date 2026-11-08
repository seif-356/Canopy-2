import AppKit

/// Media apps Canopy 2 can read and control through AppleScript (public API).
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

    /// Checked before every script: `tell application` would launch an app that isn't running.
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

enum MediaCommand: Sendable {
    case playPause
    case next
    case previous

    var verb: String {
        switch self {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
    }
}

struct Track: Equatable, Sendable {
    let player: MediaPlayer
    let title: String
    let artist: String
    let album: String
    /// Seconds.
    let duration: Double
    var isPlaying: Bool
    /// Seconds, as of `positionDate`.
    var position: Double
    var positionDate: Date
    /// Spotify only; Music artwork is fetched as raw data instead.
    let artworkURL: String?

    /// Playback position extrapolated to `date`, so the progress bar moves between polls.
    func elapsed(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(positionDate))
    }

    var artworkKey: String {
        "\(player.rawValue)|\(artist)|\(album)|\(title)"
    }
}

struct PlayerSnapshot: Sendable {
    var tracks: [Track] = []
    /// A running player that refused our Apple events (Automation permission denied).
    var blocked: MediaPlayer?
}

struct ScriptError: Error {
    let code: Int
    let message: String

    /// errAEEventNotPermitted / errAEEventWouldRequireUserConsent
    var isPermissionDenied: Bool { code == -1743 || code == -1744 }
}

/// Runs every AppleScript on one serial background queue, so a slow app or a
/// pending permission prompt never blocks the UI.
enum MediaScripts {
    private static let queue = DispatchQueue(label: "com.seif356.Canopy2.applescript", qos: .userInitiated)

    static func snapshot(of players: [MediaPlayer]) async -> PlayerSnapshot {
        await perform { fetchSnapshot(players) }
    }

    static func send(_ command: MediaCommand, to player: MediaPlayer) async {
        await perform {
            _ = run("tell application \"\(player.appName)\" to \(command.verb)")
        }
    }

    static func musicArtworkData() async -> Data? {
        await perform {
            guard MediaPlayer.music.isRunning,
                  case .success(let descriptor) = run(musicArtworkScript) else { return nil }
            let data = descriptor.data
            return data.isEmpty ? nil : data
        }
    }

    // MARK: - Private

    private static func perform<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private static func fetchSnapshot(_ players: [MediaPlayer]) -> PlayerSnapshot {
        var snapshot = PlayerSnapshot()
        for player in players where player.isRunning {
            switch run(trackScript(for: player)) {
            case .success(let descriptor):
                if let track = parseTrack(descriptor, player: player) {
                    snapshot.tracks.append(track)
                }
            case .failure(let error):
                if error.isPermissionDenied { snapshot.blocked = player }
            }
        }
        return snapshot
    }

    private static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(ScriptError(code: 0, message: "Could not create script"))
        }
        var errorInfo: NSDictionary?
        let output: NSAppleEventDescriptor? = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return .failure(ScriptError(
                code: errorInfo[NSAppleScript.errorNumber] as? Int ?? 0,
                message: errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            ))
        }
        guard let output else {
            return .failure(ScriptError(code: 0, message: "No result"))
        }
        return .success(output)
    }

    /// Script result: {state, name, artist, album, duration (s), position (s)[, artwork url]}
    /// or {"stopped"}.
    private static func parseTrack(_ list: NSAppleEventDescriptor, player: MediaPlayer) -> Track? {
        guard list.numberOfItems >= 6,
              let state = list.atIndex(1)?.stringValue,
              state != "stopped" else { return nil }

        func text(_ index: Int) -> String {
            let value = list.atIndex(index)?.stringValue ?? ""
            return value == "missing value" ? "" : value
        }
        func number(_ index: Int) -> Double {
            list.atIndex(index)?.doubleValue ?? 0
        }

        var artworkURL = list.numberOfItems >= 7 ? list.atIndex(7)?.stringValue : nil
        if let url = artworkURL, url.hasPrefix("http://") {
            artworkURL = "https://" + url.dropFirst("http://".count) // App Transport Security
        }

        return Track(
            player: player,
            title: text(2),
            artist: text(3),
            album: text(4),
            duration: number(5),
            isPlaying: state == "playing",
            position: number(6),
            positionDate: Date(),
            artworkURL: artworkURL
        )
    }

    private static func trackScript(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            """
            tell application "Spotify"
                set playerState to player state as string
                if playerState is "stopped" then return {playerState}
                try
                    set t to current track
                    return {playerState, name of t, artist of t, album of t, (duration of t) / 1000, player position, artwork url of t}
                on error
                    return {"stopped"}
                end try
            end tell
            """
        case .music:
            """
            tell application "Music"
                set playerState to player state as string
                if playerState is "stopped" then return {playerState}
                try
                    set t to current track
                    return {playerState, name of t, artist of t, album of t, duration of t, player position}
                on error
                    return {"stopped"}
                end try
            end tell
            """
        }
    }

    private static let musicArtworkScript = """
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
}
