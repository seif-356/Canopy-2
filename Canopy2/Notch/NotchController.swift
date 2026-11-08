import AppKit
import SwiftUI

/// Owns the notch panel, watches the mouse, and opens/closes the notch.
///
/// Hover detection uses NSEvent mouse monitors. Global monitors for mouse
/// events need no Accessibility permission (only key events do).
@MainActor
final class NotchController {
    let model: NotchModel
    private let nowPlaying: NowPlayingService
    private let shelf: ShelfStore

    private var panel: NotchPanel?
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var pendingOpen: Task<Void, Never>?
    private var pendingClose: Task<Void, Never>?
    /// Drag pasteboard change count at the last mouse-down. If it changes while the
    /// button is held, the user is dragging content (a file), not a window.
    private var dragChangeCountAtMouseDown = 0
    private var lastNotchlessPref: Bool?
    private var lastActivityPref: Bool?
    /// While set and in the future, moving the pointer away doesn't close the notch.
    private var holdOpenUntil: Date?

    init() {
        let nowPlaying = NowPlayingService()
        let shelf = ShelfStore()
        self.nowPlaying = nowPlaying
        self.shelf = shelf
        model = NotchModel(nowPlaying: nowPlaying, shelf: shelf)
    }

    func start() {
        dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        lastNotchlessPref = Prefs.isNotchlessEnabled
        lastActivityPref = Prefs.isMusicActivityEnabled
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
            MainActor.assumeIsolated { self?.preferencesChanged() }
        })
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

    private func preferencesChanged() {
        let notchless = Prefs.isNotchlessEnabled
        let activity = Prefs.isMusicActivityEnabled
        if notchless != lastNotchlessPref {
            lastNotchlessPref = notchless
            layout()
        }
        if activity != lastActivityPref {
            lastActivityPref = activity
            model.updateActivity()
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
            } else {
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
        guard !model.isOpen, let panel else { return }
        panel.ignoresMouseEvents = false
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            model.isOpen = true
        }
        nowPlaying.isActive = true
        nowPlaying.refresh()
    }

    func close() {
        cancelOpen()
        cancelClose()
        guard model.isOpen else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
            model.isOpen = false
        }
        model.isDropTargeted = false
        panel?.ignoresMouseEvents = true
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
        // Don't close mid-drag (e.g. while dragging a file out of the shelf).
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
