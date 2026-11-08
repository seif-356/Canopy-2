import AppKit
import SwiftUI

/// Plain window for Settings. Opened from the menu bar icon or the gear in the notch.
/// (SwiftUI's Settings scene can't be opened reliably from the notch panel.)
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var nowPlaying: NowPlayingService?
    private var notifications: NotificationMirror?

    func configure(nowPlaying: NowPlayingService, notifications: NotificationMirror) {
        self.nowPlaying = nowPlaying
        self.notifications = notifications
    }

    func show() {
        guard let nowPlaying, let notifications else { return }
        if window == nil {
            let view = SettingsView(nowPlaying: nowPlaying, notifications: notifications)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Canopy 2 Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
