import AppKit
import SwiftUI

/// What's playing, from whichever media source works on this Mac:
/// MediaRemote (all apps) first, AppleScript (Music and Spotify) as the fallback.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette = ArtworkPalette.default
    @Published private(set) var blockedPlayer: MediaPlayer?
    /// Shown in Settings so it's clear which source is in use.
    @Published private(set) var sourceDescription = "Starting…"

    /// Set while the notch is open, for faster polling.
    var isActive = false {
        didSet { source?.isActive = isActive }
    }

    private var source: MediaSource?
    private var identity: String?
    private var generation = 0

    func start() {
        configureSource()
    }

    /// (Re)chooses the media source. Called at launch and when the setting changes.
    func configureSource() {
        generation += 1
        let current = generation
        source?.stop()
        source = nil

        let preference = MediaSourcePreference(rawValue: Prefs.string(Prefs.mediaSource)) ?? .automatic
        guard preference == .automatic else {
            useAppleScript(description: "Music and Spotify (AppleScript)")
            return
        }
        guard let paths = MediaRemoteAdapterSource.bundledPaths else {
            useAppleScript(description: "Music and Spotify only: the MediaRemote helper isn't in this build")
            return
        }
        sourceDescription = "Checking MediaRemote…"
        Task {
            let works = await MediaRemoteAdapterSource.isFunctional(paths)
            guard current == generation else { return }
            if works {
                use(MediaRemoteAdapterSource(paths: paths), description: "All apps (MediaRemote)")
            } else {
                useAppleScript(description: "Music and Spotify only: MediaRemote is blocked on this macOS version")
            }
        }
    }

    func send(_ command: MediaCommand) {
        if command == .playPause, var current = track {
            // Flip the button immediately; the source confirms it.
            let now = Date()
            current.position = current.elapsed(at: now)
            current.positionDate = now
            current.isPlaying.toggle()
            track = current
        }
        source?.send(command)
    }

    func seek(to seconds: Double) {
        if var current = track {
            current.position = seconds
            current.positionDate = Date()
            track = current
        }
        source?.seek(to: seconds)
    }

    // MARK: - Private

    private func useAppleScript(description: String) {
        use(AppleScriptMediaSource(), description: description)
    }

    private func use(_ newSource: MediaSource, description: String) {
        source?.stop()
        source = newSource
        sourceDescription = description
        newSource.onUpdate = { [weak self] update in
            self?.apply(update)
        }
        newSource.onFailure = { [weak self, weak newSource] in
            guard let self, let newSource, self.source === newSource else { return }
            self.useAppleScript(description: "Music and Spotify only: MediaRemote stopped working")
        }
        newSource.isActive = isActive
        newSource.start()
    }

    private func apply(_ update: MediaUpdate) {
        if blockedPlayer != update.blockedPlayer {
            blockedPlayer = update.blockedPlayer
        }

        let newIdentity = update.track?.identity
        if newIdentity != identity {
            identity = newIdentity
            if update.artworkData == nil {
                artwork = nil
                palette = .default
            }
            if let url = update.artworkURL {
                loadArtwork(from: url, for: newIdentity)
            }
        }
        if let data = update.artworkData {
            setArtwork(data)
        }

        if track != update.track {
            track = update.track
        }
    }

    private func loadArtwork(from url: URL, for expectedIdentity: String?) {
        Task {
            guard let response = try? await URLSession.shared.data(from: url),
                  identity == expectedIdentity else { return }
            setArtwork(response.0)
        }
    }

    private func setArtwork(_ data: Data) {
        guard let image = NSImage(data: data) else { return }
        artwork = image
        palette = ArtworkPalette(image: image)
    }
}

/// Two colors sampled from the artwork, for tinting bars, banners and the widget.
struct ArtworkPalette: Equatable {
    var primary: NSColor
    var secondary: NSColor

    static let `default` = ArtworkPalette(
        primary: NSColor(deviceRed: 0.43, green: 0.9, blue: 0.66, alpha: 1),
        secondary: NSColor(deviceRed: 0.08, green: 0.32, blue: 0.27, alpha: 1)
    )

    var primaryColor: Color { Color(nsColor: primary) }
    var secondaryColor: Color { Color(nsColor: secondary) }

    init(primary: NSColor, secondary: NSColor) {
        self.primary = primary
        self.secondary = secondary
    }

    init(image: NSImage) {
        guard let sampled = Self.sample(image) else {
            self = .default
            return
        }
        primary = Self.adjust(sampled.top, minSaturation: 0.45, brightness: 0.78...1)
        secondary = Self.adjust(sampled.bottom, minSaturation: 0.35, brightness: 0.22...0.42)
    }

    /// Average colors of the top and bottom halves of the image.
    private static func sample(_ image: NSImage) -> (top: NSColor, bottom: NSColor)? {
        let side = 4
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .medium
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        func average(rows: Range<Int>) -> NSColor {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, count: CGFloat = 0
            for y in rows {
                for x in 0..<side {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    red += color.redComponent
                    green += color.greenComponent
                    blue += color.blueComponent
                    count += 1
                }
            }
            guard count > 0 else { return .gray }
            return NSColor(deviceRed: red / count, green: green / count, blue: blue / count, alpha: 1)
        }
        return (top: average(rows: 0..<side / 2), bottom: average(rows: side / 2..<side))
    }

    private static func adjust(_ color: NSColor, minSaturation: CGFloat, brightness: ClosedRange<CGFloat>) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        // Keep greys grey; make colors vivid enough to read on black.
        let newSaturation = saturation < 0.08 ? saturation : max(saturation, minSaturation)
        let newValue = min(max(value, brightness.lowerBound), brightness.upperBound)
        return NSColor(hue: hue, saturation: newSaturation, brightness: newValue, alpha: 1)
    }
}
