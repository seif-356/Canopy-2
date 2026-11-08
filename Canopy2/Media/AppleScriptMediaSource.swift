import AppKit

/// Fallback source: Music and Spotify through AppleScript.
/// Updates come from the players' own notifications plus polling
/// (every second while the notch is open, every 5 s otherwise).
@MainActor
final class AppleScriptMediaSource: MediaSource {
    var onUpdate: ((MediaUpdate) -> Void)?
    var onFailure: (() -> Void)?
    var isActive = false

    private var timer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var isRefreshing = false
    private var needsAnotherRefresh = false
    private var ticks = 0
    private var lastTrack: Track?
    private var artworkIdentity: String?

    func start() {
        let distributed: NotificationCenter = DistributedNotificationCenter.default()
        for player in MediaPlayer.allCases {
            let token = distributed.addObserver(forName: player.playbackNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((center: distributed, token: token))
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((center: workspace, token: token))
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
        onUpdate = nil
        onFailure = nil
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
        guard let player = MediaPlayer(bundleIdentifier: lastTrack?.bundleIdentifier) else { return }
        Task {
            await MediaScripts.send(command, to: player)
            try? await Task.sleep(for: .milliseconds(250))
            refresh()
        }
    }

    func seek(to seconds: Double) {
        guard let player = MediaPlayer(bundleIdentifier: lastTrack?.bundleIdentifier) else { return }
        Task {
            await MediaScripts.seek(player, to: seconds)
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

    private func apply(_ snapshot: ScriptSnapshot) {
        // Prefer whichever player is actually playing.
        let best = snapshot.tracks.first(where: \.track.isPlaying) ?? snapshot.tracks.first
        lastTrack = best?.track

        var update = MediaUpdate(track: best?.track, blockedPlayer: snapshot.blocked)
        if let string = best?.artworkURL {
            update.artworkURL = URL(string: string)
        }
        onUpdate?(update)

        // Music artwork comes as raw data, fetched once per song.
        guard let track = best?.track, track.identity != artworkIdentity else { return }
        artworkIdentity = track.identity
        guard MediaPlayer(bundleIdentifier: track.bundleIdentifier) == .music else { return }
        Task {
            guard let data = await MediaScripts.musicArtworkData(),
                  let current = lastTrack, current.identity == track.identity else { return }
            onUpdate?(MediaUpdate(track: current, artworkData: data))
        }
    }
}
