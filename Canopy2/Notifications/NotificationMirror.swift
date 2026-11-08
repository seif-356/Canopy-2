import AppKit
import SQLite3

struct MirroredNotification: Identifiable, Sendable {
    let id: Int64
    let bundleIdentifier: String
    let title: String
    let subtitle: String
    let body: String
}

/// Shows other apps' notifications in the notch.
///
/// macOS has no public API for other apps' notifications, so this reads the
/// Notification Center database (`usernoted`) read-only. That file is protected:
/// Canopy 2 needs Full Disk Access. Without it, status says so and nothing else breaks.
@MainActor
final class NotificationMirror: ObservableObject {
    enum Status: Equatable {
        case off
        case needsFullDiskAccess
        case unavailable(String)
        case running
    }

    @Published private(set) var status: Status = .off
    var onNotification: ((MirroredNotification) -> Void)?

    private let reader = NotificationDatabaseReader()
    private var timer: Timer?
    private var isPolling = false

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else {
            status = .off
            reader.reset()
            return
        }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        let reader = self.reader
        Task {
            let result = await reader.poll()
            isPolling = false
            guard timer != nil else { return } // turned off meanwhile
            switch result {
            case .notifications(let list):
                status = .running
                let ownID = Bundle.main.bundleIdentifier
                for notification in list where notification.bundleIdentifier != ownID {
                    onNotification?(notification)
                }
            case .noAccess:
                status = .needsFullDiskAccess
            case .unavailable(let reason):
                status = .unavailable(reason)
            }
        }
    }
}

/// All SQLite work happens on one serial queue.
final class NotificationDatabaseReader: @unchecked Sendable {
    enum PollResult: Sendable {
        case notifications([MirroredNotification])
        case noAccess
        case unavailable(String)
    }

    private let queue = DispatchQueue(label: "com.seif356.Canopy2.notifications")
    private var database: OpaquePointer?
    private var lastID: Int64?

    func poll() async -> PollResult {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.pollOnQueue()) }
        }
    }

    func reset() {
        queue.async {
            if let database = self.database { sqlite3_close(database) }
            self.database = nil
            self.lastID = nil
        }
    }

    // MARK: - Private

    private enum Location {
        case found(String)
        case noAccess
        case missing
    }

    private static func locateDatabase() -> Location {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let groupContainer = home.appendingPathComponent("Library/Group Containers/group.com.apple.usernoted")
        var candidates = [groupContainer.appendingPathComponent("db2/db").path(percentEncoded: false)]

        // Older macOS kept it in the per-user temp directory.
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            let userDir = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            candidates.append((userDir as NSString).appendingPathComponent("com.apple.notificationcenter/db2/db"))
        }

        for path in candidates where fileManager.fileExists(atPath: path) {
            return FileHandle(forReadingAtPath: path) == nil ? .noAccess : .found(path)
        }
        // Without Full Disk Access the container itself may be hidden.
        if fileManager.fileExists(atPath: groupContainer.path(percentEncoded: false))
            || (try? fileManager.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Group Containers").path(percentEncoded: false))) == nil {
            return .noAccess
        }
        return .missing
    }

    private func pollOnQueue() -> PollResult {
        if database == nil {
            switch Self.locateDatabase() {
            case .noAccess:
                return .noAccess
            case .missing:
                return .unavailable("Couldn't find the Notification Center database on this macOS version.")
            case .found(let path):
                var handle: OpaquePointer?
                let code = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil)
                guard code == SQLITE_OK, let handle else {
                    sqlite3_close(handle)
                    return code == SQLITE_CANTOPEN || code == SQLITE_PERM || code == SQLITE_AUTH
                        ? .noAccess
                        : .unavailable("SQLite error \(code)")
                }
                sqlite3_busy_timeout(handle, 500)
                database = handle
            }
        }
        guard let database else { return .unavailable("No database") }

        // First poll: start from the newest record so old notifications aren't replayed.
        guard let lastID else {
            guard let maxID = queryMaxID(database) else {
                return .unavailable("This macOS version stores notifications differently.")
            }
            self.lastID = maxID
            return .notifications([])
        }

        let sql = """
            SELECT r.rec_id, IFNULL(a.identifier, ''), r.data
            FROM record r LEFT JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id ASC LIMIT 20
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return .unavailable("This macOS version stores notifications differently.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastID)

        var results: [MirroredNotification] = []
        var newest = lastID
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            newest = max(newest, id)
            let appColumn = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            guard let blob = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
            if let notification = Self.parse(data, id: id, fallbackBundle: appColumn) {
                results.append(notification)
            }
        }
        self.lastID = newest
        return .notifications(results)
    }

    private func queryMaxID(_ database: OpaquePointer) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    /// Each record is a binary plist: {app, req: {titl, subt, body}, …}.
    private static func parse(_ data: Data, id: Int64, fallbackBundle: String) -> MirroredNotification? {
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        guard !(title.isEmpty && body.isEmpty) else { return nil }
        return MirroredNotification(
            id: id,
            bundleIdentifier: plist["app"] as? String ?? fallbackBundle,
            title: title,
            subtitle: subtitle,
            body: body
        )
    }
}
