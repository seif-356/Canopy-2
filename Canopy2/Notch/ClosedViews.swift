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
                ArtworkView(image: player.artwork, size: max(notchHeight - 10, 12), cornerRadius: 5)
                Spacer(minLength: 0)
                EqualizerBars(isPlaying: player.track?.isPlaying ?? false, color: player.palette.primaryColor)
                    .frame(width: max(notchHeight - 14, 10), height: max(notchHeight - 16, 8))
            }
            .padding(.horizontal, NotchMetrics.closedTopRadius + 8)
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

/// Volume / brightness level, replacing (or accompanying) the macOS pop-up.
struct HUDView: View {
    let state: HUDState
    let notchHeight: CGFloat
    let tint: Color

    var body: some View {
        HStack {
            Image(systemName: state.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26)
                .contentTransition(.symbolEffect(.replace))
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule()
                            .fill(state.kind == .brightness ? Color.white : tint)
                            .frame(width: proxy.size.width * CGFloat(state.displayLevel))
                    }
                }
                .frame(width: 72, height: 5)
                Text("\(Int((state.displayLevel * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .padding(.horizontal, NotchMetrics.closedTopRadius + 14)
        .frame(height: notchHeight)
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
