import SwiftUI

/// Full-screen desktop skin: blurred artwork, big clock, recently played on the
/// left, now playing (or search / artist page) in the middle, player bar below.
struct DesktopSkinView: View {
    @ObservedObject var state: DesktopSkinState
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var history: PlayHistory

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DesktopBackground(player: player)

                VStack {
                    DesktopClock()
                        .padding(.top, 44)
                    Spacer()
                }

                HStack(alignment: .top) {
                    HistorySidebar(history: history, state: state)
                        .frame(width: 270)
                        .frame(maxHeight: proxy.size.height * 0.62, alignment: .top)
                    Spacer()
                }
                .padding(.leading, 28)
                .padding(.top, 70)
                .frame(maxHeight: .infinity, alignment: .top)

                center
                    .padding(.top, proxy.size.height * 0.28)
                    .padding(.bottom, 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    Spacer()
                    PlayerBar(state: state, player: player)
                        .frame(maxWidth: 760)
                        .padding(.bottom, 26)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var center: some View {
        switch state.panel {
        case .nowPlaying:
            NowPlayingHero(player: player, lyrics: lyrics, showsLyrics: state.showsLyrics)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .search:
            SearchPanel(state: state)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .artist(let artist):
            ArtistPage(state: state, artist: artist)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}

// MARK: - Background and clock

/// The playing song's artwork, blurred, filling the screen and slowly drifting.
struct DesktopBackground: View {
    @ObservedObject var player: NowPlayingService
    @State private var blurred: NSImage?
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [player.palette.secondaryColor, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let blurred {
                    Image(nsImage: blurred)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(drift ? 1.14 : 1.02)
                        .offset(x: drift ? -20 : 20, y: drift ? 10 : -10)
                        .clipped()
                        .transition(.opacity)
                }
                LinearGradient(
                    colors: [Color.black.opacity(0.1), Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(.easeInOut(duration: 1.2), value: blurred)
            .onAppear {
                render(for: proxy.size)
                withAnimation(.easeInOut(duration: 28).repeatForever(autoreverses: true)) { drift = true }
            }
            .onChange(of: player.artwork) { _, _ in render(for: proxy.size) }
        }
    }

    private func render(for size: CGSize) {
        guard let artwork = player.artwork else {
            blurred = nil
            return
        }
        // Half resolution is plenty for a heavy blur and much cheaper.
        let target = CGSize(width: max(size.width / 2, 1), height: max(size.height / 2, 1))
        guard let image = ArtworkBlur.render(artwork, size: target, sigma: 30) else { return }
        blurred = NSImage(cgImage: image, size: target)
    }
}

struct DesktopClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: -6) {
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 190, weight: .semibold).width(.compressed))
                    .monospacedDigit()
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
    }
}

// MARK: - Now playing

struct NowPlayingHero: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    let showsLyrics: Bool

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                ArtworkView(image: player.artwork, size: 230, cornerRadius: 18)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                VStack(spacing: 2) {
                    Text(player.track?.title ?? "Nothing playing")
                        .font(.system(size: 17, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .lineLimit(1)
                if let track = player.track {
                    HStack(spacing: 6) {
                        if let icon = AppIcons.icon(for: track.bundleIdentifier) {
                            Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                        }
                        Text(track.appName.isEmpty ? "Playing" : "Playing in \(track.appName)")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                }
            }
            .padding(18)
            .frame(width: 290)
            .modifier(GlassBackground(palette: player.palette, hasArtwork: player.artwork != nil, cornerRadius: 26))

            if showsLyrics, lyrics.status == .synced, let track = player.track {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let line = lyrics.line(at: track.elapsed(at: context.date))?.text ?? ""
                    Text(line.isEmpty ? "♪" : line)
                        .font(.system(size: 26, weight: .bold))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                        .animation(.easeInOut(duration: 0.25), value: line)
                }
                .frame(maxWidth: 700)
            }
        }
    }

    private var subtitle: String {
        guard let track = player.track else { return "Play something in any app" }
        return track.artist.isEmpty ? track.appName : track.artist
    }
}

// MARK: - Recently played

struct HistorySidebar: View {
    @ObservedObject var history: PlayHistory
    @ObservedObject var state: DesktopSkinState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recently Played", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 6)
            if history.items.isEmpty {
                Text("Songs you play in any app show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(6)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(history.items) { item in
                        HistoryRow(item: item, thumbnail: history.thumbnails[item.id]) {
                            state.open(item)
                        }
                    }
                }
            }
        }
        .padding(12)
        .modifier(GlassBackground(palette: .default, hasArtwork: false, cornerRadius: 22))
    }
}

struct HistoryRow: View {
    let item: PlayedTrack
    let thumbnail: NSImage?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ArtworkView(image: thumbnail, size: 36, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(item.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isHovering ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Player bar

struct PlayerBar: View {
    @ObservedObject var state: DesktopSkinState
    @ObservedObject var player: NowPlayingService
    @AppStorage(Prefs.musicTarget) private var targetRaw = MusicTarget.automatic.rawValue

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(MusicTarget.allCases) { target in
                    Button {
                        targetRaw = target.rawValue
                    } label: {
                        Label(target.title, systemImage: target.rawValue == targetRaw ? "checkmark" : target.symbol)
                    }
                }
            } label: {
                TargetIcon(target: MusicTarget(rawValue: targetRaw) ?? .automatic)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Where search results and recent songs open")

            HStack(spacing: 4) {
                ControlButton(symbol: "backward.fill", size: 15, help: "Previous") { player.send(.previous) }
                ControlButton(symbol: player.track?.isPlaying == true ? "pause.fill" : "play.fill", size: 19, help: "Play/Pause") {
                    player.send(.playPause)
                }
                ControlButton(symbol: "forward.fill", size: 15, help: "Next") { player.send(.next) }
            }

            HStack(spacing: 10) {
                ArtworkView(image: player.artwork, size: 34, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.track?.title ?? "Not playing")
                        .font(.system(size: 12, weight: .semibold))
                    Text(player.track?.artist ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .lineLimit(1)
                if let track = player.track {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        ScrubBar(position: track.elapsed(at: context.date), duration: track.duration, tint: Color.white.opacity(0.8)) { seconds in
                            player.seek(to: seconds)
                        }
                    }
                    .frame(height: 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                state.showsLyrics.toggle()
            } label: {
                Image(systemName: state.showsLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Lyrics")

            AudioOutputButton()

            Button {
                state.openSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Search Apple Music")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(GlassBackground(palette: player.palette, hasArtwork: player.artwork != nil, cornerRadius: 22))
    }
}

/// Installed app icon (Music, Spotify) or a colored symbol for web services.
struct TargetIcon: View {
    let target: MusicTarget

    var body: some View {
        if let icon = AppIcons.icon(for: target.bundleIdentifier) {
            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
        } else {
            Image(systemName: target.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(target.tint.opacity(target == .automatic ? 0.25 : 0.9)))
        }
    }
}
