import Foundation

/// Files parked on the shelf. Stores references (paths), not copies:
/// moving or deleting the original removes it from the shelf.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Prefs.shelfPaths) ?? []
        items = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    func add(_ urls: [URL]) {
        var changed = false
        for url in urls where url.isFileURL {
            let file = url.standardizedFileURL
            if !items.contains(file) {
                items.append(file)
                changed = true
            }
        }
        if changed { save() }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Drops files that were moved or deleted since they were shelved.
    func pruneMissing() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        if existing.count != items.count {
            items = existing
            save()
        }
    }

    private func save() {
        UserDefaults.standard.set(items.map { $0.path(percentEncoded: false) }, forKey: Prefs.shelfPaths)
    }
}
