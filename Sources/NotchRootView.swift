import SwiftUI

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var music: MusicManager
    @ObservedObject private var timer: TimerManager
    @ObservedObject private var settings: AppSettings

    init(state: NotchState) {
        self.state = state
        music = state.music
        timer = state.timer
        settings = state.settings
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
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else if case .alert(let alert) = activity {
                AlertNotchView(state: state, alert: alert)
                    .transition(.opacity)
            } else {
                ClosedNotchView(state: state)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(open || alerting ? 0.5 : 0), radius: 16, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: open)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: state.closedActivity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: settings.sizeScale)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}

// MARK: - Closed

struct ClosedNotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var music: MusicManager
    @ObservedObject private var timer: TimerManager

    init(state: NotchState) {
        self.state = state
        music = state.music
        timer = state.timer
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
        case .none, .alert:
            EmptyView()
        case .music, .musicAndTimer:
            ArtworkView(image: music.artwork, size: h(0.62), radius: 6)
                .onTapGesture { music.openPlayer() }
        case .timer:
            Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
        case .transient(.charging(let level)):
            BatteryGauge(level: level, charging: true, width: 24)
        case .transient(.unplugged(let level)):
            BatteryGauge(level: level, width: 24)
        case .transient(.shelfAdded):
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.blue)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state.closedActivity {
        case .none, .alert:
            EmptyView()
        case .music:
            MusicBars(levels: state.audioLevels, color: music.accent).frame(height: h(0.42))
        case .timer, .musicAndTimer:
            Text(TimerManager.format(timer.remaining))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.orange)
                .minimumScaleFactor(0.6)
        case .transient(let t):
            Text(t.text)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(t.color)
        }
    }

    private func h(_ fraction: CGFloat) -> CGFloat { state.notchSize.height * fraction }
}

private extension TransientActivity {
    var text: String {
        switch self {
        case .charging(let l), .unplugged(let l): return "\(l)%"
        case .shelfAdded(let n): return "+\(n)"
        }
    }

    var color: Color {
        switch self {
        case .charging(let l), .unplugged(let l): return BatteryManager.color(for: l)
        case .shelfAdded: return .blue
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
                case .home: HomeView(music: state.music, calendar: state.calendar)
                case .calendar: CalendarTabView(calendar: state.calendar, weather: state.weather)
                case .shelf: ShelfView(shelf: state.shelf)
                case .clipboard: ClipboardView(clipboard: state.clipboard)
                case .timer: TimerView(timer: state.timer)
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
                if battery.hasBattery {
                    HStack(spacing: 5) {
                        Text("\(battery.level)%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(battery.color)
                        BatteryGauge(level: battery.level, charging: battery.isPluggedIn)
                    }
                    .help(batteryHelp)
                }
                Menu {
                    Picker("Size", selection: $settings.sizeScale) {
                        ForEach(AppSettings.sizeOptions, id: \.scale) { option in
                            Text(option.name).tag(option.scale)
                        }
                    }
                    Menu("Show in notch") {
                        Toggle("App notifications", isOn: $settings.appNotifications)
                        Toggle("Song changes", isOn: $settings.songPeek)
                        Toggle("Volume & brightness", isOn: $settings.volumeHUD)
                        Toggle("Battery alerts", isOn: $settings.batteryAlerts)
                        Toggle("Bluetooth devices", isOn: $settings.bluetoothAlerts)
                        Toggle("Meetings", isOn: $settings.meetingAlerts)
                    }
                    Button("Permissions…") { state.showPermissions?() }
                    Toggle("Live waveform (uses audio permission)", isOn: $settings.liveWaveform)
                    Toggle("Clipboard history", isOn: $settings.clipboardHistory)
                    Button("Weather city: \(state.weather.city)…") { state.weather.chooseCity() }
                    Divider()
                    Toggle("Haptic feedback", isOn: $settings.haptics)
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    Divider()
                    Text("Hotkeys: ⌃⌥I open notch · ⌃⌥T timer")
                    Button("Quit P Island") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    private var batteryHelp: String {
        if battery.isPluggedIn {
            return battery.minutesToFull.map { "ชาร์จเต็มในอีก \(BatteryManager.formatMinutes($0))" } ?? "กำลังชาร์จ"
        }
        return battery.minutesToEmpty.map { "ใช้งานได้อีกประมาณ \(BatteryManager.formatMinutes($0))" } ?? "ใช้แบตเตอรี่"
    }
}
