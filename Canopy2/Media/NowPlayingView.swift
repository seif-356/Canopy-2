import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var player: NowPlayingService

    var body: some View {
        if let track = player.track {
            playing(track)
        } else if let blocked = player.blockedPlayer {
            PermissionHint(player: blocked)
        } else {
            EmptyStateView(
                symbol: "music.note",
                title: "Nothing playing",
                subtitle: "Play something in Music or Spotify."
            )
        }
    }

    private func playing(_ track: Track) -> some View {
        HStack(spacing: 16) {
            ArtworkView(image: player.artwork, size: 104, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title.isEmpty ? "Unknown title" : track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(track.artist.isEmpty ? track.player.appName : track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    ProgressRow(position: track.elapsed(at: context.date), duration: track.duration)
                }
                .frame(height: 14)
                HStack(spacing: 30) {
                    ControlButton(symbol: "backward.fill", size: 16, help: "Previous") {
                        player.send(.previous)
                    }
                    ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 22, help: "Play/Pause") {
                        player.send(.playPause)
                    }
                    ControlButton(symbol: "forward.fill", size: 16, help: "Next") {
                        player.send(.next)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ProgressRow: View {
    let position: Double
    let duration: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.format(position))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
            Text(Self.format(duration))
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(position / duration, 0), 1))
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 20, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct PermissionHint: View {
    let player: MediaPlayer

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("Canopy 2 isn't allowed to control \(player.appName).")
                .font(.system(size: 13, weight: .medium))
            Button("Open Automation Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.15)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
