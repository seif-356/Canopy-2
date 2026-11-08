import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        if let track = player.track {
            playing(track)
        } else if let blocked = player.blockedPlayer {
            PermissionHint(player: blocked)
        } else {
            EmptyStateView(
                symbol: "music.note",
                title: "Nothing playing",
                subtitle: player.sourceDescription
            )
        }
    }

    private func playing(_ track: Track) -> some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(image: player.artwork, size: 112, cornerRadius: 16)
                if let icon = AppIcons.icon(for: track.bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .shadow(radius: 3)
                        .offset(x: 7, y: 7)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(track.artist.isEmpty ? track.appName : track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let time = track.elapsed(at: context.date)
                    VStack(alignment: .leading, spacing: 4) {
                        if lyrics.status == .synced {
                            let line = lyrics.line(at: time)?.text ?? ""
                            Text(line.isEmpty ? "♪" : line)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(player.palette.primaryColor)
                                .lineLimit(1)
                                .animation(.easeInOut(duration: 0.2), value: line)
                        }
                        ScrubBar(position: time, duration: track.duration, tint: player.palette.primaryColor) { seconds in
                            player.seek(to: seconds)
                        }
                    }
                }
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

/// Progress bar you can drag to seek.
struct ScrubBar: View {
    let position: Double
    let duration: Double
    let tint: Color
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.format(dragFraction.map { $0 * duration } ?? position))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(tint)
                        .frame(width: proxy.size.width * CGFloat(fraction))
                }
                .frame(height: dragFraction == nil ? 4 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = Self.clamp(value.location.x / max(proxy.size.width, 1))
                        }
                        .onEnded { value in
                            let target = Self.clamp(value.location.x / max(proxy.size.width, 1)) * duration
                            dragFraction = nil
                            onSeek(target)
                        }
                )
            }
            .frame(height: 14)
            .allowsHitTesting(duration > 0)
            Text(duration > 0 ? Self.format(duration) : "LIVE")
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
    }

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard duration > 0 else { return 0 }
        return Self.clamp(position / duration)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
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
                .contentTransition(.symbolEffect(.replace))
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
                SystemSettings.open(.automation)
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

enum SystemSettings {
    enum Pane: String {
        case automation = "Privacy_Automation"
        case fullDiskAccess = "Privacy_AllFiles"
        case accessibility = "Privacy_Accessibility"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}
