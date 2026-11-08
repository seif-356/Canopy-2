import Combine
import SwiftUI

enum NotchTab: Hashable {
    case nowPlaying
    case lyrics
    case shelf
}

struct HUDState: Equatable {
    enum Kind: Equatable {
        case volume
        case brightness
    }

    var kind: Kind
    /// 0…1
    var level: Float
    var isMuted = false

    var displayLevel: Float { isMuted ? 0 : level }

    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.4 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if isMuted || level <= 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

struct Banner: Identifiable, Equatable {
    enum Kind: Equatable {
        /// "Now playing" when the song changes.
        case track
        /// A mirrored notification from another app.
        case notification(bundleIdentifier: String)
    }

    let id = UUID()
    var kind: Kind
    var icon: NSImage?
    var title: String
    var subtitle: String

    static func == (lhs: Banner, rhs: Banner) -> Bool { lhs.id == rhs.id }
}

/// What the closed notch shows, most important first.
enum ClosedPresentation: Equatable {
    case idle
    case activity(withLyrics: Bool)
    case hud(HUDState)
    case banner(Banner)
}

/// State the notch views render. The controller owns it and drives it.
@MainActor
final class NotchModel: ObservableObject {
    @Published var geometry: NotchGeometry?
    @Published var isOpen = false
    @Published var tab: NotchTab = .nowPlaying
    @Published var isDropTargeted = false
    @Published var hud: HUDState?
    @Published var banner: Banner?
    /// Music playing: artwork + bars beside the camera.
    @Published private(set) var showsActivity = false
    /// Synced lyrics line under the closed notch.
    @Published private(set) var showsClosedLyrics = false

    let nowPlaying: NowPlayingService
    let lyrics: LyricsService
    let shelf: ShelfStore

    var onBannerTap: ((Banner) -> Void)?

    private var isPlaying = false
    private var hasSyncedLyrics = false
    private var cancellables: Set<AnyCancellable> = []

    init(nowPlaying: NowPlayingService, lyrics: LyricsService, shelf: ShelfStore) {
        self.nowPlaying = nowPlaying
        self.lyrics = lyrics
        self.shelf = shelf

        nowPlaying.$track
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak self] playing in
                MainActor.assumeIsolated {
                    self?.isPlaying = playing
                    self?.updateActivity()
                }
            }
            .store(in: &cancellables)

        lyrics.$status
            .map { $0 == .synced }
            .removeDuplicates()
            .sink { [weak self] synced in
                MainActor.assumeIsolated {
                    self?.hasSyncedLyrics = synced
                    self?.updateActivity()
                }
            }
            .store(in: &cancellables)
    }

    func updateActivity() {
        let activity = isPlaying && Prefs.isMusicActivityEnabled
        let lyricsLine = activity && hasSyncedLyrics && Prefs.bool(Prefs.closedLyrics)
        guard activity != showsActivity || lyricsLine != showsClosedLyrics else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showsActivity = activity
            showsClosedLyrics = lyricsLine
        }
    }

    var closedPresentation: ClosedPresentation {
        if let hud { return .hud(hud) }
        if let banner { return .banner(banner) }
        if showsActivity { return .activity(withLyrics: showsClosedLyrics) }
        return .idle
    }

    /// Size of the open notch: compact for the player, taller for lyrics.
    var openSize: CGSize {
        let notchHeight = geometry?.notchSize.height ?? 32
        switch tab {
        case .nowPlaying: return CGSize(width: 340, height: notchHeight + 126)
        case .lyrics: return CGSize(width: 380, height: notchHeight + 196)
        case .shelf: return CGSize(width: 380, height: notchHeight + 132)
        }
    }

    /// Size of the black shape while closed, including its curved "ears".
    var closedSize: CGSize {
        guard let geometry else { return .zero }
        let base = geometry.notchSize.width + NotchMetrics.closedTopRadius * 2
        let height = geometry.notchSize.height
        switch closedPresentation {
        case .idle:
            return CGSize(width: base, height: height)
        case .activity(let withLyrics):
            let width = base + (height * 0.9) * 2
            return withLyrics
                ? CGSize(width: max(width, 420), height: height + 26)
                : CGSize(width: width, height: height)
        case .hud:
            return CGSize(width: base + 240, height: height)
        case .banner:
            return CGSize(width: max(base + 160, 420), height: height + 66)
        }
    }
}
