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
            state.timer.setDuration(15)
            state.timer.start()
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
    static func runAlerts(state: NotchState) {
        let meetingURL = URL(string: "https://meet.google.com/")!
        let steps: [(String, NotchAlert, Double)] = [
            ("song peek", .nowPlaying(title: state.music.hasTrack ? state.music.title : "ตัวอย่างเพลง",
                                      artist: state.music.hasTrack ? state.music.artist : "ศิลปินตัวอย่าง"), 3),
            ("volume", .volume(level: state.controls.volume, muted: state.controls.muted), 3),
            ("brightness", .brightness(level: state.controls.brightness ?? 0.6), 3),
            ("bluetooth", .bluetooth(name: "AirPods Pro", kind: .airpodsPro, connected: true,
                                     battery: "L 80% · R 85% · เคส 60%"), 3.5),
            ("meeting", .meeting(title: "ประชุมทีม (ตัวอย่าง)", url: meetingURL, start: Date().addingTimeInterval(60)), 4.5),
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

        let note = dir.appendingPathComponent("Notes.txt")
        try? "Dropped on the P Island shelf.\n".write(to: note, atomically: true, encoding: .utf8)
        return [png, note]
    }
}
