import AppKit
import SwiftUI

/// EXPERIMENTAL: shows a Now Playing card on the lock screen while music plays.
///
/// macOS has no public API for this. It uses private SkyLight calls to put the
/// window in a space that's drawn above the lock screen. It's off by default and
/// only touches SkyLight when the screen actually locks.
@MainActor
final class LockScreenController {
    var isEnabled = false {
        didSet { if !isEnabled { hide() } }
    }

    private let player: NowPlayingService
    private let lyrics: LyricsService
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(player: NowPlayingService, lyrics: LyricsService) {
        self.player = player
        self.lyrics = lyrics
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
    }

    private func screenLocked() {
        guard isEnabled, player.track != nil, window == nil,
              let screen = NSScreen.screens.first,
              let skyLight = SkyLightBridge.shared else { return }

        let size = WidgetView.size(for: .nowPlaying)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.16,
            width: size.width,
            height: size.height
        )
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let host = FirstClickHostingView(
            rootView: WidgetView(player: player, lyrics: lyrics, preset: .nowPlaying, showsDragHandle: false)
        )
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        skyLight.moveToLockScreen(window)
        self.window = window
    }

    private func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Private SkyLight functions, looked up at runtime. nil if any is missing.
final class SkyLightBridge {
    @MainActor static let shared = SkyLightBridge()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: UInt64
    private let addWindows: SpaceAddWindows

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let mainConnection: MainConnectionID = Self.symbol(handle, "SLSMainConnectionID"),
              let spaceCreate: SpaceCreate = Self.symbol(handle, "SLSSpaceCreate"),
              let setLevel: SpaceSetAbsoluteLevel = Self.symbol(handle, "SLSSpaceSetAbsoluteLevel"),
              let showSpaces: ShowSpaces = Self.symbol(handle, "SLSShowSpaces"),
              let addWindows: SpaceAddWindows = Self.symbol(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }

        connection = mainConnection()
        space = spaceCreate(connection, 1, 0)
        guard space != 0 else { return nil }
        _ = setLevel(connection, space, 400) // above the lock screen shield
        _ = showSpaces(connection, [NSNumber(value: space)] as CFArray)
        self.addWindows = addWindows
    }

    func moveToLockScreen(_ window: NSWindow) {
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
