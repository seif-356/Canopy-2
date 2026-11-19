import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Night Mode: the whole screen becomes a lyrics lamp. A big serif clock, the
/// lyrics in the chosen style and a light around the screen edges that moves with
/// the music. Covers the menu bar and the Dock and keeps the display awake.
/// Esc leaves; Space plays or pauses; the arrow keys skip.
@MainActor
final class NightModeController {
    static let shared = NightModeController()

    private var player: NowPlayingService?
    private var lyrics: LyricsService?
    private var levels: AudioLevels?
    private var window: NightModeWindow?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var sleepAssertion = IOPMAssertionID(0)

    var isActive: Bool { window != nil }

    func configure(player: NowPlayingService, lyrics: LyricsService, levels: AudioLevels) {
        self.player = player
        self.lyrics = lyrics
        self.levels = levels
    }

    func toggle() {
        isActive ? hide() : show()
    }

    func show() {
        guard window == nil, let player, let lyrics, let levels else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let window = NightModeWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        let host = FirstClickHostingView(rootView: NightModeView(
            player: player, lyrics: lyrics, levels: levels,
            topInset: screen.safeAreaInsets.top,
            onClose: { [weak self] in self?.hide() }
        ))
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 0
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.6
        window.animator().alphaValue = 1
        NSAnimationContext.endGrouping()
        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let handled = MainActor.assumeIsolated { self?.handleKey(code) ?? false }
            return handled ? nil : event
        }

        if sleepAssertion == 0 {
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Canopy 2 Night Mode" as CFString,
                &sleepAssertion
            )
        }
    }

    func hide() {
        guard let window else { return }
        self.window = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
        NSCursor.setHiddenUntilMouseMoves(false)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.35
        window.animator().alphaValue = 0
        NSAnimationContext.endGrouping()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            window.orderOut(nil)
            window.contentView = nil
        }
        // Give the keyboard back to the app that was in front before.
        if let previousApp { _ = previousApp.activate(options: []) }
        previousApp = nil
    }

    /// Esc leaves, Space plays or pauses, the arrow keys skip. Other keys pass through.
    private func handleKey(_ code: UInt16) -> Bool {
        guard isActive, let player else { return false }
        switch code {
        case 53: hide()
        case 49: player.send(.playPause)
        case 123: player.send(.previous)
        case 124: player.send(.next)
        default: return false
        }
        return true
    }
}

/// Borderless, but can take the keyboard (Esc, Space, arrows).
final class NightModeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
