import SwiftUI

/// Apple Music catalog search: artists, songs, albums. Results open in the
/// service picked in the player bar.
struct SearchPanel: View {
    @ObservedObject var state: DesktopSkinState
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.white.opacity(0.7))
                TextField("Search songs, artists and albums", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .focused($isFocused)
                    .onSubmit { state.queryChanged() }
                    .onChange(of: state.query) { _, _ in state.queryChanged() }
                if state.isSearching {
                    ProgressView().controlSize(.small)
                }
                Button {
                    state.closePanel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.1)))

            if let results = state.results {
                if results.isEmpty {
                    Hint(text: "No results.")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        ResultsView(results: results, state: state)
                    }
                }
            } else if state.searchFailed {
                Hint(text: "Couldn't reach Apple Music search. Check your internet connection.")
            } else {
                Hint(text: "Results open in \(state.target.title). Change that with the button at the left of the player bar.")
            }
        }
        .padding(18)
        .frame(width: 780, height: 440, alignment: .top)
        .modifier(GlassBackground(palette: state.player.palette, hasArtwork: false, cornerRadius: 28))
        .onAppear { isFocused = true }
        .onExitCommand { state.closePanel() }
    }
}

private struct ResultsView: View {
    let results: SearchResults
    @ObservedObject var state: DesktopSkinState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !results.artists.isEmpty {
                SectionTitle(text: "Artists")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(results.artists) { artist in
                            ArtistBubble(artist: artist) { state.showArtist(artist) }
                        }
                    }
                }
            }
            if !results.songs.isEmpty {
                SectionTitle(text: "Songs")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 2) {
                    ForEach(results.songs) { song in
                        SongRow(song: song, number: nil) { state.open(song) }
                    }
                }
            }
            if !results.albums.isEmpty {
                SectionTitle(text: "Albums")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(results.albums) { album in
                            AlbumTile(album: album) { state.open(album) }
                        }
                    }
                }
            }
        }
    }
}

struct ArtistPage: View {
    @ObservedObject var state: DesktopSkinState
    let artist: SearchArtist

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                RemoteImage(url: artist.artworkURL, size: 220, cornerRadius: 20)
                Text(artist.name)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                Text(artist.genre.isEmpty ? "Artist" : "Artist · \(artist.genre)")
                    .foregroundStyle(Color.white.opacity(0.65))
                HStack(spacing: 8) {
                    Button {
                        state.open(artist)
                    } label: {
                        Label("Open in \(state.target.title)", systemImage: "arrow.up.right")
                    }
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { state.panel = .search }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
                .buttonStyle(GlassPillButtonStyle())
            }
            .frame(width: 240, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Top Songs")
                if state.artistSongs.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(Array(state.artistSongs.enumerated()), id: \.element.id) { index, song in
                                SongRow(song: song, number: index + 1) { state.open(song) }
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 780, height: 440, alignment: .top)
        .modifier(GlassBackground(palette: state.player.palette, hasArtwork: false, cornerRadius: 28))
        .onExitCommand { state.closePanel() }
    }
}

// MARK: - Pieces

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.white.opacity(0.55))
    }
}

private struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ArtistBubble: View {
    let artist: SearchArtist
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RemoteImage(url: artist.artworkURL, size: 84, cornerRadius: 42)
                Text(artist.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("Artist")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(width: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SongRow: View {
    let song: SearchSong
    let number: Int?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let number {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 20)
                }
                RemoteImage(url: song.artworkURL, size: 40, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(song.album.isEmpty ? song.artist : "\(song.artist) · \(song.album)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(isHovering ? 0.8 : 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isHovering ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct AlbumTile: View {
    let album: SearchAlbum
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RemoteImage(url: album.artworkURL, size: 120, cornerRadius: 12)
                Text(album.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(album.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .lineLimit(1)
            .frame(width: 120, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Image from the web with a placeholder while it loads.
struct RemoteImage: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.14)))
    }
}
