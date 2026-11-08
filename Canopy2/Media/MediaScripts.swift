import AppKit

struct ScriptError: Error {
    let code: Int
    let message: String

    /// errAEEventNotPermitted / errAEEventWouldRequireUserConsent
    var isPermissionDenied: Bool { code == -1743 || code == -1744 }
}

struct ScriptedTrack: Sendable {
    var track: Track
    /// Spotify only; Music artwork is fetched as raw data instead.
    var artworkURL: String?
}

struct ScriptSnapshot: Sendable {
    var tracks: [ScriptedTrack] = []
    var blocked: MediaPlayer?
}

/// AppleScript for Music and Spotify, run through `/usr/bin/osascript` in a separate
/// process, one at a time, on a background queue.
///
/// Not NSAppleScript: it isn't thread-safe and can crash the app when used off the
/// main thread, and on the main thread it stalls the UI while a player is slow or a
/// permission prompt is up. A child process can't crash Canopy 2, and macOS
/// attributes its Apple events (and the Automation prompt) to Canopy 2.
enum MediaScripts {
    private static let queue = DispatchQueue(label: "com.seif356.Canopy2.osascript", qos: .userInitiated)
    /// Field separator in script output (ASCII unit separator, never in song titles).
    private static let separator = "\u{1F}"

    static func snapshot(of players: [MediaPlayer]) async -> ScriptSnapshot {
        await perform { fetchSnapshot(players) }
    }

    static func send(_ command: MediaCommand, to player: MediaPlayer) async {
        await perform {
            _ = run("""
                if application "\(player.appName)" is running then
                    tell application "\(player.appName)" to \(command.appleScriptVerb)
                end if
                """)
        }
    }

    static func seek(_ player: MediaPlayer, to seconds: Double) async {
        let position = String(format: "%.2f", max(0, seconds))
        await perform {
            _ = run("""
                if application "\(player.appName)" is running then
                    tell application "\(player.appName)" to set player position to \(position)
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

    private static func fetchSnapshot(_ players: [MediaPlayer]) -> ScriptSnapshot {
        var snapshot = ScriptSnapshot()
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

    /// Runs `source` with osascript (script on stdin) and returns its stdout.
    /// `timeout` is generous so a first-run Automation prompt has time to be answered.
    private static func run(_ source: String, timeout: TimeInterval = 60) -> Result<String, ScriptError> {
        let result = ProcessRunner.run("/usr/bin/osascript", [], input: Data(source.utf8), timeout: timeout)
        guard result.status == 0 else {
            let message = result.errorOutput
            return .failure(ScriptError(code: errorCode(in: message), message: message))
        }
        return .success(result.output.trimmingCharacters(in: .newlines))
    }

    /// osascript errors end like "... (-1743)".
    private static func errorCode(in message: String) -> Int {
        guard let open = message.lastIndex(of: "("), let close = message.lastIndex(of: ")"), open < close else { return 0 }
        return Int(message[message.index(after: open)..<close]) ?? 0
    }

    /// Script output: state, name, artist, album, duration (ms), position (ms)[, artwork url]
    /// joined by `separator`, or just "stopped".
    private static func parseTrack(_ output: String, player: MediaPlayer) -> ScriptedTrack? {
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

        let track = Track(
            bundleIdentifier: player.bundleIdentifier,
            title: text(1),
            artist: text(2),
            album: text(3),
            duration: seconds(4),
            isPlaying: fields[0] == "playing",
            position: seconds(5),
            positionDate: Date()
        )
        return ScriptedTrack(track: track, artworkURL: artworkURL?.isEmpty == true ? nil : artworkURL)
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
