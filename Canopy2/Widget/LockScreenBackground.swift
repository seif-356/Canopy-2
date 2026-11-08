import AppKit
import CoreImage

/// Shows a blurred copy of the album art behind the lock screen by temporarily
/// swapping the desktop picture (macOS draws the desktop picture on the lock screen),
/// then puts the original back on unlock.
///
/// Safety: the originals are saved to UserDefaults before anything changes, and
/// `restore()` runs at every launch, so a crash while locked can't leave the
/// artwork behind. Wallpapers that aren't plain image files (aerials, live
/// wallpapers) can't be restored by URL, so in that case nothing is swapped.
@MainActor
final class LockScreenBackground {
    private let backupKey = "lockScreenWallpaperBackup"
    private var savedOptions: [String: [NSWorkspace.DesktopImageOptionKey: Any]] = [:]
    private var appliedKey: String?

    private static let restorableExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"]

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Canopy2/LockScreen", isDirectory: true)
    }

    /// Sets the blurred artwork as the background. `key` identifies the song, so
    /// repeated calls for the same song do nothing.
    func apply(artwork: NSImage, key: String) {
        guard key != appliedKey else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // Back up the originals once per lock, and only if every one can be put back.
        var backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: String] ?? [:]
        if backup.isEmpty {
            for screen in screens {
                guard let url = NSWorkspace.shared.desktopImageURL(for: screen), Self.isRestorable(url) else { return }
                backup[Self.id(of: screen)] = url.absoluteString
                savedOptions[Self.id(of: screen)] = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            }
            UserDefaults.standard.set(backup, forKey: backupKey)
        }

        guard let file = render(artwork, size: screens.map(\.frame.size).max { $0.width < $1.width } ?? .zero) else { return }
        for screen in screens where backup[Self.id(of: screen)] != nil {
            try? NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
        appliedKey = key
        removeFiles(except: file)
    }

    /// Puts the user's own desktop pictures back. Safe to call any time.
    func restore() {
        defer {
            appliedKey = nil
            savedOptions = [:]
            removeFiles(except: nil)
        }
        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: String], !backup.isEmpty else { return }
        for screen in NSScreen.screens {
            let id = Self.id(of: screen)
            guard let string = backup[id], let url = URL(string: string) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: savedOptions[id] ?? [:])
        }
        UserDefaults.standard.removeObject(forKey: backupKey)
    }

    // MARK: - Private

    private static func id(of screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.stringValue ?? screen.localizedName
    }

    private static func isRestorable(_ url: URL) -> Bool {
        url.isFileURL
            && restorableExtensions.contains(url.pathExtension.lowercased())
            && FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Artwork scaled to fill the screen, heavily blurred and slightly darkened.
    private func render(_ image: NSImage, size: CGSize) -> URL? {
        guard size.width > 0, size.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let target = CGRect(origin: .zero, size: size)
        var output = CIImage(cgImage: cgImage)
        let scale = max(size.width / output.extent.width, size.height / output.extent.height)
        output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        output = output.transformed(by: CGAffineTransform(
            translationX: (size.width - output.extent.width) / 2 - output.extent.minX,
            y: (size.height - output.extent.height) / 2 - output.extent.minY
        ))
        output = output
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 45)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -0.1,
                kCIInputSaturationKey: 1.2,
            ])
            .cropped(to: target)

        guard let rendered = CIContext().createCGImage(output, from: target),
              let data = NSBitmapImageRep(cgImage: rendered).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else { return nil }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A new name each time: macOS caches desktop pictures by URL.
        let file = folder.appendingPathComponent("artwork-\(UUID().uuidString).jpg")
        do {
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }

    private func removeFiles(except keep: URL?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != keep?.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
