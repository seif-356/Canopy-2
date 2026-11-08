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

    /// Compact player: art, title and artist with live bars; thin progress bar;
    /// controls in the middle and the audio output on the right.
    private func playing(_ track: Track) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                ArtworkView(image: player.artwork, size: 44, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? track.appName : track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                EqualizerBars(isPlaying: track.isPlaying, color: player.palette.primaryColor)
                    .frame(width: 18, height: 12)
            }
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                ScrubBar(position: track.elapsed(at: context.date), duration: track.duration, tint: Color.white.opacity(0.7)) { seconds in
                    player.seek(to: seconds)
                }
            }
            .frame(height: 14)
            HStack(spacing: 0) {
                Color.clear.frame(width: 30, height: 1) // balances the output button
                Spacer()
                HStack(spacing: 16) {
                    ControlButton(symbol: "backward.fill", size: 15, help: "Previous") {
                        player.send(.previous)
                    }
                    ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 20, help: "Play/Pause") {
                        player.send(.playPause)
                    }
                    ControlButton(symbol: "forward.fill", size: 15, help: "Next") {
                        player.send(.next)
                    }
                }
                Spacer()
                AudioOutputButton()
                    .frame(width: 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Progress bar you can drag to seek.
struct ScrubBar: View {
    let position: Double
    let duration: Double
    let tint: Color
    /// Right label shows time left ("-1:26") instead of the total.
    var showsRemaining = false
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.format(current))
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
            Text(rightLabel)
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
    }

    private var current: Double {
        dragFraction.map { $0 * duration } ?? position
    }

    private var rightLabel: String {
        guard duration > 0 else { return "LIVE" }
        return showsRemaining ? "-" + Self.format(max(0, duration - current)) : Self.format(duration)
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

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 18, height: size + 14)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.12 : 0))
                )
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
