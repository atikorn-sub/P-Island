import AppKit

final class TimerManager: ObservableObject {
    enum Phase { case idle, running, paused, finished }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var duration: TimeInterval = 5 * 60
    @Published private(set) var remaining: TimeInterval = 5 * 60

    var onFinish: (() -> Void)?

    private var endDate: Date?
    private var ticker: Timer?

    var isActive: Bool { phase == .running || phase == .paused }
    var progress: Double { duration > 0 ? remaining / duration : 0 }

    func setMinutes(_ minutes: Int) {
        setDuration(TimeInterval(minutes * 60))
    }

    func setDuration(_ seconds: TimeInterval) {
        stopTicker()
        duration = seconds
        remaining = duration
        phase = .idle
    }

    func toggle() {
        phase == .running ? pause() : start()
    }

    func start() {
        if remaining <= 0 { remaining = duration }
        guard remaining > 0 else { return }
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard phase == .running, let endDate else { return }
        stopTicker()
        remaining = max(0, endDate.timeIntervalSinceNow)
        phase = .paused
    }

    func reset() {
        stopTicker()
        remaining = duration
        phase = .idle
    }

    func adjust(minutes: Int) {
        let delta = TimeInterval(minutes * 60)
        switch phase {
        case .running:
            guard let endDate else { return }
            let newRemaining = max(1, endDate.timeIntervalSinceNow + delta)
            self.endDate = Date().addingTimeInterval(newRemaining)
            duration = max(duration + delta, newRemaining)
            remaining = newRemaining
        case .paused:
            remaining = max(1, remaining + delta)
            duration = max(duration + delta, remaining)
        case .idle, .finished:
            duration = max(60, duration + delta)
            remaining = duration
            phase = .idle
        }
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            stopTicker()
            phase = .finished
            NSSound(named: "Glass")?.play()
            onFinish?()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
