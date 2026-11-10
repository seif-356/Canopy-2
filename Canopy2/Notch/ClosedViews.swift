import SwiftUI

/// Artwork left of the camera, live bars right of it; optional lyric line below.
struct ClosedActivityView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    let notchHeight: CGFloat
    let showsLyrics: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ArtworkView(image: player.artwork, size: max(notchHeight - 14, 12), cornerRadius: 4)
                Spacer(minLength: 0)
                EqualizerBars(isPlaying: player.track?.isPlaying ?? false, color: player.palette.primaryColor)
                    .frame(width: max(notchHeight * 0.5, 10), height: max(notchHeight * 0.36, 8))
            }
            .padding(.horizontal, NotchMetrics.closedTopRadius + 6)
            .frame(height: notchHeight)

            if showsLyrics, let track = player.track {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let text = lyrics.line(at: track.elapsed(at: context.date))?.text ?? ""
                    Text(text.isEmpty ? "♪" : text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(player.palette.primaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: text)
                }
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Volume / brightness: the notch grows down a little, with the label beside the
/// camera on the left and a slim bar underneath on the right.
struct HUDView: View {
    let state: HUDState
    let notchHeight: CGFloat
    let tint: Color

    private var label: String {
        switch state.kind {
        case .volume: state.isMuted ? "Muted" : "Volume"
        case .brightness: "Brightness"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
            .frame(height: notchHeight)
            HStack {
                Spacer(minLength: 0)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: max(proxy.size.height, proxy.size.width * CGFloat(state.displayLevel)))
                            .opacity(state.displayLevel > 0 ? 1 : 0)
                    }
                }
                .frame(width: 66, height: 5)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, NotchMetrics.closedTopRadius + 12)
        .padding(.bottom, 4)
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.15), value: state.displayLevel)
    }
}

/// Drops down below the camera: a mirrored notification, or the new song.
struct BannerView: View {
    let banner: Banner
    @ObservedObject var player: NowPlayingService
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: notchHeight)
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !banner.subtitle.isEmpty {
                        Text(banner.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if banner.kind == .track {
                    EqualizerBars(isPlaying: player.track?.isPlaying ?? false, color: player.palette.primaryColor)
                        .frame(width: 18, height: 14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var icon: some View {
        if banner.kind == .track {
            ArtworkView(image: player.artwork ?? banner.icon, size: 40, cornerRadius: 8)
        } else if let symbol = banner.symbol {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .frame(width: 40, height: 40)
        } else if let image = banner.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
        }
    }
}

/// Charging / unplugged / low battery / Low Power Mode, beside the camera.
struct StatusPillView: View {
    let pill: StatusPill
    let notchHeight: CGFloat

    @State private var pulse = false

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: pill.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(pill.tint)
                    .scaleEffect(pill.isCharging && pulse ? 1.15 : 1)
                Text(pill.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(pill.value)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(pill.tint)
                if let level = pill.batteryLevel {
                    BatteryGlyph(level: level, tint: pill.tint, animateFill: pill.isCharging)
                        .frame(width: 26, height: 12)
                }
            }
        }
        .padding(.horizontal, NotchMetrics.closedTopRadius + 12)
        .frame(height: notchHeight)
        .foregroundStyle(.white)
        .onAppear {
            guard pill.isCharging else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Battery outline whose fill sweeps up to the current level when charging.
struct BatteryGlyph: View {
    let level: Double
    let tint: Color
    var animateFill = false

    @State private var shownLevel: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let capWidth = proxy.size.width * 0.08
            let bodyWidth = proxy.size.width - capWidth - 1
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: max(0, (bodyWidth - 4) * CGFloat(shownLevel)))
                        .padding(2)
                }
                .frame(width: bodyWidth)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.45))
                    .frame(width: capWidth, height: proxy.size.height * 0.4)
            }
        }
        .onAppear {
            if animateFill {
                shownLevel = 0
                withAnimation(.easeOut(duration: 1.1)) { shownLevel = level }
            } else {
                shownLevel = level
            }
        }
        .onChange(of: level) { _, newValue in
            withAnimation(.easeOut(duration: 0.4)) { shownLevel = newValue }
        }
    }
}

/// Current temperature, shown faintly beside the camera in the open notch.
struct WeatherBadge: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        if let now = weather.current {
            HStack(spacing: 4) {
                Image(systemName: now.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 11))
                Text(now.rounded)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .help(now.place.isEmpty ? "Weather" : now.place)
        }
    }
}
