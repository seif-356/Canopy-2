import AppKit
import ApplicationServices

enum MediaKey: Int {
    case volumeUp = 0      // NX_KEYTYPE_SOUND_UP
    case volumeDown = 1    // NX_KEYTYPE_SOUND_DOWN
    case brightnessUp = 2  // NX_KEYTYPE_BRIGHTNESS_UP
    case brightnessDown = 3
    case mute = 7          // NX_KEYTYPE_MUTE
}

/// Intercepts the volume, mute and brightness keys so Canopy 2 can handle them
/// itself and macOS doesn't show its own pop-up. Needs Accessibility permission.
final class MediaKeyTap {
    /// Return true to swallow the key (macOS won't see it).
    var handler: (@MainActor (_ key: MediaKey, _ isDown: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Accessibility settings.
    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }
        let mask = CGEventMask(1) << 14 // NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables slow taps; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            return Unmanaged.passUnretained(event)
        }
        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyState = (data & 0x0000_FF00) >> 8
        guard let key = MediaKey(rawValue: keyCode), let handler else {
            return Unmanaged.passUnretained(event)
        }
        let isDown = keyState == 0xA
        let swallow = MainActor.assumeIsolated { handler(key, isDown) }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}
