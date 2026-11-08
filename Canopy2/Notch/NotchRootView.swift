import SwiftUI

/// Fills the whole panel; draws the notch hanging from the top centre.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        ZStack(alignment: .top) {
            if let geometry = model.geometry {
                notch(geometry)
            }
        }
        .frame(
            width: NotchMetrics.maxOpenSize.width + NotchMetrics.shadowPadding * 2,
            height: NotchMetrics.maxOpenSize.height + NotchMetrics.shadowPadding,
            alignment: .top
        )
        .environment(\.colorScheme, .dark)
    }

    private func notch(_ geometry: NotchGeometry) -> some View {
        let isOpen = model.isOpen
        let presentation = model.closedPresentation
        let size = isOpen ? model.openSize : model.closedSize
        let expanded = isOpen || {
            if case .banner = presentation { return true }
            return false
        }()
        let shape = NotchShape(
            topRadius: expanded ? NotchMetrics.openTopRadius : NotchMetrics.closedTopRadius,
            bottomRadius: expanded ? NotchMetrics.openBottomRadius : NotchMetrics.closedBottomRadius
        )
        let notchHeight = geometry.notchSize.height

        return ZStack(alignment: .top) {
            if isOpen {
                OpenNotchView(model: model, notchHeight: notchHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else {
                switch presentation {
                case .idle:
                    EmptyView()
                case .activity(let withLyrics):
                    ClosedActivityView(
                        player: model.nowPlaying, lyrics: model.lyrics,
                        notchHeight: notchHeight, showsLyrics: withLyrics
                    )
                    .transition(.opacity)
                case .hud(let state):
                    HUDView(state: state, notchHeight: notchHeight, tint: model.nowPlaying.palette.primaryColor)
                        .transition(.opacity)
                case .status(let pill):
                    StatusPillView(pill: pill, notchHeight: notchHeight)
                        .transition(.opacity)
                case .banner(let banner):
                    BannerView(banner: banner, player: model.nowPlaying, notchHeight: notchHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { model.onBannerTap?(banner) }
                        .transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.tab)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 14, y: 4)
    }
}

struct OpenNotchView: View {
    @ObservedObject var model: NotchModel
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            header
                .frame(height: max(notchHeight, 24))
            Group {
                switch model.tab {
                case .nowPlaying:
                    NowPlayingView(player: model.nowPlaying, lyrics: model.lyrics)
                case .lyrics:
                    LyricsView(player: model.nowPlaying, lyrics: model.lyrics)
                case .shelf:
                    ShelfView(shelf: model.shelf, isTargeted: $model.isDropTargeted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, NotchMetrics.openTopRadius + 10)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }

    /// Sits beside the camera: tabs on the left, actions on the right.
    private var header: some View {
        HStack(spacing: 4) {
            TabButton(symbol: "music.note", help: "Now Playing", isSelected: model.tab == .nowPlaying) {
                model.tab = .nowPlaying
            }
            TabButton(symbol: "quote.bubble", help: "Lyrics", isSelected: model.tab == .lyrics) {
                model.tab = .lyrics
            }
            TabButton(symbol: "tray.full", help: "Shelf", isSelected: model.tab == .shelf) {
                model.tab = .shelf
            }
            Spacer()
            if model.tab == .shelf {
                ShelfClearButton(shelf: model.shelf)
            }
            WeatherBadge(weather: model.weather)
            Menu {
                Button("Settings…") { SettingsWindowController.shared.show() }
                Divider()
                Button("Quit Canopy 2") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
    }
}

struct TabButton: View {
    let symbol: String
    let help: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(isSelected ? 0.85 : 0.3))
        .help(help)
    }
}

struct EqualizerBars: View {
    let isPlaying: Bool
    var color = ArtworkPalette.default.primaryColor

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: proxy.size.width * 0.14) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(color)
                            .frame(height: proxy.size.height * level(index: index, time: time))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func level(index: Int, time: TimeInterval) -> CGFloat {
        guard isPlaying else { return 0.25 }
        let speed = 2.2 + Double(index) * 0.7
        return CGFloat(0.3 + 0.7 * abs(sin(time * speed + Double(index))))
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum AppIcons {
    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    static func name(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")
    }
}
