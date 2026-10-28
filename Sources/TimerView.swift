import SwiftUI

/// Timers, Pomodoro and stopwatch, picked with small tabs at the top.
struct TimerView: View {
    @ObservedObject var timer: TimerManager
    @AppStorage("timerMode") private var mode = "timers"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                modeButton("timers", tr("ตัวจับเวลา", "Timers"), "timer")
                modeButton("pomodoro", "Pomodoro", "leaf.fill")
                modeButton("stopwatch", tr("จับเวลา", "Stopwatch"), "stopwatch")
            }
            Group {
                switch mode {
                case "pomodoro": PomodoroPane(timer: timer)
                case "stopwatch": StopwatchPane(timer: timer)
                default: CountdownsPane(timer: timer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private func modeButton(_ id: String, _ title: String, _ symbol: String) -> some View {
        let selected = mode == id
        return Button { mode = id } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 0.95 : 0.45))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A ring that empties as time runs out.
struct TimeRing: View {
    let progress: Double
    var color: Color = .orange
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

// MARK: - Countdowns

private struct CountdownsPane: View {
    @ObservedObject var timer: TimerManager
    @State private var custom = 5

    /// Quick starts with a name, for everyday things.
    private static var everyday: [(String, Double)] { [
        (tr("☕ ชงกาแฟ", "☕ Coffee"), 4), (tr("🍜 บะหมี่", "🍜 Noodles"), 3),
        (tr("🧘 พักสายตา", "🧘 Eye break"), 1), (tr("🧺 ซักผ้า", "🧺 Laundry"), 45),
    ] }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            list.frame(maxWidth: .infinity)
            starters.frame(width: 250)
        }
    }

    @ViewBuilder private var list: some View {
        if timer.countdowns.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "timer").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3))
                Text(tr("ยังไม่มีตัวจับเวลา เลือกทางขวาเพื่อเริ่ม", "No timers yet. Start one on the right."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(timer.countdowns) { c in CountdownRow(timer: timer, countdown: c) }
                }
            }
        }
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(tr("นาที", "min")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                ForEach([1, 3, 5, 10, 15, 30], id: \.self) { m in
                    Button("\(m)") { timer.startCountdown(minutes: Double(m)) }
                        .buttonStyle(PillButtonStyle())
                        .fixedSize()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], alignment: .leading, spacing: 5) {
                ForEach(Self.everyday, id: \.0) { name, minutes in
                    Button("\(name) · \(Int(minutes))") { timer.startCountdown(minutes: minutes, name: name) }
                        .buttonStyle(PillButtonStyle())
                        .lineLimit(1)
                        .fixedSize()
                        .help(TimerManager.describe(minutes * 60))
                }
            }
            HStack(spacing: 8) {
                ControlButton(symbol: "minus", size: 11) { custom = max(1, custom - (custom > 10 ? 5 : 1)) }
                Text(tr("\(custom) นาที", "\(custom) min"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 54)
                ControlButton(symbol: "plus", size: 11) { custom = min(600, custom + (custom >= 10 ? 5 : 1)) }
                Button(tr("เริ่ม", "Start")) { timer.startCountdown(minutes: Double(custom)) }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }
}

private struct CountdownRow: View {
    @ObservedObject var timer: TimerManager
    let countdown: TimerManager.Countdown

    var body: some View {
        HStack(spacing: 10) {
            TimeRing(progress: countdown.finished ? 1 : countdown.progress(), color: color, lineWidth: 3.5)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(countdown.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Text(countdown.finished ? tr("ครบเวลาแล้ว", "Done") : TimerManager.format(countdown.remaining()))
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(countdown.finished ? .green : .white)
            }
            Spacer(minLength: 4)
            if !countdown.finished {
                small("plus") { timer.add(minutes: 1, to: countdown.id) }.help(tr("เพิ่ม 1 นาที", "Add a minute"))
            }
            small(countdown.isRunning ? "pause.fill" : countdown.finished ? "arrow.counterclockwise" : "play.fill") {
                timer.toggle(countdown.id)
            }
            small("xmark") { timer.remove(countdown.id) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var color: Color {
        countdown.finished ? .green : countdown.isRunning ? .orange : .orange.opacity(0.45)
    }

    private func small(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pomodoro

private struct PomodoroPane: View {
    @ObservedObject var timer: TimerManager

    var body: some View {
        HStack(spacing: 26) {
            ZStack {
                TimeRing(progress: timer.pomodoro?.clock.progress() ?? 1, color: ringColor, lineWidth: 7)
                VStack(spacing: 1) {
                    Text(timer.pomodoro.map { TimerManager.format($0.clock.remaining()) } ?? TimerManager.format(TimeInterval(timer.focusMinutes * 60)))
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(timer.pomodoro?.phase.title ?? tr("พร้อมโฟกัส", "Ready"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ringColor)
                }
            }
            .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 12) {
                rounds
                HStack(spacing: 16) {
                    ControlButton(symbol: timer.pomodoro?.clock.isRunning == true ? "pause.fill" : "play.fill", size: 22) {
                        timer.togglePomodoro()
                    }
                    if timer.pomodoro != nil {
                        ControlButton(symbol: "forward.end.fill", size: 14) { timer.skipPomodoroPhase() }
                            .help(tr("ข้ามไปช่วงถัดไป", "Skip to the next phase"))
                        ControlButton(symbol: "stop.fill", size: 14) { timer.stopPomodoro() }
                            .help(tr("หยุด Pomodoro", "Stop the Pomodoro"))
                    }
                }
                if timer.pomodoro == nil {
                    HStack(spacing: 5) {
                        Text(tr("โฟกัส", "Focus")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        ForEach([15, 25, 50], id: \.self) { m in
                            Button(tr("\(m) น.", "\(m)m")) { timer.focusMinutes = m }
                                .buttonStyle(PillButtonStyle())
                                .opacity(timer.focusMinutes == m ? 1 : 0.5)
                        }
                    }
                    Text(tr("พัก \(TimerManager.breakMinutes) นาทีทุกรอบ และพักยาว \(TimerManager.longBreakMinutes) นาทีทุก \(TimerManager.roundsBeforeLongBreak) รอบ",
                            "\(TimerManager.breakMinutes) min break each round, \(TimerManager.longBreakMinutes) min every \(TimerManager.roundsBeforeLongBreak)"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 🍅 for each finished focus session in this set of four.
    private var rounds: some View {
        let done = (timer.pomodoro?.completed ?? 0) % TimerManager.roundsBeforeLongBreak
        let inFocus = timer.pomodoro?.phase == .focus
        return HStack(spacing: 6) {
            ForEach(0..<TimerManager.roundsBeforeLongBreak, id: \.self) { i in
                Circle()
                    .fill(i < done ? Color.red : i == done && inFocus ? Color.red.opacity(0.45) : Color.white.opacity(0.15))
                    .frame(width: 10, height: 10)
            }
            if let p = timer.pomodoro {
                Text(tr("เสร็จแล้ว \(p.completed) รอบ", "\(p.completed) done"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var ringColor: Color {
        switch timer.pomodoro?.phase {
        case .focus: return .red
        case .shortBreak, .longBreak: return .green
        case nil: return .white.opacity(0.5)
        }
    }
}

// MARK: - Stopwatch

private struct StopwatchPane: View {
    @ObservedObject var timer: TimerManager

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                    Text(TimerManager.formatPrecise(timer.stopwatchElapsed(at: ctx.date)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                }
                HStack(spacing: 16) {
                    ControlButton(symbol: timer.stopwatchRunning ? "pause.fill" : "play.fill", size: 22) { timer.toggleStopwatch() }
                    ControlButton(symbol: "flag.fill", size: 14) { timer.lap() }
                        .help(tr("บันทึกรอบ", "Lap"))
                        .disabled(!timer.stopwatchRunning)
                    ControlButton(symbol: "arrow.counterclockwise", size: 14) { timer.resetStopwatch() }
                        .help(tr("เริ่มใหม่", "Reset"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(Array(timer.laps.enumerated()), id: \.offset) { i, lap in
                        HStack {
                            Text(tr("รอบ \(timer.laps.count - i)", "Lap \(timer.laps.count - i)"))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text(TimerManager.formatPrecise(lap))
                        }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                }
            }
            .frame(width: 170)
            .opacity(timer.laps.isEmpty ? 0 : 1)
        }
    }
}
