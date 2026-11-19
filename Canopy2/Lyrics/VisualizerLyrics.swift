import SwiftUI

/// Visualizer style: an arc of spikes moving with the music, a small player under
/// it, and the synced lyrics scrolling next to it.
struct VisualizerLyrics: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    let levels: AudioLevels

    var body: some View {
        HStack(alignment: .center, spacing: 56) {
            VStack(spacing: 18) {
                RadialVisualizer(levels: levels)
                    .frame(width: 300, height: 190)
                LockScreenControls(player: player, lyrics: lyrics, showsLyricLine: false)
                    .frame(width: 260)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            }
            if lyrics.status == .synced, player.track != nil {
                LockScreenLyrics(player: player, lyrics: lyrics, fontSize: 17)
                    .frame(width: 380, height: 320, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Spikes fanned along a downward arc, like lashes. The middle ones follow the
/// bass, the outer ones the treble.
struct RadialVisualizer: View {
    @ObservedObject var levels: AudioLevels
    var spikes = 13

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.08)
            let radius = min(size.width * 0.4, size.height * 0.45)
            let maxLength = size.height * 0.42
            let middle = spikes / 2
            for index in 0..<spikes {
                let fraction = Double(index) / Double(max(spikes - 1, 1))
                let angle = (25 + 130 * fraction) * Double.pi / 180
                let band = levels.bands[min(abs(index - middle), levels.bands.count - 1)]
                let length = 10 + CGFloat(band) * maxLength
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                let start = CGPoint(x: center.x + direction.x * radius, y: center.y + direction.y * radius)
                let end = CGPoint(x: start.x + direction.x * length, y: start.y + direction.y * length)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(0.15), Color.white]),
                        startPoint: start, endPoint: end
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                    with: .color(.white)
                )
            }
        }
        .shadow(color: .white.opacity(0.35), radius: 8)
        .onAppear { levels.retain() }
        .onDisappear { levels.release() }
    }
}
