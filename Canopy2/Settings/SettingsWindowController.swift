import AppKit
import SwiftUI

/// Plain window for Settings. Opened from the menu bar icon or the gear in the notch.
/// (SwiftUI's Settings scene can't be opened reliably from the notch panel.)
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var controller: NotchController?

    func configure(controller: NotchController) {
        self.controller = controller
    }

    func show() {
        guard let controller else { return }
        if window == nil {
            let view = SettingsView(
                nowPlaying: controller.nowPlaying,
                notifications: controller.notifications,
                weather: controller.weather,
                headphones: controller.headphones
            )
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
