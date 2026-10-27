import Foundation

/// Whether a Focus (Do Not Disturb, Work, Sleep…) is on, read from macOS's Focus database.
/// Like the notification database it needs Full Disk Access; without it Focus is simply reported as off.
final class FocusMonitor: ObservableObject {
    @Published private(set) var isActive = false
    /// The Focus's own name, e.g. "Do Not Disturb", "Work".
    @Published private(set) var modeName: String?

    /// Called on the main queue when Focus turns on or off (not for the state found at launch).
    var onChange: ((Bool, String?) -> Void)?

    private let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingRefresh: DispatchWorkItem?

    init() {
        refresh(notify: false)
        watchDirectory()
        // Scheduled Focus starts without touching the files, and the watcher needs access to start; poll as a backstop.
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.watcher == nil { self.watchDirectory() }
            self.refresh(notify: true)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// macOS rewrites Assertions.json the moment a Focus is switched, so react to the folder changing
    /// instead of polling; even a Focus that is on for only a second gets noticed.
    private func watchDirectory() {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return } // no Full Disk Access yet
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRefresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(notify: true) }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func refresh(notify: Bool) {
        let modes = modeConfigurations()
        var activeID = manualMode()
        if activeID == nil {
            activeID = modes.first { Self.isScheduledNow($0.value) }?.key
        }
        let name = activeID.map { id -> String in
            ((modes[id] as? [String: Any])?["mode"] as? [String: Any])?["name"] as? String ?? "Focus"
        }
        let active = activeID != nil
        guard active != isActive || name != modeName else { return }
        isActive = active
        modeName = name
        NSLog("%@", "Islet focus [change] active=\(active) name=\(name ?? "-")")
        if notify { onChange?(active, name) }
    }

    /// Logs the raw Focus files, for checking the format on a new macOS version (`--debug-focus`).
    func dumpForDebugging() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        NSLog("%@", "Islet focus [files] \(files.sorted())")
        for file in ["Assertions.json", "ModeConfigurations.json"] {
            // Shape first (keys and list sizes), then the tail where the newest records end up.
            if let root = json(file), let data = (root["data"] as? [[String: Any]]) {
                let shape = data.map { $0.map { "\($0.key)=\(($0.value as? [Any])?.count.description ?? "obj")" }.sorted() }
                NSLog("%@", "Islet focus [\(file) shape] \(shape)")
            }
            let text = (try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)) ?? "(unreadable)"
            NSLog("%@", "Islet focus [\(file) tail] \(text.suffix(1500))")
        }
        NSLog("%@", "Islet focus [state] active=\(isActive) name=\(modeName ?? "-")")
    }

    // MARK: Reading the database

    private func json(_ file: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// A Focus turned on by hand (Control Center, a Shortcut, another device) shows up as an assertion record.
    private func manualMode() -> String? {
        guard let data = (json("Assertions.json")?["data"] as? [[String: Any]])?.first,
              let records = data["storeAssertionRecords"] as? [[String: Any]], let record = records.first else { return nil }
        let details = record["assertionDetails"] as? [String: Any]
        return details?["assertionDetailsModeIdentifier"] as? String ?? "com.apple.donotdisturb.mode.default"
    }

    private func modeConfigurations() -> [String: Any] {
        let data = (json("ModeConfigurations.json")?["data"] as? [[String: Any]])?.first
        return data?["modeConfigurations"] as? [String: Any] ?? [:]
    }

    /// A Focus that turns on by schedule has no record while it runs, so check its time triggers ourselves.
    private static func isScheduledNow(_ config: Any) -> Bool {
        guard let triggers = ((config as? [String: Any])?["triggers"] as? [String: Any])?["triggers"] as? [[String: Any]] else {
            return false
        }
        let now = Calendar.current.dateComponents([.weekday, .hour, .minute], from: Date())
        let minute = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        for trigger in triggers {
            guard (trigger["class"] as? String)?.contains("Schedule") == true,
                  (trigger["enabledSetting"] as? Int) == 2,
                  let startHour = trigger["timePeriodStartTimeHour"] as? Int,
                  let endHour = trigger["timePeriodEndTimeHour"] as? Int else { continue }
            let start = startHour * 60 + (trigger["timePeriodStartTimeMinute"] as? Int ?? 0)
            let end = endHour * 60 + (trigger["timePeriodEndTimeMinute"] as? Int ?? 0)
            // Weekday bit mask; Sunday is the lowest bit. Missing means every day.
            if let mask = trigger["timePeriodWeekdays"] as? Int, let weekday = now.weekday,
               mask & (1 << (weekday - 1)) == 0 { continue }
            let inside = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
            if inside { return true }
        }
        return false
    }
}
