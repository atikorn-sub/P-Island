import AppKit
import Carbon
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var state: NotchState!
    private var controller: NotchController!
    private var bluetooth: BluetoothManager!
    private var waveformObserver: AnyCancellable?
    private var languageObserver: AnyCancellable?
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var launchItem: NSMenuItem!

    /// Another copy (e.g. a second P Island.app elsewhere on disk) asks the running one to come forward.
    /// `kill` / `pkill` quit through the normal path, so clean-up (like the mirror light's brightness) still runs.
    private var termSource: DispatchSourceSignal?
    private static let showSettingsNotification = Notification.Name("com.atikorn.islet.showSettings")

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource?.setEventHandler { NSApp.terminate(nil) }
        termSource?.resume()
        // Only one P Island at a time: two would stack two notches on top of each other.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSLog("%@", "Islet: already running (pid \(others[0].processIdentifier)), handing over and quitting")
            DistributedNotificationCenter.default().postNotificationName(Self.showSettingsNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: Self.showSettingsNotification, object: nil,
                                                            queue: .main) { [weak self] _ in
            self?.settingsWindow?.show()
        }

        let settings = AppSettings()
        NSLog("%@", "Islet language: setting=\(Lang.setting.rawValue) thai=\(Lang.isThai) sample=\(tr("การตั้งค่า", "Settings"))")
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
            guard let state, state.settings.songPeek, !state.isOpen, !state.isQuiet else { return }
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
        state.shelf.onMessage = { [weak state] title, subtitle, ok in
            state?.showAlert(.info(symbol: ok ? "text.bubble.fill" : "exclamationmark.triangle.fill",
                                   title: title, subtitle: subtitle), seconds: 4)
        }

        state.notifications.isEnabled = { [weak settings] in settings?.appNotifications ?? false }
        state.notifications.onNotification = { [weak state] note in
            guard let state, !state.isOpen, !state.isQuiet else { return }
            // Don't cover a reply that is being typed.
            if case .notification(_, true) = state.alert { return }
            state.showAlert(.notification(note, replying: false), seconds: 6)
        }

        state.focus.onChange = { [weak state] on, _ in
            guard let state, state.settings.respectFocus, !state.isOpen else { return }
            state.flash(.focus(on: on), seconds: 2.5)
        }
        if CommandLine.arguments.contains("--debug-focus") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { state.focus.dumpForDebugging() }
        }

        // The live waveform listens only while music is playing and the option is on.
        waveformObserver = state.music.$isPlaying.combineLatest(settings.$liveWaveform)
            .sink { [weak state] playing, enabled in
                DispatchQueue.main.async {
                    guard let levels = state?.audioLevels else { return }
                    if playing && enabled { levels.start() } else { levels.stop() }
                }
            }

        bluetooth = BluetoothManager()
        bluetooth.onEvent = { [weak state] name, kind, connected, batteryText in
            guard let state, state.settings.bluetoothAlerts, !state.isOpen, !state.isQuiet else { return }
            state.showAlert(.bluetooth(name: name, kind: kind, connected: connected, battery: batteryText), seconds: 3.5)
        }
        bluetooth.start()

        state.updates.onNewVersion = { [weak state] release in
            state?.showAlert(.update(version: release.version, page: release.page), seconds: 12)
        }
        state.updates.startAutomaticChecks { [weak settings] in settings?.checkUpdates ?? false }

        let permissionsModel = PermissionsModel(state: state) { [weak self] in self?.bluetooth.start() }
        settingsWindow = SettingsWindowController(state: state, permissions: permissionsModel)
        state.showSettings = { [weak self] pane in
            self?.controller.close()
            self?.settingsWindow.show(pane)
        }
        // Missing something important (e.g. Full Disk Access was never given): walk the user through it.
        if settings.showPermissionsAtLaunch && permissionsModel.missingEssentials {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.settingsWindow.show(.permissions) }
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
        if args.contains("--showcase") {
            Demo.runShowcase(controller: controller, state: state)
        }

        // `--settings about` opens the settings window on that pane.
        if let i = args.firstIndex(of: "--settings") {
            let pane = i + 1 < args.count ? SettingsPane(rawValue: args[i + 1]) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.settingsWindow.show(pane) }
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
        buildStatusMenu()
        // Menus are built once, so build again in the new language when it changes.
        languageObserver = state.settings.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.buildStatusMenu() }
        }
    }

    private func buildStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: tr("เปิดรอยบาก  ⌃⌥I", "Open Notch  ⌃⌥I"), action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("เล่นเดโมฟีเจอร์", "Play Feature Demo"), action: #selector(playDemo), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("การตั้งค่า…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: tr("สิทธิ์การเข้าถึง…", "Permissions…"), action: #selector(showPermissions), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("เกี่ยวกับ P Island", "About P Island"), action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        launchItem = menu.addItem(withTitle: tr("เปิดตอนเข้าเครื่อง", "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("ออกจาก P Island", "Quit P Island"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// Opening P Island again (Launchpad, Finder, Spotlight) while it runs shows Settings, so it isn't a dead click.
    func applicationWillTerminate(_ notification: Notification) {
        state?.controls.boostBrightness(false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchItem.state = state.settings.launchAtLogin ? .on : .off
    }

    @objc private func openNotch() {
        controller.open(sticky: 2)
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func showPermissions() {
        settingsWindow.show(.permissions)
    }

    @objc private func showAbout() {
        settingsWindow.show(.about)
    }

    @objc private func playDemo() {
        Demo.runAlerts(state: state)
    }

    @objc private func toggleLaunchAtLogin() {
        state.settings.launchAtLogin.toggle()
    }
}
