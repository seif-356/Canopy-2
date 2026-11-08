import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
    let timedOut: Bool

    var output: String { String(decoding: stdout, as: UTF8.self) }
    var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
}

/// Runs short-lived helper processes (osascript, perl) off the main thread.
enum ProcessRunner {
    /// Blocking. Never call on the main thread.
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let inputPipe = input.map { _ in Pipe() }
        if let inputPipe {
            process.standardInput = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8), timedOut: false)
        }

        let timedOut = Flag()
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        if let inputPipe, let input {
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
        }

        // Read stderr on another thread so a chatty process can't fill one pipe
        // while we're blocked reading the other.
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderrBox.data = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()

        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderrBox.data, timedOut: timedOut.isSet)
    }

    static func runAsync(_ executable: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run(executable, arguments, input: input, timeout: timeout))
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Splits a byte stream into lines. Used from a single reading thread.
final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let onLine: @Sendable (Data) -> Void

    init(onLine: @escaping @Sendable (Data) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { onLine(line) }
        }
    }
}
