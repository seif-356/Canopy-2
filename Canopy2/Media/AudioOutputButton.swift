import CoreAudio
import SwiftUI

/// Shows the current audio output (laptop speakers, AirPods, …) and switches it.
struct AudioOutputButton: View {
    @State private var devices: [AudioOutputDevice] = []
    @State private var currentID: AudioDeviceID?

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    SystemAudio.setDefaultOutputDevice(device.id)
                    currentID = device.id
                } label: {
                    Label(device.name, systemImage: device.id == currentID ? "checkmark" : device.symbol)
                }
            }
        } label: {
            Image(systemName: currentSymbol)
                .font(.system(size: 15, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Audio output")
        .onAppear(perform: reload)
    }

    private var currentSymbol: String {
        devices.first { $0.id == currentID }?.symbol ?? "laptopcomputer"
    }

    private func reload() {
        devices = SystemAudio.outputDevices()
        currentID = SystemAudio.defaultOutputDevice()
    }
}

struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var symbol: String {
        func isType(_ types: UInt32...) -> Bool { types.contains(transportType) }
        if isType(UInt32(kAudioDeviceTransportTypeBuiltIn)) { return "laptopcomputer" }
        if isType(UInt32(kAudioDeviceTransportTypeBluetooth), UInt32(kAudioDeviceTransportTypeBluetoothLE)) {
            return name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones"
        }
        if isType(UInt32(kAudioDeviceTransportTypeHDMI), UInt32(kAudioDeviceTransportTypeDisplayPort)) { return "tv" }
        if isType(UInt32(kAudioDeviceTransportTypeAirPlay)) { return "airplayaudio" }
        return "hifispeaker"
    }
}

extension SystemAudio {
    /// Every device that can play sound, in the order CoreAudio lists them.
    static func outputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id) else { return nil }
            return AudioOutputDevice(id: id, name: name(of: id), transportType: transportType(of: id))
        }
    }

    static func setDefaultOutputDevice(_ id: AudioDeviceID) {
        var device = id
        var address = defaultDeviceAddress()
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &device
        )
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return "Unknown device" }
        return name.takeRetainedValue() as String
    }

    private static func transportType(of id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }
}
