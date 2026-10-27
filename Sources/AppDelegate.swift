import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var state: NotchState!
    private var controller: NotchController!
    private var bluetooth: BluetoothManager!
    private var statusItem: NSStatusItem!
    private var launchItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let state = NotchState(
            settings: settings,
            music: MusicManager(),
            battery: BatteryManager(),
            shelf: ShelfManager(),
            timer: TimerManager(),
            calendar: CalendarManager(),
            controls: SystemControls(),
            clipboard: ClipboardManager(),
            weather: WeatherManager()
        )
        let controller = NotchController(state: state)
        self.state = state
        self.controller = controller

        state.battery.onEvent = { [weak state] event in
            guard let state, state.settings.batteryAlerts else { return }
            switch event {
            case .pluggedIn(let level):
                if !state.isOpen { state.flash(.charging(level)) }
            case .unplugged(let level):
                if !state.isOpen { state.flash(.unplugged(level)) }
            case .estimate(let level, let minutes):
                if !state.isOpen { state.showAlert(.batteryEstimate(level: level, minutes: minutes), seconds: 4) }
            case .low(let level):
                state.showAlert(.lowBattery(level: level, minutesLeft: state.battery.minutesToEmpty))
                NSSound(named: "Funk")?.play()
            case .full:
                state.showAlert(.fullyCharged, seconds: 4)
                NSSound(named: "Hero")?.play()
            }
        }
        // Already low when P Island starts: warn once.
        let battery = state.battery
        if settings.batteryAlerts, battery.hasBattery, !battery.isPluggedIn,
           battery.level <= BatteryManager.lowThresholds[0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                state.showAlert(.lowBattery(level: battery.level, minutesLeft: battery.minutesToEmpty))
                NSSound(named: "Funk")?.play()
            }
        }
        state.shelf.onAdded = { [weak state] count in
            guard let state, !state.isOpen else { return }
            state.flash(.shelfAdded(count), seconds: 2)
        }
        state.timer.onFinish = { [weak controller] in
            controller?.open(tab: .timer, sticky: 6)
        }
        state.music.onTrackChange = { [weak state] title, artist in
            guard let state, state.settings.songPeek, !state.isOpen else { return }
            state.showAlert(.nowPlaying(title: title, artist: artist), seconds: 3)
        }
        state.controls.onVolumeChange = { [weak state] in
            guard let state, state.settings.volumeHUD, !state.isOpen else { return }
            state.showAlert(.volume(level: state.controls.volume, muted: state.controls.muted), seconds: 1.8)
        }
        state.controls.onBrightnessChange = { [weak state] in
            guard let state, state.settings.volumeHUD, !state.isOpen, let level = state.controls.brightness else { return }
            state.showAlert(.brightness(level: level), seconds: 1.8)
        }
        state.calendar.onMeetingSoon = { [weak state] event in
            guard let state, state.settings.meetingAlerts, let url = event.meetingURL else { return }
            state.showAlert(.meeting(title: event.title, url: url, start: event.start), seconds: 60)
            NSSound(named: "Glass")?.play()
        }
        state.clipboard.isEnabled = { [weak settings] in settings?.clipboardHistory ?? false }

        bluetooth = BluetoothManager()
        bluetooth.onEvent = { [weak state] name, kind, connected, batteryText in
            guard let state, state.settings.bluetoothAlerts, !state.isOpen else { return }
            state.showAlert(.bluetooth(name: name, kind: kind, connected: connected, battery: batteryText), seconds: 3.5)
        }

        // ⌃⌥I toggles the notch, ⌃⌥T jumps to the timer.
        HotKeys.register(keyCode: kVK_ANSI_I, modifiers: controlKey | optionKey) { [weak controller] in
            controller?.toggle()
        }
        HotKeys.register(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak controller] in
            controller?.toggle(tab: .timer)
        }

        setUpStatusItem()

        let args = CommandLine.arguments
        if args.contains("--launch-at-login") {
            settings.refreshLaunchAtLogin()
            NSLog("%@", "Islet: launch at login is \(settings.launchAtLogin ? "on" : "off")")
        }
        if args.contains("--demo") {
            Demo.run(controller: controller, state: state)
        }
        if args.contains("--demo-battery") {
            Demo.runBattery(state: state)
        }
        if args.contains("--demo-alerts") {
            Demo.runAlerts(state: state)
        }

        // Developer aid: `--open shelf` keeps the notch open on that tab.
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count, let tab = NotchTab(rawValue: args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                controller.open(tab: tab, sticky: 3600)
            }
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "P Island")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Open Notch  ⌃⌥I", action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Play Feature Demo", action: #selector(playDemo), keyEquivalent: "").target = self
        menu.addItem(.separator())
        launchItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit P Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchItem.state = state.settings.launchAtLogin ? .on : .off
    }

    @objc private func openNotch() {
        controller.open(sticky: 2)
    }

    @objc private func playDemo() {
        Demo.runAlerts(state: state)
    }

    @objc private func toggleLaunchAtLogin() {
        state.settings.launchAtLogin.toggle()
    }
}
