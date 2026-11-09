import AppKit

struct PlayedTrack: Identifiable, Codable, Equatable {
    /// Track identity (app + artist + album + title).
    let id: String
    let title: String
    let artist: String
    let bundleIdentifier: String?
}

/// Songs played recently (any app), newest first. Titles persist; artwork
/// thumbnails are kept for this session only.
@MainActor
final class PlayHistory: ObservableObject {
    @Published private(set) var items: [PlayedTrack] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]

    private let key = "playHistory"
    private let limit = 30

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([PlayedTrack].self, from: data) {
            items = saved
        }
    }

    func record(_ track: Track?) {
        guard let track, track.isPlaying, !track.title.isEmpty, items.first?.id != track.identity else { return }
        items.removeAll { $0.id == track.identity }
        items.insert(PlayedTrack(id: track.identity, title: track.title, artist: track.artist,
                                 bundleIdentifier: track.bundleIdentifier), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func setArtwork(_ image: NSImage?, for identity: String?) {
        guard let image, let identity, thumbnails[identity] == nil else { return }
        thumbnails[identity] = image.thumbnail(side: 80)
    }
}

extension NSImage {
    /// Small square copy, so the history doesn't hold full-size artwork.
    func thumbnail(side: CGFloat) -> NSImage {
        let pixels = Int(side * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return self }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }
}
