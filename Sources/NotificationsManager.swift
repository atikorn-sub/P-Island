import AppKit
import SQLite3

struct AppNotification: Equatable {
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
}

/// Mirrors new Notification Center banners into the notch by reading macOS's notification database
/// (read-only). Needs Full Disk Access, which only the user can grant in System Settings.
final class NotificationsManager: ObservableObject {
    enum Access { case unknown, granted, needsFullDiskAccess }

    @Published private(set) var access: Access = .unknown

    var onNotification: ((AppNotification) -> Void)?
    var isEnabled: () -> Bool = { true }

    private var db: OpaquePointer?
    private var lastRecordID: Int64 = -1
    private var timer: Timer?
    private var deniedTicks = 0
    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""

    static let databasePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path

    init() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openIfNeeded() -> Bool {
        if db != nil { return true }
        // Without access every attempt is logged by the system, so only retry every 10 s until granted.
        if access == .needsFullDiskAccess {
            deniedTicks += 1
            guard deniedTicks % 5 == 0 else { return false }
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(Self.databasePath, &handle, flags, nil) == SQLITE_OK,
              sqlite3_exec(handle, "SELECT 1 FROM record LIMIT 1", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            if access != .needsFullDiskAccess { access = .needsFullDiskAccess }
            return false
        }
        db = handle
        if access != .granted { access = .granted }
        return true
    }

    private func poll() {
        guard isEnabled(), openIfNeeded() else { return }
        if lastRecordID < 0 {
            // Start from now: don't replay notifications that arrived before launch.
            lastRecordID = scalar("SELECT IFNULL(MAX(rec_id), 0) FROM record") ?? 0
            return
        }
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            reset()
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, lastRecordID)
        var found: [AppNotification] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            lastRecordID = sqlite3_column_int64(stmt, 0)
            guard let idText = sqlite3_column_text(stmt, 1) else { continue }
            let bundleID = String(cString: idText)
            guard bundleID != ownBundleID, let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 2)))
            let delivered = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 3))
            if let note = Self.parse(data, bundleID: bundleID, date: delivered) { found.append(note) }
        }
        // Only the newest one is shown, so a burst doesn't queue up a stream of cards.
        if let latest = found.last { onNotification?(latest) }
    }

    private static func parse(_ data: Data, bundleID: String, date: Date) -> AppNotification? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let req = plist["req"] as? [String: Any] else { return nil }
        let title = req["titl"] as? String ?? ""
        let subtitle = req["subt"] as? String ?? ""
        let body = req["body"] as? String ?? ""
        guard !(title.isEmpty && body.isEmpty) else { return nil }
        return AppNotification(bundleID: bundleID, title: title, subtitle: subtitle, body: body, date: date)
    }

    private func scalar(_ sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    private func reset() {
        sqlite3_close(db)
        db = nil
    }
}
