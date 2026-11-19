import SwiftUI

/// Lock-screen player: big artwork under the clock, a small glass control card
/// below it (title, live bars, lyric line, progress with time left, controls).
/// With synced lyrics it switches to two columns: artwork and controls on the
/// left, the lyrics scrolling on the right.
struct LockScreenView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var headphones: AirPodsMonitor
    @ObservedObject var weather: WeatherService
    let artworkSide: CGFloat
    let showsArtwork: Bool
    let showsInfoRow: Bool
    @AppStorage(Prefs.lockScreenLyricsStyle) private var lyricsStyle = LyricsStyle.lines.rawValue

    /// Share of the screen height taken by the clock at the top of the lock screen.
    static let clockFraction: CGFloat = 0.26
    /// Share kept free at the bottom for the user picture, name and password field.
    static let userAreaFraction: CGFloat = 0.24
    static let cardWidth: CGFloat = 290
    static let lyricsWidth: CGFloat = 400
    static let columnSpacing: CGFloat = 48

    /// Room for both columns of the lyrics layout.
    static func layoutWidth(for screen: NSRect) -> CGFloat {
        min(screen.width * 0.92, artworkSide(for: screen) + columnSpacing + lyricsWidth + 80)
    }
    /// Card, info row, spacing and padding, used to size the artwork to fit.
    private static let chromeHeight: CGFloat = 230

    /// Largest artwork that fits between the clock and the user picture.
    static func artworkSide(for screen: NSRect) -> CGFloat {
        let byWidth = screen.width * 0.26
        let available = screen.height * (1 - clockFraction - userAreaFraction) - chromeHeight
        return max(120, min(byWidth, available))
    }

    private var style: LyricsStyle { LyricsStyle(rawValue: lyricsStyle) ?? .lines }

    private var showsLyricsColumn: Bool {
        showsArtwork && lyrics.status == .synced && player.track != nil
    }

    var body: some View {
        VStack(spacing: 18) {
            if showsInfoRow {
                LockScreenInfoRow(battery: battery, headphones: headphones, weather: weather)
            }
            if showsLyricsColumn && (style == .constellation || style == .words) {
                VStack(spacing: 12) {
                    Group {
                        if style == .words {
                            WordByWordLyrics(player: player, lyrics: lyrics, size: min(96, artworkSide * 0.34))
                        } else {
                            ConstellationLyrics(player: player, lyrics: lyrics)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: artworkSide + 60)
                    LockScreenControls(player: player, lyrics: lyrics, showsLyricLine: false)
                        .frame(width: Self.cardWidth)
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                }
                .transition(.opacity)
            } else if showsLyricsColumn {
                HStack(alignment: .center, spacing: Self.columnSpacing) {
                    VStack(spacing: 16) {
                        DepthArtworkView(image: player.artwork, size: artworkSide)
                        LockScreenControls(player: player, lyrics: lyrics, showsLyricLine: false)
                            .frame(width: Self.cardWidth)
                            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                    }
                    LockScreenLyrics(player: player, lyrics: lyrics)
                        .frame(width: Self.lyricsWidth, height: artworkSide + 110, alignment: .leading)
                }
                .transition(.opacity)
            } else {
                if showsArtwork {
                    DepthArtworkView(image: player.artwork, size: artworkSide)
                }
                LockScreenControls(player: player, lyrics: lyrics)
                    .frame(width: Self.cardWidth)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showsLyricsColumn)
        .padding(30)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

struct LockScreenControls: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    /// Off when the lyrics have their own column.
    var showsLyricLine = true

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                VStack(spacing: 1) {
                    Text(player.track?.title ?? "Not playing")
                        .font(.system(size: 13, weight: .semibold))
                    Text(player.track.map { $0.artist.isEmpty ? $0.appName : $0.artist } ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .lineLimit(1)
                .padding(.horizontal, 28)
                HStack {
                    Spacer()
                    EqualizerBars(isPlaying: player.track?.isPlaying ?? false, color: .white)
                        .frame(width: 14, height: 10)
                }
            }
            if let track = player.track {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let time = track.elapsed(at: context.date)
                    VStack(spacing: 6) {
                        if showsLyricLine, lyrics.status == .synced {
                            let line = lyrics.line(at: time)?.text ?? ""
                            Text(line.isEmpty ? "♪" : line)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(player.palette.primaryColor)
                                .lineLimit(1)
                                .animation(.easeInOut(duration: 0.2), value: line)
                        }
                        ScrubBar(position: time, duration: track.duration, tint: .white, showsRemaining: true) { seconds in
                            player.seek(to: seconds)
                        }
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                    }
                }
                HStack {
                    ControlButton(symbol: "backward.fill", size: 15, help: "Previous") { player.send(.previous) }
                    Spacer()
                    ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 19, help: "Play/Pause") {
                        player.send(.playPause)
                    }
                    Spacer()
                    ControlButton(symbol: "forward.fill", size: 15, help: "Next") { player.send(.next) }
                }
                .padding(.horizontal, 34)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .modifier(GlassBackground(palette: player.palette, hasArtwork: player.artwork != nil, cornerRadius: 20))
    }
}

/// Weather, battery and headphones in one live row beneath the clock.
struct LockScreenInfoRow: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var headphones: AirPodsMonitor
    @ObservedObject var weather: WeatherService

    var body: some View {
        HStack(spacing: 8) {
            if let now = weather.current {
                InfoChip {
                    Image(systemName: now.symbol).symbolRenderingMode(.multicolor)
                    Text(now.rounded)
                }
            }
            if let state = battery.state {
                InfoChip {
                    Image(systemName: state.symbol)
                        .foregroundStyle(state.isPluggedIn ? Color.green : (state.percent <= 20 ? Color.red : Color.white))
                    Text("\(state.percent)%")
                }
            }
            if let device = headphones.connected {
                InfoChip {
                    Image(systemName: device.symbol)
                    if let level = device.level { Text("\(level)%") }
                }
            }
        }
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
    }
}

private struct InfoChip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.28)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }
}

/// Smoke-test stand-in for the lock screen: blurred artwork, a clock where macOS
/// draws its own, and the player where the real one goes.
struct LockScreenPreview: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var headphones: AirPodsMonitor
    @ObservedObject var weather: WeatherService
    let screen: NSRect

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackground(player: player)
            DesktopClock()
                .scaleEffect(0.6, anchor: .top)
                .padding(.top, screen.height * 0.04)
            LockScreenView(
                player: player, lyrics: lyrics, battery: battery, headphones: headphones, weather: weather,
                artworkSide: LockScreenView.artworkSide(for: screen), showsArtwork: true, showsInfoRow: true
            )
            .padding(.top, screen.height * LockScreenView.clockFraction - 30)
        }
        .frame(width: screen.width, height: screen.height)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}

/// Synced lyrics for the lock screen: scrolls so the current line sits near the
/// top; the current line is bright, past lines faded, upcoming ones dimmed. Every
/// line keeps the same size, so nothing re-wraps or jumps while it scrolls.
struct LockScreenLyrics: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    var fontSize: CGFloat = 23

    var body: some View {
        if let track = player.track, !lyrics.lines.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                LockScreenLyricsList(
                    lines: lyrics.lines, current: lyrics.index(at: track.elapsed(at: context.date)), fontSize: fontSize
                )
            }
        }
    }
}

private struct LockScreenLyricsList: View {
    let lines: [LyricLine]
    let current: Int?
    let fontSize: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: fontSize * 0.78) {
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        let isPast = current.map { line.id < $0 } ?? false
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundStyle(Color.white.opacity(isCurrent ? 1 : (isPast ? 0.25 : 0.42)))
                            .shadow(color: .black.opacity(isCurrent ? 0.35 : 0), radius: 10, y: 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 120)
                .animation(.easeInOut(duration: 0.3), value: current)
            }
            .scrollDisabled(true)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.8),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) }
            }
            .onChange(of: current) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(newValue, anchor: UnitPoint(x: 0, y: 0.3))
                }
            }
        }
    }
}
