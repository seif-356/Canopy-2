import AppKit
import SwiftUI

/// Borderless, transparent panel that floats above the menu bar on every Space.
/// It never becomes key, so opening the notch doesn't steal focus from your app.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Closed: clicks fall through to the menu bar. The controller flips this when it opens.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reacts to the first click even though the panel is never key.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
