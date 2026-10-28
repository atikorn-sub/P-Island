import AppKit

/// `Islet --demo` walks through every feature on its own, logging each step.
enum Demo {
    static func run(controller: NotchController, state: NotchState) {
        var t: Double = 0.8
        func step(_ seconds: Double, _ name: @escaping @autoclosure () -> String, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                NSLog("%@", "Islet demo: \(name())")
                action()
            }
            t += seconds
        }

        step(5, "Home — music \(state.music.hasTrack ? "\"\(state.music.title)\"" : "(nothing playing)"), calendar \(state.calendar.status)") {
            controller.open(tab: .home, sticky: 5)
        }
        step(3, "Shelf — adding sample files") {
            let files = makeSampleFiles()
            state.shelf.add(files)
            controller.open(tab: .shelf, sticky: 7)
        }
        step(4, "Converter — PNG to JPEG") {
            guard let png = state.shelf.items.first(where: { $0.url.pathExtension == "png" }) else { return }
            state.shelf.convert(png, to: .jpeg)
        }
        step(4, "Timer — 15 second countdown") {
            state.timer.startCountdown(seconds: 15, name: "Demo")
            controller.open(tab: .timer, sticky: 4)
        }
        step(5, "Closed notch — timer on the wings") {
            controller.close()
        }
        // The timer finishes ~11s from here and opens the notch with a sound by itself.
        step(18, "Waiting for timer to finish") {}
        step(4, "Battery wing — \(state.battery.level)%, plugged in: \(state.battery.isPluggedIn)") {
            controller.close()
            state.flash(.charging(state.battery.level), seconds: 3.5)
        }
        step(7, "Battery alert — low (sample 15%)") {
            state.showAlert(.lowBattery(level: 15, minutesLeft: 42))
            NSSound(named: "Funk")?.play()
        }
        step(5, "Battery alert — fully charged (sample)") {
            state.showAlert(.fullyCharged, seconds: 4)
            NSSound(named: "Hero")?.play()
        }
        step(0, "Done — shelf has \(state.shelf.items.map(\.url.lastPathComponent))") {
            NSLog("%@", "Islet demo: shelf now holds \(state.shelf.items.map(\.url.lastPathComponent))")
        }
    }

    /// `--demo-alerts` (or the menu bar item): one of each new notch card, with sample data.
    /// `--showcase`: a ~40 s tour for recording a preview video. Changes look and style along the way
    /// and puts the user's own choices back at the end.
    /// `--showcase`: the portfolio clip. Drives the notch through its features on a fixed timetable and logs
    /// each step ("Islet showcase: <name>"), so a cursor can be laid over the recording afterwards.
    /// Everything it changes (look, tabs, shelf, timers) is put back at the end.
    static func runShowcase(controller: NotchController, state: NotchState) {
        let settings = state.settings
        let defaults = UserDefaults.standard
        let saved = (settings.closedStyle, settings.notchStyle, settings.lyricsInSlimBar,
                     defaults.string(forKey: "homeSideTab"), defaults.string(forKey: "timerMode"), settings.songPeek)
        settings.songPeek = false // no "now playing" card popping up at launch
        let shelfBefore = state.shelf.items.map(\.url)
        settings.closedStyle = "wings"
        settings.notchStyle = "black"
        settings.lyricsInSlimBar = true
        defaults.set("upNext", forKey: "homeSideTab")
        defaults.set("timers", forKey: "timerMode")
        var samples: [URL] = []

        var t = 1.5
        func step(_ seconds: Double, _ name: String, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                NSLog("%@", "Islet showcase: \(name)")
                action()
            }
            t += seconds
        }

        // Open panel: Home, lyrics, calendar, shelf with its drop zones, timers.
        step(2.5, "wings") {}
        step(3.5, "home") { controller.open(tab: .home, sticky: 120) }
        step(3.5, "lyrics") { defaults.set("lyrics", forKey: "homeSideTab") }
        step(3, "calendar") { state.tab = .calendar }
        step(2.2, "shelf") {
            samples = makeSampleFiles()
            state.shelf.add(samples)
            state.tab = .shelf
        }
        step(1.2, "drop: shelf") {
            state.shelf.dropTargeting = true
            state.shelf.hoveredZone = .shelf
        }
        step(1.1, "drop: airdrop") { state.shelf.hoveredZone = .airDrop }
        step(1.1, "drop: zip") { state.shelf.hoveredZone = .zip }
        step(1.2, "drop: shrink") { state.shelf.hoveredZone = .shrink }
        step(2.6, "timers") {
            state.shelf.hoveredZone = nil
            state.shelf.dropTargeting = false
            state.tab = .timer
            state.timer.startCountdown(minutes: 4, name: tr("☕ ชงกาแฟ", "☕ Coffee"))
            state.timer.startCountdown(minutes: 3, name: tr("🍜 บะหมี่", "🍜 Noodles"))
        }
        step(3, "pomodoro") {
            defaults.set("pomodoro", forKey: "timerMode")
            state.timer.startPomodoro()
        }
        step(1.2, "close") {
            controller.close()
            state.tab = .home
        }

        // Closed notch: live activities and cards.
        step(2.8, "pomodoro wings") {}
        step(2.8, "countdown") {
            state.timer.stopPomodoro()
            state.timer.countdowns.map(\.id).forEach(state.timer.remove)
            state.calendar.demoUpcoming()
        }
        step(3.4, "download") {
            state.calendar.endDemo()
            state.downloads.demo(name: "P-Island-1.5.zip", seconds: 2.6)
        }
        step(3, "airpods") {
            state.showAlert(.bluetooth(name: tr("AirPods Pro ของฉัน", "My AirPods Pro"), kind: .airpodsPro, connected: true,
                                       battery: tr("L 80% · R 85% · เคส 60%", "L 80% · R 85% · Case 60%")), seconds: 2.8)
        }
        step(1.8, "caps lock") { state.flash(.capsLock(on: true), seconds: 1.6) }
        step(3.6, "notification") {
            state.showAlert(.notification(AppNotification(bundleID: MessagesReplier.bundleID, title: "P",
                                                          subtitle: "", body: tr("มีแอปใหม่ในพอร์ตแล้ว 🎉", "New app in the portfolio 🎉"),
                                                          date: Date()), replying: false), seconds: 3.4)
        }
        step(2.6, "volume") { state.showAlert(.volume(level: state.controls.volume, muted: false), seconds: 2.4) }
        step(4.5, "slim bar") { settings.closedStyle = "mini" }

        // Finally the glass look.
        step(3.8, "glass") {
            settings.closedStyle = "wings"
            settings.notchStyle = "glass"
            defaults.set("upNext", forKey: "homeSideTab")
            controller.open(tab: .home, sticky: 120)
        }
        step(1, "end") {
            controller.close()
            settings.closedStyle = saved.0
            settings.notchStyle = saved.1
            settings.lyricsInSlimBar = saved.2
            settings.songPeek = saved.5
            defaults.set(saved.3, forKey: "homeSideTab")
            defaults.set(saved.4, forKey: "timerMode")
            state.shelf.remove(samples.filter { !shelfBefore.contains($0) })
            samples.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    static func runAlerts(state: NotchState) {
        let meetingURL = URL(string: "https://meet.google.com/")!
        let steps: [(String, NotchAlert, Double)] = [
            ("song peek", .nowPlaying(title: state.music.hasTrack ? state.music.title : tr("ตัวอย่างเพลง", "Sample Song"),
                                      artist: state.music.hasTrack ? state.music.artist : tr("ศิลปินตัวอย่าง", "Sample Artist")), 3),
            ("volume", .volume(level: state.controls.volume, muted: state.controls.muted), 3),
            ("brightness", .brightness(level: state.controls.brightness ?? 0.6), 3),
            ("bluetooth", .bluetooth(name: "AirPods Pro", kind: .airpodsPro, connected: true,
                                     battery: tr("L 80% · R 85% · เคส 60%", "L 80% · R 85% · Case 60%")), 3.5),
            ("meeting", .meeting(title: tr("ประชุมทีม (ตัวอย่าง)", "Team meeting (sample)"), url: meetingURL, start: Date().addingTimeInterval(60)), 4.5),
            ("notification", .notification(AppNotification(bundleID: MessagesReplier.bundleID, title: tr("ตัวอย่าง", "Sample"),
                                                           subtitle: "", body: tr("นี่คือตัวอย่างแจ้งเตือนจาก Messages", "This is a sample notification from Messages"),
                                                           date: Date()), replying: false), 5),
            ("battery estimate", .batteryEstimate(level: state.battery.level, minutes: 205), 3.5),
        ]
        var t = 0.8
        for (name, alert, seconds) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                NSLog("%@", "Islet demo: \(name)")
                state.showAlert(alert, seconds: seconds - 0.3)
            }
            t += seconds
        }
    }

    /// `Islet --demo-battery`: charging wing, low-battery card, fully-charged card.
    static func runBattery(state: NotchState) {
        let level = state.battery.level
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSLog("%@", "Islet demo: battery wing \(level)%")
            state.flash(.charging(level), seconds: 3.5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            NSLog("%@", "Islet demo: low battery card (sample 15%)")
            state.showAlert(.lowBattery(level: 15, minutesLeft: 42))
            NSSound(named: "Funk")?.play()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            NSLog("%@", "Islet demo: fully charged card (sample)")
            state.showAlert(.fullyCharged, seconds: 4)
            NSSound(named: "Hero")?.play()
        }
    }

    /// A gradient PNG and a short note, saved to Application Support/Islet/Demo.
    private static func makeSampleFiles() -> [URL] {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Islet/Demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let png = dir.appendingPathComponent("Sample Photo.png")
        let image = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange, .systemYellow])?.draw(in: rect, angle: 35)
            return true
        }
        if let tiff = image.tiffRepresentation,
           let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? data.write(to: png)
        }

        let sky = dir.appendingPathComponent("Sky.png")
        let skyImage = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemBlue, .systemIndigo])?.draw(in: rect, angle: -60)
            return true
        }
        if let tiff = skyImage.tiffRepresentation,
           let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? data.write(to: sky)
        }

        let note = dir.appendingPathComponent("Notes.txt")
        try? "Dropped on the P Island shelf.\n".write(to: note, atomically: true, encoding: .utf8)
        return [png, sky, note]
    }
}
