import SwiftUI

extension Locale {
    /// The app speaks Thai: Thai month and weekday names, 24-hour time and the Buddhist year.
    static let thai = Locale(identifier: "th_TH")
}

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var music: MusicManager
    @ObservedObject private var timer: TimerManager
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var downloads: DownloadMonitor
    @ObservedObject private var calendar: CalendarManager

    init(state: NotchState) {
        self.state = state
        music = state.music
        timer = state.timer
        settings = state.settings
        downloads = state.downloads
        calendar = state.calendar
    }

    var body: some View {
        let open = state.isOpen
        let activity = state.closedActivity
        let alerting = !open && { if case .alert = activity { return true } else { return false } }()
        let size = open ? state.openSize : state.closedSize
        let shape = NotchShape(topRadius: open ? NotchState.openTopRadius : NotchState.closedTopRadius,
                               bottomRadius: open ? 30 * state.scale : alerting ? 24 * state.scale : 10)
        ZStack(alignment: .top) {
            if open {
                OpenNotchView(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.82, anchor: .top)))
            } else if case .alert(let alert) = activity {
                AlertNotchView(state: state, alert: alert)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
            } else if activity == .miniPlayer {
                MiniPlayerBar(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else {
                ClosedNotchView(state: state)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            // Ambient light from the cover, on the black look only (glass already shows what's behind).
            if open && settings.notchStyle != "glass" && settings.ambientGlow && music.hasTrack {
                AmbientGlow(music: music)
            }
        }
        .background(NotchBackground(shape: shape,
                                    glass: settings.notchStyle == "glass" && (open || alerting),
                                    notchSize: state.notchSize, hasNotch: state.hasNotch,
                                    tint: settings.glassTint))
        .clipShape(shape)
        .shadow(color: .black.opacity(open || alerting ? 0.5 : 0), radius: 16, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Opening overshoots a little and wobbles into place, like jelly; closing tucks back in
        // with only a hint of bounce so the panel never looks smaller than the notch.
        .animation(open ? .spring(response: 0.52, dampingFraction: 0.6) : .spring(response: 0.42, dampingFraction: 0.78), value: open)
        .animation(.spring(response: 0.46, dampingFraction: 0.66), value: state.closedActivity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: settings.sizeScale)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Lang.locale)
        .id(settings.language) // rebuild every label when the language changes
        .ignoresSafeArea()
    }
}

// MARK: - Closed

struct ClosedNotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var music: MusicManager
    @ObservedObject private var timer: TimerManager
    @ObservedObject private var downloads: DownloadMonitor

    init(state: NotchState) {
        self.state = state
        music = state.music
        timer = state.timer
        downloads = state.downloads
    }

    var body: some View {
        let h = state.notchSize.height
        HStack(spacing: 0) {
            leading.frame(width: state.wingWidth, height: h)
            Color.clear.frame(width: state.notchSize.width, height: h)
            trailing.frame(width: state.wingWidth, height: h)
        }
        .frame(width: state.closedSize.width, height: h)
    }

    @ViewBuilder private var leading: some View {
        switch state.closedActivity {
        case .none, .alert, .miniPlayer:
            EmptyView()
        case .music, .musicAndTimer:
            ArtworkView(image: music.artwork, trackID: music.trackID, size: h(0.62), radius: 6)
                .onTapGesture { music.openPlayer() }
        case .timer:
            timerBadge
        case .transient(.charging(let level)):
            BatteryGauge(level: level, charging: true, width: 24)
        case .transient(.unplugged(let level)):
            BatteryGauge(level: level, width: 24)
        case .transient(.shelfAdded):
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.blue)
        case .transient(.focus(let on)):
            Image(systemName: on ? "moon.fill" : "moon").font(.system(size: 14, weight: .semibold)).foregroundStyle(.indigo)
        case .transient(.capsLock(let on)):
            Image(systemName: on ? "capslock.fill" : "capslock").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.green : Color.white.opacity(0.6))
        case .transient(.camera(let on)):
            Image(systemName: on ? "video.fill" : "video.slash.fill").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.green : Color.white.opacity(0.6))
        case .transient(.microphone(let on)):
            Image(systemName: on ? "mic.fill" : "mic.slash.fill").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.orange : Color.white.opacity(0.6))
        case .download:
            downloadBadge
        case .upcoming:
            if let event = state.calendar.upcoming {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: event.color))
                    .frame(width: h(0.52), height: h(0.52))
                    .overlay(Image(systemName: event.meetingURL != nil ? "video.fill" : "calendar")
                        .font(.system(size: h(0.26), weight: .bold))
                        .foregroundStyle(.white))
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state.closedActivity {
        case .none, .alert, .miniPlayer:
            EmptyView()
        case .music:
            MusicBars(levels: state.audioLevels, color: music.accent).frame(height: h(0.42))
        case .timer, .musicAndTimer:
            Text(timerText)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(timerColor)
                .minimumScaleFactor(0.6)
        case .upcoming:
            // Re-reads the clock every few seconds so the minutes tick down on their own.
            TimelineView(.periodic(from: .now, by: 5)) { ctx in
                Text(upcomingText(at: ctx.date))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state.calendar.upcoming.map { Color(nsColor: $0.color) } ?? .white)
                    .minimumScaleFactor(0.6)
            }
        case .download:
            Text(downloadText)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.6)
        case .transient(let t):
            Text(t.text)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(t.color)
        }
    }

    private func h(_ fraction: CGFloat) -> CGFloat { state.notchSize.height * fraction }

    /// A ring filling as the download goes (Safari says how big it is), or a bobbing arrow when the size isn't known.
    @ViewBuilder private var downloadBadge: some View {
        if let fraction = downloads.primary?.fraction {
            ZStack {
                TimeRing(progress: fraction, color: .blue, lineWidth: 2.5)
                Image(systemName: "arrow.down").font(.system(size: 7, weight: .black)).foregroundStyle(.blue)
            }
            .frame(width: h(0.5), height: h(0.5))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .offset(y: sin(t * 5) * 1.5)
            }
        }
    }

    /// "in 9 min" style, then "now" once it has started.
    private func upcomingText(at date: Date) -> String {
        guard let event = state.calendar.upcoming else { return "" }
        let minutes = Int((event.start.timeIntervalSince(date) / 60).rounded(.up))
        return minutes <= 0 ? tr("ตอนนี้", "Now") : tr("\(minutes) น.", "\(minutes)m")
    }

    /// "45%" when the size is known, otherwise how much has come down, e.g. "12.4 MB".
    private var downloadText: String {
        guard let d = downloads.primary else { return "" }
        if let f = d.fraction { return "\(Int(f * 100))%" }
        return ByteCountFormatter.string(fromByteCount: d.bytes, countStyle: .file)
    }

    /// A ring emptying as the countdown runs (red for Pomodoro focus, green for its breaks), or a stopwatch.
    @ViewBuilder private var timerBadge: some View {
        switch timer.primary {
        case .countdown(let c, _):
            TimeRing(progress: c.progress(), color: timerColor, lineWidth: 2.5)
                .frame(width: h(0.5), height: h(0.5))
        default:
            Image(systemName: "stopwatch").font(.system(size: 13, weight: .semibold)).foregroundStyle(timerColor)
        }
    }

    private var timerText: String {
        if case .stopwatch = timer.primary { return TimerManager.format(timer.stopwatchElapsed().rounded(.down)) }
        return TimerManager.format(timer.remaining)
    }

    private var timerColor: Color {
        switch timer.primary {
        case .countdown(_, .focus?): return .red
        case .countdown(_, .shortBreak?), .countdown(_, .longBreak?): return .green
        case .stopwatch: return .cyan
        default: return .orange
        }
    }
}

private extension TransientActivity {
    var text: String {
        switch self {
        case .charging(let l), .unplugged(let l): return "\(l)%"
        case .shelfAdded(let n): return "+\(n)"
        case .focus(let on), .capsLock(let on), .camera(let on), .microphone(let on): return on ? tr("เปิด", "On") : tr("ปิด", "Off")
        }
    }

    var color: Color {
        switch self {
        case .charging(let l), .unplugged(let l): return BatteryManager.color(for: l)
        case .shelfAdded: return .blue
        case .focus: return .indigo
        case .capsLock(let on), .camera(let on): return on ? .green : .white.opacity(0.6)
        case .microphone(let on): return on ? .orange : .white.opacity(0.6)
        }
    }
}

struct EqualizerBars: View {
    var color: Color
    private let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        let v = (sin(t * speeds[i] + Double(i) * 1.3) + 1) / 2 * 0.75 + 0.25
                        Capsule().fill(color).frame(width: 3, height: max(3, geo.size.height * v))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: 20)
        }
    }
}

/// Bars that follow the real system audio when the live waveform is on, otherwise a gentle animation.
struct MusicBars: View {
    @ObservedObject var levels: AudioLevelMonitor
    var color: Color

    var body: some View {
        if levels.isRunning {
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(color)
                            .frame(width: 3, height: max(3, geo.size.height * CGFloat(0.2 + 0.8 * levels.levels[i])))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.linear(duration: 0.06), value: levels.levels)
            }
            .frame(width: 20)
        } else {
            EqualizerBars(color: color)
        }
    }
}

/// A moon in the header while a Focus is keeping the notch quiet.
struct FocusBadge: View {
    @ObservedObject var focus: FocusMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        if focus.isActive && settings.respectFocus {
            Image(systemName: "moon.fill")
                .font(.system(size: 12))
                .foregroundStyle(.indigo)
                .help(tr("เปิดโหมด \(focus.modeName ?? "Focus") อยู่ — แจ้งเตือนที่ไม่สำคัญจะเงียบ",
                          "\(focus.modeName ?? "Focus") is on — non-essential alerts stay quiet"))
        }
    }
}

// MARK: - Open

struct OpenNotchView: View {
    @ObservedObject var state: NotchState

    var body: some View {
        let scale = state.scale
        let base = NotchState.baseOpenSize
        VStack(spacing: 0) {
            // Divided by the scale so the header still lines up with the physical notch once scaled.
            NotchHeader(state: state, settings: state.settings, battery: state.battery)
                .frame(height: max(state.notchSize.height, 30) / scale)
            Group {
                switch state.tab {
                case .home: HomeView(music: state.music, calendar: state.calendar) { state.holdOpen = $0 }
                case .calendar: CalendarTabView(calendar: state.calendar, weather: state.weather)
                case .shelf: ShelfView(shelf: state.shelf)
                case .clipboard: ClipboardView(clipboard: state.clipboard)
                case .timer: TimerView(timer: state.timer)
                case .mirror: MirrorView(controls: state.controls)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .padding(.horizontal, NotchState.openTopRadius + 18)
        .frame(width: base.width, height: base.height)
        .foregroundStyle(.white)
        .scaleEffect(scale, anchor: .top)
        .frame(width: base.width * scale, height: base.height * scale, alignment: .top)
    }
}

struct NotchHeader: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: AppSettings
    @ObservedObject var battery: BatteryManager

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(NotchTab.allCases) { tab in
                    let selected = state.tab == tab
                    Button { state.tab = tab } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 22)
                            .background(Capsule().fill(selected ? Color.white.opacity(0.16) : .clear))
                            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
            Spacer(minLength: (state.notchSize.width + 16) / state.scale)
            HStack(spacing: 10) {
                FocusBadge(focus: state.focus, settings: settings)
                if battery.hasBattery {
                    HStack(spacing: 5) {
                        Text("\(battery.level)%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(battery.color)
                        BatteryGauge(level: battery.level, charging: battery.isPluggedIn)
                    }
                    .help(batteryHelp)
                }
                Button { state.showSettings?(nil) } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("การตั้งค่า", "Settings"))
            }
        }
    }

    private var batteryHelp: String {
        if battery.isPluggedIn {
            return battery.minutesToFull.map { tr("ชาร์จเต็มในอีก \(BatteryManager.formatMinutes($0))", "Full in \(BatteryManager.formatMinutes($0))") } ?? tr("กำลังชาร์จ", "Charging")
        }
        return battery.minutesToEmpty.map { tr("ใช้งานได้อีกประมาณ \(BatteryManager.formatMinutes($0))", "About \(BatteryManager.formatMinutes($0)) left") } ?? tr("ใช้แบตเตอรี่", "On battery")
    }
}
