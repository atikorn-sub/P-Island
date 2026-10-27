import Foundation
import SQLite3

/// Replies to the most recent incoming iMessage/SMS chat.
/// Finds the chat in Messages' own database (needs Full Disk Access) and sends through
/// Messages' AppleScript (asks for the Automation permission the first time).
enum MessagesReplier {
    static let bundleID = "com.apple.MobileSMS"

    private static let queue = DispatchQueue(label: "islet.messages")
    private static let dbPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db").path

    /// Sends `text` to the chat the latest incoming message came from. Completion gets an error message, or nil on success.
    static func replyToLatest(_ text: String, completion: @escaping (String?) -> Void) {
        queue.async {
            let error: String?
            if let guid = latestIncomingChatGUID() {
                error = send(text, toChat: guid)
            } else {
                error = "หาแชตล่าสุดไม่เจอ (ต้องให้สิทธิ์ Full Disk Access)"
            }
            DispatchQueue.main.async { completion(error) }
        }
    }

    private static func latestIncomingChatGUID() -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        let sql = """
            SELECT c.guid FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            JOIN chat c ON c.ROWID = cmj.chat_id
            WHERE m.is_from_me = 0 ORDER BY m.date DESC LIMIT 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }

    private static func send(_ text: String, toChat guid: String) -> String? {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "tell application \"Messages\" to send \(quoted(text)) to chat id \(quoted(guid))"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        if error[NSAppleScript.errorNumber] as? Int == -1743 {
            return "ต้องอนุญาตให้ P Island ควบคุม Messages ก่อน"
        }
        return error[NSAppleScript.errorMessage] as? String ?? "ส่งไม่สำเร็จ"
    }
}
