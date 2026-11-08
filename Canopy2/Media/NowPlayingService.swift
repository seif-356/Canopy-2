import AppKit

/// Tracks what Music or Spotify is playing and forwards play/pause/skip.
///
/// Updates come from the players' own distributed notifications, plus a poll
/// (every second while the notch is open, every 5 s while closed) to keep the
/// position fresh.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var blockedPlayer: MediaPlayer?

    /// Set by the controller while the notch is open, for faster polling.
    var isActive = false

    private var artworkKey: String?
    private var isRefreshing = false
    private var needsAnotherRefresh = false
    private var ticks = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        for player in MediaPlayer.allCases {
            let token = distributed.addObserver(forName: player.playbackNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        refresh()
    }

    func refresh() {
        if isRefreshing {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        let players = MediaPlayer.allCases.filter(\.isRunning)
        Task {
            let snapshot = await MediaScripts.snapshot(of: players)
            apply(snapshot)
            isRefreshing = false
            if needsAnotherRefresh {
                needsAnotherRefresh = false
                refresh()
            }
        }
    }

    func send(_ command: MediaCommand) {
        guard var current = track else { return }
        if command == .playPause {
            // Flip the button immediately; the refresh below confirms it.
            let now = Date()
            current.position = current.elapsed(at: now)
            current.positionDate = now
            current.isPlaying.toggle()
            track = current
        }
        let player = current.player
        Task {
            await MediaScripts.send(command, to: player)
            try? await Task.sleep(for: .milliseconds(250))
            refresh()
        }
    }

    // MARK: - Private

    private func tick() {
        ticks += 1
        if isActive || ticks % 5 == 0 {
            refresh()
        }
    }

    private func apply(_ snapshot: PlayerSnapshot) {
        // Prefer whichever player is actually playing.
        let best = snapshot.tracks.first(where: \.isPlaying) ?? snapshot.tracks.first

        if blockedPlayer != snapshot.blocked {
            blockedPlayer = snapshot.blocked
        }

        let key = best?.artworkKey
        if key != artworkKey {
            artworkKey = key
            artwork = nil
            if let best { loadArtwork(for: best, key: key) }
        }

        if track != best {
            track = best
        }
    }

    private func loadArtwork(for track: Track, key: String?) {
        Task {
            var data: Data?
            switch track.player {
            case .spotify:
                if let string = track.artworkURL, let url = URL(string: string) {
                    data = (try? await URLSession.shared.data(from: url))?.0
                }
            case .music:
                data = await MediaScripts.musicArtworkData()
            }
            // Drop the result if the song changed while we were loading.
            guard artworkKey == key, let data, let image = NSImage(data: data) else { return }
            artwork = image
        }
    }
}
