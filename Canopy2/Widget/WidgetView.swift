import SwiftUI

/// Frosted-glass widget: clock, now playing and lyrics. Used on the desktop and,
/// optionally, on the lock screen.
struct WidgetView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    let preset: WidgetPreset
    /// Shows a grip at the top for moving the desktop widget.
    var showsDragHandle = true

    static func size(for preset: WidgetPreset) -> CGSize {
        switch preset {
        case .lockScreen: CGSize(width: 340, height: 300)
        case .nowPlaying: CGSize(width: 340, height: 158)
        case .lyrics: CGSize(width: 340, height: 220)
        case .clock: CGSize(width: 260, height: 130)
        }
    }

    var body: some View {
        let size = Self.size(for: preset)
        ZStack(alignment: .top) {
            content
                .padding(.horizontal, 20)
                .padding(.top, showsDragHandle ? 22 : 18)
                .padding(.bottom, 18)
                .frame(width: size.width, height: size.height, alignment: .top)
            if showsDragHandle {
                WindowDragHandle()
                    .frame(height: 18)
                    .overlay(Capsule().fill(Color.white.opacity(0.35)).frame(width: 36, height: 4).allowsHitTesting(false))
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(GlassBackground(palette: player.palette, hasArtwork: player.artwork != nil))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch preset {
        case .lockScreen:
            VStack(spacing: 18) {
                ClockView(large: true)
                NowPlayingCard(player: player, compact: true)
            }
        case .nowPlaying:
            NowPlayingCard(player: player, compact: false)
        case .lyrics:
            VStack(alignment: .leading, spacing: 10) {
                NowPlayingHeader(player: player)
                LyricsCard(player: player, lyrics: lyrics)
            }
        case .clock:
            ClockView(large: false)
        }
    }
}

struct ClockView: View {
    let large: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2) {
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: large ? 15 : 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(context.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: large ? 68 : 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct NowPlayingHeader: View {
    @ObservedObject var player: NowPlayingService

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(image: player.artwork, size: 40, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.track?.title ?? "Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(player.track?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct NowPlayingCard: View {
    @ObservedObject var player: NowPlayingService
    let compact: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(image: player.artwork, size: compact ? 52 : 64, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.track?.title ?? "Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(player.track.map { $0.artist.isEmpty ? $0.appName : $0.artist } ?? "Play something to see it here")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let track = player.track {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    ScrubBar(position: track.elapsed(at: context.date), duration: track.duration, tint: .white) { seconds in
                        player.seek(to: seconds)
                    }
                }
                .frame(height: 14)
                HStack(spacing: 34) {
                    ControlButton(symbol: "backward.fill", size: 15, help: "Previous") { player.send(.previous) }
                    ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 20, help: "Play/Pause") {
                        player.send(.playPause)
                    }
                    ControlButton(symbol: "forward.fill", size: 15, help: "Next") { player.send(.next) }
                }
            }
        }
    }
}

struct LyricsCard: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        if lyrics.status == .synced, let track = player.track {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let index = lyrics.index(at: track.elapsed(at: context.date))
                let current = index.map { lyrics.lines[$0].text } ?? ""
                let next = index.flatMap { $0 + 1 < lyrics.lines.count ? lyrics.lines[$0 + 1].text : nil } ?? ""
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.isEmpty ? "♪" : current)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(3)
                    Text(next)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: current)
            }
        } else {
            Text(lyrics.status == .loading ? "Loading lyrics…" : "No synced lyrics for this song")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Liquid Glass when built with the macOS 26 SDK and running on macOS 26;
/// frosted blur tinted with the artwork colors otherwise.
struct GlassBackground: ViewModifier {
    let palette: ArtworkPalette
    let hasArtwork: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return AnyView(
                content
                    .glassEffect(.regular.tint(palette.secondaryColor.opacity(hasArtwork ? 0.35 : 0.1)), in: shape)
            )
        }
        #endif
        return AnyView(
            content
                .background(
                    ZStack {
                        VisualEffectBlur()
                        LinearGradient(
                            colors: [
                                palette.primaryColor.opacity(hasArtwork ? 0.28 : 0.08),
                                palette.secondaryColor.opacity(hasArtwork ? 0.55 : 0.2),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                )
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        )
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Drag this strip to move the window it's in.
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {}
}
