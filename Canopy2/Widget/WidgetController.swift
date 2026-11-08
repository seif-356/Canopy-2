import AppKit
import SwiftUI

/// The desktop widget window: sits on the wallpaper, below all other windows,
/// on every Space. Drag the grip at the top to move it; the position is remembered.
@MainActor
final class WidgetController {
    private let player: NowPlayingService
    private let lyrics: LyricsService
    private var window: NSWindow?
    private var preset: WidgetPreset?

    init(player: NowPlayingService, lyrics: LyricsService) {
        self.player = player
        self.lyrics = lyrics
    }

    func update(enabled: Bool, preset: WidgetPreset) {
        guard enabled else {
            window?.orderOut(nil)
            window = nil
            self.preset = nil
            return
        }
        let window = self.window ?? makeWindow()
        if preset != self.preset {
            self.preset = preset
            let host = FirstClickHostingView(rootView: WidgetView(player: player, lyrics: lyrics, preset: preset))
            host.sizingOptions = []
            window.contentView = host
            // Keep the top-left corner where the user put it.
            let size = WidgetView.size(for: preset)
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
        }
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = WidgetView.size(for: .lockScreen)
        let frame = NSRect(x: visible.minX + 40, y: visible.maxY - size.height - 40, width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Canopy2Widget")
        self.window = window
        return window
    }
}

/// Hosting view whose buttons work on the first click in a window that isn't key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
