import Foundation

struct LyricLine: Equatable, Identifiable, Sendable {
    let id: Int
    /// Seconds from the start of the song.
    let time: Double
    let text: String
}

/// Time-synced lyrics from LRCLIB (lrclib.net: free, open, no API key).
@MainActor
final class LyricsService: ObservableObject {
    enum Status: Equatable {
        case idle
        case disabled
        case loading
        case synced
        /// LRCLIB has the words but no timings.
        case unsynced
        case notFound
        case failed
    }

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var status: Status = .idle

    private var currentKey: String?
    private var task: Task<Void, Never>?
    /// Results per song for this session (network failures aren't cached).
    private var cache: [String: LRCLib.Result] = [:]

    func load(for track: Track?) {
        guard Prefs.bool(Prefs.lyricsEnabled) else {
            reset(to: .disabled)
            return
        }
        guard let track, !track.title.isEmpty else {
            reset(to: .idle)
            return
        }
        let key = track.identity
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()

        if let cached = cache[key] {
            show(cached)
            return
        }
        lines = []
        status = .loading
        let title = track.title, artist = track.artist, album = track.album, duration = track.duration
        task = Task {
            let result = await LRCLib.fetch(title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, currentKey == key else { return }
            if case .failed = result {} else { cache[key] = result }
            show(result)
        }
    }

    /// Re-evaluates after the lyrics setting changes.
    func reload(for track: Track?) {
        currentKey = nil
        load(for: track)
    }

    /// Index of the line being sung at `time` (last line that started at or before it).
    func index(at time: Double) -> Int? {
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    func line(at time: Double) -> LyricLine? {
        index(at: time).map { lines[$0] }
    }

    private func reset(to status: Status) {
        task?.cancel()
        currentKey = nil
        lines = []
        self.status = status
    }

    private func show(_ result: LRCLib.Result) {
        switch result {
        case .synced(let parsed):
            lines = parsed
            status = .synced
        case .unsynced:
            lines = []
            status = .unsynced
        case .notFound:
            lines = []
            status = .notFound
        case .failed:
            lines = []
            status = .failed
        }
    }
}

enum LRCLib {
    enum Result: Sendable {
        case synced([LyricLine])
        case unsynced
        case notFound
        case failed
    }

    private static let userAgent = "Canopy2 (https://github.com/seif-356/Canopy-2)"

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> Result {
        // 1. Exact match by title, artist, album and duration.
        if !artist.isEmpty, var components = URLComponents(string: "https://lrclib.net/api/get") {
            var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
            if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
            if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
            components.queryItems = items
            if let url = components.url {
                switch await request(url) {
                case .success(let json):
                    if let record = json as? [String: Any], let parsed = result(from: record) { return parsed }
                case .notFound:
                    break
                case .failure:
                    return .failed
                }
            }
        }

        // 2. Search, preferring a synced result with a similar duration.
        guard var search = URLComponents(string: "https://lrclib.net/api/search") else { return .failed }
        search.queryItems = artist.isEmpty
            ? [URLQueryItem(name: "q", value: title)]
            : [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        guard let url = search.url else { return .failed }
        switch await request(url) {
        case .success(let json):
            guard let records = json as? [[String: Any]], !records.isEmpty else { return .notFound }
            let synced = records.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
            let best = synced.min { lhs, rhs in
                durationDistance(lhs, duration) < durationDistance(rhs, duration)
            } ?? records.first
            return best.flatMap(result(from:)) ?? .notFound
        case .notFound:
            return .notFound
        case .failure:
            return .failed
        }
    }

    private enum Response {
        case success(Any)
        case notFound
        case failure
    }

    private static func request(_ url: URL) async -> Response {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let response = try? await URLSession.shared.data(for: request),
              let http = response.1 as? HTTPURLResponse else { return .failure }
        if http.statusCode == 404 { return .notFound }
        guard http.statusCode == 200, let json = try? JSONSerialization.jsonObject(with: response.0) else { return .failure }
        return .success(json)
    }

    private static func durationDistance(_ record: [String: Any], _ duration: Double) -> Double {
        guard duration > 0, let other = (record["duration"] as? NSNumber)?.doubleValue else { return 0 }
        return abs(other - duration)
    }

    private static func result(from record: [String: Any]) -> Result? {
        if let synced = record["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record["plainLyrics"] as? String, !plain.isEmpty {
            return .unsynced
        }
        return nil
    }

    /// Parses LRC: "[mm:ss.xx] text", possibly several time tags per line.
    static func parse(_ lrc: String) -> [LyricLine] {
        var timed: [(time: Double, text: String)] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            var rest = Substring(rawLine)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else {
                    break // metadata tag like [ar:Artist]
                }
                times.append(minutes * 60 + seconds)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                timed.append((time, text))
            }
        }
        return timed
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }
}
