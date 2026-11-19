import SwiftUI

struct NightModeView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    /// Not observed here: only the views that draw levels redraw with them.
    let levels: AudioLevels
    /// Height of the menu bar / notch area at the top of the screen.
    let topInset: CGFloat
    let onClose: () -> Void

    @AppStorage(Prefs.nightLyricsStyle) private var style = LyricsStyle.words.rawValue
    @AppStorage(Prefs.nightEdgeLight) private var edgeLight = EdgeLightMode.artwork.rawValue
    @State private var showsControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    private var lyricsStyle: LyricsStyle { LyricsStyle(rawValue: style) ?? .words }
    private var edgeLightMode: EdgeLightMode { EdgeLightMode(rawValue: edgeLight) ?? .artwork }
    private var hasSyncedLyrics: Bool { lyrics.status == .synced && player.track != nil }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DesktopBackground(player: player)
                Color.black.opacity(0.32)

                VStack(spacing: 0) {
                    NightClock(size: min(116, proxy.size.height * 0.115))
                        .padding(.top, max(topInset, 12) + 6)
                    content(in: proxy.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 70)
                        .padding(.bottom, 80)
                }

                if let color = edgeLightMode.color(palette: player.palette) {
                    EdgeLight(levels: levels, color: color)
                }

                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(28)

                if let toast {
                    Text(toast)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 34)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { _ in poke() }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .onAppear { poke() }
        .onDisappear {
            hideTask?.cancel()
            toastTask?.cancel()
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch lyricsStyle {
        case .words where hasSyncedLyrics:
            WordByWordLyrics(player: player, lyrics: lyrics, size: min(124, size.height * 0.13))
                .transition(.opacity)
        case .constellation where hasSyncedLyrics:
            ConstellationLyrics(player: player, lyrics: lyrics)
                .transition(.opacity)
        case .wave:
            VisualizerLyrics(player: player, lyrics: lyrics, levels: levels)
                .transition(.opacity)
        default:
            NightArtwork(player: player, lyrics: lyrics, side: min(300, size.height * 0.34))
                .transition(.opacity)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            NightButton(symbol: "textformat", help: "Lyrics style: \(lyricsStyle.title)") {
                let all = LyricsStyle.allCases
                let next = all[((all.firstIndex(of: lyricsStyle) ?? 0) + 1) % all.count]
                withAnimation(.easeInOut(duration: 0.4)) { style = next.rawValue }
                show(toast: next.title)
            }
            NightButton(symbol: edgeLightMode.symbol, help: "Edge light: \(edgeLightMode.title)") {
                let all = EdgeLightMode.allCases
                let next = all[((all.firstIndex(of: edgeLightMode) ?? 0) + 1) % all.count]
                withAnimation(.easeInOut(duration: 0.4)) { edgeLight = next.rawValue }
                show(toast: "Edge light: \(next.title)")
            }
            NightButton(symbol: "xmark", help: "Leave Night Mode (Esc)", action: onClose)
        }
        .opacity(showsControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: showsControls)
    }

    /// The mouse moved: show the buttons, then hide them and the pointer after a while.
    private func poke() {
        if !showsControls { showsControls = true }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showsControls = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func show(toast text: String) {
        withAnimation { toast = text }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}

/// Date and time in a serif face.
struct NightClock: View {
    var size: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: max(13, size * 0.17), weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(DesktopClock.timeFormatter.string(from: context.date))
                    .font(.system(size: size, weight: .regular, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        }
    }
}

/// Artwork with the small player (and the current lyric line) under it.
private struct NightArtwork: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    let side: CGFloat

    var body: some View {
        VStack(spacing: 18) {
            ArtworkView(image: player.artwork, size: side, cornerRadius: side * 0.08)
                .shadow(color: .black.opacity(0.4), radius: 26, y: 12)
            LockScreenControls(player: player, lyrics: lyrics)
                .frame(width: 290)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        }
    }
}

/// A bright line along the screen edges with a wide glow behind it, both pulsing
/// with the music.
struct EdgeLight: View {
    @ObservedObject var levels: AudioLevels
    let color: Color

    var body: some View {
        let pulse = Double(levels.level)
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color, lineWidth: 70)
                .blur(radius: 55)
                .opacity(0.3 + 0.6 * pulse)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color, lineWidth: 5)
                .blur(radius: 3)
                .opacity(0.55 + 0.45 * pulse)
        }
        .allowsHitTesting(false)
        .onAppear { levels.retain() }
        .onDisappear { levels.release() }
    }
}

private struct NightButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(isHovering ? 0.55 : 0.35)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}
