import SwiftUI

/// Lock-screen player: big artwork under the clock, a small glass control card
/// below it (title, live bars, lyric line, progress with time left, controls).
struct LockScreenView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var headphones: AirPodsMonitor
    @ObservedObject var weather: WeatherService
    let artworkSide: CGFloat
    let showsArtwork: Bool
    let showsInfoRow: Bool

    /// Share of the screen height taken by the clock at the top of the lock screen.
    static let clockFraction: CGFloat = 0.26
    /// Share kept free at the bottom for the user picture, name and password field.
    static let userAreaFraction: CGFloat = 0.24
    static let cardWidth: CGFloat = 290
    /// Card, info row, spacing and padding, used to size the artwork to fit.
    private static let chromeHeight: CGFloat = 230

    /// Largest artwork that fits between the clock and the user picture.
    static func artworkSide(for screen: NSRect) -> CGFloat {
        let byWidth = screen.width * 0.26
        let available = screen.height * (1 - clockFraction - userAreaFraction) - chromeHeight
        return max(120, min(byWidth, available))
    }

    var body: some View {
        VStack(spacing: 18) {
            if showsInfoRow {
                LockScreenInfoRow(battery: battery, headphones: headphones, weather: weather)
            }
            if showsArtwork {
                DepthArtworkView(image: player.artwork, size: artworkSide)
            }
            LockScreenControls(player: player, lyrics: lyrics)
                .frame(width: Self.cardWidth)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        }
        .padding(30)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

struct LockScreenControls: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService

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
                        if lyrics.status == .synced {
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
