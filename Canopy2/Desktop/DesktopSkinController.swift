import AppKit
import Combine
import SwiftUI

enum DesktopPanel: Equatable {
    case nowPlaying
    case search
    case artist(SearchArtist)
}

/// State of the desktop skin: which panel shows, the search and the artist page.
@MainActor
final class DesktopSkinState: ObservableObject {
    @Published var panel: DesktopPanel = .nowPlaying
    @Published var query = ""
    @Published private(set) var results: SearchResults?
    @Published private(set) var isSearching = false
    @Published private(set) var searchFailed = false
    @Published private(set) var artistSongs: [SearchSong] = []
    @Published var showsLyrics = true

    let player: NowPlayingService
    /// Makes the skin window key so the search field can take typing.
    var onNeedsKeyboard: (() -> Void)?
    private var searchTask: Task<Void, Never>?

    init(player: NowPlayingService) {
        self.player = player
    }

    var target: MusicTarget {
        MusicTarget.current.resolved(playingBundle: player.track?.bundleIdentifier)
    }

    /// Searches shortly after typing stops.
    func queryChanged() {
        searchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            results = nil
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await ITunesSearch.search(term)
            guard !Task.isCancelled, let self else { return }
            self.results = found
            self.searchFailed = found == nil
            self.isSearching = false
        }
    }

    func showArtist(_ artist: SearchArtist) {
        artistSongs = []
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { panel = .artist(artist) }
        Task { [weak self] in
            let songs = await ITunesSearch.songs(byArtist: artist.id)
            guard let self, self.panel == .artist(artist) else { return }
            self.artistSongs = songs
        }
    }

    func open(_ song: SearchSong) {
        target.open(query: "\(song.title) \(song.artist)", appleMusicURL: song.url)
    }

    func open(_ album: SearchAlbum) {
        target.open(query: "\(album.title) \(album.artist)", appleMusicURL: album.url)
    }

    func open(_ artist: SearchArtist) {
        target.open(query: artist.name, appleMusicURL: artist.url)
    }

    func open(_ played: PlayedTrack) {
        target.open(query: "\(played.title) \(played.artist)")
    }

    func openSearch() {
        onNeedsKeyboard?()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { panel = .search }
    }

    func closePanel() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { panel = .nowPlaying }
    }
}

/// Full-screen "desktop skin": sits above the wallpaper and desktop icons, below
/// every app window, on every Space. Blurred artwork, big clock, recently played,
/// a player bar and Apple Music catalog search.
@MainActor
final class DesktopSkinController {
    let state: DesktopSkinState
    private let player: NowPlayingService
    private let lyrics: LyricsService
    private let history: PlayHistory
    private var window: DesktopSkinWindow?
    private var observer: NSObjectProtocol?

    init(player: NowPlayingService, lyrics: LyricsService, history: PlayHistory) {
        self.player = player
        self.lyrics = lyrics
        self.history = history
        state = DesktopSkinState(player: player)
    }

    func update(enabled: Bool) {
        guard enabled else {
            window?.orderOut(nil)
            window = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            return
        }
        guard window == nil, let screen = NSScreen.screens.first else { return }
        let window = DesktopSkinWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        let host = FirstClickHostingView(rootView: DesktopSkinView(
            state: state, player: player, lyrics: lyrics, history: history
        ))
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        state.onNeedsKeyboard = { [weak window] in
            NSApp.activate()
            window?.makeKey()
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let screen = NSScreen.screens.first else { return }
                self?.window?.setFrame(screen.frame, display: true)
            }
        }
    }
}

/// Can take keyboard focus (for the search field) even though it's borderless.
final class DesktopSkinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
