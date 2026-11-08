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

/// Runs AppleScript through `/usr/bin/osascript` in a separate process, one at a time,
/// on a background queue.
///
/// Not NSAppleScript: it isn't thread-safe and can crash the app when used off the
/// main thread, and on the main thread it stalls the UI while a player is slow or a
/// permission prompt is up. A child process can't crash Canopy 2, and macOS
/// attributes its Apple events (and the Automation prompt) to Canopy 2.
enum MediaScripts {
    private static let queue = DispatchQueue(label: "com.seif356.Canopy2.osascript", qos: .userInitiated)
    /// Field separator in script output (ASCII unit separator, never in song titles).
    private static let separator = "\u{1F}"

    static func snapshot(of players: [MediaPlayer]) async -> PlayerSnapshot {
        await perform { fetchSnapshot(players) }
    }

    static func send(_ command: MediaCommand, to player: MediaPlayer) async {
        await perform {
            _ = run("""
                if application "\(player.appName)" is running then
                    tell application "\(player.appName)" to \(command.verb)
                end if
                """)
        }
    }

    static func musicArtworkData() async -> Data? {
        await perform {
            guard MediaPlayer.music.isRunning,
                  case .success(let output) = run(musicArtworkScript, timeout: 10) else { return nil }
            return decodeAppleScriptData(output)
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
            case .success(let output):
                if let track = parseTrack(output, player: player) {
                    snapshot.tracks.append(track)
                }
            case .failure(let error):
                if error.isPermissionDenied { snapshot.blocked = player }
            }
        }
        return snapshot
    }

    /// Runs `source` with osascript and returns its stdout.
    /// `timeout` is generous so a first-run Automation prompt has time to be answered.
    private static func run(_ source: String, timeout: TimeInterval = 60) -> Result<String, ScriptError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [] // no arguments: osascript reads the script from stdin
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return .failure(ScriptError(code: 0, message: "Could not start osascript: \(error.localizedDescription)"))
        }

        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        input.fileHandleForWriting.write(Data(source.utf8))
        try? input.fileHandleForWriting.close()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr, as: UTF8.self)
            return .failure(ScriptError(code: errorCode(in: message), message: message))
        }
        return .success(String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .newlines))
    }

    /// osascript errors end like "... (-1743)".
    private static func errorCode(in message: String) -> Int {
        guard let open = message.lastIndex(of: "("), let close = message.lastIndex(of: ")"), open < close else { return 0 }
        return Int(message[message.index(after: open)..<close]) ?? 0
    }

    /// Script output: state, name, artist, album, duration (ms), position (ms)[, artwork url]
    /// joined by `separator`, or just "stopped".
    private static func parseTrack(_ output: String, player: MediaPlayer) -> Track? {
        let fields = output.components(separatedBy: separator)
        guard fields.count >= 6, fields[0] != "stopped" else { return nil }

        func text(_ index: Int) -> String {
            fields[index] == "missing value" ? "" : fields[index]
        }
        func seconds(_ index: Int) -> Double {
            let value = fields[index].replacingOccurrences(of: ",", with: ".")
            return (Double(value) ?? 0) / 1000
        }

        var artworkURL = fields.count >= 7 ? text(6) : nil
        if let url = artworkURL, url.hasPrefix("http://") {
            artworkURL = "https://" + url.dropFirst("http://".count) // App Transport Security
        }

        return Track(
            player: player,
            title: text(1),
            artist: text(2),
            album: text(3),
            duration: seconds(4),
            isPlaying: fields[0] == "playing",
            position: seconds(5),
            positionDate: Date(),
            artworkURL: artworkURL?.isEmpty == true ? nil : artworkURL
        )
    }

    /// osascript prints binary results as «data TYPE0123ABCD…» (4-char type, then hex).
    private static func decodeAppleScriptData(_ output: String) -> Data? {
        guard let start = output.range(of: "«data "), let end = output.range(of: "»", options: .backwards),
              start.upperBound < end.lowerBound else { return nil }
        let body = output[start.upperBound..<end.lowerBound]
        guard body.count > 4 else { return nil }
        let hex = body.dropFirst(4).utf8
        var data = Data(capacity: hex.count / 2)
        var high: UInt8?
        for char in hex {
            let nibble: UInt8
            switch char {
            case 48...57: nibble = char - 48       // 0-9
            case 65...70: nibble = char - 55       // A-F
            case 97...102: nibble = char - 87      // a-f
            default: return nil
            }
            if let h = high {
                data.append(h << 4 | nibble)
                high = nil
            } else {
                high = nibble
            }
        }
        return data.isEmpty ? nil : data
    }

    private static func trackScript(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            """
            if application "Spotify" is not running then return "stopped"
            set sep to character id 31
            tell application "Spotify"
                set playerState to (player state as text)
                if playerState is "stopped" then return "stopped"
                try
                    set t to current track
                    set durationMs to ((duration of t) as integer)
                    set positionMs to ((player position) * 1000) as integer
                    return playerState & sep & ((name of t) as text) & sep & ((artist of t) as text) & sep & ((album of t) as text) & sep & durationMs & sep & positionMs & sep & ((artwork url of t) as text)
                on error
                    return "stopped"
                end try
            end tell
            """
        case .music:
            """
            if application "Music" is not running then return "stopped"
            set sep to character id 31
            tell application "Music"
                set playerState to (player state as text)
                if playerState is "stopped" then return "stopped"
                try
                    set t to current track
                    set durationMs to ((duration of t) * 1000) as integer
                    set positionMs to ((player position) * 1000) as integer
                    return playerState & sep & ((name of t) as text) & sep & ((artist of t) as text) & sep & ((album of t) as text) & sep & durationMs & sep & positionMs
                on error
                    return "stopped"
                end try
            end tell
            """
        }
    }

    private static let musicArtworkScript = """
        if application "Music" is not running then return ""
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
}
