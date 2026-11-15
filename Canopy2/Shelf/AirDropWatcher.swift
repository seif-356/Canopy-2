import Foundation

/// Notices files arriving by AirDrop: watches ~/Downloads and checks each new
/// file's quarantine tag, which names the AirDrop service (sharingd) as its source.
/// Reading ~/Downloads makes macOS ask for permission once.
@MainActor
final class AirDropWatcher {
    var onArrival: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var seen: Set<String> = []
    private let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)

    func setEnabled(_ enabled: Bool) {
        source?.cancel()
        source = nil
        guard enabled else { return }

        seen = Set(currentFiles().map(\.lastPathComponent))
        let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func currentFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func folderChanged() {
        // AirDrop may still be writing; look once it has settled.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.scan()
        }
    }

    private func scan() {
        for url in currentFiles() where !seen.contains(url.lastPathComponent) {
            seen.insert(url.lastPathComponent)
            let name = url.lastPathComponent
            guard !name.hasSuffix(".download"), !name.hasSuffix(".crdownload"), !name.hasSuffix(".part") else { continue }
            if Self.isFromAirDrop(url) {
                onArrival?(url)
            }
        }
    }

    static func isFromAirDrop(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let length = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0)
        guard length > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(path, "com.apple.quarantine", &buffer, length, 0, 0) > 0 else { return false }
        let tag = String(decoding: buffer, as: UTF8.self)
        return tag.localizedCaseInsensitiveContains("sharingd") || tag.localizedCaseInsensitiveContains("airdrop")
    }
}
