import SwiftUI

/// Lyrics tab: scrolls with the song; click a line to jump there.
struct LyricsView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        switch lyrics.status {
        case .synced:
            if let track = player.track {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    LyricsScroller(
                        lines: lyrics.lines,
                        current: lyrics.index(at: track.elapsed(at: context.date)),
                        tint: player.palette.primaryColor
                    ) { line in
                        player.seek(to: line.time)
                    }
                }
            } else {
                nothingPlaying
            }
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .disabled:
            EmptyStateView(symbol: "quote.bubble", title: "Lyrics are off", subtitle: "Turn them on in Settings › Media.")
        case .unsynced:
            EmptyStateView(symbol: "quote.bubble", title: "No synced lyrics", subtitle: "LRCLIB has this song's words, but without timings.")
        case .notFound:
            EmptyStateView(symbol: "quote.bubble", title: "No lyrics found", subtitle: "LRCLIB doesn't have this song.")
        case .failed:
            EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load lyrics", subtitle: "Check your internet connection.")
        case .idle:
            nothingPlaying
        }
    }

    private var nothingPlaying: some View {
        EmptyStateView(symbol: "quote.bubble", title: "Nothing playing", subtitle: "Lyrics appear here when a song plays.")
    }
}

struct LyricsScroller: View {
    let lines: [LyricLine]
    let current: Int?
    let tint: Color
    let onTap: (LyricLine) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: isCurrent ? 17 : 14, weight: isCurrent ? .bold : .medium))
                            .foregroundStyle(isCurrent ? tint : Color.white.opacity(0.38))
                            .fixedSize(horizontal: false, vertical: true)
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(line) }
                    }
                }
                .padding(.vertical, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: current)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.2),
                        .init(color: .black, location: 0.8),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: .center) }
            }
            .onChange(of: current) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}
