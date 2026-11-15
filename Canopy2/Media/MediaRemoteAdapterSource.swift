import AppKit

/// System-wide now playing (any app: browsers, Podcasts, VLC, …) through MediaRemote.
///
/// Since macOS 15.4 only Apple-entitled processes may use MediaRemote, so this runs
/// the bundled open-source mediaremote-adapter (BSD-3, github.com/ungive/mediaremote-adapter)
/// inside `/usr/bin/perl`, which is entitled, and reads its JSON stream.
@MainActor
final class MediaRemoteAdapterSource: MediaSource {
    struct Paths: Sendable {
        let script: String
        let framework: String
        let testClient: String?
    }

    /// Present when the app was built with the adapter embedded (the CI build is).
    /// Looked up by explicit paths inside the bundle, the layout the embed script creates.
    static var bundledPaths: Paths? {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let script = contents.appendingPathComponent("Resources/mediaremote-adapter.pl", isDirectory: false)
            .path(percentEncoded: false)
        let framework = contents.appendingPathComponent("Frameworks/MediaRemoteAdapter.framework", isDirectory: false)
            .path(percentEncoded: false)
        let testClient = contents.appendingPathComponent("MacOS/MediaRemoteAdapterTestClient", isDirectory: false)
            .path(percentEncoded: false)
        let fileManager = FileManager.default
        let hasScript = fileManager.fileExists(atPath: script)
        let hasFramework = fileManager.fileExists(atPath: framework)
        let hasClient = fileManager.isExecutableFile(atPath: testClient)
        NSLog("Canopy2 media: bundle %@ script=%@ framework=%@ testClient=%@",
              Bundle.main.bundleURL.path(percentEncoded: false),
              hasScript ? "yes" : "no", hasFramework ? "yes" : "no", hasClient ? "yes" : "no")
        guard hasScript, hasFramework else { return nil }
        return Paths(script: script, framework: framework, testClient: hasClient ? testClient : nil)
    }

    /// Runs the adapter's self-test. False means a macOS update broke it: use AppleScript.
    static func isFunctional(_ paths: Paths) async -> Bool {
        guard let testClient = paths.testClient else { return true }
        let result = await ProcessRunner.runAsync(
            "/usr/bin/perl", [paths.script, paths.framework, testClient, "test"], timeout: 20
        )
        NSLog("Canopy2 media: adapter self-test exit=%d timedOut=%@ %@",
              result.status, result.timedOut ? "yes" : "no", result.errorOutput)
        return result.status == 0 && !result.timedOut
    }

    var onUpdate: ((MediaUpdate) -> Void)?
    var onFailure: (() -> Void)?
    var isActive = false

    private let paths: Paths
    private var process: Process?
    private var state: [String: Any] = [:]
    private var lastIdentity: String?
    /// When artworkData last arrived, to tell early art for a new song from stale art.
    private var artworkReceivedAt = Date.distantPast
    private var isStopping = false
    private var failures = 0
    private var launchDate = Date()

    init(paths: Paths) {
        self.paths = paths
    }

    func start() {
        isStopping = false
        launch()
    }

    func stop() {
        isStopping = true
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        process = nil
        onUpdate = nil
        onFailure = nil
    }

    func refresh() {
        // Streaming: nothing to poll.
    }

    func send(_ command: MediaCommand) {
        runCommand(["send", String(command.mediaRemoteID)])
    }

    func seek(to seconds: Double) {
        runCommand(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }

    // MARK: - Private

    private func runCommand(_ arguments: [String]) {
        let base = [paths.script, paths.framework]
        Task.detached(priority: .userInitiated) {
            _ = ProcessRunner.run("/usr/bin/perl", base + arguments, timeout: 10)
        }
    }

    private func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework, "stream", "--micros", "--debounce=50"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let reader = LineReader { [weak self] line in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.handle(line) }
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil // EOF
            } else {
                reader.append(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.processEnded() }
            }
        }

        do {
            try process.run()
            self.process = process
            launchDate = Date()
        } catch {
            onFailure?()
        }
    }

    private func processEnded() {
        guard !isStopping else { return }
        // A stream that ran a while and died gets restarted; repeated quick deaths mean it's broken.
        if Date().timeIntervalSince(launchDate) > 30 { failures = 0 }
        failures += 1
        if failures > 3 {
            onFailure?()
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if !isStopping { launch() }
        }
    }

    private func handle(_ line: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = message["payload"] as? [String: Any] else { return }

        if message["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull {
                    state.removeValue(forKey: key)
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload
        }

        let track = makeTrack()
        var update = MediaUpdate(track: track)
        let identityChanged = track?.identity != lastIdentity
        lastIdentity = track?.identity
        let artworkInMessage = payload["artworkData"].map { !($0 is NSNull) } ?? false
        if artworkInMessage { artworkReceivedAt = Date() }

        // On a song change, cached artwork belongs to the old song unless it arrived
        // just now (some players send the new art a moment before the new title).
        if identityChanged && !artworkInMessage && Date().timeIntervalSince(artworkReceivedAt) > 1.5 {
            state.removeValue(forKey: "artworkData")
        }
        if identityChanged || artworkInMessage, let base64 = state["artworkData"] as? String {
            update.artworkData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        }
        onUpdate?(update)
    }

    private func makeTrack() -> Track? {
        guard let title = state["title"] as? String, !title.isEmpty else { return nil }
        func number(_ key: String) -> Double? { (state[key] as? NSNumber)?.doubleValue }

        let rate = number("playbackRate") ?? 1
        let timestamp = number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date()
        // Browser media reports a helper process; the parent is the browser itself.
        let bundle = (state["parentApplicationBundleIdentifier"] as? String) ?? (state["bundleIdentifier"] as? String)

        return Track(
            bundleIdentifier: bundle,
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            duration: (number("durationMicros") ?? 0) / 1_000_000,
            isPlaying: state["playing"] as? Bool ?? false,
            position: (number("elapsedTimeMicros") ?? 0) / 1_000_000,
            positionDate: timestamp,
            playbackRate: rate > 0 ? rate : 1
        )
    }
}
