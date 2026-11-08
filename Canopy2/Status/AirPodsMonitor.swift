import AppKit
import CoreAudio

struct HeadphoneStatus: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Single-battery devices (AirPods Max, most headphones).
    var main: Int?

    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("max") { return "airpodsmax" }
        if lower.contains("pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// Lowest earbud level, for compact displays.
    var level: Int? {
        [left, right, main].compactMap { $0 }.min()
    }

    var summary: String {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if let main { parts.append("\(main)%") }
        if let caseLevel { parts.append("Case \(caseLevel)%") }
        return parts.isEmpty ? "Connected" : parts.joined(separator: "  ·  ")
    }
}

/// Notices when Bluetooth headphones (AirPods, Beats, …) become the audio output and
/// reads their battery levels from `system_profiler` (public, no private APIs).
@MainActor
final class AirPodsMonitor: ObservableObject {
    @Published private(set) var connected: HeadphoneStatus?
    var onConnect: ((HeadphoneStatus) -> Void)?

    private var listener: AudioObjectPropertyListenerBlock?
    private var lastDeviceID: AudioDeviceID?
    private var refreshTimer: Timer?

    func start() {
        guard listener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged(announce: true) }
        }
        var address = SystemAudio.defaultDeviceAddress()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        self.listener = listener
        outputChanged(announce: false)

        // Battery drains slowly; refresh every 5 minutes while connected.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBattery() }
        }
    }

    private func outputChanged(announce: Bool) {
        guard let id = SystemAudio.defaultOutputDevice(), id != lastDeviceID else { return }
        lastDeviceID = id
        guard let device = SystemAudio.outputDevices().first(where: { $0.id == id }),
              device.isBluetooth else {
            connected = nil
            return
        }
        connected = HeadphoneStatus(name: device.name)
        Task {
            let status = await HeadphoneBattery.fetch(named: device.name) ?? HeadphoneStatus(name: device.name)
            guard lastDeviceID == id else { return }
            connected = status
            if announce { onConnect?(status) }
        }
    }

    private func refreshBattery() {
        guard let name = connected?.name else { return }
        Task {
            guard let status = await HeadphoneBattery.fetch(named: name), connected?.name == name else { return }
            connected = status
        }
    }
}

extension AudioOutputDevice {
    var isBluetooth: Bool {
        transportType == UInt32(kAudioDeviceTransportTypeBluetooth)
            || transportType == UInt32(kAudioDeviceTransportTypeBluetoothLE)
    }
}

enum HeadphoneBattery {
    /// Reads `system_profiler SPBluetoothDataType -json` and returns the battery
    /// levels of the connected device with this name.
    static func fetch(named name: String) async -> HeadphoneStatus? {
        let result = await ProcessRunner.runAsync(
            "/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json", "-detailLevel", "basic"], timeout: 20
        )
        guard result.status == 0,
              let root = (try? JSONSerialization.jsonObject(with: result.stdout)) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (deviceName, value) in entry {
                    guard let properties = value as? [String: Any],
                          deviceName == name || deviceName.localizedCaseInsensitiveContains(name)
                            || name.localizedCaseInsensitiveContains(deviceName) else { continue }
                    func level(_ key: String) -> Int? {
                        (properties[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                    }
                    return HeadphoneStatus(
                        name: deviceName,
                        left: level("device_batteryLevelLeft"),
                        right: level("device_batteryLevelRight"),
                        caseLevel: level("device_batteryLevelCase"),
                        main: level("device_batteryLevelMain")
                    )
                }
            }
        }
        return nil
    }
}
