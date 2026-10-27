import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private var syncingLogin = false

    @Published var haptics: Bool {
        didSet { defaults.set(haptics, forKey: "haptics") }
    }
    @Published var batteryAlerts: Bool {
        didSet { defaults.set(batteryAlerts, forKey: "batteryAlerts") }
    }
    @Published var songPeek: Bool {
        didSet { defaults.set(songPeek, forKey: "songPeek") }
    }
    @Published var volumeHUD: Bool {
        didSet { defaults.set(volumeHUD, forKey: "volumeHUD") }
    }
    @Published var bluetoothAlerts: Bool {
        didSet { defaults.set(bluetoothAlerts, forKey: "bluetoothAlerts") }
    }
    @Published var meetingAlerts: Bool {
        didSet { defaults.set(meetingAlerts, forKey: "meetingAlerts") }
    }
    @Published var clipboardHistory: Bool {
        didSet { defaults.set(clipboardHistory, forKey: "clipboardHistory") }
    }
    @Published var appNotifications: Bool {
        didSet { defaults.set(appNotifications, forKey: "appNotifications") }
    }
    /// Off by default: turning it on asks for the System Audio Recording permission.
    @Published var liveWaveform: Bool {
        didSet { defaults.set(liveWaveform, forKey: "liveWaveform") }
    }
    /// Album art flips over when the song changes (read by ArtworkView straight from UserDefaults).
    @Published var artworkFlip: Bool {
        didSet { defaults.set(artworkFlip, forKey: "artworkFlip") }
    }
    /// While a Focus is on, hold back app notifications, song peeks and Bluetooth cards.
    @Published var respectFocus: Bool {
        didSet { defaults.set(respectFocus, forKey: "respectFocus") }
    }
    @Published var showPermissionsAtLaunch: Bool {
        didSet { defaults.set(showPermissionsAtLaunch, forKey: "showPermissionsAtLaunch") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncingLogin, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }
    /// Scale of the opened notch and alert cards; one of `sizeOptions`.
    @Published var sizeScale: Double {
        didSet { defaults.set(sizeScale, forKey: "sizeScale") }
    }

    static let sizeOptions: [(name: String, scale: Double)] = [
        ("เล็ก", 0.85), ("ปกติ", 1.0), ("ใหญ่", 1.15), ("ใหญ่มาก", 1.3),
    ]

    init() {
        defaults.register(defaults: [
            "haptics": true, "batteryAlerts": true, "sizeScale": 1.0, "songPeek": true, "volumeHUD": true,
            "bluetoothAlerts": true, "meetingAlerts": true, "clipboardHistory": true,
            "appNotifications": true, "liveWaveform": false, "showPermissionsAtLaunch": true, "respectFocus": true,
            "artworkFlip": true,
        ])
        artworkFlip = defaults.bool(forKey: "artworkFlip")
        respectFocus = defaults.bool(forKey: "respectFocus")
        showPermissionsAtLaunch = defaults.bool(forKey: "showPermissionsAtLaunch")
        appNotifications = defaults.bool(forKey: "appNotifications")
        liveWaveform = defaults.bool(forKey: "liveWaveform")
        haptics = defaults.bool(forKey: "haptics")
        batteryAlerts = defaults.bool(forKey: "batteryAlerts")
        songPeek = defaults.bool(forKey: "songPeek")
        volumeHUD = defaults.bool(forKey: "volumeHUD")
        bluetoothAlerts = defaults.bool(forKey: "bluetoothAlerts")
        meetingAlerts = defaults.bool(forKey: "meetingAlerts")
        clipboardHistory = defaults.bool(forKey: "clipboardHistory")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let saved = defaults.double(forKey: "sizeScale")
        sizeScale = Self.sizeOptions.first { abs($0.scale - saved) < 0.01 }?.scale ?? 1.0
    }

    /// Registers again so the login item points at this copy of the app (e.g. after it was renamed or moved).
    func refreshLaunchAtLogin() {
        try? SMAppService.mainApp.unregister()
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("%@", "Islet: launch at login failed: \(error)")
        }
        syncingLogin = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        syncingLogin = false
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("%@", "Islet: launch at login failed: \(error)")
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin {
            syncingLogin = true
            launchAtLogin = actual
            syncingLogin = false
        }
    }
}
