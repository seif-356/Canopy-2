import AppKit
import SwiftUI

struct SearchSong: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let artist: String
    let artistID: Int?
    let album: String
    let artworkURL: URL?
    let url: URL?
}

struct SearchAlbum: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let artist: String
    let artworkURL: URL?
    let url: URL?
}

struct SearchArtist: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let genre: String
    let url: URL?
    var artworkURL: URL?
}

struct SearchResults: Sendable {
    var artists: [SearchArtist] = []
    var songs: [SearchSong] = []
    var albums: [SearchAlbum] = []

    var isEmpty: Bool { artists.isEmpty && songs.isEmpty && albums.isEmpty }
}

/// Apple Music catalog search through Apple's public iTunes Search API (no account, no key).
enum ITunesSearch {
    private static var country: String {
        Locale.current.region?.identifier.lowercased() ?? "us"
    }

    static func search(_ term: String) async -> SearchResults? {
        async let artistItems = fetch(["term": term, "entity": "musicArtist", "limit": "6"])
        async let songItems = fetch(["term": term, "entity": "song", "limit": "12"])
        async let albumItems = fetch(["term": term, "entity": "album", "limit": "10"])
        let (artistsRaw, songsRaw, albumsRaw) = await (artistItems, songItems, albumItems)
        guard artistsRaw != nil || songsRaw != nil || albumsRaw != nil else { return nil }

        let songs = (songsRaw ?? []).compactMap(song)
        let albums = (albumsRaw ?? []).compactMap(album)
        var artists = (artistsRaw ?? []).compactMap(artist)

        // The API has no artist photos: use one of their covers instead.
        for index in artists.indices {
            let id = artists[index].id
            if let cover = songs.first(where: { $0.artistID == id })?.artworkURL {
                artists[index].artworkURL = cover
            } else if let first = await fetch(["id": String(id), "entity": "album", "limit": "1"], endpoint: "lookup")?
                        .compactMap(album).first {
                artists[index].artworkURL = first.artworkURL
            }
        }
        return SearchResults(artists: artists, songs: songs, albums: albums)
    }

    /// Songs by an artist, for the artist page.
    static func songs(byArtist id: Int) async -> [SearchSong] {
        (await fetch(["id": String(id), "entity": "song", "limit": "15"], endpoint: "lookup") ?? []).compactMap(song)
    }

    // MARK: - Private

    private struct Response: Decodable {
        let results: [Item]
    }

    fileprivate struct Item: Decodable {
        let wrapperType: String?
        let kind: String?
        let trackId: Int?
        let trackName: String?
        let artistId: Int?
        let artistName: String?
        let collectionId: Int?
        let collectionName: String?
        let artworkUrl100: String?
        let trackViewUrl: String?
        let collectionViewUrl: String?
        let artistLinkUrl: String?
        let primaryGenreName: String?
    }

    private static func fetch(_ parameters: [String: String], endpoint: String = "search") async -> [Item]? {
        var components = URLComponents(string: "https://itunes.apple.com/\(endpoint)")
        var items = [URLQueryItem(name: "media", value: "music"), URLQueryItem(name: "country", value: country)]
        items += parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        components?.queryItems = items
        guard let url = components?.url,
              let response = try? await URLSession.shared.data(from: url),
              (response.1 as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return nil }
        return decoded.results
    }

    /// iTunes gives 100 px covers; the same URL serves larger sizes.
    private static func artwork(_ string: String?) -> URL? {
        guard let string else { return nil }
        return URL(string: string.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
    }

    private static func song(_ item: Item) -> SearchSong? {
        guard item.kind == "song", let id = item.trackId, let title = item.trackName else { return nil }
        return SearchSong(
            id: id, title: title, artist: item.artistName ?? "", artistID: item.artistId,
            album: item.collectionName ?? "", artworkURL: artwork(item.artworkUrl100),
            url: item.trackViewUrl.flatMap(URL.init(string:))
        )
    }

    private static func album(_ item: Item) -> SearchAlbum? {
        guard item.wrapperType == "collection", let id = item.collectionId, let title = item.collectionName else { return nil }
        return SearchAlbum(
            id: id, title: title, artist: item.artistName ?? "", artworkURL: artwork(item.artworkUrl100),
            url: item.collectionViewUrl.flatMap(URL.init(string:))
        )
    }

    private static func artist(_ item: Item) -> SearchArtist? {
        guard item.wrapperType == "artist", let id = item.artistId, let name = item.artistName else { return nil }
        return SearchArtist(
            id: id, name: name, genre: item.primaryGenreName ?? "",
            url: item.artistLinkUrl.flatMap(URL.init(string:)), artworkURL: nil
        )
    }
}

/// Where search results and history items open.
enum MusicTarget: String, CaseIterable, Identifiable {
    case automatic
    case appleMusic
    case spotify
    case youTubeMusic
    case soundCloud
    case amazonMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youTubeMusic: "YouTube Music"
        case .soundCloud: "SoundCloud"
        case .amazonMusic: "Amazon Music"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        default: nil
        }
    }

    /// Fallback symbol when there's no installed app icon to show.
    var symbol: String {
        switch self {
        case .automatic: "sparkles"
        case .appleMusic: "music.note"
        case .spotify: "dot.radiowaves.left.and.right"
        case .youTubeMusic: "play.circle.fill"
        case .soundCloud: "cloud.fill"
        case .amazonMusic: "music.note.house.fill"
        }
    }

    var tint: Color {
        switch self {
        case .automatic: .white
        case .appleMusic: Color(red: 0.98, green: 0.24, blue: 0.33)
        case .spotify: Color(red: 0.12, green: 0.84, blue: 0.38)
        case .youTubeMusic: Color(red: 1, green: 0.1, blue: 0.1)
        case .soundCloud: Color(red: 1, green: 0.45, blue: 0.1)
        case .amazonMusic: Color(red: 0.15, green: 0.75, blue: 0.95)
        }
    }

    static var current: MusicTarget {
        MusicTarget(rawValue: Prefs.string(Prefs.musicTarget)) ?? .automatic
    }

    /// "Automatic" means: whatever is playing right now (browser → YouTube Music), else Apple Music.
    func resolved(playingBundle: String?) -> MusicTarget {
        guard self == .automatic else { return self }
        switch playingBundle {
        case "com.spotify.client": return .spotify
        case "com.apple.Music": return .appleMusic
        case "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
             "com.microsoft.edgemac", "com.brave.Browser":
            return .youTubeMusic
        default: return .appleMusic
        }
    }

    /// Opens `query` here. `appleMusicURL` (from search results) opens the exact item in Music.
    func open(query: String, appleMusicURL: URL? = nil) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        let link: String
        switch self {
        case .automatic, .appleMusic:
            if let appleMusicURL, var components = URLComponents(url: appleMusicURL, resolvingAgainstBaseURL: false) {
                components.scheme = "music" // open in the Music app, not the browser
                if let url = components.url, NSWorkspace.shared.open(url) { return }
            }
            link = "music://music.apple.com/search?term=\(encoded)"
        case .spotify:
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
            link = installed ? "spotify:search:\(encoded)" : "https://open.spotify.com/search/\(encoded)"
        case .youTubeMusic:
            link = "https://music.youtube.com/search?q=\(encoded)"
        case .soundCloud:
            link = "https://soundcloud.com/search?q=\(encoded)"
        case .amazonMusic:
            link = "https://music.amazon.com/search/\(encoded)"
        }
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
