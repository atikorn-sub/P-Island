import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, calendar, shelf, clipboard, timer

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard"
        case .timer: return "timer"
        }
    }

    var title: String {
        switch self {
        case .home: return "หน้าหลัก"
        case .calendar: return "ปฏิทินและสภาพอากาศ"
        case .shelf: return "ชั้นวางไฟล์"
        case .clipboard: return "คลิปบอร์ด"
        case .timer: return "ตัวจับเวลา"
        }
    }
}

/// Short-lived things shown on the closed notch's "wings".
enum TransientActivity: Equatable {
    case charging(Int)
    case unplugged(Int)
    case shelfAdded(Int)
    case focus(on: Bool)
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

    /// Cards with controls: hovering them keeps them open instead of opening the full panel.
    var isInteractive: Bool {
        switch self {
        case .volume, .brightness, .meeting, .notification: return true
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
    case transient(TransientActivity)
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

    /// A Focus is on and the user wants P Island to stay quiet during it.
    var isQuiet: Bool { settings.respectFocus && focus.isActive }

    /// Open panel size at 100 %; the panel is laid out at this size and then scaled.
    static let baseOpenSize = CGSize(width: 640, height: 236)
    static let closedTopRadius: CGFloat = 6
    static let openTopRadius: CGFloat = 14

    /// Set by the controller: makes the panel take keyboard input (for typing a reply).
    var requestKeyboard: (() -> Void)?
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

    var scale: CGFloat { CGFloat(settings.sizeScale) }

    var openSize: CGSize {
        CGSize(width: Self.baseOpenSize.width * scale, height: Self.baseOpenSize.height * scale)
    }

    var closedActivity: ClosedActivity {
        if let alert { return .alert(alert) }
        if let transient { return .transient(transient) }
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
