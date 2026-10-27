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

    init() {
        refresh(notify: false)
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh(notify: true) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        if notify { onChange?(active, name) }
    }

    /// Logs the raw Focus files, for checking the format on a new macOS version (`--debug-focus`).
    func dumpForDebugging() {
        for file in ["Assertions.json", "ModeConfigurations.json"] {
            let text = (try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)) ?? "(unreadable)"
            NSLog("%@", "Islet focus [\(file)] \(text.prefix(3000))")
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
