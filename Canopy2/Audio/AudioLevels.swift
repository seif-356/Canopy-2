import Accelerate
import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// How loud the music is right now, in a few frequency bands (bass first), for the
/// visualizer and the edge light.
///
/// With "React to the music" on (macOS 14.2 or later) it listens to what the Mac
/// plays through a Core Audio tap: nothing is recorded or saved, only loudness is
/// kept. Without that (setting off, older macOS, or permission denied) it makes up
/// gentle motion while a song plays, so the visuals never sit dead still.
///
/// Views that show levels call `retain()` when they appear and `release()` when
/// they go, so the tap only runs while something on screen uses it.
@MainActor
final class AudioLevels: ObservableObject {
    static let bandCount = 8

    @Published private(set) var bands = [Float](repeating: 0, count: AudioLevels.bandCount)
    /// Overall loudness, 0…1, weighted toward the bass.
    @Published private(set) var level: Float = 0
    /// True while the levels come from the real sound output.
    @Published private(set) var isLive = false
    /// What listening to the music is doing; stays at the last result when nothing uses it.
    @Published private(set) var listening: Listening = .idle

    enum Listening: Equatable {
        /// Not tried since launch.
        case idle
        /// "React to the music" is off.
        case off
        /// Needs macOS 14.2 or later.
        case unsupported
        /// Couldn't set up the tap (no output device?).
        case failed
        /// Tapping the output, no sound yet.
        case waiting
        /// Sound is coming through.
        case hearing
        /// Only silence while a song played: most likely no permission.
        case silent
    }

    /// Whether a song is playing; set by the owner.
    var isPlaying: () -> Bool = { false }

    private var users = 0
    private var tap: AnyObject?
    /// Bumped whenever listening stops, so a tap still being set up is thrown away.
    private var tapGeneration = 0
    private var timer: Timer?
    private var latest = [Float](repeating: 0, count: AudioLevels.bandCount)
    private var silentSince: Date?
    private var targets = [Float](repeating: 0, count: AudioLevels.bandCount)
    private var nextTargetDate = Date.distantPast

    func retain() {
        users += 1
        if users == 1 { start() }
    }

    func release() {
        guard users > 0 else { return }
        users -= 1
        if users == 0 { stop() }
    }

    private func start() {
        if !Prefs.bool(Prefs.reactToMusic) {
            listening = .off
        } else if #available(macOS 14.2, *) {
            let tap = SystemAudioTap(bandCount: Self.bandCount) { [weak self] bands in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(bands) }
                }
            }
            listening = .waiting
            tapGeneration += 1
            let generation = tapGeneration
            // Setting up the tap waits for the user to answer the macOS permission
            // prompt the first time, so do it off the main thread: the app keeps
            // drawing (with made-up motion) meanwhile.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let started = tap.start()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.tapStarted(tap, started: started, generation: generation) }
                }
            }
        } else {
            listening = .unsupported
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        stopTap()
        bands = [Float](repeating: 0, count: Self.bandCount)
        level = 0
    }

    private func stopTap() {
        tapGeneration += 1
        if #available(macOS 14.2, *) { (tap as? SystemAudioTap)?.stop() }
        tap = nil
        isLive = false
    }

    private func tapStarted(_ newTap: AnyObject, started: Bool, generation: Int) {
        guard generation == tapGeneration, users > 0 else {
            // Listening stopped while the tap was being set up.
            if #available(macOS 14.2, *), started { (newTap as? SystemAudioTap)?.stop() }
            return
        }
        if started {
            tap = newTap
            isLive = true
            silentSince = nil
            NSLog("Canopy2 audio: listening to the system output")
        } else {
            listening = .failed
            NSLog("Canopy2 audio: system audio tap unavailable, using made-up motion")
        }
    }

    /// Listens for a few seconds (e.g. from Settings) to show whether sound comes through.
    func test(seconds: Double = 6) {
        retain()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.release()
        }
    }

    private func receive(_ raw: [Float]) {
        guard tap != nil else { return }
        latest = raw
        let isSilent = raw.allSatisfy { $0 == 0 }
        if !isSilent, listening != .hearing {
            listening = .hearing
            NSLog("Canopy2 audio: hearing sound")
        }
        // Without permission the tap delivers pure digital silence. If that goes on
        // while a song plays, give up on it and fall back to made-up motion.
        if isSilent && isPlaying() && listening != .hearing {
            if let since = silentSince {
                if Date().timeIntervalSince(since) > 5 {
                    NSLog("Canopy2 audio: only silence from the tap (no permission?), using made-up motion")
                    stopTap()
                    listening = .silent
                }
            } else {
                silentSince = Date()
            }
        } else {
            silentSince = nil
        }
    }

    private func tick() {
        let source = isLive ? latest : madeUpTargets()
        var next = bands
        for index in 0..<Self.bandCount {
            let target = source[index]
            // Rise fast, fall slowly, like a level meter.
            next[index] += (target - next[index]) * (target > next[index] ? 0.55 : 0.12)
            if abs(target - next[index]) < 0.002 { next[index] = target }
        }
        guard next != bands else { return }
        bands = next
        let bass = (next[0] + next[1] + next[2]) / 3
        let all = next.reduce(0, +) / Float(next.count)
        level = min(1, bass * 0.65 + all * 0.45)
    }

    private func madeUpTargets() -> [Float] {
        guard isPlaying() else { return [Float](repeating: 0, count: Self.bandCount) }
        let now = Date()
        if now >= nextTargetDate {
            targets = (0..<Self.bandCount).map { index in
                Float.random(in: 0.2...0.85) * (1 - Float(index) * 0.07)
            }
            nextTargetDate = now.addingTimeInterval(Double.random(in: 0.12...0.3))
        }
        return targets
    }
}

/// Listens to everything the Mac plays (a global Core Audio process tap feeding a
/// private aggregate device) and reports band loudness about 30 times a second.
/// macOS asks for "System Audio Recording" permission the first time.
@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {
    private let bandCount: Int
    private let onBands: @Sendable ([Float]) -> Void
    private let queue = DispatchQueue(label: "com.seif356.Canopy2.audio-tap", qos: .userInteractive)
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var procID: AudioDeviceIOProcID?

    init(bandCount: Int, onBands: @escaping @Sendable ([Float]) -> Void) {
        self.bandCount = bandCount
        self.onBands = onBands
    }

    deinit { stop() }

    func start() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        var tap = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != 0 else { return false }
        tapID = tap

        guard let output = SystemAudio.defaultOutputDevice(), let outputUID = Self.uid(of: output) else {
            stop()
            return false
        }
        let subDevices: [[String: Any]] = [[kAudioSubDeviceUIDKey: outputUID]]
        let taps: [[String: Any]] = [[
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapUIDKey: description.uuid.uuidString,
        ]]
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Canopy 2 Listener",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: taps,
        ]
        var aggregate = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate) == noErr, aggregate != 0 else {
            stop()
            return false
        }
        aggregateID = aggregate

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let hasFormat = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr
        let sampleRate = hasFormat && format.mSampleRate > 0 ? format.mSampleRate : 48_000
        let interleaved = !hasFormat || format.mFormatFlags & UInt32(kAudioFormatFlagIsNonInterleaved) == 0

        let analyzer = SpectrumAnalyzer(bandCount: bandCount, sampleRate: sampleRate)
        let onBands = self.onBands
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue) { _, input, _, _, _ in
            analyzer.append(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)), interleaved: interleaved)
            if let bands = analyzer.bandsIfDue() { onBands(bands) }
        }
        guard status == noErr, let proc else {
            stop()
            return false
        }
        procID = proc
        guard AudioDeviceStart(aggregate, proc) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if aggregateID != 0 {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = 0
        tapID = 0
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}

/// Mono mix of the newest samples, turned into log-spaced band levels (0…1) with
/// an FFT. Each band adapts to its own recent peak, so the output volume and the
/// song's loudness don't matter. Used only on the tap's queue.
final class SpectrumAnalyzer {
    private static let size = 1024
    private static let log2n = vDSP_Length(10)

    private let setup: FFTSetup
    private let window: [Float]
    private let edges: [Int]
    private var ring = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var head = 0
    private var newSamples = 0
    private var peaks: [Float]
    private var lastEmit = DispatchTime.now().uptimeNanoseconds

    init(bandCount: Int, sampleRate: Double) {
        setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        var window = [Float](repeating: 0, count: Self.size)
        vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
        self.window = window
        let half = Self.size / 2
        let binHz = sampleRate / Double(Self.size)
        var edges: [Int] = []
        for index in 0...bandCount {
            let hertz = 40 * pow(14_000 / 40, Double(index) / Double(bandCount))
            var bin = min(max(Int((hertz / binHz).rounded()), 1), half - 1)
            if let last = edges.last { bin = max(bin, last + 1) }
            edges.append(min(bin, half))
        }
        self.edges = edges
        peaks = [Float](repeating: 30, count: bandCount)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func append(_ buffers: UnsafeMutableAudioBufferListPointer, interleaved: Bool) {
        guard let first = buffers.first, let firstData = first.mData else { return }
        if interleaved || buffers.count == 1 {
            let channels = max(Int(first.mNumberChannels), 1)
            let floats = firstData.assumingMemoryBound(to: Float.self)
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += floats[frame * channels + channel] }
                push(sum / Float(channels))
            }
        } else {
            let pointers = buffers.compactMap { $0.mData?.assumingMemoryBound(to: Float.self) }
            let frames = buffers.map { Int($0.mDataByteSize) / MemoryLayout<Float>.size }.min() ?? 0
            guard !pointers.isEmpty else { return }
            for frame in 0..<frames {
                var sum: Float = 0
                for pointer in pointers { sum += pointer[frame] }
                push(sum / Float(pointers.count))
            }
        }
    }

    private func push(_ sample: Float) {
        ring[head] = sample
        head = (head + 1) % Self.size
        newSamples += 1
    }

    /// Band levels, at most about 30 times a second; nil when it's too soon.
    func bandsIfDue() -> [Float]? {
        let now = DispatchTime.now().uptimeNanoseconds
        guard newSamples >= 256, now &- lastEmit >= 30_000_000 else { return nil }
        lastEmit = now
        newSamples = 0

        let count = Self.size
        let half = count / 2
        let bandCount = edges.count - 1
        var windowed = [Float](repeating: 0, count: count)
        var energy: Float = 0
        for index in 0..<count {
            let sample = ring[(head + index) % count]
            energy += sample * sample
            windowed[index] = sample * window[index]
        }
        guard energy > 0 else { return [Float](repeating: 0, count: bandCount) }

        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        let setup = self.setup
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { output in
                    vDSP_zvmags(&split, 1, output.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }

        var result = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let lower = edges[band]
            let upper = min(max(edges[band + 1], lower + 1), half)
            guard upper > lower else { continue }
            var sum: Float = 0
            for bin in lower..<upper { sum += magnitudes[bin] }
            let decibels = 10 * log10(sum / Float(upper - lower) + 1e-9)
            // Follow the band's recent peak down slowly (about 2.4 dB a second).
            peaks[band] = max(decibels, peaks[band] - 0.08, -10)
            let floor = peaks[band] - 40
            result[band] = pow(min(max((decibels - floor) / 40, 0), 1), 1.6)
        }
        return result
    }
}

/// The "System Audio Recording" permission, read through the private TCC framework
/// (there is no public API for it); `.unknown` when that isn't available. macOS
/// asks the user the first time the app starts listening.
enum AudioCapturePermission {
    enum State {
        case allowed
        case denied
        /// Not asked yet, or can't tell.
        case unknown

        var title: String {
            switch self {
            case .allowed: "Allowed"
            case .denied: "Not allowed"
            case .unknown: "Not asked yet"
            }
        }
    }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32

    static var state: State {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return .unknown }
        let preflight = unsafeBitCast(symbol, to: Preflight.self)
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .allowed
        case 1: return .denied
        default: return .unknown
        }
    }

    /// System Settings → Privacy & Security → Screen & System Audio Recording.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension AudioLevels.Listening {
    var title: String {
        switch self {
        case .idle: "Not tried yet"
        case .off: "Off"
        case .unsupported: "Needs macOS 14.2 or later"
        case .failed: "Couldn't listen to the sound output"
        case .waiting: "Listening… play something"
        case .hearing: "Hearing the music"
        case .silent: "No sound came through: allow Canopy 2 under System Audio Recording"
        }
    }

    var symbol: String {
        switch self {
        case .hearing: "waveform"
        case .waiting: "ear"
        case .silent, .failed: "exclamationmark.triangle.fill"
        case .idle, .off, .unsupported: "waveform.slash"
        }
    }
}
