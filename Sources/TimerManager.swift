import AppKit

/// Countdowns (as many as you like, side by side), a Pomodoro cycle and a stopwatch.
final class TimerManager: ObservableObject {
    struct Countdown: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var duration: TimeInterval
        /// Set while running.
        var endDate: Date?
        /// Time left while paused (or when finished: 0).
        var pausedRemaining: TimeInterval
        var finished = false

        var isRunning: Bool { endDate != nil }

        func remaining(at date: Date = Date()) -> TimeInterval {
            endDate.map { max(0, $0.timeIntervalSince(date)) } ?? pausedRemaining
        }

        func progress(at date: Date = Date()) -> Double {
            duration > 0 ? remaining(at: date) / duration : 0
        }
    }

    enum PomodoroPhase: Equatable {
        case focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .focus: return tr("โฟกัส", "Focus")
            case .shortBreak: return tr("พักสั้น", "Short break")
            case .longBreak: return tr("พักยาว", "Long break")
            }
        }
    }

    // MARK: State

    @Published private(set) var countdowns: [Countdown] = []

    /// The running Pomodoro, if any: its phase, how many focus sessions are done, and its clock.
    @Published private(set) var pomodoro: (phase: PomodoroPhase, completed: Int, clock: Countdown)?
    @Published var focusMinutes = UserDefaults.standard.object(forKey: "pomodoro.focus") as? Int ?? 25 {
        didSet { UserDefaults.standard.set(focusMinutes, forKey: "pomodoro.focus") }
    }
    static let breakMinutes = 5, longBreakMinutes = 15, roundsBeforeLongBreak = 4

    @Published private(set) var stopwatchStart: Date?
    @Published private(set) var stopwatchBanked: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []

    /// A countdown or Pomodoro phase ran out: (title, what's next).
    var onFinish: ((String, String) -> Void)?

    private var ticker: Timer?

    // MARK: Summary for the closed notch

    /// Anything to show on the notch's wings.
    var isActive: Bool { primary != nil }

    /// What the wings show: the Pomodoro, else the countdown ending soonest, else the stopwatch.
    enum Primary { case countdown(Countdown, PomodoroPhase?), stopwatch }

    var primary: Primary? {
        if let p = pomodoro { return .countdown(p.clock, p.phase) }
        let live = countdowns.filter { !$0.finished }
        if let next = live.filter(\.isRunning).min(by: { $0.remaining() < $1.remaining() }) ?? live.first {
            return .countdown(next, nil)
        }
        if stopwatchStart != nil || stopwatchBanked > 0 { return .stopwatch }
        return nil
    }

    var remaining: TimeInterval {
        switch primary {
        case .countdown(let c, _): return c.remaining()
        case .stopwatch: return stopwatchElapsed()
        case nil: return 0
        }
    }

    // MARK: Countdowns

    func startCountdown(minutes: Double, name: String? = nil) {
        startCountdown(seconds: minutes * 60, name: name)
    }

    func startCountdown(seconds: TimeInterval, name: String? = nil) {
        guard seconds > 0 else { return }
        let label = name ?? tr("ตัวจับเวลา \(Self.describe(seconds))", "\(Self.describe(seconds)) timer")
        countdowns.append(Countdown(name: label, duration: seconds, endDate: Date().addingTimeInterval(seconds), pausedRemaining: seconds))
        startTicker()
    }

    func toggle(_ id: Countdown.ID) {
        update(id) { c in
            if let end = c.endDate {
                c.pausedRemaining = max(0, end.timeIntervalSinceNow)
                c.endDate = nil
            } else if c.finished {
                c.finished = false
                c.endDate = Date().addingTimeInterval(c.duration)
            } else {
                c.endDate = Date().addingTimeInterval(c.pausedRemaining)
            }
        }
        startTicker()
    }

    func add(minutes: Int, to id: Countdown.ID) {
        let delta = TimeInterval(minutes * 60)
        update(id) { c in
            if let end = c.endDate {
                let left = max(1, end.timeIntervalSinceNow + delta)
                c.endDate = Date().addingTimeInterval(left)
                c.duration = max(c.duration + delta, left)
            } else {
                c.pausedRemaining = max(1, c.pausedRemaining + delta)
                c.duration = max(c.duration + delta, c.pausedRemaining)
                c.finished = false
            }
        }
        startTicker()
    }

    func remove(_ id: Countdown.ID) {
        countdowns.removeAll { $0.id == id }
    }

    private func update(_ id: Countdown.ID, _ change: (inout Countdown) -> Void) {
        guard let i = countdowns.firstIndex(where: { $0.id == id }) else { return }
        change(&countdowns[i])
    }

    // MARK: Pomodoro

    func startPomodoro() {
        pomodoro = (.focus, 0, Self.clock(minutes: focusMinutes))
        startTicker()
    }

    func togglePomodoro() {
        guard var p = pomodoro else { return startPomodoro() }
        if let end = p.clock.endDate {
            p.clock.pausedRemaining = max(0, end.timeIntervalSinceNow)
            p.clock.endDate = nil
        } else {
            p.clock.endDate = Date().addingTimeInterval(p.clock.pausedRemaining)
        }
        pomodoro = p
        startTicker()
    }

    /// Ends this phase now and moves on to the next.
    func skipPomodoroPhase() {
        advancePomodoro(announce: false)
    }

    func stopPomodoro() {
        pomodoro = nil
    }

    private func advancePomodoro(announce: Bool) {
        guard let p = pomodoro else { return }
        let next: (PomodoroPhase, Int)
        if p.phase == .focus {
            let done = p.completed + 1
            next = (done % Self.roundsBeforeLongBreak == 0 ? .longBreak : .shortBreak, done)
        } else {
            next = (.focus, p.completed)
        }
        let minutes = next.0 == .focus ? focusMinutes : next.0 == .shortBreak ? Self.breakMinutes : Self.longBreakMinutes
        pomodoro = (next.0, next.1, Self.clock(minutes: minutes))
        if announce {
            let title = p.phase == .focus ? tr("โฟกัสครบแล้ว 🍅", "Focus session done 🍅") : tr("หมดเวลาพัก", "Break's over")
            let detail = next.0 == .focus
                ? tr("เริ่มโฟกัสรอบที่ \(next.1 % Self.roundsBeforeLongBreak + 1) — \(minutes) นาที", "Focus round \(next.1 % Self.roundsBeforeLongBreak + 1) — \(minutes) min")
                : tr("\(next.0.title) \(minutes) นาที ลุกยืดเส้นหน่อย", "\(next.0.title), \(minutes) min — stretch a little")
            onFinish?(title, detail)
        }
    }

    private static func clock(minutes: Int) -> Countdown {
        let s = TimeInterval(minutes * 60)
        return Countdown(name: "", duration: s, endDate: Date().addingTimeInterval(s), pausedRemaining: s)
    }

    // MARK: Stopwatch

    var stopwatchRunning: Bool { stopwatchStart != nil }

    func stopwatchElapsed(at date: Date = Date()) -> TimeInterval {
        stopwatchBanked + (stopwatchStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleStopwatch() {
        if let start = stopwatchStart {
            stopwatchBanked += Date().timeIntervalSince(start)
            stopwatchStart = nil
        } else {
            stopwatchStart = Date()
            startTicker()
        }
    }

    func lap() {
        guard stopwatchRunning else { return }
        laps.insert(stopwatchElapsed(), at: 0)
    }

    func resetStopwatch() {
        stopwatchStart = nil
        stopwatchBanked = 0
        laps = []
    }

    // MARK: Ticking

    /// Ticks four times a second while anything runs, and stops by itself when nothing does.
    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        let now = Date()
        for i in countdowns.indices where countdowns[i].isRunning && countdowns[i].remaining(at: now) <= 0 {
            countdowns[i].endDate = nil
            countdowns[i].pausedRemaining = 0
            countdowns[i].finished = true
            NSSound(named: "Glass")?.play()
            onFinish?(tr("ครบเวลา", "Time's up"), countdowns[i].name)
        }
        if let p = pomodoro, p.clock.isRunning, p.clock.remaining(at: now) <= 0 {
            NSSound(named: p.phase == .focus ? "Hero" : "Glass")?.play()
            advancePomodoro(announce: true)
        }
        let running = countdowns.contains(where: \.isRunning) || pomodoro?.clock.isRunning == true || stopwatchRunning
        if !running {
            ticker?.invalidate()
            ticker = nil
        }
        objectWillChange.send()
    }

    // MARK: Formatting

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Stopwatch style, with hundredths: 1:02.34
    static func formatPrecise(_ t: TimeInterval) -> String {
        let cs = Int((t * 100).rounded(.down))
        let s = cs / 100
        if s >= 3600 { return String(format: "%d:%02d:%02d.%02d", s / 3600, s / 60 % 60, s % 60, cs % 100) }
        return String(format: "%d:%02d.%02d", s / 60, s % 60, cs % 100)
    }

    /// "5 นาที", "90 วินาที", "1 ชม. 30 นาที"
    static func describe(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return tr("\(s) วินาที", "\(s) sec") }
        let h = s / 3600, m = s / 60 % 60
        if h == 0, s % 60 != 0 { return tr("\(m) นาที \(s % 60) วินาที", "\(m) min \(s % 60) sec") }
        if h > 0 { return m > 0 ? tr("\(h) ชม. \(m) นาที", "\(h) h \(m) min") : tr("\(h) ชม.", "\(h) h") }
        return tr("\(m) นาที", "\(m) min")
    }
}
