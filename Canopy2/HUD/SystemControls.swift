import AppKit
import AudioToolbox
import CoreAudio

/// Output volume of the default audio device (public CoreAudio API).
enum SystemAudio {
    static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultDeviceAddress()
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil // 0 = kAudioObjectUnknown
    }

    static func volume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress()
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ volume: Float) {
        guard let device = defaultOutputDevice() else { return }
        var value = Float32(min(max(volume, 0), 1))
        var address = volumeAddress()
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress()
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var value = UInt32(muted ? 1 : 0)
        var address = muteAddress()
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func defaultDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

/// Calls `onChange` when the output volume or mute state changes, from any source.
@MainActor
final class VolumeObserver {
    var onChange: (() -> Void)?

    private var device: AudioDeviceID?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    func start() {
        guard defaultDeviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attach() }
        }
        var address = SystemAudio.defaultDeviceAddress()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        defaultDeviceListener = listener
        attach()
    }

    func stop() {
        detach()
        if let defaultDeviceListener {
            var address = SystemAudio.defaultDeviceAddress()
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, defaultDeviceListener)
        }
        defaultDeviceListener = nil
    }

    private func attach() {
        detach()
        guard let device = SystemAudio.defaultOutputDevice() else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        var volume = SystemAudio.volumeAddress()
        var mute = SystemAudio.muteAddress()
        AudioObjectAddPropertyListenerBlock(device, &volume, DispatchQueue.main, listener)
        AudioObjectAddPropertyListenerBlock(device, &mute, DispatchQueue.main, listener)
        self.device = device
        deviceListener = listener
    }

    private func detach() {
        guard let device, let deviceListener else { return }
        var volume = SystemAudio.volumeAddress()
        var mute = SystemAudio.muteAddress()
        AudioObjectRemovePropertyListenerBlock(device, &volume, DispatchQueue.main, deviceListener)
        AudioObjectRemovePropertyListenerBlock(device, &mute, DispatchQueue.main, deviceListener)
        self.device = nil
        self.deviceListener = nil
    }
}

/// Built-in display brightness through the private DisplayServices framework
/// (looked up at runtime; does nothing if it's missing).
enum DisplayBrightness {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getter: Getter? = symbol("DisplayServicesGetBrightness")
    private static let setter: Setter? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get() -> Float? {
        guard let getter, let display = builtInDisplay else { return nil }
        var value: Float = 0
        return getter(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) {
        guard let setter, let display = builtInDisplay else { return }
        _ = setter(display, min(max(value, 0), 1))
    }
}
