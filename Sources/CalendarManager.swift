import AppKit
import EventKit

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    /// Zoom / Google Meet / Teams / FaceTime / Webex link found in the event, if any.
    let meetingURL: URL?
}

/// An unfinished reminder from the Reminders app.
struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    /// The due date has a time, not just a day.
    let hasTime: Bool
    let color: NSColor
    let overdue: Bool
}

final class CalendarManager: ObservableObject {
    enum Status { case notDetermined, denied, authorized }

    @Published private(set) var status: Status
    /// Remaining events today (Home tab).
    @Published private(set) var events: [CalendarEvent] = []
    /// Month shown in the Calendar tab, as its first day.
    @Published private(set) var month: Date
    @Published var selectedDay: Date {
        didSet {
            selectedEvents = events(on: selectedDay)
            reloadReminders()
            // Stepping past the month's edge turns the month too.
            let cal = Calendar.current
            if !cal.isDate(selectedDay, equalTo: month, toGranularity: .month),
               let first = cal.date(from: cal.dateComponents([.year, .month], from: selectedDay)) {
                month = first
                reloadMonth()
            }
        }
    }
    @Published private(set) var selectedEvents: [CalendarEvent] = []
    /// Day-of-month numbers in `month` that have events.
    @Published private(set) var busyDays: Set<Int> = []

    /// Reminders access, and the unfinished ones for the selected day (today: also overdue and undated).
    @Published private(set) var remindersStatus: Status
    @Published private(set) var reminders: [ReminderItem] = []

    /// The next timed event starting within 10 minutes (or begun in the last minute), for the notch's wings.
    @Published private(set) var upcoming: CalendarEvent?

    /// Called once per meeting, about a minute before it starts.
    var onMeetingSoon: ((CalendarEvent) -> Void)?

    private let store = EKEventStore()
    private var alertedMeetings: Set<String> = []
    private var meetingTimer: Timer?

    init() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        month = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        selectedDay = today
        status = Self.currentStatus()
        remindersStatus = Self.remindersStatus()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        reload()
        reloadReminders()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.checkMeetings() }
        RunLoop.main.add(timer, forMode: .common)
        meetingTimer = timer
    }

    private static func currentStatus() -> Status {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private static func remindersStatus() -> Status {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestRemindersAccess() {
        NSApp.activate(ignoringOtherApps: true)
        store.requestFullAccessToReminders { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.remindersStatus = Self.remindersStatus()
                self?.reloadReminders()
            }
        }
    }

    func openRemindersPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Moves the selected day by `days` (the arrows beside the day's title).
    func step(days: Int) {
        if let day = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) { selectedDay = day }
    }

    func goToToday() {
        selectedDay = Calendar.current.startOfDay(for: Date())
    }

    // MARK: Reminders

    func reloadReminders() {
        remindersStatus = Self.remindersStatus()
        guard remindersStatus == .authorized else {
            if !reminders.isEmpty { reminders = [] }
            return
        }
        let cal = Calendar.current
        let day = cal.startOfDay(for: selectedDay)
        let isToday = cal.isDateInToday(day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { return }
        let now = Date()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] found in
            let items: [ReminderItem] = (found ?? []).compactMap { r in
                let due = r.dueDateComponents.flatMap { cal.date(from: $0) }
                // Today shows what's due today, anything overdue, and things with no date; other days, what's due then.
                if let due {
                    guard isToday ? due < dayEnd : (due >= day && due < dayEnd) else { return nil }
                } else if !isToday {
                    return nil
                }
                let hasTime = r.dueDateComponents?.hour != nil
                let overdue = due.map { hasTime ? $0 < now : $0 < cal.startOfDay(for: now) } ?? false
                return ReminderItem(id: r.calendarItemIdentifier, title: r.title ?? "", due: due, hasTime: hasTime,
                                    color: r.calendar?.color ?? .systemOrange, overdue: overdue)
            }
            // Dated first (soonest first), then undated by title.
            .sorted { a, b in
                switch (a.due, b.due) {
                case let (x?, y?): return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.title.localizedCompare(b.title) == .orderedAscending
                }
            }
            NSLog("%@", "Islet reminders: \(found?.count ?? 0) unfinished, \(items.count) for \(isToday ? "today" : "the selected day")")
            DispatchQueue.main.async {
                guard let self, cal.isDate(self.selectedDay, inSameDayAs: day) else { return }
                if self.reminders != items { self.reminders = items }
            }
        }
    }

    /// Ticks the reminder off in the Reminders app.
    func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminders.removeAll { $0.id == item.id }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            NSLog("%@", "Islet reminders: couldn't complete '\(item.title)': \(error)")
            reloadReminders()
        }
    }

    func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = Self.currentStatus()
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func showMonth(offset: Int) {
        let cal = Calendar.current
        guard let new = cal.date(byAdding: .month, value: offset, to: month) else { return }
        month = new
        reloadMonth()
    }

    func reload() {
        guard status == .authorized else { return }
        let now = Date()
        let cal = Calendar.current
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return }
        events = fetch(from: now, to: endOfDay)
        selectedEvents = events(on: selectedDay)
        reloadMonth()
        reloadReminders()
        updateUpcoming()
    }

    func events(on day: Date) -> [CalendarEvent] {
        guard status == .authorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return fetch(from: start, to: end)
    }

    private func reloadMonth() {
        guard status == .authorized else { return }
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .month, value: 1, to: month) else { return }
        var days = Set<Int>()
        for event in fetch(from: month, to: end) {
            var day = cal.startOfDay(for: max(event.start, month))
            let last = min(event.end, end)
            while day < last {
                days.insert(cal.component(.day, from: day))
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        busyDays = days
    }

    private func fetch(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map {
                CalendarEvent(id: $0.calendarItemIdentifier + "\($0.startDate.timeIntervalSince1970)",
                              title: $0.title ?? "",
                              start: $0.startDate, end: $0.endDate,
                              isAllDay: $0.isAllDay,
                              color: $0.calendar.color ?? .systemBlue,
                              meetingURL: Self.meetingURL(in: $0))
            }
    }

    // MARK: Meetings

    private static let meetingPattern = try! NSRegularExpression(
        pattern: #"https://[A-Za-z0-9.-]*(zoom\.us/(j|my|w)/|meet\.google\.com/|teams\.microsoft\.com/l/meetup-join/|teams\.live\.com/meet/|facetime\.apple\.com/join|[A-Za-z0-9-]+\.webex\.com/)[^\s<>"')]*"#,
        options: [.caseInsensitive])

    private static func meetingURL(in event: EKEvent) -> URL? {
        let fields = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in fields {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingPattern.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }

    private var demoUntil: Date?

    /// `--demo-countdown`: a made-up meeting 7 minutes away, for a minute.
    func demoUpcoming() {
        demoUntil = Date().addingTimeInterval(60)
        upcoming = CalendarEvent(id: "demo", title: tr("ประชุมทีม (ตัวอย่าง)", "Team meeting (sample)"),
                                 start: Date().addingTimeInterval(7 * 60), end: Date().addingTimeInterval(37 * 60),
                                 isAllDay: false, color: .systemBlue, meetingURL: URL(string: "https://meet.google.com/"))
    }

    /// Ends the demo meeting early.
    func endDemo() {
        demoUntil = nil
        upcoming = nil
        updateUpcoming()
    }

    private func updateUpcoming() {
        if let until = demoUntil, until > Date() { return }
        guard status == .authorized else { return }
        let now = Date()
        let next = fetch(from: now.addingTimeInterval(-60), to: now.addingTimeInterval(10 * 60))
            .first { !$0.isAllDay && $0.start > now.addingTimeInterval(-60) }
        if next?.id != upcoming?.id || (next == nil) != (upcoming == nil) { upcoming = next }
    }

    private func checkMeetings() {
        updateUpcoming()
        guard status == .authorized else { return }
        let now = Date()
        for event in fetch(from: now.addingTimeInterval(-60), to: now.addingTimeInterval(90)) {
            guard event.meetingURL != nil, !event.isAllDay, !alertedMeetings.contains(event.id) else { continue }
            let lead = event.start.timeIntervalSince(now)
            guard lead <= 75, lead >= -60 else { continue }
            alertedMeetings.insert(event.id)
            onMeetingSoon?(event)
        }
    }
}
