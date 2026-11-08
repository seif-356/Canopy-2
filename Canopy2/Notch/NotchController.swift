import AppKit
import Combine
import SwiftUI

/// Owns the notch panel and every feature service, watches the mouse,
/// and decides what the notch shows.
///
/// Hover detection uses NSEvent mouse monitors. Global monitors for mouse
/// events need no Accessibility permission (only key events do).
@MainActor
final class NotchController {
    let model: NotchModel
    let nowPlaying: NowPlayingService
    let lyrics: LyricsService
    let shelf: ShelfStore
    let notifications: NotificationMirror

    private let volumeObserver = VolumeObserver()
    private let keyTap = MediaKeyTap()
    private let widget: WidgetController
    private let lockScreen: LockScreenController

    private var panel: NotchPanel?
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var pendingOpen: Task<Void, Never>?
    private var pendingClose: Task<Void, Never>?
    private var hudHideTask: Task<Void, Never>?
    private var bannerHideTask: Task<Void, Never>?
    private var keyTapRetryTimer: Timer?
    /// Drag pasteboard change count at the last mouse-down. If it changes while the
    /// button is held, the user is dragging content (a file), not a window.
    private var dragChangeCountAtMouseDown = 0
    /// While set and in the future, moving the pointer away doesn't close the notch.
    private var holdOpenUntil: Date?
    private var appliedPrefs: [String: String]?
    private var lastTrackIdentity: String?

    init() {
        let nowPlaying = NowPlayingService()
        let lyrics = LyricsService()
        let shelf = ShelfStore()
        self.nowPlaying = nowPlaying
        self.lyrics = lyrics
        self.shelf = shelf
        notifications = NotificationMirror()
        widget = WidgetController(player: nowPlaying, lyrics: lyrics)
        lockScreen = LockScreenController(player: nowPlaying, lyrics: lyrics)
        model = NotchModel(nowPlaying: nowPlaying, lyrics: lyrics, shelf: shelf)
    }

    func start() {
        dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        layout()
        installEventMonitors()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        })

        nowPlaying.$track
            .sink { [weak self] track in
                MainActor.assumeIsolated { self?.trackUpdated(track) }
            }
            .store(in: &cancellables)

        notifications.onNotification = { [weak self] notification in
            self?.showNotificationBanner(notification)
        }
        volumeObserver.onChange = { [weak self] in
            self?.volumeChanged()
        }
        keyTap.handler = { [weak self] key, isDown in
            self?.handleMediaKey(key, isDown: isDown) ?? false
        }
        model.onBannerTap = { [weak self] banner in
            self?.bannerTapped(banner)
        }

        lockScreen.start()
        nowPlaying.start()
        applyPreferences()
    }

    // MARK: - Preferences

    private func applyPreferences() {
        let current = Prefs.snapshot()
        let previous = appliedPrefs
        appliedPrefs = current
        func changed(_ key: String) -> Bool { previous?[key] != current[key] }
        let isFirst = previous == nil

        if changed(Prefs.showOnNotchless) && !isFirst { layout() }
        if changed(Prefs.mediaSource) && !isFirst { nowPlaying.configureSource() }
        if changed(Prefs.showMusicActivity) || changed(Prefs.closedLyrics) { model.updateActivity() }
        if changed(Prefs.lyricsEnabled) { lyrics.reload(for: nowPlaying.track) }
        if changed(Prefs.notificationMirroring) {
            notifications.setEnabled(Prefs.bool(Prefs.notificationMirroring))
        }
        if changed(Prefs.volumeHUD) || changed(Prefs.replaceSystemHUD) {
            if Prefs.bool(Prefs.volumeHUD) || Prefs.bool(Prefs.replaceSystemHUD) {
                volumeObserver.start()
            } else {
                volumeObserver.stop()
            }
        }
        if changed(Prefs.replaceSystemHUD) { updateKeyTap(prompt: !isFirst) }
        if changed(Prefs.widgetEnabled) || changed(Prefs.widgetPreset) {
            widget.update(
                enabled: Prefs.bool(Prefs.widgetEnabled),
                preset: WidgetPreset(rawValue: Prefs.string(Prefs.widgetPreset)) ?? .lockScreen
            )
        }
        if changed(Prefs.lockScreenWidget) { lockScreen.isEnabled = Prefs.bool(Prefs.lockScreenWidget) }
    }

    // MARK: - Layout

    private func layout() {
        guard let screen = NotchGeometry.preferredScreen() else {
            hide()
            return
        }
        let geometry = NotchGeometry(screen: screen)
        if !geometry.hasHardwareNotch && !Prefs.isNotchlessEnabled {
            hide()
            return
        }
        model.geometry = geometry
        let panel = self.panel ?? makePanel(frame: geometry.windowFrame)
        panel.setFrame(geometry.windowFrame, display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel(frame: NSRect) -> NotchPanel {
        let panel = NotchPanel(frame: frame)
        let hostingView = NotchHostingView(rootView: NotchRootView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    private func hide() {
        close()
        panel?.orderOut(nil)
        model.geometry = nil
    }

    /// Clicks pass through the panel unless something clickable is showing.
    private func updateMouseHandling() {
        panel?.ignoresMouseEvents = !(model.isOpen || model.banner != nil)
    }

    // MARK: - Now playing → lyrics and banners

    private func trackUpdated(_ track: Track?) {
        let identity = track?.identity
        guard identity != lastTrackIdentity else { return }
        let previous = lastTrackIdentity
        lastTrackIdentity = identity
        lyrics.load(for: track)

        // Banner for a new song (not for the first one seen after launch).
        guard let track, previous != nil, track.isPlaying, Prefs.bool(Prefs.trackBanner), !model.isOpen else { return }
        showBanner(Banner(
            kind: .track,
            icon: AppIcons.icon(for: track.bundleIdentifier),
            title: track.title,
            subtitle: track.artist.isEmpty ? track.appName : track.artist
        ))
    }

    private func showNotificationBanner(_ notification: MirroredNotification) {
        let appName = AppIcons.name(for: notification.bundleIdentifier)
        let details = [notification.subtitle, notification.body].filter { !$0.isEmpty }.joined(separator: " · ")
        showBanner(Banner(
            kind: .notification(bundleIdentifier: notification.bundleIdentifier),
            icon: AppIcons.icon(for: notification.bundleIdentifier),
            title: notification.title.isEmpty ? appName : notification.title,
            subtitle: notification.title.isEmpty ? details : (details.isEmpty ? appName : details)
        ))
    }

    private func showBanner(_ banner: Banner) {
        guard model.geometry != nil, !model.isOpen else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            model.banner = banner
        }
        updateMouseHandling()
        bannerHideTask?.cancel()
        bannerHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            self?.hideBanner()
        }
    }

    private func hideBanner() {
        bannerHideTask?.cancel()
        bannerHideTask = nil
        guard model.banner != nil else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            model.banner = nil
        }
        updateMouseHandling()
    }

    private func bannerTapped(_ banner: Banner) {
        hideBanner()
        switch banner.kind {
        case .track:
            open(tab: .nowPlaying)
        case .notification(let bundleIdentifier):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    // MARK: - Volume & brightness

    private func volumeChanged() {
        guard Prefs.bool(Prefs.volumeHUD) || Prefs.bool(Prefs.replaceSystemHUD),
              let level = SystemAudio.volume() else { return }
        showHUD(HUDState(kind: .volume, level: level, isMuted: SystemAudio.isMuted()))
    }

    private func showHUD(_ state: HUDState) {
        guard model.geometry != nil, !model.isOpen else { return }
        if model.hud == nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.hud = state }
        } else {
            model.hud = state
        }
        hudHideTask?.cancel()
        hudHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { self.model.hud = nil }
        }
    }

    private func updateKeyTap(prompt: Bool) {
        keyTapRetryTimer?.invalidate()
        keyTapRetryTimer = nil
        guard Prefs.bool(Prefs.replaceSystemHUD) else {
            keyTap.stop()
            return
        }
        if keyTap.start() { return }
        // Not allowed yet: ask once, then keep checking until the user allows it.
        if prompt { MediaKeyTap.requestTrust() }
        keyTapRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, Prefs.bool(Prefs.replaceSystemHUD) else {
                    timer.invalidate()
                    return
                }
                if self.keyTap.start() {
                    timer.invalidate()
                    self.keyTapRetryTimer = nil
                }
            }
        }
    }

    /// Handles volume/brightness keys instead of macOS. Returns true to swallow the key.
    private func handleMediaKey(_ key: MediaKey, isDown: Bool) -> Bool {
        guard Prefs.bool(Prefs.replaceSystemHUD) else { return false }
        let step: Float = 1.0 / 16
        switch key {
        case .volumeUp, .volumeDown:
            // Devices without software volume (some HDMI/USB outputs): let macOS handle it.
            guard let current = SystemAudio.volume() else { return false }
            if isDown {
                let target = current + (key == .volumeUp ? step : -step)
                if key == .volumeUp && SystemAudio.isMuted() { SystemAudio.setMuted(false) }
                SystemAudio.setVolume((target / step).rounded() * step)
                showHUD(HUDState(kind: .volume, level: SystemAudio.volume() ?? target, isMuted: SystemAudio.isMuted()))
            }
            return true
        case .mute:
            guard SystemAudio.volume() != nil else { return false }
            if isDown {
                SystemAudio.setMuted(!SystemAudio.isMuted())
                showHUD(HUDState(kind: .volume, level: SystemAudio.volume() ?? 0, isMuted: SystemAudio.isMuted()))
            }
            return true
        case .brightnessUp, .brightnessDown:
            guard let current = DisplayBrightness.get() else { return false }
            if isDown {
                let target = current + (key == .brightnessUp ? step : -step)
                DisplayBrightness.set((target / step).rounded() * step)
                showHUD(HUDState(kind: .brightness, level: DisplayBrightness.get() ?? target))
            }
            return true
        }
    }

    // MARK: - Mouse tracking

    private func installEventMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            eventMonitors.append(local)
        }
    }

    private var isDraggingContent: Bool {
        NSPasteboard(name: .drag).changeCount != dragChangeCountAtMouseDown
    }

    private var isMouseButtonDown: Bool {
        NSEvent.pressedMouseButtons & 0x1 != 0
    }

    private func openHotZone(_ geometry: NotchGeometry) -> NSRect {
        var zone = geometry.rectHangingFromTop(model.closedSize).insetBy(dx: -8, dy: 0)
        zone.size.height += 4 // include the very top pixel row of the screen
        return zone
    }

    private func keepOpenZone(_ geometry: NotchGeometry) -> NSRect {
        geometry.rectHangingFromTop(NotchMetrics.openSize).insetBy(dx: -12, dy: -12)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            return
        }
        guard let geometry = model.geometry else { return }
        let point = NSEvent.mouseLocation

        if model.isOpen {
            if keepOpenZone(geometry).contains(point) {
                cancelClose()
                if event.type == .leftMouseDragged && isDraggingContent {
                    model.tab = .shelf
                }
            } else {
                scheduleClose()
            }
            return
        }

        if openHotZone(geometry).contains(point) {
            if event.type == .leftMouseDragged {
                // Dragging a file onto the notch opens the shelf right away.
                if isDraggingContent { open(tab: .shelf) }
            } else if model.banner == nil {
                // (A banner is clickable; don't turn hovering it into opening.)
                scheduleOpen()
            }
        } else {
            cancelOpen()
        }
    }

    // MARK: - Open / close

    /// Opens the notch for a few seconds so it's obvious the app is running
    /// (it has no Dock icon, and the menu bar icon can hide behind the notch).
    func showHello() {
        let seconds = 3.0
        holdOpenUntil = Date().addingTimeInterval(seconds)
        open()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            self.holdOpenUntil = nil
            if let geometry = self.model.geometry, !self.keepOpenZone(geometry).contains(NSEvent.mouseLocation) {
                self.close()
            }
        }
    }

    func open(tab: NotchTab? = nil) {
        cancelOpen()
        cancelClose()
        if let tab { model.tab = tab }
        guard !model.isOpen, panel != nil else { return }
        hideBanner()
        hudHideTask?.cancel()
        model.hud = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            model.isOpen = true
        }
        updateMouseHandling()
        nowPlaying.isActive = true
    }

    func close() {
        cancelOpen()
        cancelClose()
        guard model.isOpen else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
            model.isOpen = false
        }
        model.isDropTargeted = false
        updateMouseHandling()
        nowPlaying.isActive = false
    }

    private func scheduleOpen() {
        guard pendingOpen == nil else { return }
        pendingOpen = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.pendingOpen = nil
            // Only open if the pointer is still on the notch.
            if let geometry = self.model.geometry, self.openHotZone(geometry).contains(NSEvent.mouseLocation) {
                self.open()
            }
        }
    }

    private func scheduleClose() {
        // Don't close mid-drag (e.g. while dragging a file out of the shelf or scrubbing).
        guard pendingClose == nil, !isMouseButtonDown else { return }
        if let holdOpenUntil, holdOpenUntil > Date() { return }
        pendingClose = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.pendingClose = nil
            guard let geometry = self.model.geometry,
                  !self.keepOpenZone(geometry).contains(NSEvent.mouseLocation),
                  !self.isMouseButtonDown else { return }
            self.close()
        }
    }

    private func cancelOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    private func cancelClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }
}
