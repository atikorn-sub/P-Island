import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, calendar, shelf, clipboard, timer, mirror

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard"
        case .timer: return "timer"
        case .mirror: return "web.camera.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return tr("หน้าหลัก", "Home")
        case .calendar: return tr("ปฏิทินและสภาพอากาศ", "Calendar & Weather")
        case .shelf: return tr("ชั้นวางไฟล์", "Shelf")
        case .clipboard: return tr("คลิปบอร์ด", "Clipboard")
        case .timer: return tr("ตัวจับเวลา", "Timer")
        case .mirror: return tr("กระจก (กล้องหน้า)", "Mirror (camera)")
        }
    }
}

/// Short-lived things shown on the closed notch's "wings".
enum TransientActivity: Equatable {
    case charging(Int)
    case unplugged(Int)
    case shelfAdded(Int)
    case focus(on: Bool)
    case capsLock(on: Bool)
    case camera(on: Bool)
    case microphone(on: Bool)
}

enum BluetoothKind: Equatable {
    case airpods, airpodsPro, airpodsMax, headphones, speaker, keyboard, mouse, trackpad, gamepad, other

    var symbol: String {
        switch self {
        case .airpods: return "airpods"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .keyboard: return "keyboard.fill"
        case .mouse: return "magicmouse.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .gamepad: return "gamecontroller.fill"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Things important enough to drop the notch down into a card.
enum NotchAlert: Equatable {
    case lowBattery(level: Int, minutesLeft: Int?)
    case fullyCharged
    case batteryEstimate(level: Int, minutes: Int)
    case nowPlaying(title: String, artist: String)
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case meeting(title: String, url: URL, start: Date)
    case bluetooth(name: String, kind: BluetoothKind, connected: Bool, battery: String?)
    case notification(AppNotification, replying: Bool)
    case info(symbol: String, title: String, subtitle: String)
    case update(version: String, page: URL)

    /// Cards with controls: hovering them keeps them open instead of opening the full panel.
    var isInteractive: Bool {
        switch self {
        case .volume, .brightness, .meeting, .notification, .update: return true
        default: return false
        }
    }

    /// Stays up even when the pointer leaves, e.g. while typing a reply.
    var keepsFocus: Bool {
        if case .notification(_, true) = self { return true }
        return false
    }

    /// Height of the card below the physical notch, at 100 % size.
    var extraHeight: CGFloat {
        switch self {
        case .volume, .brightness: return 30
        case .nowPlaying: return 46
        case .notification(let note, let replying):
            if replying { return 100 }
            return note.bundleID == MessagesReplier.bundleID ? 84 : 60
        default: return 52
        }
    }

    /// Width of the card at 100 % size.
    var width: CGFloat {
        if case .notification = self { return 400 }
        return 340
    }
}

enum ClosedActivity: Equatable {
    case none
    case music
    case timer
    case musicAndTimer
    case miniPlayer
    case transient(TransientActivity)
    case download
    case alert(NotchAlert)
}

final class NotchState: ObservableObject {
    @Published var isOpen = false
    @Published var tab: NotchTab = .home
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true
    @Published private(set) var transient: TransientActivity?
    @Published private(set) var alert: NotchAlert?

    let settings: AppSettings
    let music: MusicManager
    let battery: BatteryManager
    let shelf: ShelfManager
    let timer: TimerManager
    let calendar: CalendarManager
    let controls: SystemControls
    let clipboard: ClipboardManager
    let weather: WeatherManager
    let notifications = NotificationsManager()
    let audioLevels = AudioLevelMonitor()
    let focus = FocusMonitor()
    let updates = UpdateChecker()
    let downloads = DownloadMonitor()

    /// A Focus is on and the user wants P Island to stay quiet during it.
    var isQuiet: Bool { settings.respectFocus && focus.isActive }

    /// Open panel size at 100 %; the panel is laid out at this size and then scaled.
    static let baseOpenSize = CGSize(width: 640, height: 236)
    static let closedTopRadius: CGFloat = 6
    static let openTopRadius: CGFloat = 14

    /// A menu from the panel (the sound output list) is up: leaving the panel's area mustn't close it.
    var holdOpen = false
    /// Set by the controller: makes the panel take keyboard input (for typing a reply).
    var requestKeyboard: (() -> Void)?
    /// Set by the controller: opens the full panel (e.g. clicking the song in the slim bar).
    var openPanel: (() -> Void)?
    /// Set by the app delegate: opens the settings window, on a given pane or the last one shown.
    var showSettings: ((SettingsPane?) -> Void)?

    private var transientWork: DispatchWorkItem?
    private var alertWork: DispatchWorkItem?
    private var alertHeld = false

    init(settings: AppSettings, music: MusicManager, battery: BatteryManager, shelf: ShelfManager,
         timer: TimerManager, calendar: CalendarManager, controls: SystemControls,
         clipboard: ClipboardManager, weather: WeatherManager) {
        self.settings = settings
        self.music = music
        self.battery = battery
        self.shelf = shelf
        self.timer = timer
        self.calendar = calendar
        self.controls = controls
        self.clipboard = clipboard
        self.weather = weather
    }

    var wingWidth: CGFloat { notchSize.height + 12 }

    /// Each half of the slim music bar, beside the camera; kept inside the notch window.
    var miniWingWidth: CGFloat {
        let room = (openSize.width + 60 - notchSize.width) / 2 - Self.closedTopRadius - 4
        return min(230 * scale, room)
    }

    var scale: CGFloat { CGFloat(settings.sizeScale) }

    var openSize: CGSize {
        CGSize(width: Self.baseOpenSize.width * scale, height: Self.baseOpenSize.height * scale)
    }

    var closedActivity: ClosedActivity {
        if let alert { return .alert(alert) }
        if let transient { return .transient(transient) }
        if downloads.primary != nil { return .download }
        // Slim bar: stays out a little while after pausing so play is still one click away.
        if settings.closedStyle == "mini", music.hasTrack, music.isPlaying || music.recentlyPaused {
            return .miniPlayer
        }
        let playing = music.hasTrack && music.isPlaying
        if timer.isActive { return playing ? .musicAndTimer : .timer }
        if playing { return .music }
        return .none
    }

    /// Size of the black shape while closed, including the flared top corners.
    var closedSize: CGSize {
        switch closedActivity {
        case .alert(let alert):
            let width = max(notchSize.width + wingWidth * 2, alert.width * scale) + Self.closedTopRadius * 2
            return CGSize(width: width, height: notchSize.height + alert.extraHeight * scale)
        case .none:
            return CGSize(width: notchSize.width + Self.closedTopRadius * 2, height: notchSize.height)
        case .miniPlayer:
            return CGSize(width: notchSize.width + miniWingWidth * 2 + Self.closedTopRadius * 2, height: notchSize.height)
        default:
            return CGSize(width: notchSize.width + wingWidth * 2 + Self.closedTopRadius * 2, height: notchSize.height)
        }
    }

    func showAlert(_ alert: NotchAlert, seconds: Double = 6) {
        self.alert = alert
        if !alertHeld { scheduleAlertDismiss(after: seconds) }
    }

    func dismissAlert() {
        alertWork?.cancel()
        alertHeld = false
        alert = nil
    }

    /// While the pointer is on an interactive card, keep it up; let it go shortly after the pointer leaves.
    func holdAlert(_ hold: Bool) {
        guard hold != alertHeld else { return }
        alertHeld = hold
        if hold {
            alertWork?.cancel()
        } else if alert != nil {
            scheduleAlertDismiss(after: 1.5)
        }
    }

    private func scheduleAlertDismiss(after seconds: Double) {
        alertWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.alert = nil }
        alertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func flash(_ activity: TransientActivity, seconds: Double = 3) {
        transientWork?.cancel()
        transient = activity
        let work = DispatchWorkItem { [weak self] in self?.transient = nil }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
