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

final class CalendarManager: ObservableObject {
    enum Status { case notDetermined, denied, authorized }

    @Published private(set) var status: Status
    /// Remaining events today (Home tab).
    @Published private(set) var events: [CalendarEvent] = []
    /// Month shown in the Calendar tab, as its first day.
    @Published private(set) var month: Date
    @Published var selectedDay: Date {
        didSet { selectedEvents = events(on: selectedDay) }
    }
    @Published private(set) var selectedEvents: [CalendarEvent] = []
    /// Day-of-month numbers in `month` that have events.
    @Published private(set) var busyDays: Set<Int> = []

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
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        reload()
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

    private func checkMeetings() {
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
