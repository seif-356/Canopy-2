import Foundation
import IOKit.ps

struct BatteryState: Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isLowPowerMode: Bool

    var symbol: String {
        if isCharging || isPluggedIn { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

enum BatteryEvent {
    case pluggedIn(BatteryState)
    case unplugged(BatteryState)
    case low(BatteryState)
    case full(BatteryState)
    case lowPowerMode(BatteryState)
}

/// Watches the internal battery (public IOKit power-source API) and reports
/// plug/unplug, low battery (20 % and 10 %), fully charged and Low Power Mode.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var state: BatteryState?
    var onEvent: ((BatteryEvent) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var warnedThresholds: Set<Int> = []
    private static let lowThresholds = [20, 10]

    func start() {
        guard runLoopSource == nil else { return }
        state = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
    }

    private func update() {
        guard let new = Self.read() else { return }
        let old = state
        state = new
        guard let old else { return }

        if new.isPluggedIn && !old.isPluggedIn {
            onEvent?(.pluggedIn(new))
        } else if !new.isPluggedIn && old.isPluggedIn {
            onEvent?(.unplugged(new))
        }
        if new.isPluggedIn && new.percent >= 100 && old.percent < 100 {
            onEvent?(.full(new))
        }
        if new.isLowPowerMode != old.isLowPowerMode {
            onEvent?(.lowPowerMode(new))
        }

        // Warn once per threshold while on battery; re-arm when charged above it.
        warnedThresholds = warnedThresholds.filter { new.percent <= $0 }
        if !new.isPluggedIn,
           let threshold = Self.lowThresholds.sorted().first(where: { new.percent <= $0 }),
           !warnedThresholds.contains(threshold) {
            warnedThresholds.insert(threshold)
            onEvent?(.low(new))
        }
    }

    static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else { return nil }
        let sources = list as NSArray
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source as CFTypeRef)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            return BatteryState(
                percent: min(max(percent, 0), 100),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        }
        return nil
    }
}
